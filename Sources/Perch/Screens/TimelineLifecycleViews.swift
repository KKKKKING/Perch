import AppKit

final class TimelineRefreshBar: FlippedView {
    private let indicator = NSView()
    private let theme = ThemeManager.shared.theme

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: UI.columnW, height: 2))
        wantsLayer = true
        layer?.backgroundColor = theme.accent.withAlphaComponent(0.16).cgColor
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = theme.accent.cgColor
        indicator.layer?.cornerRadius = 1
        addSubview(indicator)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        indicator.frame = NSRect(x: 0, y: 0, width: max(80, bounds.width * 0.38), height: 2)
        let anim = CABasicAnimation(keyPath: "position.x")
        anim.fromValue = -indicator.frame.width / 2
        anim.toValue = bounds.width + indicator.frame.width / 2
        anim.duration = 1.0
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.4, 1)
        indicator.layer?.position = CGPoint(x: indicator.frame.midX, y: indicator.frame.midY)
        if indicator.layer?.animation(forKey: "sweep") == nil {
            indicator.layer?.add(anim, forKey: "sweep")
        }
    }
}

/// A "new posts" overlay floating over the top of a timeline feed: either the
/// corner count badge (`NewPostsBadgeView`) or the home column's centred pill
/// (`NewPostsPillView`). The panel positions it by `centeredOverlay`.
protocol TimelineOverlay: AnyObject {
    var overlaySize: NSSize { get }
    var centeredOverlay: Bool { get }
}

final class NewPostsBadgeView: HoverControl {
    private let label: NSTextField
    private let theme = ThemeManager.shared.theme

    init(count: Int, isX: Bool, onClick: @escaping () -> Void) {
        let txt = count > 99 ? "99+" : String(count)
        label = makeLabel(txt, font: Fonts.sans(11.5, .heavy), color: .white, align: .center)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = theme.isDark ? 0.36 : 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        toolTip = isX ? "\(count) new - click to jump" : "\(txt) 条新内容 - 点击查看"
        addSubview(label)
        self.onClick = onClick
        self.onState = { [weak self] h, _ in self?.apply(hover: h) }
        apply(hover: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    var badgeSize: NSSize {
        let w = max(22, label.perchSingleLineWidth + 8)
        return NSSize(width: w, height: 22)
    }

    private func apply(hover: Bool) {
        layer?.backgroundColor = (hover ? theme.accentBgHover : theme.accentBg).cgColor
    }

    override func layout() {
        super.layout()
        label.placeSingleLine(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }
}

/// The home column's "new posts" pill (设计稿 `NewPostsPill`): a centred accent pill
/// with an up-chevron, a facepile of the new authors (from `TimelineShowAlert.usersResults`),
/// and the unread count. Floats over the top of the feed; tap scrolls to top + clears unread.
final class NewPostsPillView: HoverControl {
    private let theme = ThemeManager.shared.theme
    private let chevron: GlyphView
    private let stack: AvatarStackView?
    private let label: NSTextField

    init(count: Int, authors: [Person], isX: Bool, onClick: @escaping () -> Void) {
        let txt = count > 99 ? "99+" : String(count)
        let shown = Array(authors.prefix(3))
        chevron = GlyphView(name: "chevron-up", size: 18, color: .white)
        stack = shown.isEmpty ? nil
            : AvatarStackView(people: shown, size: 24, maxCount: 3, ring: theme.accentBg, overlap: 7)
        label = makeLabel(txt, font: Fonts.sans(14, .heavy), color: .white, align: .center)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = theme.isDark ? 0.36 : 0.16
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        toolTip = isX ? "\(count) new posts from people you follow - click to load"
                      : "\(txt) 条来自关注账号的新内容 · 点击加载"
        addSubview(chevron)
        if let stack { addSubview(stack) }
        addSubview(label)
        self.onClick = onClick
        self.onState = { [weak self] h, _ in self?.apply(hover: h) }
        apply(hover: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var hasAvatars: Bool { stack != nil }
    private let gap: CGFloat = 8

    var pillSize: NSSize {
        let countW = label.perchSingleLineWidth
        let w: CGFloat = hasAvatars
            ? 11 + 18 + gap + (stack?.frame.width ?? 0) + gap + countW + 15
            : 16 + 18 + gap + countW + 16
        return NSSize(width: min(w, UI.columnW - 24), height: 36)
    }

    private func apply(hover: Bool) {
        layer?.backgroundColor = (hover ? theme.accentBgHover : theme.accentBg).cgColor
    }

    override func layout() {
        super.layout()
        var x: CGFloat = hasAvatars ? 11 : 16
        chevron.frame = NSRect(x: x, y: (bounds.height - 18) / 2, width: 18, height: 18)
        x += 18 + gap
        if let stack {
            stack.frame = NSRect(x: x, y: (bounds.height - stack.frame.height) / 2,
                                 width: stack.frame.width, height: stack.frame.height)
            x += stack.frame.width + gap
        }
        label.placeSingleLine(x: x, y: 0, width: bounds.width - x - (hasAvatars ? 15 : 16), height: bounds.height)
    }
}

extension NewPostsBadgeView: TimelineOverlay {
    var overlaySize: NSSize { badgeSize }
    var centeredOverlay: Bool { false }
}

extension NewPostsPillView: TimelineOverlay {
    var overlaySize: NSSize { pillSize }
    var centeredOverlay: Bool { true }
}

/// A torn-seam break in the timeline (设计稿 `GapRow`): two dashed rules flanking
/// a centred pill. Tapping loads down from the post above it; a spinner shows
/// while loading. Mirrors the prototype's single-line layout + bottom border.
final class TimelineGapView: HoverControl {
    static let rowHeight: CGFloat = 57   // 13 + 30 pill + 13 + 1 border

    private let status: TimelineGapStatus
    private let theme = ThemeManager.shared.theme
    private let pill = FlippedView()
    private let glyph: GlyphView
    private let label: NSTextField
    private let border = NSView()

    init(gap: TimelineGap, width: CGFloat, isX: Bool, onClick: @escaping () -> Void) {
        self.status = gap.status
        let loading = gap.status == .loading
        self.glyph = GlyphView(name: loading ? "refresh" : "chevron-down", size: 15, color: theme.accent)
        let text: String
        switch gap.status {
        case .loading: text = isX ? "Loading…" : "加载中…"
        case .error:   text = isX ? "Couldn’t load — retry" : "加载失败，点击重试"
        case .idle:    text = isX ? "Load missing posts" : "加载中断的内容"
        }
        self.label = makeLabel(text, font: Fonts.sans(13, .bold), color: theme.accent)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        wantsLayer = true
        layer?.backgroundColor = theme.bgLayer1.cgColor

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 15
        pill.layer?.borderWidth = 1
        pill.layer?.shadowColor = NSColor.black.cgColor
        pill.layer?.shadowOpacity = theme.isDark ? 0.4 : 0.12
        pill.layer?.shadowRadius = 12
        pill.layer?.shadowOffset = CGSize(width: 0, height: 4)
        pill.addSubview(glyph)
        pill.addSubview(label)
        addSubview(pill)

        border.wantsLayer = true
        border.layer?.backgroundColor = theme.borderDefault.cgColor
        addSubview(border)

        enabledControl = !loading
        self.onClick = loading ? nil : onClick
        self.onState = { [weak self] h, _ in self?.applyHover(h) }
        applyHover(false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var pillWidth: CGFloat { 51 + label.perchSingleLineWidth }   // 14·2 pad + glyph 15 + gap 8

    private func applyHover(_ h: Bool) {
        let active = h && status != .loading
        pill.layer?.backgroundColor = (active ? theme.accentBg : theme.bgBase).cgColor
        pill.layer?.borderColor = (active ? NSColor.clear : theme.borderDefault).cgColor
        let fg = active ? NSColor.white : theme.accent
        label.textColor = fg
        glyph.color = fg
    }

    override func layout() {
        super.layout()
        let pw = pillWidth
        let px = floor((bounds.width - pw) / 2)
        pill.frame = NSRect(x: px, y: 13, width: pw, height: 30)
        glyph.frame = NSRect(x: 14, y: 7.5, width: 15, height: 15)
        label.placeSingleLine(x: 37, y: 0, width: label.perchSingleLineWidth, height: 30)
        border.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        if status == .loading, glyph.layer?.animation(forKey: "spin") == nil { spin() }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pw = pillWidth
        let px = floor((bounds.width - pw) / 2)
        let cy: CGFloat = 28   // pill vertical centre (13 + 15)
        theme.gray400.withAlphaComponent(0.9).setStroke()
        func dash(_ x0: CGFloat, _ x1: CGFloat) {
            guard x1 - x0 > 8 else { return }
            let p = NSBezierPath()
            p.lineWidth = 2
            p.lineCapStyle = .round
            p.setLineDash([5, 5], count: 2, phase: 0)
            p.move(to: CGPoint(x: x0, y: cy))
            p.line(to: CGPoint(x: x1, y: cy))
            p.stroke()
        }
        dash(16, px - 12)
        dash(px + pw + 12, bounds.width - 16)
    }

    private func spin() {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue = -CGFloat.pi * 2
        anim.duration = 0.8
        anim.repeatCount = .infinity
        glyph.wantsLayer = true
        glyph.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glyph.layer?.position = CGPoint(x: glyph.frame.midX, y: glyph.frame.midY)
        glyph.layer?.add(anim, forKey: "spin")
    }
}

final class FeedTabStripView: FlippedView {
    private let selected: HomeFeed
    private let isX: Bool
    private let onSelect: (HomeFeed) -> Void
    private let theme = ThemeManager.shared.theme
    private var buttons: [HoverControl] = []

    static let height: CGFloat = 50

    init(selected: HomeFeed, isX: Bool, onSelect: @escaping (HomeFeed) -> Void) {
        self.selected = selected
        self.isX = isX
        self.onSelect = onSelect
        super.init(frame: NSRect(x: 0, y: 0, width: UI.columnW, height: Self.height))
        bgColor = theme.bgBase
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        for feed in HomeFeed.allCases {
            let on = feed == selected
            let btn = HoverControl()
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 17
            let glyph = GlyphView(name: feed.icon, size: 16, color: on ? theme.fgHeading : theme.fgSubdued)
            let label = makeLabel(isX ? feed.labelX : feed.labelW,
                                  font: Fonts.sans(13, .bold),
                                  color: on ? theme.fgHeading : theme.fgSubdued)
            btn.addSubview(glyph)
            btn.addSubview(label)
            btn.onClick = { [weak self] in self?.onSelect(feed) }
            btn.onState = { h, _ in
                btn.layer?.backgroundColor = (on ? self.theme.bgElevated : (h ? self.theme.gray75 : NSColor.clear)).cgColor
            }
            btn.layer?.backgroundColor = (on ? theme.bgElevated : NSColor.clear).cgColor
            buttons.append(btn)
            addSubview(btn)
        }
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        line.autoresizingMask = [.width, .minYMargin]
        line.frame = NSRect(x: 0, y: Self.height - 1, width: UI.columnW, height: 1)
        addSubview(line)
    }

    override func layout() {
        super.layout()
        let outer = NSRect(x: 12, y: 8, width: bounds.width - 24, height: 34)
        let bg = NSBezierPath(roundedRect: outer, xRadius: 17, yRadius: 17)
        NSGraphicsContext.current?.cgContext.saveGState()
        theme.gray100.setFill()
        bg.fill()
        NSGraphicsContext.current?.cgContext.restoreGState()

        let w = outer.width / CGFloat(max(1, buttons.count))
        for (i, btn) in buttons.enumerated() {
            btn.frame = NSRect(x: outer.minX + CGFloat(i) * w + 3, y: outer.minY + 3,
                               width: w - 6, height: outer.height - 6)
            let glyph = btn.subviews.compactMap { $0 as? GlyphView }.first
            let label = btn.subviews.compactMap { $0 as? NSTextField }.first
            let labelW = label?.perchSingleLineWidth ?? 0
            let groupW = 16 + 7 + labelW
            var x = floor((btn.bounds.width - groupW) / 2)
            glyph?.frame = NSRect(x: x, y: 6, width: 16, height: 16)
            x += 23
            label?.placeSingleLine(x: x, y: 0, width: labelW, height: btn.bounds.height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let outer = NSRect(x: 12, y: 8, width: bounds.width - 24, height: 34)
        theme.gray100.setFill()
        NSBezierPath(roundedRect: outer, xRadius: 17, yRadius: 17).fill()
    }
}

final class TimelineSkeletonView: FlippedView {
    private let width: CGFloat
    private let isX: Bool
    private let theme = ThemeManager.shared.theme

    init(width: CGFloat, isX: Bool, count: Int = 6) {
        self.width = width
        self.isX = isX
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        bgColor = theme.bgBase
        build(count: count)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(count: Int) {
        var y: CGFloat = 0
        let colX: CGFloat = 67          // 16 pad + 40 avatar + 11 gap
        let colRight = width - 16
        let colW = colRight - colX
        for i in 0..<count {
            let media = i % 3 == 1
            let h: CGFloat = media ? 258 : 100
            let row = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: h))
            row.bgColor = theme.bgBase
            row.addSubview(block(x: 16, y: 14, w: 40, h: 40, r: 20))   // avatar
            // name row: name · handle … time
            let nameW: CGFloat = isX ? 104 : 88
            row.addSubview(block(x: colX, y: 16, w: nameW, h: 13, r: 6))
            row.addSubview(block(x: colX + nameW + 8, y: 17, w: isX ? 70 : 46, h: 11, r: 5))
            row.addSubview(block(x: colRight - 30, y: 17, w: 30, h: 11, r: 5))
            // two text lines
            row.addSubview(block(x: colX, y: 35, w: colW * 0.96, h: 12, r: 6))
            row.addSubview(block(x: colX, y: 55, w: colW * 0.82, h: 12, r: 6))
            // optional media + action-stat row
            var ay: CGFloat = 75
            if media {
                row.addSubview(block(x: colX, y: 75, w: colW, h: 150, r: 12))
                ay = 233
            }
            var ax = colX
            for bw in [CGFloat(26), 26, 26, 18] {
                row.addSubview(block(x: ax, y: ay, w: bw, h: 11, r: 5))
                ax += bw + 40
            }
            Screens.addBottomBorder(row, theme: theme)
            addSubview(row)
            y += h
        }
        frame = NSRect(x: 0, y: 0, width: width, height: y)
    }

    private func block(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> NSView {
        skelBlock(x: x, y: y, w: w, h: h, r: r, theme: theme)
    }
}

/// First-load placeholder for the notification center: alternating engagement-card
/// (avatar + kind badge + body + action pills) and aggregate (kind icon + avatar stack)
/// skeleton rows. Mirrors NotifEngageRowView / NotifAggRowView geometry.
final class NotifSkeletonView: FlippedView {
    private let theme = ThemeManager.shared.theme

    init(width: CGFloat, isX: Bool, count: Int = 6) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        bgColor = theme.bgBase
        var y: CGFloat = 0
        for i in 0..<count {
            y += (i % 2 == 0) ? engageRow(y: y, width: width, isX: isX) : aggRow(y: y, width: width)
        }
        frame = NSRect(x: 0, y: 0, width: width, height: y)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func engageRow(y: CGFloat, width: CGFloat, isX: Bool) -> CGFloat {
        let h: CGFloat = 140
        let row = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: h))
        row.bgColor = theme.bgBase
        let colX: CGFloat = 65
        let colW = width - 16 - colX
        row.addSubview(skel(14, 14, 40, 40, 20))                  // avatar
        row.addSubview(skel(14 + 40 - 9, 14 + 40 - 9, 18, 18, 9)) // kind badge
        row.addSubview(skel(colX, 16, isX ? 120 : 96, 14, 7))     // name
        row.addSubview(skel(colX, 38, 92, 11, 5))                 // context line
        row.addSubview(skel(colX, 60, colW * 0.94, 13, 6))        // body line 1
        row.addSubview(skel(colX, 82, colW * 0.72, 13, 6))        // body line 2
        row.addSubview(skel(colX, 104, 64, 28, 14))               // reply pill
        row.addSubview(skel(colX + 72, 104, 30, 28, 14))          // like pill
        Screens.addBottomBorder(row, theme: theme)
        addSubview(row)
        return h
    }

    private func aggRow(y: CGFloat, width: CGFloat) -> CGFloat {
        let h: CGFloat = 96
        let row = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: h))
        row.bgColor = theme.bgBase
        let colX: CGFloat = 48
        let colW = width - 16 - colX
        row.addSubview(skel(14, 16, 20, 20, 10))                  // kind icon
        var ax = colX                                             // avatar stack
        for _ in 0..<3 { row.addSubview(skel(ax, 12, 30, 30, 15)); ax += 22 }
        row.addSubview(skel(colX, 50, colW * 0.66, 13, 6))        // line 1
        row.addSubview(skel(colX, 71, colW * 0.44, 12, 6))        // line 2
        Screens.addBottomBorder(row, theme: theme)
        addSubview(row)
        return h
    }

    private func skel(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSView {
        skelBlock(x: x, y: y, w: w, h: h, r: r, theme: theme)
    }
}

final class DetailSkeletonView: FlippedView {
    private let theme = ThemeManager.shared.theme

    init(width: CGFloat, isX: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        bgColor = theme.bgBase
        let padX: CGFloat = 16
        let textW = width - padX * 2
        var y: CGFloat = 14

        addSubview(skelBlock(x: padX, y: y, w: 46, h: 46, r: 23, theme: theme))
        addSubview(skelBlock(x: padX + 57, y: y + 6, w: isX ? 120 : 90, h: 14, r: 7, theme: theme))
        addSubview(skelBlock(x: padX + 57, y: y + 26, w: isX ? 80 : 50, h: 12, r: 6, theme: theme))
        y += 46

        y += 12
        addSubview(skelBlock(x: padX, y: y, w: textW * 0.94, h: 14, r: 7, theme: theme))
        addSubview(skelBlock(x: padX, y: y + 26, w: textW * 0.88, h: 14, r: 7, theme: theme))
        addSubview(skelBlock(x: padX, y: y + 52, w: textW * 0.60, h: 14, r: 7, theme: theme))
        y += 66

        y += 10
        addSubview(skelBlock(x: padX, y: y, w: textW, h: 180, r: 12, theme: theme))
        y += 180

        y += 14
        addSubview(skelBlock(x: padX, y: y, w: 140, h: 12, r: 6, theme: theme))
        y += 24

        let actRow = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 39))
        Screens.addTopBorder(actRow, theme: theme)
        let span = textW
        let btnW: CGFloat = 24
        let gap = (span - btnW * 5) / 4
        for i in 0..<5 {
            actRow.addSubview(skelBlock(x: padX + CGFloat(i) * (btnW + gap), y: 14, w: btnW, h: 12, r: 6, theme: theme))
        }
        Screens.addBottomBorder(actRow, theme: theme)
        addSubview(actRow)
        y += 39

        addSubview(skelBlock(x: padX, y: y + 13, w: 36, h: 36, r: 18, theme: theme))
        addSubview(skelBlock(x: padX + 47, y: y + 21, w: 120, h: 13, r: 6, theme: theme))
        y += 62

        for _ in 0..<3 {
            let row = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 72))
            row.addSubview(skelBlock(x: padX, y: 12, w: 36, h: 36, r: 18, theme: theme))
            row.addSubview(skelBlock(x: padX + 47, y: 14, w: 90, h: 11, r: 5, theme: theme))
            row.addSubview(skelBlock(x: padX + 47, y: 31, w: textW * 0.80, h: 11, r: 5, theme: theme))
            row.addSubview(skelBlock(x: padX + 47, y: 48, w: textW * 0.55, h: 11, r: 5, theme: theme))
            Screens.addBottomBorder(row, theme: theme)
            addSubview(row)
            y += 72
        }

        frame = NSRect(x: 0, y: 0, width: width, height: y)
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ProfileSkeletonView: FlippedView {
    private let theme = ThemeManager.shared.theme

    init(width: CGFloat, isX: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        bgColor = theme.bgBase
        let padX: CGFloat = 16
        let bioW = width - padX * 2

        let banner = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 124))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = theme.gray100.cgColor
        addSubview(banner)

        addSubview(skelBlock(x: padX, y: 82, w: 90, h: 90, r: 45, theme: theme))
        addSubview(skelBlock(x: width - padX - 100, y: 138, w: 100, h: 34, r: 17, theme: theme))

        var y: CGFloat = 182

        addSubview(skelBlock(x: padX, y: y, w: isX ? 160 : 120, h: 18, r: 9, theme: theme))
        y += 26
        if isX {
            addSubview(skelBlock(x: padX, y: y + 1, w: 100, h: 13, r: 6, theme: theme))
            y += 19
        }

        y += 11
        addSubview(skelBlock(x: padX, y: y, w: bioW * 0.92, h: 12, r: 6, theme: theme))
        addSubview(skelBlock(x: padX, y: y + 20, w: bioW * 0.68, h: 12, r: 6, theme: theme))
        y += 32

        y += 11
        addSubview(skelBlock(x: padX, y: y, w: 14, h: 14, r: 3, theme: theme))
        addSubview(skelBlock(x: padX + 19, y: y + 1, w: 70, h: 13, r: 6, theme: theme))
        addSubview(skelBlock(x: padX + 107, y: y, w: 14, h: 14, r: 3, theme: theme))
        addSubview(skelBlock(x: padX + 126, y: y + 1, w: 90, h: 13, r: 6, theme: theme))
        y += 16

        y += 11
        addSubview(skelBlock(x: padX, y: y, w: 80, h: 13, r: 6, theme: theme))
        addSubview(skelBlock(x: padX + 100, y: y, w: 80, h: 13, r: 6, theme: theme))
        y += 18

        y += 14
        let tabRow = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 41))
        tabRow.addSubview(skelBlock(x: padX, y: 13, w: isX ? 40 : 30, h: 14, r: 6, theme: theme))
        tabRow.addSubview(skelBlock(x: padX + (isX ? 66 : 56), y: 13, w: isX ? 44 : 30, h: 14, r: 6, theme: theme))
        Screens.addBottomBorder(tabRow, theme: theme)
        addSubview(tabRow)
        y += 41

        let colX: CGFloat = 67
        let colRight = width - 16
        let colW = colRight - colX
        for _ in 0..<4 {
            let row = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 100))
            row.bgColor = theme.bgBase
            row.addSubview(skelBlock(x: 16, y: 14, w: 40, h: 40, r: 20, theme: theme))
            let nameW: CGFloat = isX ? 104 : 88
            row.addSubview(skelBlock(x: colX, y: 16, w: nameW, h: 13, r: 6, theme: theme))
            row.addSubview(skelBlock(x: colX + nameW + 8, y: 17, w: isX ? 70 : 46, h: 11, r: 5, theme: theme))
            row.addSubview(skelBlock(x: colRight - 30, y: 17, w: 30, h: 11, r: 5, theme: theme))
            row.addSubview(skelBlock(x: colX, y: 35, w: colW * 0.96, h: 12, r: 6, theme: theme))
            row.addSubview(skelBlock(x: colX, y: 55, w: colW * 0.82, h: 12, r: 6, theme: theme))
            var ax = colX
            for bw in [CGFloat(26), 26, 26, 18] {
                row.addSubview(skelBlock(x: ax, y: 75, w: bw, h: 11, r: 5, theme: theme))
                ax += bw + 40
            }
            Screens.addBottomBorder(row, theme: theme)
            addSubview(row)
            y += 100
        }

        frame = NSRect(x: 0, y: 0, width: width, height: y)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private func skelBlock(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, theme: Theme) -> NSView {
    let v = FlippedView(frame: NSRect(x: x, y: y, width: w, height: h))
    v.wantsLayer = true
    v.layer?.cornerRadius = r
    v.layer?.backgroundColor = theme.gray100.cgColor
    let anim = CABasicAnimation(keyPath: "opacity")
    anim.fromValue = 0.62
    anim.toValue = 1.0
    anim.duration = 0.9
    anim.autoreverses = true
    anim.repeatCount = .infinity
    v.layer?.add(anim, forKey: "pulse")
    return v
}

/// Red warning triangle in a circle (设计稿 error badge): white triangle with a
/// red exclamation on a negative-bg disc.
final class WarningBadge: NSView {
    private let theme = ThemeManager.shared.theme
    override func draw(_ dirtyRect: NSRect) {
        theme.negativeBg.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        let cx = bounds.midX, my = bounds.midY
        let tri = NSBezierPath()
        tri.lineJoinStyle = .round
        tri.lineWidth = 3
        tri.move(to: CGPoint(x: cx, y: my + 11))
        tri.line(to: CGPoint(x: cx - 12, y: my - 9))
        tri.line(to: CGPoint(x: cx + 12, y: my - 9))
        tri.close()
        NSColor.white.setFill(); NSColor.white.setStroke()
        tri.fill(); tri.stroke()
        theme.negativeBg.setFill()
        NSBezierPath(roundedRect: NSRect(x: cx - 1.1, y: my - 5, width: 2.2, height: 8.5),
                     xRadius: 1.1, yRadius: 1.1).fill()
        NSBezierPath(ovalIn: NSRect(x: cx - 1.3, y: my - 8.6, width: 2.6, height: 2.6)).fill()
    }
}

final class TimelineErrorView: FlippedView {
    init(width: CGFloat, isX: Bool, retrying: Bool, onRetry: @escaping () -> Void) {
        let theme = ThemeManager.shared.theme
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 238))
        bgColor = theme.bgBase

        let badge = WarningBadge(frame: NSRect(x: (width - 56) / 2, y: 70, width: 56, height: 56))
        addSubview(badge)

        let title = makeLabel(isX ? "Couldn't load timeline" : "加载失败",
                              font: Fonts.sans(16, .heavy), color: theme.fgHeading, align: .center)
        title.placeSingleLine(x: 28, y: 140, width: width - 56, height: 20)
        addSubview(title)
        let sub = makeLabel(isX ? "Check your connection and try again." : "请检查网络连接后重试。",
                            font: Fonts.sans(14), color: theme.fgSubdued, align: .center)
        sub.placeSingleLine(x: 28, y: 166, width: width - 56, height: 18)
        addSubview(sub)

        let labelText = retrying ? (isX ? "Retrying…" : "重试中…") : (isX ? "Try again" : "重试")
        let labelW = makeLabel(labelText, font: Fonts.sans(14, .bold), color: .white).perchSingleLineWidth
        let btnW = labelW + 24 + 16 + 8
        let btn = HoverControl(frame: NSRect(x: (width - btnW) / 2, y: 196, width: btnW, height: 38))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 19
        btn.layer?.backgroundColor = theme.accentBg.cgColor
        btn.enabledControl = !retrying
        let g = GlyphView(name: "refresh", size: 16, color: .white)
        g.frame = NSRect(x: 18, y: 11, width: 16, height: 16)
        btn.addSubview(g)
        let l = makeLabel(labelText, font: Fonts.sans(14, .bold), color: .white)
        l.placeSingleLine(x: 18 + 16 + 8, y: 0, width: labelW, height: 38)
        btn.addSubview(l)
        if retrying {
            let anim = CABasicAnimation(keyPath: "transform.rotation.z")
            anim.fromValue = 0; anim.toValue = -CGFloat.pi * 2
            anim.duration = 0.8; anim.repeatCount = .infinity
            g.wantsLayer = true
            g.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            g.layer?.position = CGPoint(x: g.frame.midX, y: g.frame.midY)
            g.layer?.add(anim, forKey: "spin")
        } else {
            btn.onClick = onRetry
        }
        btn.onState = { h, _ in
            guard !retrying else { return }
            btn.layer?.backgroundColor = (h ? theme.accentBgHover : theme.accentBg).cgColor
        }
        addSubview(btn)
    }
    required init?(coder: NSCoder) { fatalError() }
}
