import AppKit

/// Action-bar button: icon (+ optional count). Color shifts on hover / active.
final class ActionButtonView: HoverControl {
    private let iconName: String
    private let activeColor: NSColor
    private(set) var active: Bool
    private var count: Int?
    private let glyph: GlyphView
    private var countLabel: NSTextField?
    private let glyphSize: CGFloat

    init(icon: String, count: Int?, color: NSColor, active: Bool, title: String,
         glyphSize: CGFloat = 18, onClick: @escaping () -> Void) {
        self.iconName = icon
        self.activeColor = color
        self.active = active
        self.count = count
        self.glyphSize = glyphSize
        self.glyph = GlyphView(name: icon, size: glyphSize, color: ThemeManager.shared.theme.fgSubdued)
        super.init(frame: .zero)
        toolTip = title
        addSubview(glyph)
        self.onClick = onClick
        self.onState = { [weak self] _, _ in self?.refresh() }
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func rebuild() {
        countLabel?.removeFromSuperview()
        countLabel = nil
        var w = glyphSize
        var h = glyphSize
        if let c = count, c != 0 {
            let l = makeLabel(fmtCount(c), font: Fonts.sans(13, .medium), color: currentColor())
            addSubview(l)
            let lw = max(8, l.perchSingleLineWidth)
            h = max(glyphSize, l.perchSingleLineHeight)
            l.placeSingleLine(x: glyphSize + 6, y: 0, width: lw, height: h)
            countLabel = l
            w = glyphSize + 6 + lw
        }
        glyph.frame = NSRect(x: 0, y: floor((h - glyphSize) / 2), width: glyphSize, height: glyphSize)
        frame = NSRect(x: frame.minX, y: frame.minY, width: w, height: h)
        refresh()
    }

    private func currentColor() -> NSColor {
        if active { return activeColor }
        return hovering ? activeColor : ThemeManager.shared.theme.fgSubdued
    }

    private func refresh() {
        let c = currentColor()
        glyph.color = c
        countLabel?.textColor = c
    }

    func setActive(_ a: Bool, count newCount: Int?) {
        active = a
        count = newCount
        rebuild()
    }

    var contentWidth: CGFloat { frame.width }
}

/// Build a styled popover menu item (icon + label, hover highlight).
func makePopoverMenuItem(icon: String, label: String, danger: Bool = false,
                         width: CGFloat, onClick: @escaping () -> Void) -> HoverControl {
    let theme = ThemeManager.shared.theme
    let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: 38))
    row.wantsLayer = true
    row.layer?.cornerRadius = 9
    let glyph = GlyphView(name: icon, size: 18, color: danger ? theme.negative : theme.fgSubdued)
    glyph.frame = NSRect(x: 11, y: 10, width: 18, height: 18)
    row.addSubview(glyph)
    let lbl = makeLabel(label, font: Fonts.sans(14, .semibold), color: danger ? theme.negative : theme.fgBody)
    lbl.placeSingleLine(x: 11 + 18 + 11, y: 0, width: width - 51, height: 38)
    row.addSubview(lbl)
    row.onState = { h, _ in
        row.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor
    }
    row.onClick = onClick
    return row
}

/// Repost control. Weibo → repost-with-comment sheet. X → small menu (Repost / Quote).
final class RepostActionView: NSView {
    private let post: Post
    private let callbacks: PostCallbacks
    private let button: ActionButtonView
    private let menuUp: Bool

    init(post: Post, count: Int?, active: Bool, callbacks: PostCallbacks, menuUp: Bool = false) {
        self.post = post
        self.callbacks = callbacks
        self.menuUp = menuUp
        let theme = ThemeManager.shared.theme
        self.button = ActionButtonView(icon: "repost", count: count, color: theme.green700, active: active,
                                       title: post.author.platform == .x ? "Repost" : "转发", onClick: {})
        super.init(frame: .zero)
        addSubview(button)
        button.onClick = { [weak self] in self?.handle() }
        frame = NSRect(x: 0, y: 0, width: button.contentWidth, height: button.frame.height)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    var contentWidth: CGFloat { button.contentWidth }

    private func handle() {
        if post.author.platform != .x {
            callbacks.onRepost(post)
        } else {
            showMenu()
        }
    }

    private func showMenu() {
        let theme = ThemeManager.shared.theme
        let w: CGFloat = 184
        let content = FlippedView()
        content.frame = NSRect(x: 0, y: 0, width: w, height: 6 + 38 + 38 + 6)
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 12
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1

        let item1 = makePopoverMenuItem(icon: "repost", label: post.reposted ? "Undo repost" : "Repost", danger: post.reposted, width: w - 12) { [weak self] in
            gPopoverHost?.dismissPopover()
            guard let self else { return }
            self.callbacks.onDirectRepost(self.post)
        }
        item1.frame = NSRect(x: 6, y: 6, width: w - 12, height: 38)
        content.addSubview(item1)
        let item2 = makePopoverMenuItem(icon: "pencil", label: "Quote", width: w - 12) { [weak self] in
            gPopoverHost?.dismissPopover()
            guard let self else { return }
            self.callbacks.onQuote(self.post)
        }
        item2.frame = NSRect(x: 6, y: 6 + 38, width: w - 12, height: 38)
        content.addSubview(item2)

        gPopoverHost?.presentPopover(content, width: w, height: content.frame.height,
                                     anchor: button, edge: menuUp ? .above : .below, dx: -6, dy: 0)
    }
}
