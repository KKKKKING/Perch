import AppKit

extension Notification.Name {
    /// Posted on the main thread whenever the debug network log changes (append / clear / seed).
    static let debugLogDidChange = Notification.Name("perch.debugLogDidChange")
}

/// One captured X API request, already redacted for safe display.
struct DebugLogEntry {
    let id: String
    let platform: Platform
    let method: String
    let urlString: String
    let host: String
    let path: String
    let query: String
    let requestHeaders: [(String, String)]   // redacted
    let requestBody: DebugJSON?
    let responseBody: DebugJSON?
    let status: Int?        // nil = transport error / no response
    let durationMs: Int?
    let error: String?
    let timeLabel: String

    var isError: Bool { error != nil || (status ?? 0) >= 400 }
}

/// Redaction-safe, in-memory ring buffer of X API requests for the debug Inspector.
/// Capture happens at the single `send()` choke point; cookies and tokens are stripped
/// before anything is stored.
final class DebugLog {
    static let shared = DebugLog()
    private init() {}

    private(set) var entries: [DebugLogEntry] = []
    private let maxEntries = 400
    private var counter = 0

    // Flags mirror the developer settings; pushed in by AppState.
    var enabled = false
    var jsonInline = true
    var netLog = true
    /// Gate for the inline `code` buttons on posts & column headers.
    var inline: Bool { enabled && jsonInline }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // MARK: Recording (called from the network layer; may run off-main)

    func record(method: String, url: URL?, requestHeaders: [String: String]?,
                requestBody: Data?, status: Int?, responseBody: Data?,
                durationMs: Int?, error: String?, platform: Platform = .x) {
        guard enabled, netLog else { return }
        // Keep snapshots deterministic: live capture is suppressed; use debugSeed instead.
        guard ProcessInfo.processInfo.environment["PERCH_SNAPSHOT"] == nil else { return }
        let id = nextId()
        let entry = DebugLog.makeEntry(id: id, platform: platform, method: method, url: url,
                                       requestHeaders: requestHeaders, requestBody: requestBody,
                                       status: status, responseBody: responseBody,
                                       durationMs: durationMs, error: error,
                                       timeLabel: DebugLog.timeFmt.string(from: Date()))
        append(entry)
    }

    private func nextId() -> String {
        counter += 1
        return "req-\(counter)"
    }

    private func append(_ entry: DebugLogEntry) {
        let mutate = { [self] in
            entries.append(entry)
            if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
            NotificationCenter.default.post(name: .debugLogDidChange, object: nil)
        }
        if Thread.isMainThread { mutate() } else { DispatchQueue.main.async(execute: mutate) }
    }

    func clear() {
        entries.removeAll()
        NotificationCenter.default.post(name: .debugLogDidChange, object: nil)
    }

    /// Replace the log with deterministic entries for snapshots (bypasses the snapshot guard).
    func debugSeed(_ seed: [DebugLogEntry]) {
        entries = seed
        NotificationCenter.default.post(name: .debugLogDidChange, object: nil)
    }

    // MARK: Entry construction + redaction

    static func makeEntry(id: String, platform: Platform, method: String, url: URL?,
                          requestHeaders: [String: String]?, requestBody: Data?,
                          status: Int?, responseBody: Data?, durationMs: Int?,
                          error: String?, timeLabel: String) -> DebugLogEntry {
        let comps = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let reqTree = requestBody.flatMap { DebugJSON.parse($0) }
        let resTree: DebugJSON?
        if let rb = responseBody, !rb.isEmpty {
            resTree = rb.count <= 512_000 ? DebugJSON.parse(rb) : .string("⟨response too large: \(rb.count) bytes⟩")
        } else {
            resTree = nil
        }
        return DebugLogEntry(
            id: id, platform: platform, method: method,
            urlString: url?.absoluteString ?? "",
            host: comps?.host ?? "",
            path: comps?.path ?? (url?.path ?? ""),
            query: comps?.percentEncodedQuery ?? "",
            requestHeaders: redactHeaders(requestHeaders),
            requestBody: reqTree, responseBody: resTree,
            status: status, durationMs: durationMs, error: error, timeLabel: timeLabel)
    }

    /// Strip cookies & auth tokens, keep header names. Over-redacts rather than risk a leak.
    static func redactHeaders(_ headers: [String: String]?) -> [(String, String)] {
        guard let headers else { return [] }
        return headers.keys.sorted { $0.lowercased() < $1.lowercased() }.map { key in
            (key, redactValue(forKey: key, value: headers[key] ?? ""))
        }
    }

    static func redactValue(forKey key: String, value: String) -> String {
        let k = key.lowercased()
        if k == "cookie" || k == "set-cookie" { return "⟨stripped⟩" }
        if k == "authorization" { return "Bearer ••••••••••••  ⟨redacted⟩" }
        if k.range(of: "(?:cookie|authorization|token|secret|csrf|bearer|ct0|guest|transaction)",
                   options: [.regularExpression, .caseInsensitive]) != nil {
            return "⟨redacted⟩"
        }
        return value
    }
}
