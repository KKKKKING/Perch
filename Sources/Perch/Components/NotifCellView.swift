import AppKit

/// A notification row. Manual flipped layout; computes its own height for a width
/// via a single dual-path `layout(place:)` (measure vs build), so off-screen rows
/// in `NotificationFeed` cost only a cheap height measurement. One cell class with
/// internal branching renders both the aggregated (like/repost/follow) and the
/// engagement (reply/mention/quote) layouts — symmetric with `PostCellView`.
final class NotifCellView: HoverControl {
    private(set) var notif: NotifItem
    private var unread: Bool
    private let width: CGFloat
    private let isX: Bool
    private let callbacks: NotifCallbacks
    private let theme = ThemeManager.shared.theme

    /// Called when this cell's height changes (an embedded image resolved its aspect).
    var onHeightChanged: (() -> Void)?

    init(notif: NotifItem, unread: Bool, width: CGFloat, isX: Bool, callbacks: NotifCallbacks) {
        self.notif = notif
        self.unread = unread
        self.width = width
        self.isX = isX
        self.callbacks = callbacks
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        wantsLayer = true
        build()
        onState = { [weak self] h, _ in
            guard let self else { return }
            let base = self.unread ? unreadTint(self.theme) : NSColor.clear
            self.layer?.backgroundColor = (h ? self.theme.bgLayer1 : base).cgColor
        }
        onClick = { [weak self] in self?.rowClicked() }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Reset a recycled cell to a new notification and re-lay it out (table reuse).
    func configure(notif: NotifItem, unread: Bool) {
        self.notif = notif
        self.unread = unread
        build()
    }

    /// Compute the row height for `notif` without instantiating avatars, tiles, or
    /// buttons — no image loads. Used for table row heights.
    func measuredHeight(for notif: NotifItem, unread: Bool) -> CGFloat {
        let savedNotif = self.notif, savedUnread = self.unread
        self.notif = notif
        self.unread = unread
        let h = layout(place: false)
        self.notif = savedNotif
        self.unread = savedUnread
        return h
    }

    private func build() { layout(place: true) }

    /// Single layout source. `place == true` builds and positions subviews
    /// (display); `place == false` only accumulates height (measurement).
    @discardableResult
    private func layout(place: Bool) -> CGFloat {
        if place { subviews.forEach { $0.removeFromSuperview() } }
        let h = notif.kind.isAggregated ? layoutAgg(place: place) : layoutEngage(place: place)
        if place {
            frame = NSRect(x: frame.minX, y: frame.minY, width: width, height: h)
            layer?.backgroundColor = (unread ? unreadTint(theme) : NSColor.clear).cgColor
            needsDisplay = true
        }
        return h
    }

    // ── Aggregated row: like / repost / follow ──
    private func layoutAgg(place: Bool) -> CGFloat {
        let callbacks = self.callbacks
        let n = notif
        let kind = n.kind
        let isFollow = kind == .follow
        let lead = n.actors.first
        let others = max(0, n.count - 1)
        let padL: CGFloat = 14, padR: CGFloat = 16, padT: CGFloat = 13, padB: CGFloat = 13
        let iconW: CGFloat = 22, gap: CGFloat = 12
        let contentX = padL + iconW + gap

        // right column (thumb / follow-back pill) reserves width in both paths
        let thumbItem: MediaItem? = isFollow ? nil : (n.post?.media?.items.first ?? n.post?.media?.item)
        var rightW: CGFloat = 0
        if thumbItem != nil { rightW = 46 }
        else if isFollow, n.single { rightW = NotifPillButton.width(textOff: isX ? "Follow back" : "回关") }
        let contentW = width - contentX - padR - (rightW > 0 ? rightW + gap : 0)

        if place {
            let icon = KindIconView(glyph: kind.iconGlyph, char: kind.iconChar, size: 20, color: kind.color(theme))
            icon.frame = NSRect(x: padL + (iconW - 20) / 2, y: padT + 3, width: 20, height: 20)
            addSubview(icon)
        }

        var y = padT
        // avatar stack (constant height: 30 avatar + 2*2 ring)
        if place {
            let ringColor = unread ? unreadTint(theme) : theme.bgBase
            let stack = AvatarStackView(people: n.actors, size: 30, ring: ringColor)
            stack.frame.origin = CGPoint(x: contentX, y: y)
            addSubview(stack)
        }
        y += 34 + 8

        // name + verb line
        let line = NSMutableAttributedString()
        let para = NSMutableParagraphStyle(); para.lineHeightMultiple = 1.4
        let baseAttr: [NSAttributedString.Key: Any] = [.font: Fonts.sans(14.5), .foregroundColor: theme.fgBody, .paragraphStyle: para]
        line.append(NSAttributedString(string: lead?.name ?? "", attributes: [.font: Fonts.sans(14.5, .bold), .foregroundColor: theme.fgHeading, .paragraphStyle: para]))
        if isX {
            if others > 0 { line.append(NSAttributedString(string: " and \(others) other\(others > 1 ? "s" : "")", attributes: baseAttr)) }
            line.append(NSAttributedString(string: " " + kind.verb(true), attributes: baseAttr))
        } else {
            if others > 0 { line.append(NSAttributedString(string: " 和另外 \(others) 个人", attributes: baseAttr)) }
            line.append(NSAttributedString(string: kind.verb(false), attributes: baseAttr))
        }
        line.append(NSAttributedString(string: " · \(n.time)", attributes: [.font: Fonts.sans(14.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: para]))
        let lineH = measureHeight(line, width: contentW)
        if place {
            let lineField = NSTextField(labelWithAttributedString: line)
            lineField.isBezeled = false; lineField.drawsBackground = false
            lineField.lineBreakMode = .byWordWrapping; lineField.maximumNumberOfLines = 0
            lineField.frame = NSRect(x: contentX, y: y, width: contentW, height: lineH)
            addSubview(lineField)
        }
        y += lineH

        // post / bio preview (2-line clamp)
        let preview: String? = (!isFollow ? n.post?.text : (n.single ? n.bio : nil))
        if let preview {
            y += 3
            let para2 = NSMutableParagraphStyle(); para2.lineHeightMultiple = 1.4; para2.lineBreakMode = .byTruncatingTail
            let attr = NSAttributedString(string: preview, attributes: [.font: Fonts.sans(14), .foregroundColor: theme.fgSubdued, .paragraphStyle: para2])
            let lh = ceil(Fonts.sans(14).boundingRectForFont.height * 1.4)
            let h = min(measureHeight(attr, width: contentW), lh * 2 + 2)
            if place {
                let pv = NSTextField(labelWithAttributedString: attr)
                pv.isBezeled = false; pv.drawsBackground = false
                pv.lineBreakMode = .byTruncatingTail; pv.maximumNumberOfLines = 2
                pv.frame = NSRect(x: contentX, y: y, width: contentW, height: h)
                addSubview(pv)
            }
            y += h
        }

        let rowH = max(y + padB, padT + 20 + padB)

        // right view (vertically centered → never drives height)
        if place {
            if let item = thumbItem {
                let v = NotifThumbView(item: item, isVideo: n.post?.media?.type == .video, size: 46)
                v.frame.origin = CGPoint(x: width - padR - rightW, y: (rowH - v.frame.height) / 2)
                addSubview(v)
            } else if isFollow, n.single {
                let alreadyFollowing = lead.map { callbacks.isFollowing($0) } ?? false
                let v = NotifPillButton(textOff: isX ? "Follow back" : "回关", textOn: isX ? "Following" : "已关注",
                                        accent: theme.accent, filledOff: true, filledOn: false, on: alreadyFollowing, toggles: true)
                v.onToggle = { on in if let lead { callbacks.onFollow(lead, on) } }
                v.frame.origin = CGPoint(x: width - padR - rightW, y: (rowH - v.frame.height) / 2)
                addSubview(v)
            }
        }
        return ceil(rowH)
    }

    // ── Engagement card: reply / mention / quote ──
    private func layoutEngage(place: Bool) -> CGFloat {
        let callbacks = self.callbacks
        let n = notif
        let kind = n.kind
        let actor = n.engageActor()
        let post = n.post
        let padL: CGFloat = 14, padR: CGFloat = 16, padT: CGFloat = 13, padB: CGFloat = 11
        let avatarSize: CGFloat = 40, gap: CGFloat = 11
        let contentX = padL + avatarSize + gap
        let contentW = width - contentX - padR

        // avatar + kind badge
        if place, let actor {
            let aw = HoverControl(frame: NSRect(x: padL, y: padT, width: avatarSize, height: avatarSize))
            let av = AvatarView(person: actor, size: avatarSize)
            av.frame = NSRect(x: 0, y: 0, width: avatarSize, height: avatarSize)
            aw.addSubview(av)
            aw.onClick = { callbacks.onSeen(n.id); callbacks.onOpenProfile(actor) }
            addSubview(aw)
            let badge = FlippedView(frame: NSRect(x: padL + avatarSize - 16, y: padT + avatarSize - 16, width: 19, height: 19))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 19 / 2
            badge.layer?.backgroundColor = theme.bgBase.cgColor
            let bi = KindIconView(glyph: kind.iconGlyph, char: kind.iconChar, size: 13, color: kind.color(theme))
            bi.frame = NSRect(x: 3, y: 3, width: 13, height: 13)
            badge.addSubview(bi)
            addSubview(badge)
        }

        var y = padT
        // header row: name + verified + handle + time (constant height)
        if place {
            var hx = contentX
            let name = makeLabel(actor?.name ?? "", font: Fonts.sans(15, .bold), color: theme.fgHeading)
            name.lineBreakMode = .byTruncatingTail
            let nameW = min(name.perchSingleLineWidth, contentW * 0.6)
            name.frame = NSRect(x: hx, y: y, width: nameW, height: 20)
            addSubview(name)
            let nameClick = HoverControl(frame: name.frame)
            nameClick.onClick = { if let actor { callbacks.onSeen(n.id); callbacks.onOpenProfile(actor) } }
            addSubview(nameClick)
            hx += nameW + 6
            if actor?.verified == true {
                let v = VerifiedBadge(size: 14)
                v.frame = NSRect(x: hx, y: y + 3, width: 14, height: 14)
                addSubview(v)
                hx += 14 + 6
            }
            let time = makeLabel("· \(n.time)", font: Fonts.sans(13.5), color: theme.fgSubdued)
            let timeW = time.perchSingleLineWidth
            let timeX = contentX + contentW - timeW
            if isX, let actor {
                let handle = makeLabel("@\(actor.handle)", font: Fonts.sans(13.5), color: theme.fgSubdued)
                handle.lineBreakMode = .byTruncatingTail
                let avail = max(0, timeX - hx - 6)
                let hw = min(handle.perchSingleLineWidth, avail)
                handle.frame = NSRect(x: hx, y: y + 3, width: hw, height: 18)
                addSubview(handle)
            }
            time.frame = NSRect(x: timeX, y: y + 3, width: timeW, height: 18)
            addSubview(time)
        }
        y += 20

        // context line: kind icon + ctx (constant height)
        y += 1
        if place {
            let ctxIcon = KindIconView(glyph: kind.iconGlyph, char: kind.iconChar, size: 13, color: theme.fgSubdued)
            ctxIcon.frame = NSRect(x: contentX, y: y + 1, width: 13, height: 13)
            addSubview(ctxIcon)
            let ctx = makeLabel(kind.ctx(isX), font: Fonts.sans(12.5, .semibold), color: theme.fgSubdued)
            ctx.frame = NSRect(x: contentX + 13 + 5, y: y, width: contentW - 18, height: 16)
            addSubview(ctx)
        }
        y += 16

        // body text
        y += 4
        let bodyText = kind == .reply ? (n.text ?? "") : (post?.text ?? n.text ?? "")
        let rich = RichTextView(text: bodyText, font: Fonts.sans(15), color: theme.fgBody, accent: theme.accent,
                                lineHeightMultiple: 1.46, onMention: place ? { _ in } : nil)
        let textH = rich.height(forWidth: contentW)
        if place {
            rich.frame = NSRect(x: contentX, y: y, width: contentW, height: textH)
            addSubview(rich)
        }
        y += textH

        // reference content
        if kind == .reply, let post {
            y += 9
            let refH = RefPostView.contentHeight(post: post, isX: isX, width: contentW)
            if place {
                let ref = RefPostView(post: post, isX: isX, width: contentW)
                ref.frame.origin = CGPoint(x: contentX, y: y)
                addSubview(ref)
            }
            y += refH
        } else if kind == .mention, let media = post?.media, media.type == .images, !media.items.isEmpty {
            y += 10
            let mh = MediaImagesView.contentHeight(items: media.items, width: contentW)
            if place {
                let mv = MediaImagesView(items: media.items, width: contentW)
                mv.onHeightChanged = { [weak self] in
                    guard let self else { return }
                    self.build()
                    self.onHeightChanged?()
                }
                mv.frame.origin = CGPoint(x: contentX, y: y)
                addSubview(mv)
            }
            y += mh
        } else if kind == .quote, let q = post?.quote {
            y += 9
            let qh = QuotePostView.contentHeight(quote: q, width: contentW)
            if place {
                let qid = post?.quoteSrcId
                let qv = QuotePostView(quote: q, width: contentW,
                    onClick: qid.map { id in { [weak self] in
                        guard let self else { return }
                        self.callbacks.onOpenPost(Post(id: id, author: q.author, time: q.time,
                            text: q.text, media: q.media, stats: Stats(reposts: 0, likes: 0)))
                    }},
                    onOpenProfile: { [weak self] p in self?.callbacks.onOpenProfile(p) })
                qv.frame.origin = CGPoint(x: contentX, y: y)
                addSubview(qv)
            }
            y += qh
        }

        // action buttons (constant height)
        // For reply notifications, n.post is the parent (your post); the actual reply tweet
        // is identified by n.id ("t_<tweetId>"), authored by the actor, with body n.text.
        let actionPost: Post?
        if kind == .reply, let actor {
            let replyId = String(n.id.dropFirst(2))
            let rp = Post(id: replyId, author: actor, time: n.time, text: n.text ?? "",
                          stats: Stats(reposts: 0, likes: 0), replyToId: post?.id)
            actionPost = rp
        } else {
            actionPost = post
        }
        y += 11
        if place {
            let reply = NotifPillButton(textOff: isX ? "Reply" : "回复", glyph: "reply", accent: theme.accent)
            reply.onToggle = { _ in callbacks.onSeen(n.id); callbacks.onReply(actionPost) }
            reply.frame.origin = CGPoint(x: contentX, y: y)
            addSubview(reply)
            let like = NotifPillButton(textOff: nil, glyph: "heart", accent: theme.magenta800, on: actionPost?.liked ?? false, toggles: true)
            like.onToggle = { _ in
                guard let actionPost else { return }
                callbacks.onSeen(n.id)
                callbacks.onAction(actionPost.id, "liked")
            }
            like.frame.origin = CGPoint(x: contentX + reply.contentWidth + 8, y: y)
            addSubview(like)
        }
        y += 30

        return ceil(y + padB)
    }

    private func rowClicked() {
        let n = notif
        callbacks.onSeen(n.id)
        if n.kind.isAggregated {
            let isFollow = n.kind == .follow
            guard !isFollow || n.single else { return }
            if isFollow { if let lead = n.actors.first { callbacks.onOpenProfile(lead) } }
            else if let post = n.post { callbacks.onOpenPost(post) }
        } else if let post = n.post {
            callbacks.onOpenPost(post)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if unread {
            theme.accent.setFill()
            NSBezierPath(ovalIn: NSRect(x: 5, y: 19, width: 6, height: 6)).fill()
        }
        theme.borderDefault.setStroke()
        let p = NSBezierPath()
        p.move(to: CGPoint(x: 0, y: bounds.height - 0.5))
        p.line(to: CGPoint(x: bounds.width, y: bounds.height - 0.5))
        p.lineWidth = 1
        p.stroke()
    }
}
