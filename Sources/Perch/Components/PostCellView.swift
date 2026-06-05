import AppKit

/// A timeline post card. Manual flipped layout; computes its own height for a width.
final class PostCellView: HoverControl {
    private(set) var post: Post
    private let callbacks: PostCallbacks
    private let isDetail: Bool
    private let cardWidth: CGFloat

    private var moreGlyph: GlyphView?
    private var codeGlyph: HoverControl?
    private var actionBar: FlippedView?
    private let theme = ThemeManager.shared.theme

    /// Avatar centre, cached for drawing the thread connecting line.
    private var avatarCenterX: CGFloat = 36
    private var avatarCenterY: CGFloat = 32

    /// Long posts collapse past this many lines behind a 展开 / Show more button.
    private let foldLineLimit = 10
    private var expanded = false
    /// Called when this cell's height changes (fold toggle / image resolved).
    var onHeightChanged: (() -> Void)?

    init(post: Post, width: CGFloat, callbacks: PostCallbacks) {
        self.post = post
        self.callbacks = callbacks
        self.cardWidth = width
        self.isDetail = false
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))
        wantsLayer = true
        build()
        onState = { [weak self] h, _ in
            guard let self else { return }
            self.layer?.backgroundColor = (h ? self.theme.bgLayer1 : NSColor.clear).cgColor
            self.moreGlyph?.alphaValue = h ? 1 : 0
            self.codeGlyph?.alphaValue = h ? 1 : 0
        }
        onClick = { [weak self] in guard let self else { return }; self.callbacks.onOpenPost(self.post) }
    }
    required init?(coder: NSCoder) { fatalError() }

    var cellHeight: CGFloat { frame.height }

    /// Reset a recycled cell to a new post and re-lay it out (NSTableView reuse).
    func configure(post: Post) {
        self.post = post
        self.expanded = false
        build()
    }

    /// Compute the cell height for `post` without instantiating avatars, media
    /// tiles, or buttons — no image loads. Used for NSTableView row heights so
    /// only on-screen rows pay full view-construction cost.
    func measuredHeight(for post: Post) -> CGFloat {
        let savedPost = self.post, savedExpanded = expanded
        self.post = post
        self.expanded = false
        let h = layout(place: false)
        self.post = savedPost
        self.expanded = savedExpanded
        return h
    }

    private func build() { layout(place: true) }

    /// Single layout source. `place == true` builds and positions subviews
    /// (display); `place == false` only accumulates height (measurement).
    @discardableResult
    private func layout(place: Bool) -> CGFloat {
        if place {
            subviews.forEach { $0.removeFromSuperview() }
            moreGlyph = nil
            codeGlyph = nil
            actionBar = nil
        }
        let a = post.author
        let isX = a.platform == .x
        let padX: CGFloat = 16
        let avatarSize: CGFloat = 40
        let contentX = padX + avatarSize + 11
        let contentW = cardWidth - contentX - padX
        // Thread continuations sit tight against the post above so the line reads as one.
        var top: CGFloat = post.connectTop ? 6 : 12

        // repostedBy / pinned line
        if let rb = post.repostedBy {
            if place { addBadgeLine(icon: "repost", text: "\(rb) \(isX ? "reposted" : "转发了")", y: top) }
            top += 16 + 5
        } else if post.pinned {
            if place { addBadgeLine(icon: "pin", text: isX ? "Pinned" : "置顶", y: top) }
            top += 16 + 5
        }

        let rowTop = top
        avatarCenterX = padX + avatarSize / 2
        avatarCenterY = rowTop + avatarSize / 2

        var cy = rowTop
        // header row
        let headerH: CGFloat = 22
        if place {
            // avatar (clickable → profile)
            let avatar = AvatarView(person: a, size: avatarSize)
            let avatarWrap = HoverControl(frame: NSRect(x: padX, y: rowTop, width: avatarSize, height: avatarSize))
            avatar.frame = NSRect(x: 0, y: 0, width: avatarSize, height: avatarSize)
            avatarWrap.addSubview(avatar)
            avatarWrap.onClick = { [weak self] in guard let self else { return }; self.callbacks.onOpenProfile(self.post.author) }
            addSubview(avatarWrap)

            var hx = contentX
            let name = makeLabel(a.name, font: Fonts.sans(15, .bold), color: theme.fgHeading)
            let nameW = min(name.perchSingleLineWidth, contentW * 0.62)
            name.placeSingleLine(x: hx, y: cy, width: nameW, height: headerH)
            addSubview(name)
            let nameClick = HoverControl(frame: name.frame)
            nameClick.onClick = { [weak self] in guard let self else { return }; self.callbacks.onOpenProfile(self.post.author) }
            addSubview(nameClick)
            hx += nameW + 6
            if a.verified {
                let v = VerifiedBadge(size: 15)
                v.frame = NSRect(x: hx, y: cy + floor((headerH - 15) / 2), width: 15, height: 15)
                addSubview(v)
                hx += 15 + 6
            }
            // more icon at right
            let more = GlyphView(name: "more", size: 18, color: theme.fgSubdued)
            more.frame = NSRect(x: contentX + contentW - 18, y: cy + floor((headerH - 18) / 2), width: 18, height: 18)
            more.alphaValue = 0
            addSubview(more)
            moreGlyph = more

            // debug: raw-JSON button, left of `more`, revealed on hover with it
            var rightInset: CGFloat = 18
            if DebugLog.shared.inline {
                let th = theme
                let codeBtn = HoverControl(frame: NSRect(x: contentX + contentW - 42, y: cy + floor((headerH - 22) / 2), width: 22, height: 22))
                codeBtn.wantsLayer = true
                codeBtn.layer?.cornerRadius = 6
                let cg = GlyphView(name: "code", size: 15, color: th.fgSubdued)
                cg.frame = NSRect(x: (22 - 15) / 2, y: (22 - 15) / 2, width: 15, height: 15)
                codeBtn.addSubview(cg)
                codeBtn.alphaValue = 0
                codeBtn.toolTip = isX ? "View raw data" : "查看原始数据"
                codeBtn.onState = { [weak codeBtn] h, _ in
                    codeBtn?.layer?.backgroundColor = (h ? th.gray100 : NSColor.clear).cgColor
                    cg.color = h ? th.accent : th.fgSubdued
                }
                codeBtn.onClick = { [weak self] in guard let self else { return }; self.callbacks.onOpenJson(self.post) }
                addSubview(codeBtn)
                codeGlyph = codeBtn
                rightInset = 42
            }

            // time
            let time = makeLabel("· \(post.time)", font: Fonts.sans(14), color: theme.fgSubdued)
            let timeW = time.perchSingleLineWidth
            let timeX = contentX + contentW - rightInset - 6 - timeW
            // handle (X only) fills between
            if isX {
                let handle = makeLabel("@\(a.handle)", font: Fonts.sans(14), color: theme.fgSubdued)
                let avail = max(0, timeX - hx - 6)
                let hw = min(handle.perchSingleLineWidth, avail)
                handle.placeSingleLine(x: hx, y: cy, width: hw, height: headerH)
                addSubview(handle)
            }
            time.placeSingleLine(x: timeX, y: cy, width: timeW, height: headerH)
            addSubview(time)
        }

        cy += headerH + 2

        // body text (collapses past foldLineLimit lines behind a Show more button)
        let rich = RichTextView(text: post.text, font: Fonts.sans(15), color: theme.fgBody, accent: theme.accent,
                                lineHeightMultiple: 1.46, onMention: place ? { [weak self] h in self?.callbacks.onMention(h) } : nil)
        let folded = !expanded && rich.lineCount(forWidth: contentW) > foldLineLimit
        if folded { rich.lineLimit = foldLineLimit }
        let textH = rich.height(forWidth: contentW)
        if place {
            rich.onTap = { [weak self] in guard let self else { return }; self.callbacks.onOpenPost(self.post) }
            rich.frame = NSRect(x: contentX, y: cy, width: contentW, height: textH)
            addSubview(rich)
        }
        cy += textH
        if folded {
            cy += 3
            let label = makeLabel(isX ? "Show more" : "展开", font: Fonts.sans(15, .semibold), color: theme.accent)
            let lh = label.perchSingleLineHeight
            if place {
                let lw = label.perchSingleLineWidth
                let btn = HoverControl(frame: NSRect(x: contentX, y: cy, width: lw + 4, height: lh + 4))
                label.frame = NSRect(x: 0, y: 2, width: lw, height: lh)
                btn.addSubview(label)
                btn.onClick = { [weak self] in
                    guard let self else { return }
                    self.expanded = true
                    self.build()
                    self.onHeightChanged?()
                }
                addSubview(btn)
            }
            cy += lh + 4
        }

        // media
        if let media = post.media {
            cy += 10
            let mh: CGFloat
            switch media.type {
            case .images:
                mh = MediaImagesView.contentHeight(items: media.items, width: contentW)
                if place {
                    let items = media.items
                    let miv = MediaImagesView(items: items, width: contentW, onTap: { [weak self] idx in
                        guard let self else { return }
                        self.callbacks.onOpenMedia(MediaViewerContext(items: items, initialIndex: idx,
                                                                      author: self.post.author, type: .images, dur: nil))
                    })
                    miv.onHeightChanged = { [weak self] in
                        guard let self else { return }
                        self.build()
                        self.onHeightChanged?()
                    }
                    miv.frame.origin = CGPoint(x: contentX, y: cy)
                    addSubview(miv)
                }
            case .video:
                let vAspect = max(9.0 / 21.0, media.item?.aspect ?? 16.0 / 9.0)
                mh = ceil(contentW / vAspect)
                if place {
                    let vitem = media.item ?? MediaItem(Gradient("#1c1c22", "#0e0e12"))
                    let playbackKey = VideoPlaybackStore.tweetKey(postId: post.id, item: vitem)
                    let vp = VideoPlayerView(item: vitem, durText: media.dur, isX: isX, variant: .inline,
                        playbackKey: playbackKey,
                        onOpenWindow: { [weak self] in
                            guard let self else { return }
                            self.callbacks.onOpenMedia(MediaViewerContext(items: [vitem], initialIndex: 0,
                                                                          author: media.source ?? self.post.author,
                                                                          type: .video, dur: media.dur,
                                                                          playbackKey: playbackKey))
                        })
                    vp.frame = NSRect(x: contentX, y: cy, width: contentW, height: mh)
                    addSubview(vp)
                }
            case .link:
                mh = LinkCardView.contentHeight(media: media, width: contentW)
                if place {
                    let lc = LinkCardView(media: media, width: contentW)
                    lc.frame.origin = CGPoint(x: contentX, y: cy)
                    addSubview(lc)
                }
            }
            cy += mh
            if media.type == .video, let source = media.source {
                cy += 9
                if place {
                    let sourceView = MediaSourceView(source: source, isX: isX, width: contentW,
                                                     onOpenProfile: { [weak self] person in
                                                         self?.callbacks.onOpenProfile(person)
                                                     })
                    sourceView.frame.origin = CGPoint(x: contentX, y: cy)
                    addSubview(sourceView)
                }
                cy += MediaSourceView.rowHeight
            }
        }

        // quote
        if let q = post.quote {
            cy += 10
            let qh = QuotePostView.contentHeight(quote: q, width: contentW)
            if place {
                let qid = post.quoteSrcId
                let qv = QuotePostView(quote: q, width: contentW,
                    onClick: qid.map { id in { [weak self] in
                        guard let self else { return }
                        self.callbacks.onOpenPost(Post(id: id, author: q.author, time: q.time,
                            text: q.text, media: q.media, stats: Stats(reposts: 0, likes: 0)))
                    }},
                    onOpenProfile: { [weak self] p in self?.callbacks.onOpenProfile(p) },
                    onMention: { [weak self] h in self?.callbacks.onMention(h) },
                    onOpenMedia: { [weak self] ctx in self?.callbacks.onOpenMedia(ctx) })
                qv.frame.origin = CGPoint(x: contentX, y: cy)
                addSubview(qv)
            }
            cy += qh
        }

        // action bar
        cy += 9
        if place {
            let bar = FlippedView(frame: NSRect(x: contentX, y: cy, width: min(340, contentW), height: 20))
            addSubview(bar)
            actionBar = bar
            buildActionBar(into: bar)
        }
        cy += 20

        let bottomGap: CGFloat = post.connectBottom ? 4 : 10
        let bottom = max(cy + bottomGap, rowTop + avatarSize + bottomGap)
        let h = ceil(bottom)
        if place {
            frame = NSRect(x: frame.minX, y: frame.minY, width: cardWidth, height: h)
        }
        return h
    }

    private func addBadgeLine(icon: String, text: String, y: CGFloat) {
        let g = GlyphView(name: icon, size: icon == "pin" ? 13 : 14, color: theme.fgSubdued)
        g.frame = NSRect(x: 51, y: y, width: icon == "pin" ? 13 : 14, height: icon == "pin" ? 13 : 14)
        addSubview(g)
        let l = makeLabel(text, font: Fonts.sans(12.5, .semibold), color: theme.fgSubdued)
        l.placeSingleLine(x: 51 + 18, y: y, width: cardWidth - 51 - 18 - 16, height: 16)
        addSubview(l)
    }

    private func buildActionBar(into bar: FlippedView) {
        bar.subviews.forEach { $0.removeFromSuperview() }
        let isX = post.author.platform == .x
        let reply = ActionButtonView(icon: "reply", count: post.stats.replies, color: theme.accent, active: false,
                                     title: isX ? "Reply" : "评论") { [weak self] in guard let self else { return }; self.callbacks.onReply(self.post) }
        let repost = RepostActionView(post: post, count: post.stats.reposts, active: post.reposted, callbacks: callbacks)
        let like = ActionButtonView(icon: "heart", count: post.stats.likes, color: theme.magenta800, active: post.liked,
                                    title: isX ? "Like" : "赞") { [weak self] in guard let self else { return }; self.callbacks.onAction(self.post.id, "liked") }
        let bookmark = ActionButtonView(icon: "bookmark", count: nil, color: theme.accent, active: post.bookmarked,
                                        title: isX ? "Bookmark" : "收藏") { [weak self] in guard let self else { return }; self.callbacks.onAction(self.post.id, "bookmarked") }
        let share = ActionButtonView(icon: "share", count: nil, color: theme.accent, active: false,
                                     title: isX ? "Share" : "分享") {}
        share.onClick = { [weak self, weak share] in
            guard let self, let share else { return }
            presentShareMenu(post: self.post, anchor: share, callbacks: self.callbacks)
        }

        let items: [NSView] = [reply, repost, like, bookmark, share]
        let widths: [CGFloat] = [reply.contentWidth, repost.contentWidth, like.contentWidth, bookmark.contentWidth, share.contentWidth]
        let total = widths.reduce(0, +)
        let span = bar.frame.width
        let gap = items.count > 1 ? max(0, (span - total) / CGFloat(items.count - 1)) : 0
        var x: CGFloat = 0
        for (i, item) in items.enumerated() {
            item.frame.origin = CGPoint(x: x, y: 0)
            bar.addSubview(item)
            x += widths[i] + gap
        }
    }

    /// Cheap in-place refresh (like/bookmark/repost toggled) — rebuilds the action bar only.
    func refresh(with merged: Post) {
        self.post = merged
        if let bar = actionBar { buildActionBar(into: bar) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Thread connecting line (drawn behind the avatar, which masks the middle).
        if post.connectTop || post.connectBottom {
            theme.gray400.setStroke()
            let line = NSBezierPath()
            line.lineWidth = 2
            let x = avatarCenterX
            if post.connectTop {
                line.move(to: CGPoint(x: x, y: 0))
                line.line(to: CGPoint(x: x, y: avatarCenterY))
            }
            if post.connectBottom {
                line.move(to: CGPoint(x: x, y: avatarCenterY))
                line.line(to: CGPoint(x: x, y: bounds.height))
            }
            line.stroke()
        }
        // Bottom hairline, except between linked thread posts.
        if !post.connectBottom {
            theme.borderDefault.setStroke()
            let p = NSBezierPath()
            p.move(to: CGPoint(x: 0, y: bounds.height - 0.5))
            p.line(to: CGPoint(x: bounds.width, y: bounds.height - 0.5))
            p.lineWidth = 1
            p.stroke()
        }
    }
}
