import AppKit

/// Async image cache with in-flight de-duplication and Twitter URL sizing.
/// Returns nil on failure so callers keep their gradient fallback visible.
final class ImageLoader {
    static let shared = ImageLoader()

    enum Size { case small, large, orig }

    private let cache = NSCache<NSString, NSImage>()
    private var inflight: [String: [(NSImage?) -> Void]] = [:]
    private let lock = NSLock()
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024)
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0"]
        session = URLSession(configuration: cfg)
        cache.countLimit = 240
    }

    /// pbs.twimg.com/media/<id>.<ext> → /media/<id>?format=<ext>&name=<size>
    private func sized(_ url: String, _ size: Size) -> String {
        let name: String
        switch size { case .small: name = "small"; case .large: name = "large"; case .orig: name = "orig" }
        guard url.contains("pbs.twimg.com/media"), !url.contains("?"),
              let dot = url.lastIndex(of: ".") else { return url }
        let ext = String(url[url.index(after: dot)...])
        let base = String(url[..<dot])
        return "\(base)?format=\(ext)&name=\(name)"
    }

    func image(for url: String, size: Size = .small, completion: @escaping (NSImage?) -> Void) {
        let key = sized(url, size)
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached); return
        }
        lock.lock()
        if inflight[key] != nil {
            inflight[key]?.append(completion)
            lock.unlock()
            return
        }
        inflight[key] = [completion]
        lock.unlock()

        guard let u = URL(string: key) else { deliver(key, nil); return }
        session.dataTask(with: u) { [weak self] data, _, _ in
            let img = data.flatMap { NSImage(data: $0) }
            if let img { self?.cache.setObject(img, forKey: key as NSString) }
            self?.deliver(key, img)
        }.resume()
    }

    private func deliver(_ key: String, _ img: NSImage?) {
        lock.lock()
        let cbs = inflight[key] ?? []
        inflight[key] = nil
        lock.unlock()
        DispatchQueue.main.async { cbs.forEach { $0(img) } }
    }
}
