import AppKit

/// A single reply, in X's conversation model. The whole row is tappable: tapping
/// pushes a focal screen where this reply becomes the big post (its parents stack
/// above, its own replies list below) — so sub-replies are reached by drilling in,
/// not by inline nesting. The avatar / name deep-link to the author; the reply /
/// like buttons act in place. Ported from design/project/app/detail.jsx (CommentNode).
///
/// Reuse-friendly for `NSTableView` (`reuseId` + `configure(comment:)`); off-screen
/// rows cost a cheap, view-free `contentHeight` measurement (comments carry no
/// media, so it's pure text math).
final class CommentNodeView: HoverControl {
    static let reuseId = NSUserInterfaceItemIdentifier("comment")
    private static let pad: CGFloat = 16
    private static let avSize: CGFloat = 36
    private static let gap: CGFloat = 11

    private var comment: Comment
    private let width: CGFloat
    private let theme = ThemeManager.shared.theme
    private let onOpenProfile: (Person) -> Void
    private let onMention: (String) -> Void
    private let onReply: (Comment) -> Void
    private let onOpenPost: (Comment) -> Void

    private var likedLocal: Bool
    private var likeBtn: ActionButtonView?

    init(comment: Comment, width: CGFloat,
         onOpenProfile: @escaping (Person) -> Void,
         onMention: @escaping (String) -> Void,
         onReply: @escaping (Comment) -> Void,
         onOpenPost: @escaping (Comment) -> Void) {
        self.comment = comment
        self.width = width
        self.onOpenProfile = onOpenProfile
        self.onMention = onMention
        self.onReply = onReply
        self.onOpenPost = onOpenPost
        self.likedLocal = comment.liked
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        wantsLayer = true
        build()
        onState = { [weak self] h, _ in
            guard let self else { return }
            self.layer?.backgroundColor = (h ? self.theme.bgLayer1 : NSColor.clear).cgColor
        }
        onClick = { [weak self] in guard let self else { return }; self.onOpenPost(self.comment) }
    }
    required init?(coder: NSCoder) { fatalError() }

    var cellHeight: CGFloat { frame.height }

    /// Reset a recycled cell to a new comment and re-lay it out (table reuse).
    func configure(comment: Comment) {
        self.comment = comment
        self.likedLocal = comment.liked
        build()
    }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        likeBtn = nil

        let a = comment.author
        let isX = a.platform == .x
        let topPad: CGFloat = 12
        let contentX = Self.pad + Self.avSize + Self.gap
        let contentW = width - contentX - Self.pad

        let avatar = AvatarView(person: a, size: Self.avSize)
        let aw = HoverControl(frame: NSRect(x: Self.pad, y: topPad, width: Self.avSize, height: Self.avSize))
        avatar.frame = NSRect(x: 0, y: 0, width: Self.avSize, height: Self.avSize)
        aw.addSubview(avatar)
        aw.onClick = { [weak self] in self?.onOpenProfile(a) }
        addSubview(aw)

        var cy = topPad
        let headerH: CGFloat = 18
        var hx = contentX
        let name = makeLabel(a.name, font: Fonts.sans(14.5, .bold), color: theme.fgHeading)
        name.lineBreakMode = .byTruncatingTail
        let nameW = min(name.perchSingleLineWidth, contentW * 0.55)
        name.frame = NSRect(x: hx, y: cy + (headerH - name.intrinsicContentSize.height) / 2, width: nameW, height: name.intrinsicContentSize.height)
        addSubview(name)
        let nameClick = HoverControl(frame: name.frame)
        nameClick.onClick = { [weak self] in self?.onOpenProfile(a) }
        addSubview(nameClick)
        hx += nameW + 6
        if a.verified {
            let v = VerifiedBadge(size: 13)
            v.frame = NSRect(x: hx, y: cy + 2, width: 13, height: 13)
            addSubview(v)
            hx += 13 + 6
        }
        let time = makeLabel("· \(comment.time)", font: Fonts.sans(13.5), color: theme.fgSubdued)
        let timeW = time.perchSingleLineWidth
        if isX {
            let handle = makeLabel("@\(a.handle)", font: Fonts.sans(13.5), color: theme.fgSubdued)
            handle.lineBreakMode = .byTruncatingTail
            let avail = max(0, contentW - (hx - contentX) - timeW - 6)
            let hw = min(handle.perchSingleLineWidth, avail)
            handle.frame = NSRect(x: hx, y: cy + (headerH - handle.intrinsicContentSize.height) / 2, width: hw, height: handle.intrinsicContentSize.height)
            addSubview(handle)
            hx += hw + 6
        }
        time.frame = NSRect(x: hx, y: cy + (headerH - time.intrinsicContentSize.height) / 2, width: timeW, height: time.intrinsicContentSize.height)
        addSubview(time)
        cy += headerH + 2

        let rich = RichTextView(text: comment.text, font: Fonts.sans(14.5), color: theme.fgBody, accent: theme.accent,
                                lineHeightMultiple: 1.46, onMention: { [weak self] h in self?.onMention(h) })
        let textH = rich.height(forWidth: contentW)
        rich.onTap = { [weak self] in guard let self else { return }; self.onOpenPost(self.comment) }
        rich.frame = NSRect(x: contentX, y: cy, width: contentW, height: textH)
        addSubview(rich)
        cy += textH + 8

        // actions: reply + like (design gap 24)
        let reply = ActionButtonView(icon: "reply", count: comment.stats.replies ?? 0, color: theme.accent, active: false,
                                     title: isX ? "Reply" : "回复") { [weak self] in guard let self else { return }; self.onReply(self.comment) }
        reply.frame.origin = CGPoint(x: contentX, y: cy)
        addSubview(reply)
        let likes = comment.stats.likes + (likedLocal ? 1 : 0) - (comment.liked ? 1 : 0)
        let like = ActionButtonView(icon: "heart", count: likes, color: theme.magenta800, active: likedLocal,
                                    title: isX ? "Like" : "赞") { [weak self] in self?.toggleLike() }
        like.frame.origin = CGPoint(x: contentX + reply.contentWidth + 24, y: cy)
        addSubview(like)
        likeBtn = like
        cy += 20

        cy += 12   // bottom padding (design: padding 12px 16px)
        frame = NSRect(x: 0, y: 0, width: width, height: ceil(cy))
        needsDisplay = true
    }

    /// Pure-math row height — mirrors `build()`'s vertical accumulation exactly
    /// (only a throwaway `RichTextView` for text measurement, as `PostCellView`
    /// does). Keep in sync with `build()`.
    static func contentHeight(comment: Comment, width: CGFloat) -> CGFloat {
        let theme = ThemeManager.shared.theme
        let topPad: CGFloat = 12
        let contentX = pad + avSize + gap
        let contentW = width - contentX - pad
        var cy = topPad
        cy += 18 + 2   // header row
        let rich = RichTextView(text: comment.text, font: Fonts.sans(14.5), color: theme.fgBody, accent: theme.accent,
                                lineHeightMultiple: 1.46, onMention: nil)
        cy += rich.height(forWidth: contentW) + 8
        cy += 20        // reply + like row
        cy += 12        // bottom padding
        return ceil(cy)
    }

    private func toggleLike() {
        likedLocal.toggle()
        let likes = comment.stats.likes + (likedLocal ? 1 : 0) - (comment.liked ? 1 : 0)
        likeBtn?.setActive(likedLocal, count: likes)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // bottom hairline (design: borderBottom 1px var(--border-default))
        theme.borderDefault.setStroke()
        let line = NSBezierPath()
        line.move(to: CGPoint(x: 0, y: bounds.height - 0.5))
        line.line(to: CGPoint(x: bounds.width, y: bounds.height - 0.5))
        line.lineWidth = 1
        line.stroke()
    }
}
