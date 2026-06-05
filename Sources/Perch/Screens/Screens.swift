import AppKit

enum Screens {

    /// Build a vertical timeline list as a flipped document view.
    static func timelineList(posts: [Post], width: CGFloat, isX: Bool, isSearch: Bool,
                             callbacks: PostCallbacks) -> FlippedView {
        timelineRows(rows: posts.map { .post($0) }, status: posts.isEmpty ? .empty : .ready,
                     width: width, isX: isX, isSearch: isSearch, type: "home",
                     refreshing: false, callbacks: callbacks,
                     onRetry: {}, onGap: { _ in },
                     onWillReflow: nil, onDidReflow: nil)
    }

    static func timelineRows(rows: [TimelineRow], status: TimelineStatus, width: CGFloat,
                             isX: Bool, isSearch: Bool, type: String, refreshing: Bool,
                             callbacks: PostCallbacks, onRetry: @escaping () -> Void,
                             onGap: @escaping (String) -> Void,
                             onWillReflow: (() -> Void)?,
                             onDidReflow: (() -> Void)?) -> FlippedView {
        let theme = ThemeManager.shared.theme
        let doc = FeedDocument(width: width)
        doc.bgColor = theme.bgBase
        if isSearch {
            doc.append(searchHeader(isX: isX, width: width))
        }
        if status == .loading && rows.isEmpty {
            doc.append(TimelineSkeletonView(width: width, isX: isX))
        } else if status == .error && rows.isEmpty {
            doc.append(TimelineErrorView(width: width, isX: isX, retrying: refreshing, onRetry: onRetry))
        } else if rows.isEmpty {
            doc.append(timelineEmptyState(isX: isX, type: type, width: width))
        } else {
            for row in rows {
                switch row {
                case .post(let p):
                let cell = PostCellView(post: p, width: width, callbacks: callbacks)
                cell.onHeightChanged = { [weak doc] in
                    onWillReflow?()
                    doc?.restack()
                    onDidReflow?()
                }
                doc.append(cell)
                case .gap(let gap):
                    doc.append(TimelineGapView(gap: gap, width: width, isX: isX) {
                        onGap(gap.id)
                    })
                }
            }
        }
        doc.restack()
        return doc
    }

    static func timelineEmptyState(isX: Bool, type: String, width: CGFloat) -> FlippedView {
        let copy: (title: String, body: String, icon: String)
        switch type {
        case "likes":
            copy = (isX ? "No likes yet" : "还没有赞过",
                    isX ? "Posts you like will be collected here." : "你点赞过的内容会收藏在这里。", "heart")
        case "bookmarks":
            copy = (isX ? "No bookmarks yet" : "还没有收藏",
                    isX ? "Save posts to read them later." : "收藏内容方便稍后阅读。", "bookmark")
        case "search":
            copy = (isX ? "No results" : "没有结果",
                    isX ? "Try a different search term." : "换个关键词试试。", "search")
        case "lists":
            copy = (isX ? "No lists yet" : "还没有列表",
                    isX ? "Create or follow Lists on X, then pick one from the header menu." : "在 X 上创建或关注列表后，从顶部菜单选择。", "list")
        case "profile":
            copy = (isX ? "No posts yet" : "还没有动态",
                    isX ? "When they post, it will appear here." : "TA 发布的内容会出现在这里。", "user")
        default:
            copy = (isX ? "Your timeline is empty" : "时间线还是空的",
                    isX ? "Follow some people and their posts will show up here." : "关注一些人，他们的内容会出现在这里。", "home")
        }
        return iconEmptyState(title: copy.title, body: copy.body, icon: copy.icon, width: width)
    }

    /// Centred empty state with a circular glyph badge (设计稿 `TimelineEmpty`).
    static func iconEmptyState(title: String, body: String, icon: String, width: CGFloat) -> FlippedView {
        let theme = ThemeManager.shared.theme
        let v = FlippedView()
        v.bgColor = theme.bgBase
        let top: CGFloat = 72

        let badge = FlippedView(frame: NSRect(x: (width - 56) / 2, y: top, width: 56, height: 56))
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 28
        badge.layer?.backgroundColor = theme.gray100.cgColor
        let g = GlyphView(name: icon, size: 28, color: theme.fgSubdued)
        g.frame = NSRect(x: 14, y: 14, width: 28, height: 28)
        badge.addSubview(g)
        v.addSubview(badge)

        var y = top + 56 + 14
        let t = makeLabel(title, font: Fonts.sans(16, .heavy), color: theme.fgHeading, align: .center)
        t.placeSingleLine(x: 28, y: y, width: width - 56, height: 22)
        v.addSubview(t)
        y += 22 + 5

        let bodyW = min(CGFloat(280), width - 56)
        let s = makeLabel(body, font: Fonts.sans(14), color: theme.fgSubdued, align: .center)
        s.maximumNumberOfLines = 0
        s.lineBreakMode = .byWordWrapping
        s.preferredMaxLayoutWidth = bodyW
        let bodyH = s.sizeThatFits(NSSize(width: bodyW, height: .greatestFiniteMagnitude)).height
        s.frame = NSRect(x: (width - bodyW) / 2, y: y, width: bodyW, height: bodyH)
        v.addSubview(s)
        y += bodyH + top

        v.frame = NSRect(x: 0, y: 0, width: width, height: y)
        return v
    }

    static func emptyState(title: String, sub: String, width: CGFloat, top: CGFloat) -> FlippedView {
        let theme = ThemeManager.shared.theme
        let v = FlippedView()
        let t = makeLabel(title, font: Fonts.sans(16, .bold), color: theme.fgHeading, align: .center)
        t.frame = NSRect(x: 28, y: top, width: width - 56, height: 22)
        v.addSubview(t)
        let s = makeLabel(sub, font: Fonts.sans(14), color: theme.fgSubdued, align: .center)
        s.frame = NSRect(x: 28, y: top + 28, width: width - 56, height: 20)
        v.addSubview(s)
        v.frame = NSRect(x: 0, y: 0, width: width, height: top + 28 + 20 + 40)
        return v
    }

    static func searchHeader(isX: Bool, width: CGFloat, query: String = "",
                             onSubmit: ((String) -> Void)? = nil) -> FlippedView {
        let theme = ThemeManager.shared.theme
        let v = FlippedView()
        var y: CGFloat = 12
        // search field — editable, submits the trimmed query on Return
        let field = SearchFieldView(width: width - 32, isX: isX, query: query,
                                    onSubmit: { q in onSubmit?(q) })
        field.frame = NSRect(x: 16, y: y, width: width - 32, height: 38)
        v.addSubview(field)
        y += 38 + 12

        let trends: [[String]] = isX
            ? [["Trending in Design", "#DesignSystems", "12.4K posts"], ["Technology", "Native Mac apps", "8,902 posts"], ["Trending", "#Spectrum2", "3,201 posts"]]
            : [["热搜", "原生桌面客户端", "阅读 1,204万"], ["设计", "深色模式怎么调", "阅读 642万"], ["摄影", "#胶片日记#", "讨论 8.1万"]]
        for t in trends {
            let row = HoverControl(frame: NSRect(x: 0, y: y, width: width, height: 54))
            row.wantsLayer = true
            let l0 = makeLabel(t[0], font: Fonts.sans(12), color: theme.fgSubdued)
            l0.frame = NSRect(x: 16, y: 6, width: width - 32, height: 15)
            row.addSubview(l0)
            let l1 = makeLabel(t[1], font: Fonts.sans(15, .bold), color: theme.fgHeading)
            l1.frame = NSRect(x: 16, y: 21, width: width - 32, height: 19)
            row.addSubview(l1)
            let l2 = makeLabel(t[2], font: Fonts.sans(12), color: theme.fgSubdued)
            l2.frame = NSRect(x: 16, y: 40, width: width - 32, height: 15)
            row.addSubview(l2)
            let term = t[1]
            row.onState = { h, _ in row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor }
            row.onClick = { onSubmit?(term) }
            v.addSubview(row)
            y += 54
        }
        // bottom hairline separating the header from the feed (设计稿)
        let div = NSView(frame: NSRect(x: 0, y: y + 4, width: width, height: 1))
        div.wantsLayer = true
        div.layer?.backgroundColor = theme.borderDefault.cgColor
        v.addSubview(div)
        y += 12
        v.frame = NSRect(x: 0, y: 0, width: width, height: y)
        return v
    }

    // ── Detail screen ──
    /// The focal post of the detail screen — the row that "differs by focus":
    /// identity/text/media/quote/meta → action-row → replies sort header → reply
    /// affordance. Conversation ancestors (above) and replies (below) are their own
    /// rows in `DetailFeed`'s single `NSTableView`; this is returned as one
    /// self-sizing, persistent row in the middle. Re-lays itself in place when async
    /// media resolves its height or Follow is toggled, then notifies the feed so it
    /// can re-measure this row. A short thread stub joins the last ancestor above to
    /// the focal avatar when `hasAncestors`.
    static func focalPost(post: Post, hasAncestors: Bool = false, width: CGFloat,
                          callbacks: PostCallbacks,
                          onMediaHeightChanged: @escaping () -> Void,
                          onFollowToggled: @escaping () -> Void) -> RebuildableDocument {
        let theme = ThemeManager.shared.theme
        let doc = RebuildableDocument()
        doc.bgColor = theme.bgBase
        // Re-runs when a dynamic image resolves its height or Follow is toggled.
        doc.rebuild = { [weak doc] in
        guard let doc else { return }
        doc.subviews.forEach { $0.removeFromSuperview() }
        let a = post.author
        let isX = a.platform == .x
        let padX: CGFloat = 16

        // thread stub — joins the last ancestor row above to this focal avatar
        if hasAncestors {
            let stub = FlippedView(frame: NSRect(x: padX + 19, y: 0, width: 2, height: 14))
            stub.wantsLayer = true
            stub.layer?.backgroundColor = theme.gray400.cgColor
            doc.addSubview(stub)
        }
        var y: CGFloat = 14

        // identity row
        let avatar = AvatarView(person: a, size: 44)
        let aw = HoverControl(frame: NSRect(x: padX, y: y, width: 44, height: 44))
        avatar.frame = NSRect(x: 0, y: 0, width: 44, height: 44)
        aw.addSubview(avatar)
        aw.onClick = { callbacks.onOpenProfile(a) }
        doc.addSubview(aw)

        // header right side: more (···) button + optional Subscribe pill (X)
        var rightX = width - padX
        let moreBtn = HoverControl(frame: NSRect(x: rightX - 32, y: y + 7, width: 32, height: 32))
        moreBtn.wantsLayer = true
        moreBtn.layer?.cornerRadius = 16
        let moreGlyph = GlyphView(name: "more", size: 19, color: theme.fgSubdued)
        moreGlyph.frame = NSRect(x: 6.5, y: 6.5, width: 19, height: 19)
        moreBtn.addSubview(moreGlyph)
        moreBtn.onState = { h, _ in moreBtn.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor }
        moreBtn.onClick = { presentMoreMenu(post: post, anchor: moreBtn, callbacks: callbacks) }
        doc.addSubview(moreBtn)
        rightX -= 32
        // Follow / Following — state-aware, hidden on your own post.
        let ownHandle = TwitterService.shared.account?.handle
        let isOwnPost = ownHandle != nil && a.handle.caseInsensitiveCompare(ownHandle!) == .orderedSame
        if isX && !isOwnPost {
            let following = callbacks.isFollowing(a)
            let label = following ? "Following" : "Follow"
            let lbl = makeLabel(label, font: Fonts.sans(14, .bold), color: following ? theme.fgHeading : theme.bgBase)
            let pillW = lbl.intrinsicContentSize.width + 36
            let pill = HoverControl(frame: NSRect(x: rightX - 8 - pillW, y: y + 6, width: pillW, height: 34))
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 17
            pill.layer?.backgroundColor = (following ? NSColor.clear : theme.fgHeading).cgColor
            if following { pill.layer?.borderWidth = 1; pill.layer?.borderColor = theme.borderStrong.cgColor }
            lbl.frame = NSRect(x: 0, y: (34 - lbl.intrinsicContentSize.height) / 2, width: pillW, height: lbl.intrinsicContentSize.height)
            lbl.alignment = .center
            pill.addSubview(lbl)
            pill.onClick = {
                callbacks.onFollow(a, !following)
                doc.rebuild?()
                onFollowToggled()
            }
            doc.addSubview(pill)
            rightX -= 8 + pillW
        }

        let nameY = y + 4
        let name = makeLabel(a.name, font: Fonts.sans(15.5, .bold), color: theme.fgHeading)
        name.lineBreakMode = .byTruncatingTail
        let nameMaxW = max(40, rightX - 8 - (padX + 44 + 11))
        name.frame = NSRect(x: padX + 44 + 11, y: nameY, width: min(name.perchSingleLineWidth, nameMaxW), height: 20)
        doc.addSubview(name)
        if a.verified {
            let v = VerifiedBadge(size: 15)
            v.frame = NSRect(x: padX + 44 + 11 + name.frame.width + 5, y: nameY + 2, width: 15, height: 15)
            doc.addSubview(v)
        }
        let sub = makeLabel(isX ? "@\(a.handle)" : "微博", font: Fonts.sans(14), color: theme.fgSubdued)
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: padX + 44 + 11, y: nameY + 22, width: rightX - 8 - (padX + 44 + 11), height: 18)
        doc.addSubview(sub)
        y += 44

        // text
        y += 12
        let textW = width - padX * 2
        let rich = RichTextView(text: post.text, font: Fonts.sans(17), color: theme.fgBody, accent: theme.accent,
                                lineHeightMultiple: 1.5, onMention: { callbacks.onMention($0) })
        let textH = rich.height(forWidth: textW)
        rich.frame = NSRect(x: padX, y: y, width: textW, height: textH)
        doc.addSubview(rich)
        y += textH

        if let media = post.media {
            y += 10
            let mv: NSView
            switch media.type {
            case .images:
                let items = media.items
                let miv = MediaImagesView(items: items, width: textW, onTap: { idx in
                    callbacks.onOpenMedia(MediaViewerContext(items: items, initialIndex: idx,
                                                             author: a, type: .images, dur: nil))
                })
                miv.onHeightChanged = { [weak doc] in doc?.rebuild?(); onMediaHeightChanged() }
                mv = miv
            case .video:
                let vitem = media.item ?? MediaItem(Gradient("#1c1c22", "#0e0e12"))
                let playbackKey = VideoPlaybackStore.tweetKey(postId: post.id, item: vitem)
                let vp = VideoPlayerView(item: vitem, durText: media.dur, isX: a.platform == .x, variant: .inline,
                    playbackKey: playbackKey,
                    onOpenWindow: {
                        callbacks.onOpenMedia(MediaViewerContext(items: [vitem], initialIndex: 0,
                                                                 author: media.source ?? a, type: .video,
                                                                 dur: media.dur, playbackKey: playbackKey))
                    })
                let vAspect = max(9.0 / 21.0, media.item?.aspect ?? 16.0 / 9.0)
                vp.frame = NSRect(x: 0, y: 0, width: textW, height: ceil(textW / vAspect))
                mv = vp
            case .link: mv = LinkCardView(media: media, width: textW)
            }
            mv.frame.origin = CGPoint(x: padX, y: y)
            doc.addSubview(mv)
            y += mv.frame.height
            if media.type == .video, let source = media.source {
                y += 9
                let sourceView = MediaSourceView(source: source, isX: isX, width: textW,
                                                 onOpenProfile: { callbacks.onOpenProfile($0) })
                sourceView.frame.origin = CGPoint(x: padX, y: y)
                doc.addSubview(sourceView)
                y += MediaSourceView.rowHeight
            }
        }
        if let q = post.quote {
            y += 10
            let qid = post.quoteSrcId
            let qv = QuotePostView(quote: q, width: textW,
                onClick: qid.map { id in {
                    callbacks.onOpenPost(Post(id: id, author: q.author, time: q.time,
                        text: q.text, media: q.media, stats: Stats(reposts: 0, likes: 0)))
                }},
                onOpenProfile: { p in callbacks.onOpenProfile(p) },
                onMention: { h in callbacks.onMention(h) },
                onOpenMedia: { ctx in callbacks.onOpenMedia(ctx) })
            qv.frame.origin = CGPoint(x: padX, y: y)
            doc.addSubview(qv)
            y += qv.frame.height
        }

        // meta (timestamp · bold view count)
        y += 14
        let metaStr = NSMutableAttributedString(string: post.time,
            attributes: [.font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued])
        if let views = post.stats.views, !views.isEmpty {
            metaStr.append(NSAttributedString(string: " · ", attributes: [.font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued]))
            metaStr.append(NSAttributedString(string: views, attributes: [.font: Fonts.sans(13.5, .bold), .foregroundColor: theme.fgHeading]))
            metaStr.append(NSAttributedString(string: isX ? " Views" : " 查看", attributes: [.font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued]))
        }
        let meta = NSTextField(labelWithAttributedString: metaStr)
        meta.isBezeled = false; meta.drawsBackground = false
        meta.frame = NSRect(x: padX, y: y, width: textW, height: 18)
        doc.addSubview(meta)
        y += 18 + 12

        // action row — inline counts, space-between, border top+bottom
        let actRow = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 8 + 22 + 8 + 1))
        addTopBorder(actRow, theme: theme)
        let reply = ActionButtonView(icon: "reply", count: post.stats.replies, color: theme.accent, active: false, title: isX ? "Reply" : "评论") { callbacks.onReply(post) }
        let repost = RepostActionView(post: post, count: post.stats.reposts, active: post.reposted, callbacks: callbacks)
        let like = ActionButtonView(icon: "heart", count: post.stats.likes, color: theme.magenta800, active: post.liked, title: isX ? "Like" : "赞") { callbacks.onAction(post.id, "liked") }
        let bookmark = ActionButtonView(icon: "bookmark", count: nil, color: theme.accent, active: post.bookmarked, title: isX ? "Bookmark" : "收藏") { callbacks.onAction(post.id, "bookmarked") }
        let share = ActionButtonView(icon: "share", count: nil, color: theme.accent, active: false, title: isX ? "Share" : "分享") {}
        share.onClick = { presentShareMenu(post: post, anchor: share, callbacks: callbacks) }
        let acts: [NSView] = [reply, repost, like, bookmark, share]
        let widths: [CGFloat] = [reply.contentWidth, repost.contentWidth, like.contentWidth, bookmark.contentWidth, share.contentWidth]
        let total = widths.reduce(0, +)
        let span = width - padX * 2
        let gap = acts.count > 1 ? max(0, (span - total) / CGFloat(acts.count - 1)) : 0
        var ax = padX
        for (i, item) in acts.enumerated() {
            item.frame.origin = CGPoint(x: ax, y: 9)
            actRow.addSubview(item)
            ax += widths[i] + gap
        }
        addBottomBorder(actRow, theme: theme)
        doc.addSubview(actRow)
        y += actRow.frame.height

        // replies sort header ("Most relevant" / "相关")
        let sortRow = HoverControl(frame: NSRect(x: 0, y: y, width: width, height: 32))
        let sortLbl = makeLabel(isX ? "Most relevant" : "相关", font: Fonts.sans(13.5, .bold), color: theme.fgSubdued)
        let sortLblW = sortLbl.intrinsicContentSize.width
        sortLbl.frame = NSRect(x: padX, y: 10 + (16 - sortLbl.intrinsicContentSize.height) / 2, width: sortLblW, height: sortLbl.intrinsicContentSize.height)
        sortRow.addSubview(sortLbl)
        let sortChev = GlyphView(name: "chevron-down", size: 14, color: theme.fgSubdued)
        sortChev.frame = NSRect(x: padX + sortLblW + 3, y: 11, width: 14, height: 14)
        sortRow.addSubview(sortChev)
        doc.addSubview(sortRow)
        y += 32

        // reply affordance
        let aff = HoverControl(frame: NSRect(x: 0, y: y, width: width, height: 13 + 36 + 13 + 1))
        aff.onClick = { callbacks.onReply(post) }
        let circle = FlippedView(frame: NSRect(x: padX, y: 13, width: 36, height: 36))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 18
        circle.layer?.backgroundColor = theme.bgLayer2.cgColor
        circle.layer?.borderColor = theme.borderDefault.cgColor
        circle.layer?.borderWidth = 1
        let pencil = GlyphView(name: "pencil", size: 17, color: theme.fgSubdued)
        pencil.frame = NSRect(x: 9.5, y: 9.5, width: 17, height: 17)
        circle.addSubview(pencil)
        aff.addSubview(circle)
        let phl = makeLabel(isX ? "Post your reply" : "写下你的评论…", font: Fonts.sans(15), color: theme.fgSubdued)
        phl.frame = NSRect(x: padX + 36 + 11, y: 13 + (36 - phl.intrinsicContentSize.height) / 2, width: width - padX - 36 - 11 - padX, height: phl.intrinsicContentSize.height)
        aff.addSubview(phl)
        addBottomBorder(aff, theme: theme)
        doc.addSubview(aff)
        y += aff.frame.height

        doc.frame = NSRect(x: 0, y: 0, width: width, height: ceil(y))
        }
        doc.rebuild?()
        return doc
    }

    static func statAttr(_ n: Int, _ lbl: String, theme: Theme, size: CGFloat) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: fmtCount(n), attributes: [.font: Fonts.sans(size, .bold), .foregroundColor: theme.fgHeading]))
        s.append(NSAttributedString(string: " " + lbl, attributes: [.font: Fonts.sans(size), .foregroundColor: theme.fgSubdued]))
        return s
    }

    static func addBottomBorder(_ v: NSView, theme: Theme) {
        let line = NSView(frame: NSRect(x: 0, y: v.bounds.height - 1, width: v.bounds.width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        line.autoresizingMask = [.width]
        v.addSubview(line)
    }
    static func addTopBorder(_ v: NSView, theme: Theme) {
        let line = NSView(frame: NSRect(x: 0, y: 0, width: v.bounds.width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        line.autoresizingMask = [.width]
        v.addSubview(line)
    }

    // ── Profile screen ──
    static func profile(person: Person, profile: Profile, isOwn: Bool, posts: [Post], width: CGFloat, callbacks: PostCallbacks,
                        followState: FollowState) -> FlippedView {
        let theme = ThemeManager.shared.theme
        let prof = profile
        let isX = person.platform == .x
        let head = FlippedView()
        head.bgColor = theme.bgBase
        let padX: CGFloat = 16

        // banner
        let banner = GradientTile(prof.banner)
        banner.frame = NSRect(x: 0, y: 0, width: width, height: 124)
        head.addSubview(banner)

        // avatar (overlaps banner)
        let avatarWrap = FlippedView(frame: NSRect(x: padX, y: 124 - 42, width: 90, height: 90))
        avatarWrap.wantsLayer = true
        avatarWrap.layer?.cornerRadius = 45
        avatarWrap.layer?.backgroundColor = theme.bgBase.cgColor
        let avatar = AvatarView(person: person, size: 82)
        avatar.frame = NSRect(x: 4, y: 4, width: 82, height: 82)
        avatarWrap.addSubview(avatar)
        head.addSubview(avatarWrap)

        // edit / follow button (bottom-aligned with avatar row)
        let btnY: CGFloat = 124 - 42 + 90 - 34 - 6
        if isOwn {
            let edit = makePillButton(title: isX ? "Edit profile" : "编辑资料", filled: false, theme: theme) {}
            edit.frame.origin = CGPoint(x: width - padX - edit.frame.width, y: btnY)
            head.addSubview(edit)
        } else {
            let follow = FollowButton(isX: isX, state: followState, theme: theme)
            follow.onToggle = { on in callbacks.onFollow(person, on) }
            follow.frame.origin = CGPoint(x: width - padX - follow.frame.width, y: btnY)
            head.addSubview(follow)
        }

        var y: CGFloat = 124 - 42 + 90 + 10
        // name + verified
        let name = makeLabel(person.name, font: Fonts.sans(21, .heavy), color: theme.fgHeading)
        name.frame = NSRect(x: padX, y: y, width: min(name.intrinsicContentSize.width, width - padX * 2 - 24), height: 26)
        head.addSubview(name)
        if person.verified {
            let v = VerifiedBadge(size: 18)
            v.frame = NSRect(x: padX + name.frame.width + 6, y: y + 4, width: 18, height: 18)
            head.addSubview(v)
        }
        y += 26
        if isX {
            let h = makeLabel("@\(person.handle)", font: Fonts.sans(14.5), color: theme.fgSubdued)
            h.frame = NSRect(x: padX, y: y + 1, width: width - padX * 2, height: 18)
            head.addSubview(h)
            y += 19
        }
        // bio
        if !prof.bio.isEmpty {
            y += 11
            let bioW = width - padX * 2
            let bio = RichTextView(text: prof.bio, font: Fonts.sans(14.5), color: theme.fgBody, accent: theme.accent, lineHeightMultiple: 1.5)
            let bioH = bio.height(forWidth: bioW)
            bio.frame = NSRect(x: padX, y: y, width: bioW, height: bioH)
            head.addSubview(bio)
            y += bioH
        }

        // location + joined
        var mx = padX
        func addMeta(_ icon: String, _ text: String) {
            guard !text.isEmpty else { return }
            let g = GlyphView(name: icon, size: 15, color: theme.fgSubdued)
            g.frame = NSRect(x: mx, y: y, width: 15, height: 15)
            head.addSubview(g)
            mx += 15 + 5
            let l = makeLabel(text, font: Fonts.sans(13.5), color: theme.fgSubdued)
            l.frame = NSRect(x: mx, y: y, width: l.intrinsicContentSize.width, height: 16)
            head.addSubview(l)
            mx += l.intrinsicContentSize.width + 18
        }
        if !prof.location.isEmpty || !prof.joined.isEmpty {
            y += 11
            addMeta("location", prof.location)
            addMeta("calendar", prof.joined)
            y += 16
        }

        // stats
        y += 11
        let following = NSTextField(labelWithAttributedString: statAttr2(prof.following, isX ? "Following" : "关注", theme: theme))
        following.isBezeled = false; following.drawsBackground = false
        following.frame = NSRect(x: padX, y: y, width: following.intrinsicContentSize.width, height: 18)
        head.addSubview(following)
        let followers = NSTextField(labelWithAttributedString: statAttr2(prof.followers, isX ? "Followers" : "粉丝", theme: theme))
        followers.isBezeled = false; followers.drawsBackground = false
        followers.frame = NSRect(x: padX + following.intrinsicContentSize.width + 20, y: y, width: followers.intrinsicContentSize.width, height: 18)
        head.addSubview(followers)
        y += 18

        // tabs
        y += 14
        let tabs = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 11 + 18 + 11 + 1))
        let postsTab = makeLabel(isX ? "Posts" : "微博", font: Fonts.sans(14.5, .heavy), color: theme.fgHeading)
        postsTab.frame = NSRect(x: padX, y: 11, width: postsTab.intrinsicContentSize.width, height: 18)
        tabs.addSubview(postsTab)
        let underline = NSView(frame: NSRect(x: padX, y: 11 + 18 + 11 - 3, width: postsTab.intrinsicContentSize.width + 4, height: 3))
        underline.wantsLayer = true
        underline.layer?.backgroundColor = theme.accent.cgColor
        tabs.addSubview(underline)
        let mediaTab = makeLabel(isX ? "Media" : "相册", font: Fonts.sans(14.5, .semibold), color: theme.fgSubdued)
        mediaTab.frame = NSRect(x: padX + postsTab.intrinsicContentSize.width + 26, y: 11, width: mediaTab.intrinsicContentSize.width, height: 18)
        tabs.addSubview(mediaTab)
        addBottomBorder(tabs, theme: theme)
        head.addSubview(tabs)
        y += tabs.frame.height

        // posts (header is one row; cells follow and can re-flow)
        head.frame = NSRect(x: 0, y: 0, width: width, height: ceil(y))
        let doc = FeedDocument(width: width, bottomPad: 20)
        doc.bgColor = theme.bgBase
        doc.append(head)
        if posts.isEmpty {
            doc.append(emptyState(title: isX ? "No posts yet" : "还没有内容",
                                  sub: isX ? "When they post, it’ll show up here." : "发布的内容会显示在这里。",
                                  width: width, top: 56))
        } else {
            for p in posts {
                let cell = PostCellView(post: p, width: width, callbacks: callbacks)
                cell.onHeightChanged = { [weak doc] in doc?.restack() }
                doc.append(cell)
            }
        }
        doc.restack()
        return doc
    }

    static func statAttr2(_ count: String, _ lbl: String, theme: Theme) -> NSAttributedString {
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: count, attributes: [.font: Fonts.sans(14, .bold), .foregroundColor: theme.fgHeading]))
        s.append(NSAttributedString(string: " " + lbl, attributes: [.font: Fonts.sans(14), .foregroundColor: theme.fgSubdued]))
        return s
    }
}

/// Carries the detail screen's "load more replies" capability: whether more remain,
/// and a loader whose completion delivers the rebuilt roots + updated has-more flag.
struct DetailMore {
    let hasMore: Bool
    let load: (@escaping (_ roots: [Comment], _ hasMore: Bool) -> Void) -> Void
}

/// Mutable follow state shared so re-renders preserve it within a screen instance.
final class FollowState {
    var following = false
}

/// Editable search field (pill) for the search column header. Submits the trimmed
/// query on Return; matches 设计稿 `SearchHeader` (search glyph + borderless input).
final class SearchFieldView: FlippedView, NSTextFieldDelegate {
    private let field = NSTextField()
    private let onSubmit: (String) -> Void

    init(width: CGFloat, isX: Bool, query: String, onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        let theme = ThemeManager.shared.theme
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 38))
        wantsLayer = true
        layer?.cornerRadius = 19
        layer?.backgroundColor = theme.bgLayer1.cgColor
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1

        let sicon = GlyphView(name: "search", size: 18, color: theme.fgSubdued)
        sicon.frame = NSRect(x: 12, y: 10, width: 18, height: 18)
        addSubview(sicon)

        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Fonts.sans(14)
        field.textColor = theme.fgBody
        field.stringValue = query
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(
            string: isX ? "Search posts and people" : "搜索微博和用户",
            attributes: [.foregroundColor: theme.fgSubdued, .font: Fonts.sans(14)])
        field.delegate = self
        let fh: CGFloat = 20
        field.frame = NSRect(x: 38, y: (38 - fh) / 2, width: max(0, width - 38 - 12), height: fh)
        field.autoresizingMask = [.width]
        addSubview(field)
    }
    required init?(coder: NSCoder) { fatalError() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !q.isEmpty { onSubmit(q) }
            return true
        }
        return false
    }
}

func makePillButton(title: String, filled: Bool, theme: Theme, onClick: @escaping () -> Void) -> HoverControl {
    let btn = HoverControl()
    btn.wantsLayer = true
    btn.layer?.cornerRadius = 17
    let label = makeLabel(title, font: Fonts.sans(14, .bold), color: filled ? theme.bgBase : theme.fgHeading)
    btn.addSubview(label)
    let w = label.intrinsicContentSize.width + 36
    btn.frame = NSRect(x: 0, y: 0, width: w, height: 34)
    label.frame = NSRect(x: 18, y: (34 - label.intrinsicContentSize.height) / 2, width: label.intrinsicContentSize.width, height: label.intrinsicContentSize.height)
    if filled {
        btn.layer?.backgroundColor = theme.fgHeading.cgColor
    } else {
        btn.layer?.borderColor = theme.borderStrong.cgColor
        btn.layer?.borderWidth = 1
    }
    btn.onClick = onClick
    return btn
}

/// Follow / Following button with hover→Unfollow behavior.
final class FollowButton: HoverControl {
    private let isX: Bool
    private let state: FollowState
    private let themeRef: Theme
    private let label = NSTextField(labelWithString: "")
    /// Fired with the new follow value when the user toggles (route to the API).
    var onToggle: ((Bool) -> Void)?

    init(isX: Bool, state: FollowState, theme: Theme) {
        self.isX = isX
        self.state = state
        self.themeRef = theme
        super.init(frame: NSRect(x: 0, y: 0, width: 100, height: 34))
        wantsLayer = true
        layer?.cornerRadius = 17
        label.isBezeled = false; label.drawsBackground = false; label.isEditable = false
        label.font = Fonts.sans(14, .bold)
        label.alignment = .center
        addSubview(label)
        onClick = { [weak self] in
            guard let self else { return }
            self.state.following.toggle()
            self.render()
            self.onToggle?(self.state.following)
        }
        onState = { [weak self] _, _ in self?.render() }
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func render() {
        let following = state.following
        let text: String
        if following {
            text = isX ? (hovering ? "Unfollow" : "Following") : (hovering ? "取消关注" : "已关注")
        } else {
            text = isX ? "Follow" : "关注"
        }
        label.stringValue = text
        let w = label.intrinsicContentSize.width + 36
        frame = NSRect(x: frame.minX, y: frame.minY, width: w, height: 34)
        label.frame = NSRect(x: 0, y: (34 - label.intrinsicContentSize.height) / 2, width: w, height: label.intrinsicContentSize.height)
        if following {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = (hovering ? themeRef.negative : themeRef.borderStrong).cgColor
            label.textColor = hovering ? themeRef.negative : themeRef.fgHeading
        } else {
            layer?.backgroundColor = themeRef.fgHeading.cgColor
            layer?.borderWidth = 0
            label.textColor = themeRef.bgBase
        }
    }
}
