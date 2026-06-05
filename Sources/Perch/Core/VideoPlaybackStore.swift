import AVFoundation
import Foundation

extension Notification.Name {
    static let videoPlaybackSessionDidChange = Notification.Name("perch.videoPlaybackSessionDidChange")
}

final class VideoPlaybackSession {
    let key: String
    let videoURL: String
    let player: AVPlayer

    private(set) var manualMuted: Bool?
    private(set) var isPlaying = false
    private(set) var speed: Float = 1
    private(set) var duration: Double?

    init(key: String, videoURL: String, url: URL) {
        self.key = key
        self.videoURL = videoURL
        self.player = AVPlayer(url: url)
    }

    var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    func effectiveMuted(defaultMuted: Bool) -> Bool {
        manualMuted ?? defaultMuted
    }

    func play(defaultMuted: Bool) {
        player.isMuted = effectiveMuted(defaultMuted: defaultMuted)
        player.rate = speed
        isPlaying = true
        notifyChanged()
    }

    func pause() {
        player.pause()
        isPlaying = false
        notifyChanged()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        notifyChanged()
    }

    func setManualMuted(_ muted: Bool, defaultMuted: Bool) {
        manualMuted = muted
        player.isMuted = effectiveMuted(defaultMuted: defaultMuted)
        notifyChanged()
    }

    func applyMuted(defaultMuted: Bool) {
        player.isMuted = effectiveMuted(defaultMuted: defaultMuted)
    }

    func setSpeed(_ newSpeed: Float) {
        speed = newSpeed
        if isPlaying { player.rate = newSpeed }
        notifyChanged()
    }

    func updateDuration(_ seconds: Double) {
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .videoPlaybackSessionDidChange, object: self)
    }
}

final class VideoPlaybackStore {
    static let shared = VideoPlaybackStore()

    private var sessions: [String: VideoPlaybackSession] = [:]
    private var activeWindowKeysByOwner: [ObjectIdentifier: String?] = [:]

    private init() {}

    func session(key: String, videoURL: String) -> VideoPlaybackSession? {
        if let existing = sessions[key] { return existing }
        guard let url = URL(string: videoURL) else { return nil }
        let session = VideoPlaybackSession(key: key, videoURL: videoURL, url: url)
        sessions[key] = session
        return session
    }

    func beginWindowPlayback(owner: AnyObject, key: String?) {
        activeWindowKeysByOwner[ObjectIdentifier(owner)] = key
    }

    func endWindowPlayback(owner: AnyObject) {
        activeWindowKeysByOwner.removeValue(forKey: ObjectIdentifier(owner))
    }

    var hasActiveWindowPlayback: Bool {
        !activeWindowKeysByOwner.isEmpty
    }

    func isActiveInWindow(key: String?) -> Bool {
        guard let key else { return false }
        return activeWindowKeysByOwner.values.contains { $0 == .some(key) }
    }

    static func tweetKey(postId: String, item: MediaItem) -> String? {
        guard let seed = item.videoURL ?? item.url else { return nil }
        return "tweet:\(postId):\(seed)"
    }

    static func quoteKey(author: Person, text: String, item: MediaItem) -> String? {
        let seed = item.videoURL ?? item.url ?? text
        guard !seed.isEmpty else { return nil }
        return "quote:\(author.handle):\(seed)"
    }
}
