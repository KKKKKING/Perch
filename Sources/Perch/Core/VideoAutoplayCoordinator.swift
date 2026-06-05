import AppKit

/// Global coordinator: at most one inline timeline video plays at a time —
/// the one with the largest visible area, tie-broken by distance to viewport center.
final class VideoAutoplayCoordinator {
    static let shared = VideoAutoplayCoordinator()

    private let minFrac: CGFloat = 0.5

    private let views = NSHashTable<VideoPlayerView>.weakObjects()
    private let observedClips = NSHashTable<NSClipView>.weakObjects()
    private weak var current: VideoPlayerView?
    private var pending = false

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(scheduleEvaluate),
            name: NSWindow.didResizeNotification, object: nil)
    }

    func register(_ v: VideoPlayerView) {
        views.add(v)
        observeClip(of: v)
        scheduleEvaluate()
    }

    func unregister(_ v: VideoPlayerView) {
        if current === v { current = nil }
        views.remove(v)
        scheduleEvaluate()
    }

    private func observeClip(of v: VideoPlayerView) {
        guard let clip = v.enclosingScrollView?.contentView, !observedClips.contains(clip) else { return }
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scheduleEvaluate),
            name: NSView.boundsDidChangeNotification, object: clip)
        observedClips.add(clip)
    }

    @objc func scheduleEvaluate() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            self?.pending = false
            self?.evaluate()
        }
    }

    private func evaluate() {
        guard !VideoPlaybackStore.shared.hasActiveWindowPlayback else { return }
        var best: VideoPlayerView?
        var bestKey: (CGFloat, CGFloat)?
        for v in views.allObjects {
            guard let s = v.visibilityScore(), s.frac >= minFrac else { continue }
            let key = (s.area, -s.centerDist)
            if bestKey == nil || key.0 > bestKey!.0 || (key.0 == bestKey!.0 && key.1 > bestKey!.1) {
                bestKey = key; best = v
            }
        }
        if best !== current {
            current?.autopause()
            current = best
            best?.autoplay()
        }
        for v in views.allObjects where v !== current { v.recycleIfOffscreen() }
    }
}
