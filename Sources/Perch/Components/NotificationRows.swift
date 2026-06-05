import AppKit

/// Interaction hooks for notification rows.
struct NotifCallbacks {
    var onOpenPost: (Post) -> Void = { _ in }
    var onOpenProfile: (Person) -> Void = { _ in }
    var onReply: (Post?) -> Void = { _ in }
    var onSeen: (String) -> Void = { _ in }
    var onAction: (String, String) -> Void = { _, _ in }
    var onFollow: (Person, Bool) -> Void = { _, _ in }
    var isFollowing: (Person) -> Bool = { _ in false }
}

/// A leading icon for a kind/filter: a glyph, or a literal character ("@").
final class KindIconView: NSView {
    init(glyph: String?, char: String?, size: CGFloat, color: NSColor) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        if let char {
            let l = makeLabel(char, font: Fonts.sans(size + 1, .heavy), color: color, align: .center)
            let lh = l.intrinsicContentSize.height
            l.frame = NSRect(x: 0, y: (size - lh) / 2, width: size, height: lh)
            addSubview(l)
        } else if let glyph {
            let g = GlyphView(name: glyph, size: size, color: color)
            g.frame = bounds
            addSubview(g)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}

/// Overlapping avatar row for aggregated notifications (first avatar on top).
final class AvatarStackView: FlippedView {
    init(people: [Person], size: CGFloat = 30, maxCount: Int = 8, ring: NSColor, overlap: CGFloat = 8) {
        super.init(frame: .zero)
        let shown = Array(people.prefix(maxCount))
        let step = size - overlap
        let ringW: CGFloat = 2
        // add in reverse so the first avatar ends up on top
        for idx in stride(from: shown.count - 1, through: 0, by: -1) {
            let wrap = FlippedView(frame: NSRect(x: CGFloat(idx) * step, y: 0, width: size + ringW * 2, height: size + ringW * 2))
            wrap.wantsLayer = true
            wrap.layer?.cornerRadius = (size + ringW * 2) / 2
            wrap.layer?.backgroundColor = ring.cgColor
            let av = AvatarView(person: shown[idx], size: size)
            av.frame = NSRect(x: ringW, y: ringW, width: size, height: size)
            wrap.addSubview(av)
            addSubview(wrap)
        }
        let w = CGFloat(max(0, shown.count - 1)) * step + size + ringW * 2
        frame = NSRect(x: 0, y: 0, width: w, height: size + ringW * 2)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A small rounded media thumbnail (gradient/image + optional video glyph).
final class NotifThumbView: FlippedView {
    init(item: MediaItem, isVideo: Bool, size: CGFloat = 46) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        let theme = ThemeManager.shared.theme
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1
        let tile = ImageTile(item)
        tile.frame = bounds
        tile.autoresizingMask = [.width, .height]
        addSubview(tile)
        if isVideo {
            let g = GlyphView(name: "play", size: 16, color: .white)
            g.frame = NSRect(x: (size - 16) / 2, y: (size - 16) / 2, width: 16, height: 16)
            addSubview(g)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// A pill button used on rows: Follow-back (two-state), Reply, Like (toggle).
final class NotifPillButton: HoverControl {
    private let theme = ThemeManager.shared.theme
    private let textOff: String?
    private let textOn: String?
    private let glyph: String?
    private let accentColor: NSColor
    private let filledOff: Bool
    private let filledOn: Bool
    private let toggles: Bool
    private var on: Bool
    private let label = NSTextField(labelWithString: "")
    private var glyphView: GlyphView?
    var onToggle: ((Bool) -> Void)?

    init(textOff: String?, textOn: String? = nil, glyph: String? = nil, accent: NSColor,
         filledOff: Bool = false, filledOn: Bool = false, on: Bool = false, toggles: Bool = false) {
        self.textOff = textOff
        self.textOn = textOn
        self.glyph = glyph
        self.accentColor = accent
        self.filledOff = filledOff
        self.filledOn = filledOn
        self.toggles = toggles
        self.on = on
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 15
        layer?.borderWidth = 1
        label.isBezeled = false; label.drawsBackground = false; label.isEditable = false
        label.font = Fonts.sans(13, .bold)
        addSubview(label)
        if let glyph {
            let g = GlyphView(name: glyph, size: 16, color: accent)
            addSubview(g)
            glyphView = g
        }
        onClick = { [weak self] in
            guard let self else { return }
            if self.toggles { self.on.toggle(); self.render(); self.onToggle?(self.on) }
            else { self.onToggle?(self.on) }
        }
        onState = { [weak self] _, _ in self?.render() }
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func render() {
        let filled = on ? filledOn : filledOff
        let text = on ? textOn : textOff
        let c: NSColor = filled ? .white : ((on || hovering) ? accentColor : theme.fgSubdued)
        label.stringValue = text ?? ""
        label.textColor = c
        let lw = (text != nil && !(text!.isEmpty)) ? label.intrinsicContentSize.width : 0
        let gw: CGFloat = glyph != nil ? 16 : 0
        let gap: CGFloat = (gw > 0 && lw > 0) ? 6 : 0
        let iconOnly = lw == 0 && gw > 0
        let maxX = frame.maxX
        let w: CGFloat = iconOnly ? 30 : (13 + gw + gap + lw + 13)
        // keep right edge stable across width changes (rows are right-aligned)
        let newX = frame.width == 30 && frame.minX == 0 ? frame.minX : maxX - w
        frame = NSRect(x: max(0, newX < 0 ? frame.minX : newX), y: frame.minY, width: w, height: 30)
        var x: CGFloat = iconOnly ? (30 - gw) / 2 : 13
        if let g = glyphView {
            g.color = c
            g.frame = NSRect(x: x, y: (30 - 16) / 2, width: 16, height: 16)
            x += gw + gap
        }
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: x, y: (30 - lh) / 2, width: lw, height: lh)
        if filled {
            layer?.backgroundColor = (hovering ? theme.accentBgHover : accentColor).cgColor
            layer?.borderColor = NSColor.clear.cgColor
        } else {
            layer?.backgroundColor = (hovering ? accentColor.withAlphaComponent(0.1) : NSColor.clear).cgColor
            layer?.borderColor = theme.borderStrong.cgColor
        }
    }

    /// Final width for layout (call after the button is created).
    var contentWidth: CGFloat { frame.width }

    /// Width of a text-only (no-glyph) pill without building it — mirrors `render()`.
    static func width(textOff: String?) -> CGFloat {
        guard let textOff, !textOff.isEmpty else { return 30 }
        let l = NSTextField(labelWithString: textOff)
        l.font = Fonts.sans(13, .bold)
        return 13 + l.intrinsicContentSize.width + 13
    }
}

/// Compact "the post they engaged with" reference block (reply rows).
final class RefPostView: FlippedView {
    init(post: Post, isX: Bool, width: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        let theme = ThemeManager.shared.theme
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.backgroundColor = theme.bgLayer1.cgColor
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1

        let padX: CGFloat = 11, padY: CGFloat = 9
        var x = padX
        let hasMedia = post.media?.type == .images && !(post.media?.items.isEmpty ?? true)
        if hasMedia, let item = post.media?.items.first {
            let thumb = NotifThumbView(item: item, isVideo: false, size: 42)
            thumb.frame.origin = CGPoint(x: padX, y: padY)
            addSubview(thumb)
            x += 42 + 10
        }
        let textW = width - x - padX
        let label = makeLabel(isX ? "@\(post.author.handle) · your post" : "\(post.author.name) · 你的微博",
                              font: Fonts.sans(12.5, .semibold), color: theme.fgSubdued)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: x, y: padY, width: textW, height: 16)
        addSubview(label)

        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.45
        para.lineBreakMode = .byTruncatingTail
        let attr = NSAttributedString(string: post.text, attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: para])
        let lineH = ceil(Fonts.sans(13.5).boundingRectForFont.height * 1.45)
        let textH = min(measureHeight(attr, width: textW), lineH * 2 + 2)
        let body = NSTextField(labelWithAttributedString: attr)
        body.isBezeled = false; body.drawsBackground = false
        body.lineBreakMode = .byTruncatingTail
        body.maximumNumberOfLines = 2
        body.frame = NSRect(x: x, y: padY + 16 + 2, width: textW, height: textH)
        addSubview(body)

        let h = max(padY + 42 + padY, padY + 16 + 2 + textH + padY)
        frame = NSRect(x: 0, y: 0, width: width, height: ceil(h))
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Height for `width` without building the view — mirrors `init`.
    static func contentHeight(post: Post, isX: Bool, width: CGFloat) -> CGFloat {
        let theme = ThemeManager.shared.theme
        let padX: CGFloat = 11, padY: CGFloat = 9
        var x = padX
        let hasMedia = post.media?.type == .images && !(post.media?.items.isEmpty ?? true)
        if hasMedia { x += 42 + 10 }
        let textW = width - x - padX
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.45
        para.lineBreakMode = .byTruncatingTail
        let attr = NSAttributedString(string: post.text, attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: para])
        let lineH = ceil(Fonts.sans(13.5).boundingRectForFont.height * 1.45)
        let textH = min(measureHeight(attr, width: textW), lineH * 2 + 2)
        let h = max(padY + 42 + padY, padY + 16 + 2 + textH + padY)
        return ceil(h)
    }
}

/// Unread row tint: `color-mix(in srgb, accent 7%, bg-base)`.
func unreadTint(_ theme: Theme) -> NSColor {
    theme.bgBase.blended(withFraction: 0.07, of: theme.accent) ?? theme.bgBase
}
