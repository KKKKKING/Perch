import AppKit

/// Circular initials avatar (PAvatar). Color comes from the person + current theme.
final class AvatarView: NSView {
    private let person: Person
    private let diameter: CGFloat
    private let label = NSTextField(labelWithString: "")
    private let overlay = CALayer()
    private let imageLayer = CALayer()

    init(person: Person, size: CGFloat) {
        self.person = person
        self.diameter = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.masksToBounds = true
        let theme = ThemeManager.shared.theme
        layer?.backgroundColor = person.color(theme).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.borderWidth = 1

        // bottom inner shadow approximation
        overlay.frame = bounds
        let grad = CAGradientLayer()
        grad.frame = bounds
        grad.colors = [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.18).cgColor]
        grad.startPoint = CGPoint(x: 0.5, y: 0.4)
        grad.endPoint = CGPoint(x: 0.5, y: 0.0)
        overlay.addSublayer(grad)
        layer?.addSublayer(overlay)

        label.stringValue = AvatarView.initials(person.name)
        label.font = NSFont.systemFont(ofSize: size * 0.42, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
        label.placeSingleLine(x: 0, y: 0, width: size, height: size)

        // real profile image (faded in over the initials) when available
        if let url = person.avatarURL, !url.isEmpty {
            imageLayer.frame = bounds
            imageLayer.contentsGravity = .resizeAspectFill
            imageLayer.masksToBounds = true
            imageLayer.opacity = 0
            layer?.addSublayer(imageLayer)
            ImageLoader.shared.image(for: AvatarView.upscale(url), size: .small) { [weak self] img in
                guard let self, let img else { return }
                var rect = CGRect(origin: .zero, size: img.size)
                guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
                self.imageLayer.contents = cg
                self.label.isHidden = true        // hide initials once the photo loads
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.22
                self.imageLayer.opacity = 1
                self.imageLayer.add(fade, forKey: "fade")
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// X serves `*_normal.jpg` (48px); request a sharper variant for retina.
    static func upscale(_ url: String) -> String {
        url.replacingOccurrences(of: "_normal.", with: "_400x400.")
    }

    override func layout() {
        super.layout()
        overlay.frame = bounds
        overlay.sublayers?.forEach { $0.frame = bounds }
        imageLayer.frame = bounds
        label.placeSingleLine(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " }).map { String($0) }
        let firsts = words.prefix(2).compactMap { $0.first }.map { String($0) }
        return firsts.joined()
    }
}

/// Small platform badge: X (𝕏) or Weibo (微).
final class PlatformBadge: NSView {
    init(platform: Platform, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.masksToBounds = true
        let theme = ThemeManager.shared.theme
        let isX = platform == .x
        layer?.backgroundColor = (isX ? theme.gray1000 : NSColor(hex: "#e6162d")).cgColor
        layer?.borderColor = theme.bgLayer1.cgColor
        layer?.borderWidth = 2

        let label = NSTextField(labelWithString: isX ? "𝕏" : "微")
        label.font = NSFont.systemFont(ofSize: isX ? size * 0.6 : size * 0.56, weight: .heavy)
        label.textColor = .white
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
        label.isSelectable = false
        label.placeSingleLine(x: 0, y: 0, width: size, height: size)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}

/// Unread count pill.
final class NotifBadge: NSView {
    private let attrStr: NSAttributedString
    private let textSize: CGSize
    private let ringW: CGFloat
    private let contentH: CGFloat

    init?(count: Int, maxCount: Int = 99, ring: NSColor?, mini: Bool = false) {
        if count <= 0 { return nil }
        let txt = count > maxCount ? "\(maxCount)+" : String(count)
        let wide = txt.count > 1
        let h: CGFloat = mini ? 15 : 17
        let pad: CGFloat = wide ? (mini ? 3.5 : 4.5) : 0
        let rw: CGFloat = ring != nil ? 2 : 0
        let fontSize: CGFloat = mini ? 9.5 : 10.5
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let kern = -fontSize * 0.02
        let ps = NSMutableParagraphStyle()
        ps.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white, .kern: kern,
            .paragraphStyle: ps,
        ]
        self.attrStr = NSAttributedString(string: txt, attributes: attrs)
        self.textSize = attrStr.size()
        self.ringW = rw
        self.contentH = h

        let contentW = max(h, ceil(textSize.width) + pad * 2)
        let totalW = contentW + rw * 2
        let totalH = h + rw * 2
        super.init(frame: NSRect(x: 0, y: 0, width: totalW, height: totalH))
        wantsLayer = true
        let theme = ThemeManager.shared.theme
        layer?.backgroundColor = theme.negativeBg.cgColor
        layer?.cornerRadius = totalH / 2
        layer?.masksToBounds = true
        if let ring {
            layer?.borderColor = ring.cgColor
            layer?.borderWidth = rw
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let cw = bounds.width - ringW * 2
        let x = ringW + (cw - textSize.width) / 2
        let y = ringW + (contentH - textSize.height) / 2
        attrStr.draw(at: NSPoint(x: x, y: y))
    }
}

/// Verified seal badge (accent seal + white check).
final class VerifiedBadge: NSView {
    init(size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        let g = GlyphView(name: "verified", size: size, color: ThemeManager.shared.theme.accent)
        addSubview(g)
        g.frame = bounds
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}
