import AppKit
import AVFoundation

/// Where the shared player lives.
/// `.inline`  — Timeline card: rounded box, PiP + "open in window" affordances.
/// `.window`  — fills its container inside the media-viewer window; fullscreen only.
enum VideoVariant { case inline, window }

/// A view that swallows mouse events for hit-testing but stays visually on top
/// (used for non-interactive overlays so clicks fall through to the body).
private final class PassthroughView: FlippedView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Shared video player — one component for both the inline Timeline card and the
/// floating viewer window. Muted autoplay, hover-reveal controls, a bottom-left
/// countdown at rest, click-to-play/pause (engaging sound on a default-muted
/// clip), a two-level settings menu (speed + quality), fullscreen, and
/// a floating draggable picture-in-picture mini-player. Ported from
/// design/project/app/videoplayer.jsx.
final class VideoPlayerView: FlippedView {
    private let item: MediaItem
    private let isX: Bool
    private let variant: VideoVariant
    private let onOpenWindow: (() -> Void)?
    private let playbackKey: String?
    private let playbackSession: VideoPlaybackSession?
    private let durationHint: Double

    // playback state
    private var playing = false
    private var t: Double = 0
    private var muted = true
    private var localManualMuted: Bool?
    private var speed: Float = 1
    private var quality = "auto"
    private var hover = false
    private var gearOpen = false
    private var userPaused = false
    private enum Mode { case normal, fs, pip }
    private var mode: Mode = .normal

    // AVPlayer (real video) — gradient-only items use a fake playhead
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var videoHost: NSView?
    private var readyObs: NSKeyValueObservation?
    private var endObserver: Any?
    private var timeObserver: Any?
    private var sessionObserver: Any?
    private var fakeTimer: Timer?
    private var built = false
    private var duration: Double
    private var hasRealVideo: Bool { item.videoURL != nil }
    private var defaultMuted: Bool { variant == .inline }

    // views — `stage` is the reparentable surface (gradient + video + overlays)
    private let stage = HoverControl()
    private let gradView = NSView()
    private let gradLayer = CAGradientLayer()
    private var poster: ImageTile?
    private let centerPlay = PassthroughView()
    private let centerGlyph = GlyphView(name: "s2play", size: 24, color: .white)
    private let restPill = PassthroughView()
    private let restLabel = NSTextField(labelWithString: "")
    private var controlBar: VPControlBar!
    private var settingsMenu: VPSettingsMenu?
    private var settingsBackdrop: HoverControl?

    // fs / pip
    private var overlayWindow: NSWindow?
    private var pipPlaceholder: NSView?
    private var previousPresentationOptions: NSApplication.PresentationOptions?
    private var windowPlaybackActive = false

    init(item: MediaItem, durText: String?, isX: Bool, variant: VideoVariant,
         playbackKey: String? = nil, onOpenWindow: (() -> Void)? = nil) {
        self.item = item
        self.isX = isX
        self.variant = variant
        self.onOpenWindow = onOpenWindow
        self.playbackKey = playbackKey
        if let playbackKey, let videoURL = item.videoURL {
            self.playbackSession = VideoPlaybackStore.shared.session(key: playbackKey, videoURL: videoURL)
        } else {
            self.playbackSession = nil
        }
        self.durationHint = VideoPlayerView.parseDur(durText)
        self.duration = durationHint
        super.init(frame: .zero)
        syncFromPlaybackState()
        observePlaybackSession()
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        if variant == .inline {
            layer?.cornerRadius = 14
            layer?.masksToBounds = true
            layer?.borderWidth = 1
            layer?.borderColor = ThemeManager.shared.theme.borderDefault.cgColor
        }
        buildStage()
        addSubview(stage)
        layoutStage()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if variant == .inline { VideoAutoplayCoordinator.shared.unregister(self) }
        if variant == .window { endWindowPlayback() }
        if let sessionObserver { NotificationCenter.default.removeObserver(sessionObserver) }
        teardownOverlay()
        if variant == .window { pausePlayback() }
        teardownPlayer()
    }

    private func observePlaybackSession() {
        guard let playbackSession else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: .videoPlaybackSessionDidChange, object: playbackSession, queue: .main) { [weak self] _ in
            self?.syncFromPlaybackState()
            self?.updateUI()
            self?.applyControlVisibility()
        }
    }

    private func syncFromPlaybackState() {
        if let playbackSession {
            playing = playbackSession.isPlaying
            speed = playbackSession.speed
            muted = playbackSession.effectiveMuted(defaultMuted: defaultMuted)
            t = playbackSession.currentTime
            if let d = playbackSession.duration { duration = d }
        } else {
            muted = localManualMuted ?? defaultMuted
        }
    }

    private func beginWindowPlayback() {
        guard variant == .window, !windowPlaybackActive else { return }
        windowPlaybackActive = true
        VideoPlaybackStore.shared.beginWindowPlayback(owner: self, key: playbackKey)
        VideoAutoplayCoordinator.shared.scheduleEvaluate()
    }

    private func endWindowPlayback() {
        guard windowPlaybackActive else { return }
        windowPlaybackActive = false
        VideoPlaybackStore.shared.endWindowPlayback(owner: self)
        VideoAutoplayCoordinator.shared.scheduleEvaluate()
    }

    // MARK: - Stage construction

    private func buildStage() {
        stage.wantsLayer = true
        stage.layer?.masksToBounds = true
        stage.layer?.backgroundColor = NSColor.black.cgColor
        stage.onState = { [weak self] hov, _ in self?.setHover(hov) }
        stage.onClick = { [weak self] in self?.onBodyClick() }

        gradView.wantsLayer = true
        let usesBlackVideoBackground = variant == .window && hasRealVideo
        gradLayer.colors = usesBlackVideoBackground
            ? [NSColor.black.cgColor, NSColor.black.cgColor]
            : [item.grad.c0.cgColor, item.grad.c1.cgColor]
        gradLayer.startPoint = CGPoint(x: 0, y: 1)
        gradLayer.endPoint = CGPoint(x: 1, y: 0)
        gradView.layer = gradLayer
        stage.addSubview(gradView)

        if item.url != nil {
            let p = ImageTile(item, size: variant == .window ? .large : .small)
            stage.addSubview(p)
            poster = p
        }

        // center play badge (when paused)
        centerPlay.wantsLayer = true
        centerPlay.layer?.cornerRadius = 27
        centerPlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor
        centerPlay.addSubview(centerGlyph)
        stage.addSubview(centerPlay)

        // rest pill (countdown when controls hidden)
        restPill.wantsLayer = true
        restPill.layer?.cornerRadius = 7
        restPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        restLabel.font = Fonts.sans(12, .bold)
        restLabel.textColor = .white
        restLabel.lineBreakMode = .byClipping
        restLabel.isBezeled = false; restLabel.drawsBackground = false
        restPill.addSubview(restLabel)
        stage.addSubview(restPill)

        controlBar = VPControlBar(
            variant: variant, isX: isX,
            onToggle: { [weak self] in self?.toggleFromControls() },
            onMute: { [weak self] in self?.toggleMute() },
            onSeek: { [weak self] frac in self?.seek(to: frac) },
            onGear: { [weak self] in self?.toggleGear() },
            onPip: { [weak self] in self?.enterPip() },
            onFullscreen: { [weak self] in self?.toggleFullscreen() })
        stage.addSubview(controlBar)

        refreshGlyphs()
        updateUI()
        applyControlVisibility()
    }

    override func layout() {
        super.layout()
        if mode == .normal { stage.frame = bounds }
        layoutStage()
    }

    private func layoutStage() {
        let b = stage.bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // oversized gradient for the slow pan animation
        let over: CGFloat = 1.25
        gradView.frame = NSRect(x: -b.width * (over - 1) / 2, y: -b.height * (over - 1) / 2,
                                width: b.width * over, height: b.height * over)
        gradLayer.frame = gradView.bounds
        poster?.frame = b
        videoHost?.frame = b
        playerLayer?.frame = videoHost?.bounds ?? b
        CATransaction.commit()

        centerPlay.frame = NSRect(x: (b.width - 54) / 2, y: (b.height - 54) / 2, width: 54, height: 54)
        centerGlyph.frame = NSRect(x: (54 - 24) / 2 + 2, y: (54 - 24) / 2, width: 24, height: 24)

        let pillH: CGFloat = 26
        let restTextW = restLabel.perchSingleLineWidth
        let pillW = restTextW + 20
        restPill.layer?.cornerRadius = 8
        restPill.frame = NSRect(x: 10, y: b.height - 10 - pillH, width: pillW, height: pillH)
        restLabel.placeSingleLine(x: 10, y: 0, width: restTextW, height: pillH)

        let barH: CGFloat = 72
        controlBar.frame = NSRect(x: 0, y: b.height - barH, width: b.width, height: barH)
        positionSettingsMenu()
    }

    // MARK: - Player build / teardown

    private func buildPlayerIfNeeded() {
        guard !built else { return }
        built = true
        if hasRealVideo, let v = item.videoURL, let url = URL(string: v) {
            let p: AVPlayer
            if let playbackSession {
                p = playbackSession.player
                playbackSession.applyMuted(defaultMuted: defaultMuted)
                syncFromPlaybackState()
            } else {
                p = AVPlayer(url: url)
                p.isMuted = muted
            }
            player = p
            let host = NSView()
            host.wantsLayer = true
            host.layer = CALayer()
            host.layer?.backgroundColor = NSColor.black.cgColor
            let pl = AVPlayerLayer(player: p)
            pl.videoGravity = .resizeAspect
            host.layer?.addSublayer(pl)
            stage.addSubview(host, positioned: .above, relativeTo: poster ?? gradView)
            videoHost = host
            playerLayer = pl
            readyObs = pl.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else { return }
                self?.poster?.isHidden = true
            }
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
                guard let self else { return }
                if let playbackSession = self.playbackSession {
                    playbackSession.seek(to: 0)
                    if playbackSession.isPlaying { playbackSession.play(defaultMuted: self.defaultMuted) }
                } else {
                    self.player?.seek(to: .zero)
                    if self.playing { self.player?.play() }
                }
            }
            timeObserver = p.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
                guard let self else { return }
                if let d = self.player?.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                    self.playbackSession?.updateDuration(d)
                }
                self.t = time.seconds.isFinite ? time.seconds : 0
                if let playbackSession = self.playbackSession {
                    self.playing = playbackSession.isPlaying
                    self.speed = playbackSession.speed
                    self.muted = playbackSession.effectiveMuted(defaultMuted: self.defaultMuted)
                }
                self.updateUI()
            }
            layoutStage()
        }
    }

    private func teardownPlayer() {
        readyObs?.invalidate(); readyObs = nil
        if let e = endObserver { NotificationCenter.default.removeObserver(e); endObserver = nil }
        if let to = timeObserver { player?.removeTimeObserver(to); timeObserver = nil }
        if playbackSession == nil { player?.pause() }
        playerLayer?.player = nil
        videoHost?.removeFromSuperview()
        player = nil; playerLayer = nil; videoHost = nil
        fakeTimer?.invalidate(); fakeTimer = nil
        built = false
        poster?.isHidden = false
    }

    // MARK: - Playback control

    private func startPlayback() {
        buildPlayerIfNeeded()
        if let playbackSession {
            playbackSession.play(defaultMuted: defaultMuted)
            syncFromPlaybackState()
        } else if hasRealVideo {
            playing = true
            player?.isMuted = muted
            player?.rate = speed
        } else {
            playing = true
            startFakeTimer()
        }
        startGradientAnimation()
        updateUI(); applyControlVisibility()
    }

    private func pausePlayback() {
        if let playbackSession {
            playbackSession.pause()
            syncFromPlaybackState()
        } else {
            playing = false
            player?.pause()
        }
        fakeTimer?.invalidate(); fakeTimer = nil
        stopGradientAnimation()
        updateUI(); applyControlVisibility()
    }

    private func startFakeTimer() {
        fakeTimer?.invalidate()
        fakeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            var nx = self.t + 0.1 * Double(self.speed)
            if nx >= self.duration { nx = 0 }
            self.t = nx
            self.updateUI()
        }
    }

    private func toggleFromControls() {
        closeGear()
        if playing { userPaused = true; pausePlayback() }
        else { userPaused = false; startPlayback() }
    }

    private func onBodyClick() {
        if gearOpen { closeGear(); return }
        if variant == .inline {              // clicking the body opens the media viewer
            onOpenWindow?()
            return
        }
        if playing {
            userPaused = true
            pausePlayback()
        } else {
            userPaused = false
            startPlayback()
        }
    }

    private func toggleMute() {
        muted.toggle()
        if let playbackSession {
            playbackSession.setManualMuted(muted, defaultMuted: defaultMuted)
            syncFromPlaybackState()
        } else {
            localManualMuted = muted
        }
        applyMuted()
        refreshGlyphs()
    }

    private func applyMuted() {
        if let playbackSession {
            playbackSession.applyMuted(defaultMuted: defaultMuted)
            muted = playbackSession.effectiveMuted(defaultMuted: defaultMuted)
        } else {
            player?.isMuted = muted
        }
    }

    private func seek(to frac: CGFloat) {
        let target = duration * Double(max(0, min(1, frac)))
        t = target
        if hasRealVideo {
            if let playbackSession {
                playbackSession.seek(to: target)
            } else {
                player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
            }
        }
        updateUI()
    }

    // MARK: - Gradient pan animation

    private func startGradientAnimation() {
        guard gradView.layer?.animation(forKey: "pan") == nil else { return }
        let anim = CABasicAnimation(keyPath: "position.x")
        let base = gradView.layer?.position.x ?? 0
        anim.fromValue = base - stage.bounds.width * 0.12
        anim.toValue = base + stage.bounds.width * 0.12
        anim.duration = 9
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradView.layer?.add(anim, forKey: "pan")
    }
    private func stopGradientAnimation() { gradView.layer?.removeAnimation(forKey: "pan") }

    // MARK: - UI refresh

    private func updateUI() {
        let remaining = max(0, duration - t)
        restLabel.stringValue = VideoPlayerView.fmt(remaining)
        controlBar.update(t: t, dur: duration)
        refreshGlyphs()
        let showControls = hover || !playing || gearOpen
        centerPlay.isHidden = playing || variant == .inline
        restPill.isHidden = showControls
        layoutStage()
    }

    private func refreshGlyphs() {
        centerGlyph.setName("s2play")
        controlBar.setPlaying(playing)
        controlBar.setMuted(muted)
        controlBar.setMode(mode)
    }

    private func setHover(_ h: Bool) {
        guard h != hover else { return }
        hover = h
        applyControlVisibility()
    }

    private func applyControlVisibility() {
        let showControls = hover || !playing || gearOpen
        controlBar.isHidden = !showControls
        restPill.isHidden = showControls
        controlBar.setPlaying(playing)
    }

    // MARK: - Settings menu

    private func toggleGear() {
        if gearOpen { closeGear() } else { openGear() }
    }
    private func openGear() {
        gearOpen = true
        let backdrop = HoverControl(frame: stage.bounds)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.onClick = { [weak self] in self?.closeGear() }
        stage.addSubview(backdrop)
        settingsBackdrop = backdrop
        let menu = VPSettingsMenu(
            isX: isX, speed: speed, quality: quality,
            onSpeed: { [weak self] s in self?.setSpeed(s) },
            onQuality: { [weak self] q in self?.setQuality(q) },
            onDismiss: { [weak self] in self?.closeGear() })
        menu.onLayoutChange = { [weak self] in self?.positionSettingsMenu() }
        stage.addSubview(menu)
        settingsMenu = menu
        positionSettingsMenu()
        applyControlVisibility()
    }
    private func closeGear() {
        guard gearOpen else { return }
        gearOpen = false
        settingsMenu?.removeFromSuperview()
        settingsMenu = nil
        settingsBackdrop?.removeFromSuperview()
        settingsBackdrop = nil
        applyControlVisibility()
    }
    private func positionSettingsMenu() {
        guard let menu = settingsMenu else { return }
        let size = menu.fittingSize2
        let gearFrame = controlBar.gearFrameInStage()
        var x = gearFrame.maxX + 4 - size.width
        x = max(8, min(stage.bounds.width - size.width - 8, x))
        let y = gearFrame.minY - 8 - size.height
        menu.frame = NSRect(x: x, y: max(8, y), width: size.width, height: size.height)
    }
    private func setSpeed(_ s: Float) {
        speed = s
        if let playbackSession {
            playbackSession.setSpeed(s)
            syncFromPlaybackState()
        } else if playing && hasRealVideo {
            player?.rate = s
        }
        closeGear()
    }
    private func setQuality(_ q: String) { quality = q; closeGear() }

    // MARK: - Fullscreen (window variant)

    private func toggleFullscreen() {
        closeGear()
        mode == .fs ? exitOverlay() : enterFullscreen()
    }

    private func enterFullscreen() {
        guard mode == .normal, let screen = window?.screen ?? NSScreen.main else { return }
        mode = .fs
        enterFullscreenPresentation()
        let win = makeOverlayWindow(frame: screen.frame, kind: .fullscreen)
        let host = FlippedView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        reparentStage(into: host, frame: host.bounds)
        win.contentView = host
        overlayWindow = win
        win.makeKeyAndOrderFront(nil)
        refreshGlyphs()
    }

    // MARK: - Picture in picture (inline variant)

    private func enterPip() {
        guard mode == .normal else { return }
        closeGear()
        mode = .pip
        let w: CGFloat = 320, h: CGFloat = 180
        let anchor = window?.frame ?? NSScreen.main?.frame ?? .zero
        let origin = NSPoint(x: anchor.maxX - w - 18, y: anchor.minY + 18)
        let win = makeOverlayWindow(frame: NSRect(x: origin.x, y: origin.y, width: w, height: h), kind: .pip)
        let host = PipHostView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        host.wantsLayer = true
        host.layer?.cornerRadius = 12
        host.layer?.masksToBounds = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        host.onDrag = { [weak win] delta in
            guard let win else { return }
            var origin = win.frame.origin
            origin.x += delta.x; origin.y += delta.y
            win.setFrameOrigin(origin)
        }
        reparentStage(into: host, frame: host.bounds)

        // pip chrome: drag handle + open-in + close across the top
        let chrome = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: 34))
        chrome.wantsLayer = true
        let grad = CAGradientLayer()
        grad.frame = chrome.bounds
        grad.colors = [NSColor.black.withAlphaComponent(0.5).cgColor, NSColor.clear.cgColor]
        chrome.layer?.addSublayer(grad)
        var bx = w - 4 - 28
        let close = VPControlBar.circleButton(name: "close", size: 15, dim: 28,
            title: isX ? "Close" : "关闭") { [weak self] in self?.exitOverlay() }
        close.frame = NSRect(x: bx, y: 3, width: 28, height: 28); chrome.addSubview(close); bx -= 30
        if onOpenWindow != nil {
            let openin = VPControlBar.circleButton(name: "s2openin", size: 15, dim: 28,
                title: isX ? "Open in window" : "在新窗口打开") { [weak self] in
                self?.exitOverlay(); self?.onOpenWindow?()
            }
            openin.frame = NSRect(x: bx, y: 3, width: 28, height: 28); chrome.addSubview(openin)
        }
        host.addSubview(chrome)
        host.dragHandleHeight = 34

        win.contentView = host
        overlayWindow = win
        win.makeKeyAndOrderFront(nil)
        if !playing { userPaused = false; startPlayback() }
        showPipPlaceholder()
    }

    private func showPipPlaceholder() {
        let theme = ThemeManager.shared.theme
        let ph = FlippedView(frame: bounds)
        ph.autoresizingMask = [.width, .height]
        ph.wantsLayer = true
        ph.layer?.backgroundColor = theme.bgLayer1.cgColor
        let icon = GlyphView(name: "pip", size: 30, color: theme.fgSubdued)
        let label = makeLabel(isX ? "Playing in picture-in-picture" : "正在画中画播放",
                              font: Fonts.sans(13.5, .semibold), color: theme.fgSubdued, align: .center)
        let btn = HoverControl()
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 16
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = theme.borderStrong.cgColor
        btn.layer?.backgroundColor = theme.bgLayer2.cgColor
        let btnLabel = makeLabel(isX ? "Return here" : "回到此处", font: Fonts.sans(13, .bold), color: theme.fgBody, align: .center)
        btn.addSubview(btnLabel)
        btn.onClick = { [weak self] in self?.exitOverlay() }
        ph.addSubview(icon); ph.addSubview(label); ph.addSubview(btn)
        addSubview(ph)
        pipPlaceholder = ph

        let lw = label.intrinsicContentSize.width
        let blw = btnLabel.intrinsicContentSize.width
        let cx = bounds.width / 2
        let groupTop = (bounds.height - (30 + 12 + 18 + 12 + 32)) / 2
        icon.frame = NSRect(x: cx - 15, y: groupTop, width: 30, height: 30)
        label.frame = NSRect(x: cx - lw / 2, y: groupTop + 30 + 8, width: lw, height: 18)
        btn.frame = NSRect(x: cx - (blw + 32) / 2, y: groupTop + 30 + 8 + 18 + 12, width: blw + 32, height: 32)
        btnLabel.frame = NSRect(x: 16, y: (32 - btnLabel.intrinsicContentSize.height) / 2, width: blw, height: btnLabel.intrinsicContentSize.height)
    }

    // MARK: - Overlay helpers

    private enum OverlayKind { case fullscreen, pip }

    private func makeOverlayWindow(frame: NSRect, kind: OverlayKind) -> NSWindow {
        let win = PanelWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = kind == .pip
        win.level = kind == .fullscreen ? .screenSaver : .floating
        if kind == .fullscreen {
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        }
        win.isMovableByWindowBackground = false
        return win
    }

    private func enterFullscreenPresentation() {
        guard previousPresentationOptions == nil else { return }
        previousPresentationOptions = NSApp.presentationOptions
        var opts = NSApp.presentationOptions
        opts.subtract([.hideDock, .hideMenuBar])
        opts.formUnion([.autoHideDock, .autoHideMenuBar])
        NSApp.presentationOptions = opts
    }

    private func restorePresentationOptions() {
        guard let previousPresentationOptions else { return }
        NSApp.presentationOptions = previousPresentationOptions
        self.previousPresentationOptions = nil
    }

    private func reparentStage(into host: NSView, frame: NSRect) {
        stage.removeFromSuperview()
        stage.frame = frame
        stage.autoresizingMask = [.width, .height]
        host.addSubview(stage, positioned: .below, relativeTo: nil)
        layoutStage()
    }

    private func exitOverlay() {
        guard mode != .normal else { return }
        mode = .normal
        pipPlaceholder?.removeFromSuperview(); pipPlaceholder = nil
        teardownOverlay()
        stage.removeFromSuperview()
        stage.autoresizingMask = []
        addSubview(stage, positioned: .below, relativeTo: nil)
        stage.frame = bounds
        layoutStage()
        refreshGlyphs()
        applyControlVisibility()
    }

    private func teardownOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow?.contentView = nil
        overlayWindow = nil
        restorePresentationOptions()
    }

    // MARK: - Inline coordinator entry points

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard variant == .inline else { return }
        if window != nil {
            VideoAutoplayCoordinator.shared.register(self)
        } else {
            suspend()
            VideoAutoplayCoordinator.shared.unregister(self)
        }
    }

    /// Coordinator: this inline video became the most-visible one.
    func autoplay() {
        guard variant == .inline, mode == .normal, !userPaused else { return }
        guard !VideoPlaybackStore.shared.isActiveInWindow(key: playbackKey) else { return }
        startPlayback()
    }
    /// Coordinator: another inline video took over.
    func autopause() {
        guard variant == .inline else { return }
        guard !VideoPlaybackStore.shared.isActiveInWindow(key: playbackKey) else { return }
        pausePlayback()
    }
    func suspend() {
        userPaused = false
        if VideoPlaybackStore.shared.isActiveInWindow(key: playbackKey) {
            if mode == .normal { teardownOverlay() }
            return
        }
        pausePlayback()
        if mode == .normal { teardownOverlay() }
    }
    func recycleIfOffscreen() {
        guard variant == .inline, built, !playing, mode == .normal, visibilityScore() == nil else { return }
        teardownPlayer()
        t = 0
        updateUI()
    }

    func visibilityScore() -> (area: CGFloat, centerDist: CGFloat, frac: CGFloat)? {
        guard window != nil, let scroll = enclosingScrollView, let doc = scroll.documentView else { return nil }
        let visible = scroll.documentVisibleRect
        let mine = convert(bounds, to: doc)
        let inter = mine.intersection(visible)
        guard !inter.isNull, inter.height > 0 else { return nil }
        let area = inter.width * inter.height
        let full = bounds.width * bounds.height
        let frac = full > 0 ? area / full : 0
        return (area, abs(inter.midY - visible.midY), frac)
    }

    // MARK: - Window variant entry points (media viewer)

    func activate() {
        guard variant == .window else { return }
        beginWindowPlayback()
        userPaused = false
        startPlayback()
    }
    func deactivate() {
        guard variant == .window else { return }
        if mode != .normal { exitOverlay() }
        pausePlayback()
        endWindowPlayback()
        updateUI()
    }
    func togglePlay() { toggleFromControls() }

    // MARK: - Helpers

    static func parseDur(_ s: String?) -> Double {
        guard let s else { return 30 }
        let parts = s.split(separator: ":").map { Double($0) ?? 0 }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts.first ?? 30
    }
    static func fmt(_ sec: Double) -> String {
        let s = max(0, Int(sec.rounded()))
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

/// Drag host for the picture-in-picture mini-player. Drags from the top handle
/// strip only; tracks global mouse location so motion doesn't feed back as the
/// window moves under the cursor.
private final class PipHostView: FlippedView {
    var onDrag: ((CGPoint) -> Void)?
    var dragHandleHeight: CGFloat = 34
    private var lastGlobal: NSPoint?

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)   // flipped: top = small y
        lastGlobal = pt.y <= dragHandleHeight ? NSEvent.mouseLocation : nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let last = lastGlobal else { return }
        let now = NSEvent.mouseLocation
        onDrag?(CGPoint(x: now.x - last.x, y: now.y - last.y))
        lastGlobal = now
    }
    override func mouseUp(with event: NSEvent) { lastGlobal = nil }
}
