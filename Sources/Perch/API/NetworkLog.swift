import Foundation

/// Append-only, redaction-safe log of every X API network request, written to a
/// plain-text file — one line per request, in chronological (request-start) order.
/// Purpose: diagnosing request frequency / error bursts (e.g. an over-capacity retry
/// storm on the notifications endpoint) without attaching a debugger or capturing a HAR.
///
/// Scope: all `URLSession.shared` traffic from the API layer — GraphQL reads/writes, the
/// v2 notifications + badge polls, media upload, relationship REST, plus the
/// once-per-session query-id bundle scrape and transaction-id pair fetch. Image and
/// media-download traffic runs on separate `URLSession`s (`ImageLoader`,
/// `MediaDownloadOperation`) and is intentionally excluded — it would bury the API signal.
///
/// Redaction (脱敏): only the method, host, path, status, byte count and elapsed time are
/// recorded. The query string, every header (cookie / auth_token / ct0 / x-csrf-token /
/// bearer / x-client-transaction-id), the request body and any success-response body are
/// NEVER written — paths carry no ids or secrets (those live in the query/body), so the
/// line is PII-free by construction. For a failed request a ≤200-char prefix of the error
/// envelope is appended; X error envelopes carry no secrets, and the same text already
/// surfaces in user-facing toasts via `TwitterAPIError.http`.
///
/// The file lives at `~/Library/Logs/Perch/network.log` (override with the `PERCH_NETLOG`
/// env var); it self-rotates to `network.log.1` past ~1 MB so it can't grow without bound.
/// Writes are serialized on a private queue and never block the request. Disabled entirely
/// under `PERCH_SNAPSHOT` (deterministic, sessionless snapshot runs make no live calls).
final class NetworkLog {
    static let shared = NetworkLog()

    private let queue = DispatchQueue(label: "com.perch.networklog")
    private let fileURL: URL?
    private let maxBytes: UInt64 = 1_000_000
    private var handle: FileHandle?
    private var written: UInt64 = 0
    private let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let env = ProcessInfo.processInfo.environment
        guard env["PERCH_SNAPSHOT"] == nil else { fileURL = nil; return }
        if let override = env["PERCH_NETLOG"], !override.isEmpty {
            fileURL = URL(fileURLWithPath: override)
        } else if let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            fileURL = lib.appendingPathComponent("Logs/Perch/network.log")
        } else {
            fileURL = nil
        }
    }

    /// Record one completed (or failed) request. `status` is nil on a transport failure;
    /// `detail` must already be redaction-safe (an error-envelope prefix or a short reason).
    /// `startedAt` stamps the line so the log reads in dispatch order.
    func log(method: String, url: URL?, status: Int?, bytes: Int,
             startedAt: Date, detail: String? = nil) {
        guard let fileURL else { return }
        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let host = url?.host ?? "?"
        let path = (url?.path).flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        let when = stamp.string(from: startedAt)
        var line = "\(when)  \(method.uppercased()) \(status.map(String.init) ?? "ERR")  "
            + "\(Self.humanBytes(bytes))  \(elapsedMs)ms  \(host)\(path)"
        if let detail, !detail.isEmpty {
            let clean = detail.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            line += "  — " + String(clean.prefix(200))
        }
        line += "\n"
        queue.async { [weak self] in self?.write(line, to: fileURL) }
    }

    // MARK: - Private (serial-queue only)

    private func write(_ line: String, to url: URL) {
        let fm = FileManager.default
        if handle == nil {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            handle = try? FileHandle(forWritingTo: url)
            written = (try? handle?.seekToEnd()) ?? 0   // seek to end + seed size from the offset
        }
        guard let h = handle, let data = line.data(using: .utf8) else { return }
        try? h.write(contentsOf: data)
        written += UInt64(data.count)
        if written > maxBytes { rotate(url) }
    }

    /// Keep a single prior generation (`network.log.1`) and start the live file fresh.
    private func rotate(_ url: URL) {
        try? handle?.close()
        handle = nil
        written = 0
        let fm = FileManager.default
        let rotated = url.appendingPathExtension("1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: url, to: rotated)
    }

    private static func humanBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n)B" }
        let kb = Double(n) / 1024
        if kb < 1024 { return String(format: "%.1fKB", kb) }
        return String(format: "%.1fMB", kb / 1024)
    }
}
