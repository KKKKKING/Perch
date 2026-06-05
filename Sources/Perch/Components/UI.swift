import AppKit

// ── Layout constants ──
enum UI {
    static let columnW: CGFloat = 374
    static let columnMinW: CGFloat = 320
    static let railW: CGFloat = 78
    static let cardW: CGFloat = 210
}

// ── Fonts: SF Pro via system fonts with mapped weights ──
enum Fonts {
    static func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }
    // semantic helpers
    static func heading(_ size: CGFloat) -> NSFont { sans(size, .heavy) }
    static func title(_ size: CGFloat) -> NSFont { sans(size, .bold) }
    static func body(_ size: CGFloat) -> NSFont { sans(size, .regular) }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

func fmtCount(_ n: Int) -> String {
    if n >= 1_000_000 {
        let v = Double(n) / 1_000_000
        return trimZero(v) + "M"
    }
    if n >= 1000 {
        let v = Double(n) / 1000
        return trimZero(v) + "K"
    }
    return String(n)
}

private func trimZero(_ v: Double) -> String {
    let s = String(format: "%.1f", v)
    return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
}

// ── Column metadata ──
struct ColMeta {
    let icon: String
    let labelX: String
    let labelW: String
}

let COL_META: [String: ColMeta] = [
    "home": ColMeta(icon: "home", labelX: "Home", labelW: "主页"),
    "mentions": ColMeta(icon: "bell", labelX: "Notifications", labelW: "消息"),
    "search": ColMeta(icon: "search", labelX: "Search", labelW: "搜索"),
    "likes": ColMeta(icon: "heart", labelX: "Likes", labelW: "赞过"),
    "bookmarks": ColMeta(icon: "bookmark", labelX: "Bookmarks", labelW: "收藏"),
    "lists": ColMeta(icon: "list", labelX: "Lists", labelW: "列表"),
    "profile": ColMeta(icon: "user", labelX: "Profile", labelW: "我的主页"),
]

func colMeta(_ type: String) -> ColMeta { COL_META[type] ?? COL_META["home"]! }

let COL_TYPES = ["home", "mentions", "search", "bookmarks", "likes", "lists", "profile"]
let ADDABLE = ["home", "mentions", "search", "bookmarks", "likes", "lists", "profile"]
let MORE_TYPES = ["bookmarks", "likes", "lists"]

// ── A simple flipped container (y grows downward) for manual top-down layout ──
class FlippedView: NSView {
    override var isFlipped: Bool { true }
    var bgColor: NSColor? {
        didSet {
            wantsLayer = true
            layer?.backgroundColor = bgColor?.cgColor
        }
    }
}

// ── Label helpers ──
func makeLabel(_ text: String, font: NSFont, color: NSColor, align: NSTextAlignment = .left) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = font
    l.textColor = color
    l.alignment = align
    l.lineBreakMode = .byClipping
    l.isBezeled = false
    l.drawsBackground = false
    l.isEditable = false
    l.isSelectable = false
    return l
}

extension NSFont {
    var perchSingleLineHeight: CGFloat {
        ceil(ascender - descender + leading) + 2
    }
}

extension NSTextField {
    var perchSingleLineHeight: CGFloat {
        let fontH = font?.perchSingleLineHeight ?? 0
        return ceil(max(intrinsicContentSize.height, fontH))
    }

    var perchSingleLineWidth: CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]
        return ceil((stringValue as NSString).size(withAttributes: attrs).width) + 6
    }

    func placeSingleLine(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let h = perchSingleLineHeight
        frame = NSRect(x: x, y: y + floor((height - h) / 2), width: max(0, width), height: h)
    }
}

// ── Text measurement for wrapping multi-line attributed strings ──
func measureHeight(_ attr: NSAttributedString, width: CGFloat) -> CGFloat {
    let textStorage = NSTextStorage(attributedString: attr)
    let textContainer = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
    textContainer.lineFragmentPadding = 0
    let layoutManager = NSLayoutManager()
    layoutManager.addTextContainer(textContainer)
    textStorage.addLayoutManager(layoutManager)
    layoutManager.glyphRange(for: textContainer)
    return ceil(layoutManager.usedRect(for: textContainer).height)
}

// ── Geometry helpers for flipped layout ──
extension NSView {
    /// Place a subview at top-left origin (x, y) with size in a flipped parent.
    func place(_ child: NSView, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        child.frame = NSRect(x: x, y: y, width: w, height: h)
        if child.superview !== self { addSubview(child) }
    }
}

// ── Popover hosting (custom styled menus anchored to a source view) ──
enum PopoverEdge { case below, right, above, custom }

protocol PopoverHost: AnyObject {
    /// Present `content` (sized w×h) anchored relative to `anchor`.
    func presentPopover(_ content: NSView, width: CGFloat, height: CGFloat,
                        anchor: NSView, edge: PopoverEdge, dx: CGFloat, dy: CGFloat)
    func dismissPopover()
}

weak var gPopoverHost: PopoverHost?

// ── Interaction callbacks threaded through post / screen views ──
struct PostCallbacks {
    var onAction: (String, String) -> Void = { _, _ in }
    var onReply: (Post) -> Void = { _ in }
    var onQuote: (Post) -> Void = { _ in }
    var onRepost: (Post) -> Void = { _ in }
    var onDirectRepost: (Post) -> Void = { _ in }
    var onOpenPost: (Post) -> Void = { _ in }
    var onOpenJson: (Post) -> Void = { _ in }
    var onOpenProfile: (Person) -> Void = { _ in }
    var onMention: (String) -> Void = { _ in }
    var onOpenMedia: (MediaViewerContext) -> Void = { _ in }
    var onFollow: (Person, Bool) -> Void = { _, _ in }
    var onMute: (Person, Bool) -> Void = { _, _ in }
    var onBlock: (Person, Bool) -> Void = { _, _ in }
    var onCopyLink: (Post) -> Void = { _ in }
    var onAddToLists: (Post, NSView) -> Void = { _, _ in }
    var onMuteConversation: (Post) -> Void = { _ in }
    var onOpenURL: (String) -> Void = { _ in }
    var onEmbed: (Post) -> Void = { _ in }
    var onToast: (String) -> Void = { _ in }
    // relationship-state lookups for menu labels
    var isFollowing: (Person) -> Bool = { _ in false }
    var isMuted: (Person) -> Bool = { _ in false }
    var isBlocked: (Person) -> Bool = { _ in false }
}

// rounded background helper
func roundedLayerView(radius: CGFloat, fill: NSColor?, border: NSColor? = nil, borderWidth: CGFloat = 0) -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.cornerRadius = radius
    v.layer?.masksToBounds = true
    if let fill { v.layer?.backgroundColor = fill.cgColor }
    if let border {
        v.layer?.borderColor = border.cgColor
        v.layer?.borderWidth = borderWidth
    }
    return v
}
