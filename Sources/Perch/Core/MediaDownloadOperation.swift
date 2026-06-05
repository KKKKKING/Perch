import Foundation

final class MediaDownloadOperation: NSObject, URLSessionDownloadDelegate {
    enum DownloadError: Error {
        case httpStatus(Int)
        case missingDownloadsDirectory
        case moveFailed(Error)
        case unknown
    }

    private let sourceURL: URL
    private let progress: (Double?) -> Void
    private let completion: (Result<URL, Error>) -> Void
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var savedURL: URL?
    private var finishError: Error?

    init(sourceURL: URL,
         progress: @escaping (Double?) -> Void,
         completion: @escaping (Result<URL, Error>) -> Void) {
        self.sourceURL = sourceURL
        self.progress = progress
        self.completion = completion
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0"]
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }

    func start() {
        var req = URLRequest(url: sourceURL)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        task = session.downloadTask(with: req)
        DispatchQueue.main.async { self.progress(nil) }
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        session.invalidateAndCancel()
    }

    static func originalImageURL(from raw: String) -> URL? {
        guard var comps = URLComponents(string: raw) else { return nil }
        let isTwitterImage = comps.host == "pbs.twimg.com" && comps.path.contains("/media/")
        guard isTwitterImage else { return comps.url }

        var items = comps.queryItems ?? []
        if !items.contains(where: { $0.name == "format" }) {
            let ext = (comps.path as NSString).pathExtension
            if !ext.isEmpty {
                comps.path = (comps.path as NSString).deletingPathExtension
                items.append(URLQueryItem(name: "format", value: ext))
            }
        }
        if let idx = items.firstIndex(where: { $0.name == "name" }) {
            items[idx] = URLQueryItem(name: "name", value: "orig")
        } else {
            items.append(URLQueryItem(name: "name", value: "orig"))
        }
        comps.queryItems = items
        return comps.url
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let value: Double?
        if totalBytesExpectedToWrite > 0 {
            value = min(1, max(0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
        } else {
            value = nil
        }
        DispatchQueue.main.async { self.progress(value) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if let http = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                finishError = DownloadError.httpStatus(http.statusCode)
                return
            }
            let ext = Self.fileExtension(response: downloadTask.response, sourceURL: sourceURL)
            let destination = try Self.uniqueDestinationURL(fileExtension: ext)
            try FileManager.default.moveItem(at: location, to: destination)
            savedURL = destination
        } catch {
            finishError = DownloadError.moveFailed(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let result: Result<URL, Error>
        if let error {
            result = .failure(error)
        } else if let finishError {
            result = .failure(finishError)
        } else if let savedURL {
            result = .success(savedURL)
        } else {
            result = .failure(DownloadError.unknown)
        }
        DispatchQueue.main.async { self.completion(result) }
        session.finishTasksAndInvalidate()
    }

    private static func fileExtension(response: URLResponse?, sourceURL: URL) -> String {
        if let mime = response?.mimeType?.lowercased() {
            switch mime {
            case "video/mp4": return "mp4"
            case "image/jpeg": return "jpg"
            case "image/png": return "png"
            case "image/gif": return "gif"
            case "image/webp": return "webp"
            default: break
            }
        }
        if let comps = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false),
           let format = comps.queryItems?.first(where: { $0.name == "format" })?.value,
           !format.isEmpty {
            return format
        }
        let ext = sourceURL.pathExtension
        return ext.isEmpty ? "bin" : ext
    }

    private static func uniqueDestinationURL(fileExtension ext: String) throws -> URL {
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw DownloadError.missingDownloadsDirectory
        }
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        var candidate = dir.appendingPathComponent("perch-media-\(stamp)").appendingPathExtension(cleanExt)
        var i = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("perch-media-\(stamp)-\(i)").appendingPathExtension(cleanExt)
            i += 1
        }
        return candidate
    }
}
