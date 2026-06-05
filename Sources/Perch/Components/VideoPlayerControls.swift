import AppKit

// MARK: - Control bar

/// The hover-revealed control bar shared by inline + window players.
/// A `HoverControl` so clicks on its background are swallowed (don't reach the
/// body click handler). Ported from the controlBar in videoplayer.jsx.
final class VPControlBar: HoverControl {
    private let variant: VideoVariant
    private let isX: Bool
    private let gradLayer = CAGradientLayer()
    private let seek = VPSeekBar()
    private let timeLabel = NSTextField(labelWithString: "0:00 / 0:00")

    private let playBtn: HoverControl
    private let playGlyph: GlyphView
    private let muteBtn: HoverControl
    private let muteGlyph: GlyphView
    private let gearBtn: HoverControl
    private var pipBtn: HoverControl?
    private var fsBtn: HoverControl?
    private var fsGlyph: GlyphView?

    private let onToggle: () -> Void

    init(variant: VideoVariant, isX: Bool,
         onToggle: @escaping () -> Void,
         onMute: @escaping () -> Void,
         onSeek: @escaping (CGFloat) -> Void,
         onGear: @escaping () -> Void,
         onPip: @escaping () -> Void,
         onFullscreen: @escaping () -> Void) {
        self.variant = variant
        self.isX = isX
        self.onToggle = onToggle
        playGlyph = GlyphView(name: "s2pause", size: 17, color: .white)
        muteGlyph = GlyphView(name: "s2mute", size: 18, color: .white)
        playBtn = VPControlBar.makeButton(glyph: playGlyph, dim: 34)
        muteBtn = VPControlBar.makeButton(glyph: muteGlyph, dim: 34)
        gearBtn = VPControlBar.circleButton(name: "settings", size: 18, dim: 34, title: isX ? "Settings" : "设置", onClick: onGear)
        super.init(frame: .zero)
        wantsLayer = true

        gradLayer.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.64).cgColor]
        gradLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradLayer.endPoint = CGPoint(x: 0.5, y: 1)
        layer?.addSublayer(gradLayer)

        seek.onScrub = onSeek
        addSubview(seek)

        playBtn.onClick = onToggle
        playBtn.toolTip = isX ? "Play / Pause" : "播放 / 暂停"
        addSubview(playBtn)

        timeLabel.font = Fonts.sans(12.5, .semibold)
        timeLabel.textColor = .white
        timeLabel.lineBreakMode = .byClipping
        timeLabel.isBezeled = false; timeLabel.drawsBackground = false
        addSubview(timeLabel)

        muteBtn.onClick = onMute
        addSubview(muteBtn)
        addSubview(gearBtn)

        let g = GlyphView(name: "s2fullscreen", size: 18, color: .white)
        let fs = VPControlBar.makeButton(glyph: g, dim: 34)
        fs.onClick = onFullscreen
        fs.toolTip = isX ? "Fullscreen" : "全屏"
        addSubview(fs); fsBtn = fs; fsGlyph = g

        if variant == .inline {
            let pip = VPControlBar.circleButton(name: "pip", size: 18, dim: 34,
                title: isX ? "Picture in picture" : "画中画", onClick: onPip)
            addSubview(pip); pipBtn = pip
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(t: Double, dur: Double) {
        timeLabel.stringValue = "\(VideoPlayerView.fmt(t)) / \(VideoPlayerView.fmt(dur))"
        seek.setFraction(dur > 0 ? CGFloat(min(1, t / dur)) : 0)
        needsLayout = true
    }
    func setPlaying(_ playing: Bool) { playGlyph.setName(playing ? "s2pause" : "s2play") }
    func setMuted(_ muted: Bool) { muteGlyph.setName(muted ? "s2mute" : "s2volume") }
    func setMode(_ mode: Any) {
        guard let g = fsGlyph else { return }
        let fs = String(describing: mode).contains("fs")
        g.setName(fs ? "s2fullscreenexit" : "s2fullscreen")
        fsBtn?.toolTip = fs ? (isX ? "Exit fullscreen" : "退出全屏") : (isX ? "Fullscreen" : "全屏")
    }

    /// Gear button frame in the parent (stage) coordinate space.
    func gearFrameInStage() -> NSRect {
        NSRect(x: frame.origin.x + gearBtn.frame.origin.x,
               y: frame.origin.y + gearBtn.frame.origin.y,
               width: gearBtn.frame.width, height: gearBtn.frame.height)
    }

    override func layout() {
        super.layout()
        gradLayer.frame = NSRect(x: 0, y: -16, width: bounds.width, height: bounds.height + 16)
        let insetX: CGFloat = 16
        // seek row (top)
        seek.frame = NSRect(x: insetX, y: 8, width: bounds.width - insetX * 2, height: 16)
        // buttons row
        let rowY: CGFloat = 8 + 16 + 4
        let dim: CGFloat = 34
        playBtn.frame = NSRect(x: 12, y: rowY, width: dim, height: dim)

        // right-aligned cluster
        var rx = bounds.width - 12 - dim
        if let fs = fsBtn { fs.frame = NSRect(x: rx, y: rowY, width: dim, height: dim); rx -= dim + 2 }
        if let pip = pipBtn { pip.frame = NSRect(x: rx, y: rowY, width: dim, height: dim); rx -= dim + 2 }
        gearBtn.frame = NSRect(x: rx, y: rowY, width: dim, height: dim); rx -= dim + 2
        muteBtn.frame = NSRect(x: rx, y: rowY, width: dim, height: dim); rx -= 2

        let tw = timeLabel.perchSingleLineWidth
        timeLabel.placeSingleLine(x: rx - 6 - tw, y: rowY, width: tw, height: dim)
    }

    // MARK: button factories

    static func circleButton(name: String, size: CGFloat, dim: CGFloat, title: String,
                             onClick: @escaping () -> Void) -> HoverControl {
        let g = GlyphView(name: name, size: size, color: .white)
        let btn = makeButton(glyph: g, dim: dim)
        btn.onClick = onClick
        btn.toolTip = title
        return btn
    }

    static func makeButton(glyph: GlyphView, dim: CGFloat) -> HoverControl {
        let btn = HoverControl(frame: NSRect(x: 0, y: 0, width: dim, height: dim))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = dim / 2
        let size = glyph.frame.width
        glyph.frame = NSRect(x: (dim - size) / 2, y: (dim - size) / 2, width: size, height: size)
        btn.addSubview(glyph)
        btn.onState = { [weak btn] h, _ in
            guard let btn else { return }
            btn.layer?.backgroundColor = NSColor.white.withAlphaComponent(h ? 0.18 : 0).cgColor
            btn.layer?.setAffineTransform(h ? CGAffineTransform(scaleX: 1.06, y: 1.06) : .identity)
        }
        return btn
    }
}

/// Clickable / draggable seek track: 4px rail, accent fill, 12px white knob.
final class VPSeekBar: HoverControl {
    var onScrub: ((CGFloat) -> Void)?
    private var fraction: CGFloat = 0

    func setFraction(_ f: CGFloat) { fraction = max(0, min(1, f)); needsDisplay = true }

    private func scrub(_ event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        onScrub?(max(0, min(1, pt.x / bounds.width)))
    }
    override func mouseDown(with event: NSEvent) { scrub(event) }
    override func mouseDragged(with event: NSEvent) { scrub(event) }
    override func mouseUp(with event: NSEvent) { scrub(event) }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let theme = ThemeManager.shared.theme
        let h: CGFloat = 4
        let y = (bounds.height - h) / 2
        let rail = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: bounds.width, height: h), xRadius: 2, yRadius: 2)
        NSColor.white.withAlphaComponent(0.3).setFill()
        rail.fill()
        let fw = bounds.width * fraction
        if fw > 0 {
            let fill = NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: fw, height: h), xRadius: 2, yRadius: 2)
            theme.accent.setFill()
            fill.fill()
        }
        let knob = NSBezierPath(ovalIn: NSRect(x: fw - 6, y: (bounds.height - 12) / 2, width: 12, height: 12))
        NSColor.white.setFill()
        knob.fill()
    }
}

// MARK: - Settings menu (speed + quality)

/// Two-level dark-glass settings popover. Ported from the gear menu in videoplayer.jsx.
final class VPSettingsMenu: FlippedView {
    private enum View { case root, speed, quality }
    private var view: View = .root
    private let isX: Bool
    private var speed: Float
    private var quality: String
    private let onSpeed: (Float) -> Void
    private let onQuality: (String) -> Void

    /// Owner sets this to reposition when the panel resizes between levels.
    var onLayoutChange: (() -> Void)?

    private let SPEEDS: [Float] = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    private var QUALS: [(String, String)] {
        [("auto", isX ? "Auto" : "自动"), ("270p", "270p"), ("360p", "360p"),
         ("720p", "720p"), ("1080p", "1080p"), ("2160p", "2160p")]
    }

    private(set) var fittingSize2: CGSize = .zero

    init(isX: Bool, speed: Float, quality: String,
         onSpeed: @escaping (Float) -> Void, onQuality: @escaping (String) -> Void,
         onDismiss: @escaping () -> Void) {
        self.isX = isX
        self.speed = speed
        self.quality = quality
        self.onSpeed = onSpeed
        self.onQuality = onQuality
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.086, alpha: 0.97).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func lang(_ en: String, _ zh: String) -> String { isX ? en : zh }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        let width: CGFloat = view == .root ? 252 : 230
        var rows: [NSView] = []

        if view == .root {
            let speedLabel = speed == 1 ? "1x" : "\(trim(speed))x"
            let qLabel = quality == "auto" ? lang("Auto (2160p)", "自动 (2160p)") : quality
            rows.append(rootRow(icon: "s2play", circled: true, label: lang("Playback speed", "播放速度"),
                                value: speedLabel, width: width) { [weak self] in self?.go(.speed) })
            rows.append(rootRow(icon: "poll", circled: false, label: lang("Quality", "视频质量"),
                                value: qLabel, width: width) { [weak self] in self?.go(.quality) })
        } else if view == .speed {
            rows.append(subHeader(lang("Playback speed", "播放速度"), width: width))
            for sp in SPEEDS {
                rows.append(optRow(label: "\(trim(sp))x", on: sp == speed, width: width) { [weak self] in
                    self?.speed = sp; self?.onSpeed(sp)
                })
            }
        } else {
            rows.append(subHeader(lang("Quality", "视频质量"), width: width))
            for (v, lbl) in QUALS {
                rows.append(optRow(label: lbl, on: v == quality, width: width) { [weak self] in
                    self?.quality = v; self?.onQuality(v)
                })
            }
        }

        var y: CGFloat = 6
        for r in rows {
            r.frame = NSRect(x: 0, y: y, width: width, height: r.frame.height)
            addSubview(r)
            y += r.frame.height
        }
        y += 6
        let maxH: CGFloat = 268
        fittingSize2 = CGSize(width: width, height: min(maxH, y))
        frame = NSRect(x: frame.origin.x, y: frame.origin.y, width: width, height: fittingSize2.height)
        onLayoutChange?()
    }

    private func go(_ v: View) { view = v; rebuild() }
    private func trim(_ f: Float) -> String {
        f == f.rounded() ? String(Int(f)) : String(f).replacingOccurrences(of: "0.", with: ".")
    }

    // MARK: row builders

    private func rootRow(icon: String, circled: Bool, label: String, value: String?, width: CGFloat,
                         onClick: @escaping () -> Void) -> HoverControl {
        let h: CGFloat = 48
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: h))
        row.wantsLayer = true
        let iconSize: CGFloat = circled ? 12 : 18
        let badge = FlippedView(frame: NSRect(x: 16, y: (h - 22) / 2, width: 22, height: 22))
        if circled {
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 11
            badge.layer?.borderWidth = 1.6
            badge.layer?.borderColor = NSColor.white.cgColor
        }
        let g = GlyphView(name: icon, size: iconSize, color: .white)
        g.frame = NSRect(x: (22 - iconSize) / 2 + (circled ? 1 : 0), y: (22 - iconSize) / 2, width: iconSize, height: iconSize)
        badge.addSubview(g)
        row.addSubview(badge)

        let title = makeLabel(label, font: Fonts.sans(15, .semibold), color: .white)
        let tw = title.intrinsicContentSize.width
        title.frame = NSRect(x: 16 + 22 + 14, y: (h - title.intrinsicContentSize.height) / 2, width: tw, height: title.intrinsicContentSize.height)
        row.addSubview(title)
        if let value {
            let val = makeLabel(" · \(value)", font: Fonts.sans(15, .medium), color: NSColor.white.withAlphaComponent(0.55))
            val.frame = NSRect(x: 16 + 22 + 14 + tw, y: (h - val.intrinsicContentSize.height) / 2,
                               width: min(val.intrinsicContentSize.width, width - (16 + 22 + 14 + tw) - 14),
                               height: val.intrinsicContentSize.height)
            row.addSubview(val)
        }
        row.onState = { [weak row] hov, _ in row?.layer?.backgroundColor = NSColor.white.withAlphaComponent(hov ? 0.08 : 0).cgColor }
        row.onClick = onClick
        return row
    }

    private func subHeader(_ title: String, width: CGFloat) -> HoverControl {
        let h: CGFloat = 42
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: h))
        row.wantsLayer = true
        let line = NSView(frame: NSRect(x: 0, y: h - 1, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        row.addSubview(line)
        let chev = GlyphView(name: "chevron-down", size: 18, color: .white)
        chev.rotationDegrees = -90
        chev.frame = NSRect(x: 14, y: (h - 18) / 2, width: 18, height: 18)
        row.addSubview(chev)
        let lbl = makeLabel(title, font: Fonts.sans(15, .bold), color: .white)
        lbl.frame = NSRect(x: 14 + 18 + 12, y: (h - lbl.intrinsicContentSize.height) / 2, width: lbl.intrinsicContentSize.width, height: lbl.intrinsicContentSize.height)
        row.addSubview(lbl)
        row.onClick = { [weak self] in self?.go(.root) }
        return row
    }

    private func optRow(label: String, on: Bool, width: CGFloat, onClick: @escaping () -> Void) -> HoverControl {
        let h: CGFloat = 32
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: h))
        row.wantsLayer = true
        let lbl = makeLabel(label, font: Fonts.sans(14, .medium), color: .white)
        lbl.frame = NSRect(x: 14, y: (h - lbl.intrinsicContentSize.height) / 2, width: lbl.intrinsicContentSize.width, height: lbl.intrinsicContentSize.height)
        row.addSubview(lbl)

        let radio = FlippedView(frame: NSRect(x: width - 14 - 20, y: (h - 20) / 2, width: 20, height: 20))
        radio.wantsLayer = true
        radio.layer?.cornerRadius = 10
        if on {
            radio.layer?.backgroundColor = ThemeManager.shared.theme.accent.cgColor
            let check = GlyphView(name: "checkmark", size: 13, color: .white)
            check.frame = NSRect(x: (20 - 13) / 2, y: (20 - 13) / 2, width: 13, height: 13)
            radio.addSubview(check)
        } else {
            radio.layer?.borderWidth = 1.5
            radio.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        }
        row.addSubview(radio)
        row.onState = { [weak row] hov, _ in row?.layer?.backgroundColor = NSColor.white.withAlphaComponent(hov ? 0.08 : 0).cgColor }
        row.onClick = onClick
        return row
    }
}
