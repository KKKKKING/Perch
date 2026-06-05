import AppKit

// MARK: - Media Viewer

/// Floating media viewer window — image gallery + the shared video player in ONE
/// surface. Horizontal slide carousel; arrows / chevrons / arrow keys switch
/// slides. Chrome (counter, nav, actions) is hover-revealed. Ported from
/// design/project/app/media.jsx.
final class MediaViewerView: FlippedView {
    private let ctx: MediaViewerContext
    private let onClose: () -> Void
    private let theme = ThemeManager.shared.theme
    private weak var panelController: PanelWindowController?
    private var eventMonitor: Any?

    static let defaultSize = CGSize(width: 860, height: 624)
    private var W: CGFloat { bounds.width }
    private var H: CGFloat { bounds.height }
    private let headerH: CGFloat = 38
    private var stageW: CGFloat { W }
    private var stageH: CGFloat { H - headerH }

    private var idx: Int
    private var isX: Bool { ctx.author.platform == .x }
    private var isVideo: Bool { ctx.type == .video }

    private let card = FlippedView()
    private let stage = HoverControl()
    private let track = FlippedView()

    // header pieces (repositioned on resize)
    private var header: FlippedView?
    private var headerLine: NSView?
    private var titleLabel: NSTextField?

    /// A carousel slide: a zoomable image or a shared video player.
    private struct Slide {
        let container: FlippedView
        let zoomView: ZoomableImageScrollView?
        let player: VideoPlayerView?
    }
    private var slides: [Slide] = []

    // hover-revealed chrome
    private let chrome = FadeContainer()
    private var counterLabel: NSTextField?
    private var counterBadge: FlippedView?
    private var prevChevron: HoverControl?
    private var nextChevron: HoverControl?
    private var actionButtons: [HoverControl] = []   // right-anchored: [share, copy?, download]
    private var altOverlay: FlippedView?
    private var toast: NSView?
    private var toastTimer: Timer?
    private var downloadOperation: MediaDownloadOperation?

    init(context: MediaViewerContext, onClose: @escaping () -> Void) {
        self.ctx = context
        self.onClose = onClose
        self.idx = max(0, min(context.initialIndex, context.items.count - 1))
        super.init(frame: NSRect(origin: .zero, size: MediaViewerView.defaultSize))
        wantsLayer = true
        build()
        installMonitor()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        downloadOperation?.cancel()
        removeMonitor()
    }

    private func build() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.black.cgColor
        card.frame = bounds
        addSubview(card)

        buildHeader()
        buildStage()
        activateSlide(idx)
    }

    // ── Header (traffic lights + title) ──
    private func buildHeader() {
        let header = FlippedView(frame: NSRect(x: 0, y: 0, width: W, height: headerH))
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(hex: "#141318").cgColor
        self.header = header
        let line = NSView(frame: NSRect(x: 0, y: headerH - 1, width: W, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        header.addSubview(line)
        self.headerLine = line

        let dots: [(NSColor, Bool)] = [
            (NSColor(hex: "#ff5f57"), true),
            (NSColor(hex: "#febc2e"), false),
            (NSColor(hex: "#28c840"), false),
        ]
        var dx: CGFloat = 14
        for (color, closeable) in dots {
            let dot = HoverControl(frame: NSRect(x: dx, y: (headerH - 12) / 2, width: 12, height: 12))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 6
            dot.layer?.backgroundColor = color.cgColor
            if closeable { dot.onClick = { [weak self] in self?.close() } }
            header.addSubview(dot)
            dx += 20
        }

        let title = NSTextField(labelWithString: ctx.author.name.isEmpty ? (isX ? "Media" : "媒体") : ctx.author.name)
        title.font = Fonts.sans(13, .bold)
        title.textColor = NSColor(hex: "#e7e7ea")
        title.alignment = .center
        title.isBezeled = false; title.drawsBackground = false
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: 80, y: (headerH - title.intrinsicContentSize.height) / 2, width: max(0, W - 160), height: title.intrinsicContentSize.height)
        header.addSubview(title)
        self.titleLabel = title
        card.addSubview(header)
    }

    // ── Stage (carousel + overlays) ──
    private func buildStage() {
        stage.frame = NSRect(x: 0, y: headerH, width: stageW, height: stageH)
        stage.wantsLayer = true
        stage.layer?.masksToBounds = true
        stage.layer?.backgroundColor = NSColor.black.cgColor
        stage.onState = { [weak self] hov, _ in self?.chrome.setShown(hov) }
        card.addSubview(stage)

        let n = ctx.items.count
        track.frame = NSRect(x: -CGFloat(idx) * stageW, y: 0, width: stageW * CGFloat(n), height: stageH)
        stage.addSubview(track)

        for (i, item) in ctx.items.enumerated() {
            let container = FlippedView(frame: NSRect(x: CGFloat(i) * stageW, y: 0, width: stageW, height: stageH))
            container.wantsLayer = true
            container.layer?.backgroundColor = NSColor.black.cgColor
            container.layer?.masksToBounds = true
            var zoom: ZoomableImageScrollView?
            var player: VideoPlayerView?
            if isVideo {
                let vp = VideoPlayerView(item: item, durText: ctx.dur, isX: isX, variant: .window,
                                         playbackKey: ctx.playbackKey)
                vp.frame = container.bounds
                vp.autoresizingMask = [.width, .height]
                container.addSubview(vp)
                player = vp
            } else {
                let z = ZoomableImageScrollView(item)
                z.frame = container.bounds
                z.autoresizingMask = [.width, .height]
                container.addSubview(z)
                zoom = z
            }
            track.addSubview(container)
            slides.append(Slide(container: container, zoomView: zoom, player: player))
        }

        buildChrome()
    }

    private func buildChrome() {
        chrome.frame = stage.bounds
        chrome.autoresizingMask = [.width, .height]
        stage.addSubview(chrome)
        let n = ctx.items.count

        // counter — top-left
        if n > 1 {
            let badge = FlippedView()
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 13
            badge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
            let lbl = makeLabel("\(idx + 1) / \(n)", font: Fonts.sans(12.5, .bold), color: .white)
            let lw = lbl.intrinsicContentSize.width
            badge.frame = NSRect(x: 12, y: 12, width: lw + 22, height: 26)
            lbl.frame = NSRect(x: 11, y: (26 - lbl.intrinsicContentSize.height) / 2, width: lw, height: lbl.intrinsicContentSize.height)
            badge.addSubview(lbl)
            chrome.addSubview(badge)
            counterLabel = lbl
            counterBadge = badge

            // prev / next chevrons
            let prev = chevronButton(rotation: 90) { [weak self] in self?.go(-1) }
            chrome.addSubview(prev)
            prevChevron = prev
            let next = chevronButton(rotation: -90) { [weak self] in self?.go(1) }
            chrome.addSubview(next)
            nextChevron = next
        }

        // actions — top-right, right-anchored: share, copy (images only), download
        let sh = glassButton(glyph: "share", size: 18) {}
        sh.onClick = { [weak self, weak sh] in if let sh { self?.onShare(sender: sh) } }
        chrome.addSubview(sh); actionButtons.append(sh)
        if !isVideo {
            let cp = glassButton(glyph: "copy", size: 18) { [weak self] in self?.onCopy() }
            chrome.addSubview(cp); actionButtons.append(cp)
        }
        let dl = glassButton(glyph: "download", size: 19) { [weak self] in self?.onDownload() }
        chrome.addSubview(dl); actionButtons.append(dl)

        layoutChrome()
        buildAlt()
    }

    /// Reposition chrome children that are anchored to the stage edges/center.
    private func layoutChrome() {
        counterBadge?.frame.origin = CGPoint(x: 12, y: 12)
        prevChevron?.frame.origin = CGPoint(x: 12, y: (stageH - 48) / 2)
        nextChevron?.frame.origin = CGPoint(x: stageW - 12 - 48, y: (stageH - 48) / 2)
        var ax = stageW - 12 - 38
        for btn in actionButtons {
            btn.frame.origin = CGPoint(x: ax, y: 12)
            ax -= 46
        }
    }

    // ── ALT description overlay (images only; always visible, not gated by chrome) ──
    // Rebuilt rather than repositioned: width depends on stageW, which changes the
    // wrapped text height — so a resize re-flows the whole overlay.
    private func layoutAlt() { buildAlt() }
    private func buildAlt() {
        altOverlay?.removeFromSuperview()
        altOverlay = nil
        guard !isVideo, let alt = ctx.items[idx].alt, !alt.isEmpty else { return }

        let container = FlippedView()
        let descW: CGFloat = min(520, stageW * 0.72)
        let descAttr = NSAttributedString(string: alt, attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: NSColor.white
        ])
        let descH = measureHeight(descAttr, width: descW - 26) + 20
        let desc = FlippedView(frame: NSRect(x: 0, y: 0, width: descW, height: descH))
        desc.wantsLayer = true
        desc.layer?.cornerRadius = 10
        desc.layer?.backgroundColor = NSColor(hex: "#0f0e14").withAlphaComponent(0.92).cgColor
        let descLbl = makeLabel(alt, font: Fonts.sans(13.5), color: .white)
        descLbl.lineBreakMode = .byWordWrapping
        descLbl.maximumNumberOfLines = 0
        descLbl.preferredMaxLayoutWidth = descW - 26
        descLbl.frame = NSRect(x: 13, y: 10, width: descW - 26, height: descH - 20)
        desc.addSubview(descLbl)
        desc.isHidden = true
        container.addSubview(desc)
        let y = descH + 8

        let btn = HoverControl(frame: NSRect(x: 0, y: y, width: 40, height: 24))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        btn.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        let bl = makeLabel("ALT", font: Fonts.sans(11, .heavy), color: .white, align: .center)
        bl.frame = NSRect(x: 0, y: (24 - bl.intrinsicContentSize.height) / 2, width: 40, height: bl.intrinsicContentSize.height)
        btn.addSubview(bl)
        btn.onClick = {
            let open = desc.isHidden
            desc.isHidden = !open
            btn.layer?.backgroundColor = (open ? NSColor.white : NSColor.black.withAlphaComponent(0.6)).cgColor
            bl.textColor = open ? NSColor(hex: "#15141a") : .white
        }
        container.addSubview(btn)

        container.frame = NSRect(x: 12, y: stageH - 12 - (y + 24), width: descW, height: y + 24)
        stage.addSubview(container, positioned: .below, relativeTo: chrome)
        altOverlay = container
    }

    // ── Navigation ──
    private func go(_ delta: Int) {
        let n = ctx.items.count
        jump(to: (idx + delta + n) % n)
    }

    private func jump(to newIdx: Int) {
        guard newIdx != idx, newIdx >= 0, newIdx < ctx.items.count else { return }
        slides[idx].player?.deactivate()
        idx = newIdx
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.34
            c.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.4, 1)
            track.animator().setFrameOrigin(NSPoint(x: -CGFloat(idx) * stageW, y: 0))
        }
        activateSlide(idx)
        counterLabel?.stringValue = "\(idx + 1) / \(ctx.items.count)"
        buildAlt()
    }

    private func activateSlide(_ i: Int) {
        guard i < slides.count else { return }
        slides[i].player?.activate()
    }

    private func togglePlayActive() { slides[idx].player?.togglePlay() }

    // ── Actions ──
    private func currentImage() -> NSImage {
        if let img = slides[idx].zoomView?.loadedImage { return img }
        if let img = ctx.items[idx].localImage { return img }
        return MediaViewerView.renderGradient(ctx.items[idx])
    }

    private var shareLink: String {
        (isX ? "https://x.com/" : "https://weibo.com/") + (ctx.author.handle.isEmpty ? "media" : ctx.author.handle) + "/status"
    }

    private func onDownload() {
        guard downloadOperation == nil else { return }
        let item = ctx.items[idx]
        if isVideo {
            guard let raw = item.videoURL, let url = URL(string: raw) else {
                showToast(isX ? "Download failed" : "下载失败", glyphName: "close", glyphColor: theme.negative)
                return
            }
            startDownload(url)
        } else if let raw = item.url, let url = MediaDownloadOperation.originalImageURL(from: raw) {
            startDownload(url)
        } else if MediaViewerView.saveToDownloads(currentImage()) != nil {
            showToast(isX ? "Saved to Downloads" : "已保存到下载")
        } else {
            showToast(isX ? "Download failed" : "下载失败", glyphName: "close", glyphColor: theme.negative)
        }
    }

    private func startDownload(_ url: URL) {
        let op = MediaDownloadOperation(sourceURL: url,
            progress: { [weak self] fraction in
                self?.showDownloadProgress(fraction)
            },
            completion: { [weak self] result in
                guard let self else { return }
                self.downloadOperation = nil
                switch result {
                case .success:
                    self.showToast(self.isX ? "Saved to Downloads" : "已保存到下载")
                case .failure:
                    self.showToast(self.isX ? "Download failed" : "下载失败",
                                   glyphName: "close", glyphColor: self.theme.negative)
                }
            })
        downloadOperation = op
        op.start()
    }

    private func showDownloadProgress(_ fraction: Double?) {
        let text: String
        if let fraction {
            let pct = Int((fraction * 100).rounded())
            text = isX ? "Downloading \(pct)%" : "正在下载 \(pct)%"
        } else {
            text = isX ? "Downloading..." : "正在下载..."
        }
        showToast(text, glyphName: "download", glyphColor: .white, autoDismiss: false)
    }

    private func onCopy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if isVideo {
            pb.setString(shareLink, forType: .string)
            showToast(isX ? "Link copied" : "已复制链接")
        } else {
            pb.writeObjects([currentImage()])
            showToast(isX ? "Image copied" : "已复制图片")
        }
    }
    private func onShare(sender: NSView) {
        let menu = NSMenu()
        let copyLink = menu.addItem(withTitle: isX ? "Copy link" : "复制链接", action: #selector(menuCopyLink), keyEquivalent: "")
        copyLink.target = self
        let save = menu.addItem(withTitle: isX ? "Save to Downloads" : "保存到下载", action: #selector(menuSave), keyEquivalent: "")
        save.target = self
        menu.addItem(.separator())
        let msg = menu.addItem(withTitle: isX ? "Messages" : "信息", action: #selector(menuShareMessages), keyEquivalent: "")
        msg.target = self
        let mail = menu.addItem(withTitle: isX ? "Mail" : "邮件", action: #selector(menuShareMail), keyEquivalent: "")
        mail.target = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }
    @objc private func menuCopyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(shareLink, forType: .string)
        showToast(isX ? "Link copied" : "已复制链接")
    }
    @objc private func menuSave() { onDownload() }
    @objc private func menuShareMessages() { showToast((isX ? "Shared to " : "已分享到") + (isX ? "Messages" : "信息")) }
    @objc private func menuShareMail() { showToast((isX ? "Shared to " : "已分享到") + (isX ? "Mail" : "邮件")) }

    // ── Toast ──
    private func showToast(_ text: String, glyphName: String = "checkmark-circle",
                           glyphColor: NSColor? = nil, autoDismiss: Bool = true) {
        toast?.removeFromSuperview()
        toastTimer?.invalidate()
        let pill = FlippedView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 19
        pill.layer?.backgroundColor = NSColor(hex: "#0f0e14").withAlphaComponent(0.94).cgColor
        let glyph = GlyphView(name: glyphName, size: 17, color: glyphColor ?? theme.green700)
        let lbl = makeLabel(text, font: Fonts.sans(13.5, .semibold), color: .white)
        let lw = lbl.intrinsicContentSize.width
        let w = 16 + 17 + 8 + lw + 16
        let h: CGFloat = 38
        pill.frame = NSRect(x: (stageW - w) / 2, y: stageH - (isVideo ? 76 : 18) - h, width: w, height: h)
        glyph.frame = NSRect(x: 16, y: (h - 17) / 2, width: 17, height: 17)
        lbl.frame = NSRect(x: 16 + 17 + 8, y: (h - lbl.intrinsicContentSize.height) / 2, width: lw, height: lbl.intrinsicContentSize.height)
        pill.addSubview(glyph); pill.addSubview(lbl)
        stage.addSubview(pill)
        toast = pill
        if autoDismiss {
            toastTimer = Timer.scheduledTimer(withTimeInterval: 1.9, repeats: false) { [weak self] _ in
                self?.toast?.removeFromSuperview(); self?.toast = nil
            }
        }
    }

    private func layoutToast() {
        guard let pill = toast else { return }
        let s = pill.frame.size
        pill.frame.origin = CGPoint(x: (stageW - s.width) / 2, y: stageH - (isVideo ? 76 : 18) - s.height)
    }

    // ── Button builders ──
    private func glassButton(glyph: String, size: CGFloat, diameter: CGFloat = 38, onClick: @escaping () -> Void) -> HoverControl {
        let btn = HoverControl(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = diameter / 2
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let g = GlyphView(name: glyph, size: size, color: .white)
        g.frame = NSRect(x: (diameter - size) / 2, y: (diameter - size) / 2, width: size, height: size)
        btn.addSubview(g)
        btn.onState = { h, _ in
            btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(h ? 0.22 : 0.12).cgColor
            btn.layer?.setAffineTransform(h ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity)
        }
        btn.onClick = onClick
        return btn
    }

    private func chevronButton(rotation: CGFloat, onClick: @escaping () -> Void) -> HoverControl {
        let d: CGFloat = 48, size: CGFloat = 22
        let btn = HoverControl(frame: NSRect(x: 0, y: 0, width: d, height: d))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = d / 2
        btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let g = GlyphView(name: "chevron-down", size: size, color: .white)
        g.rotationDegrees = rotation
        g.frame = NSRect(x: (d - size) / 2, y: (d - size) / 2, width: size, height: size)
        btn.addSubview(g)
        btn.onState = { h, _ in
            btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(h ? 0.22 : 0.12).cgColor
            btn.layer?.setAffineTransform(h ? CGAffineTransform(scaleX: 1.05, y: 1.05) : .identity)
        }
        btn.onClick = onClick
        return btn
    }

    // ── Gradient render / save ──
    static func renderGradient(_ item: MediaItem, _ w: CGFloat = 1280, _ h: CGFloat = 720) -> NSImage {
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        let grad = NSGradient(starting: item.grad.c0, ending: item.grad.c1)
        grad?.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -45)
        img.unlockFocus()
        return img
    }
    static func saveToDownloads(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        guard let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return nil }
        let url = dir.appendingPathComponent("perch-media-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // ── Keyboard ──
    private func installMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            switch event.keyCode {
            case 53: self.close(); return nil                 // Esc
            case 123: self.go(-1); return nil                 // ←
            case 124: self.go(1); return nil                  // →
            case 49:                                          // Space
                if self.isVideo { self.togglePlayActive(); return nil }
                return event
            default: return event
            }
        }
    }
    private func removeMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func close() { onClose() }

    override func layout() {
        super.layout()
        card.frame = bounds

        // header spans the full width
        header?.frame = NSRect(x: 0, y: 0, width: W, height: headerH)
        headerLine?.frame = NSRect(x: 0, y: headerH - 1, width: W, height: 1)
        if let t = titleLabel {
            let th = t.intrinsicContentSize.height
            t.frame = NSRect(x: 80, y: (headerH - th) / 2, width: max(0, W - 160), height: th)
        }

        // stage + carousel track + slide containers
        stage.frame = NSRect(x: 0, y: headerH, width: stageW, height: stageH)
        let n = ctx.items.count
        track.frame = NSRect(x: -CGFloat(idx) * stageW, y: 0, width: stageW * CGFloat(n), height: stageH)
        for (i, slide) in slides.enumerated() {
            slide.container.frame = NSRect(x: CGFloat(i) * stageW, y: 0, width: stageW, height: stageH)
        }

        // chrome (auto-resizes to stage) — reposition its anchored children
        layoutChrome()
        layoutAlt()
        layoutToast()

        // re-fit non-zoomed images to the new viewport
        for slide in slides { slide.zoomView?.relayoutForResize() }
    }
}

extension MediaViewerView: PanelContentView {
    var panelPreferredSize: CGSize { Self.defaultSize }
    var panelTitle: String { ctx.author.name.isEmpty ? (isX ? "Media" : "媒体") : ctx.author.name }
    func attach(to panel: PanelWindowController) { panelController = panel }
    var panelResizable: Bool { true }
    var panelMinSize: CGSize { CGSize(width: 480, height: 360) }
}

/// Container whose chrome fades in/out on hover and ignores clicks while hidden.
final class FadeContainer: FlippedView {
    private var shown = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        alphaValue = 0
    }
    required init?(coder: NSCoder) { fatalError() }

    func setShown(_ on: Bool) {
        guard on != shown else { return }
        shown = on
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            animator().alphaValue = on ? 1 : 0
        }
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        shown ? super.hitTest(point) : nil
    }
}
