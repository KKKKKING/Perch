import AppKit

/// A virtualized column list (timeline or notifications) whose scroll position can
/// be captured and restored across the per-state-change canvas rebuild.
protocol ColumnFeed: AnyObject {
    var scrollView: NSScrollView { get }
    func currentAnchor() -> TimelineAnchor
    func restore(anchor: TimelineAnchor)
    func scrollToTop()
}

/// One timeline column with iOS-style in-column push/pop navigation.
final class ColumnView: FlippedView {
    private let appState: AppState
    private let col: ColumnSpec
    private let isLast: Bool
    private let isFirst: Bool
    private let theme = ThemeManager.shared.theme
    private let contentWidth: CGFloat

    private let track = NSView()
    private let divider = NSView()
    private var panels: [ColumnPanel] = []
    private var screens: [NavScreen] = []
    private var idx = 0

    private var callbacks = PostCallbacks()
    /// The virtualized list for this column (timeline or notifications).
    private var feed: ColumnFeed?
    private var timelineScrollObserver: NSObjectProtocol?
    /// True while a programmatic restore is scrolling, so the scroll observer
    /// doesn't re-capture (and corrupt) the anchor from an interim position.
    private var suppressAnchorCapture = false

    init(appState: AppState, col: ColumnSpec, contentWidth: CGFloat, isLast: Bool, isFirst: Bool) {
        self.appState = appState
        self.col = col
        self.contentWidth = contentWidth
        self.isLast = isLast
        self.isFirst = isFirst
        super.init(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 800))
        bgColor = theme.bgBase
        wantsLayer = true
        clipsToBounds = true
        setupCallbacks()
        addSubview(track)
        buildInitial()
        // divider added last so it renders above column content
        divider.wantsLayer = true
        divider.layer?.backgroundColor = theme.borderDefault.cgColor
        divider.isHidden = isLast
        addSubview(divider)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let o = timelineScrollObserver { NotificationCenter.default.removeObserver(o) } }

    private var account: Account { appState.colAccount(col) }

    private func setupCallbacks() {
        let appState = self.appState
        let colId = col.id
        callbacks.onAction = { appState.onAction($0, $1) }
        callbacks.onReply = { appState.openReply($0) }
        callbacks.onQuote = { appState.openQuote($0) }
        callbacks.onRepost = { appState.openRepost($0) }
        callbacks.onDirectRepost = { appState.directRepost($0) }
        callbacks.onOpenPost = { appState.pushScreen(colId, .post($0.id)) }
        callbacks.onOpenProfile = { appState.pushScreen(colId, .profile($0)) }
        callbacks.onMention = { h in
            let handle = h.hasPrefix("@") ? String(h.dropFirst()) : h
            let stub = Person(name: handle, handle: handle, colorToken: "indigo-700", verified: false, platform: .x)
            appState.pushScreen(colId, .profile(stub))
        }
        callbacks.onOpenMedia = { ctx in appState.openMediaViewer(ctx) }
        callbacks.onOpenJson = { post in
            let isX = post.author.platform == .x
            let title = (isX ? "Tweet · " : "微博 · ") + post.author.name
            let sub = (isX ? "@" + post.author.handle : post.author.name) + " · id " + post.id
            appState.openJsonViewer(JsonViewerContext(title: title, subtitle: sub, json: DebugJSON.from(post: post)))
        }
        callbacks.onFollow = { appState.follow($0, on: $1) }
        callbacks.onMute = { appState.mute($0, on: $1) }
        callbacks.onBlock = { appState.block($0, on: $1) }
        callbacks.onCopyLink = { appState.copyPostLink($0) }
        callbacks.onAddToLists = { [weak self] post, anchor in self?.presentListsPicker(post: post, anchor: anchor) }
        callbacks.onMuteConversation = { appState.muteConversation($0) }
        callbacks.onOpenURL = { appState.openExternal($0) }
        callbacks.onEmbed = { appState.copyEmbed($0) }
        callbacks.onToast = { appState.showToastNow($0) }
        callbacks.isFollowing = { appState.isFollowing($0) }
        callbacks.isMuted = { appState.isMuted($0) }
        callbacks.isBlocked = { appState.isBlocked($0) }
    }

    private func buildInitial() {
        // primary panel: notification center for the bell column, bookmarks folder
        // browser for the bookmarks column, else the standard timeline
        let timeline: ColumnPanel
        switch col.type {
        case "mentions": timeline = makeNotificationsPanel()
        case "bookmarks": timeline = makeBookmarksPanel()
        default: timeline = makeTimelinePanel()
        }
        panels = [timeline]
        track.addSubview(timeline)
        // existing pushed screens (no animation)
        screens = appState.colNav[col.id] ?? []
        for s in screens {
            let p = makePushedPanel(s)
            panels.append(p)
            track.addSubview(p)
        }
        idx = screens.count
        needsLayout = true
    }

    /// Rebuild all panels from current app state (preserves nav depth, no animation).
    func reload() {
        if let o = timelineScrollObserver { NotificationCenter.default.removeObserver(o); timelineScrollObserver = nil }
        captureVisibleAnchor()
        panels.forEach { $0.removeFromSuperview() }
        panels.removeAll()
        track.subviews.forEach { $0.removeFromSuperview() }
        buildInitial()
        layoutTrackImmediately()
        restoreVisibleAnchor()
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        let count = panels.count
        track.frame = NSRect(x: -CGFloat(idx) * w, y: 0, width: w * CGFloat(count), height: h)
        for (i, p) in panels.enumerated() {
            p.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        if !isLast {
            divider.frame = NSRect(x: w - 1, y: 0, width: 1, height: h)
        }
    }

    // ── Nav stack updates (called by RootViewController on nav change) ──
    func updateStack(_ newStack: [NavScreen]) {
        if newStack.count > screens.count {
            // push
            for s in newStack[screens.count...] {
                let p = makePushedPanel(s)
                panels.append(p)
                track.addSubview(p)
            }
            screens = newStack
            layoutTrackImmediately()
            idx = newStack.count
            animateTrack()
        } else if newStack.count < screens.count {
            // pop
            idx = newStack.count
            animateTrack { [weak self] in
                guard let self else { return }
                while self.panels.count > newStack.count + 1 {
                    self.panels.removeLast().removeFromSuperview()
                }
                self.screens = newStack
                self.layoutTrackImmediately()
            }
        } else {
            screens = newStack
            idx = newStack.count
            layoutTrackImmediately()
        }
    }

    private func layoutTrackImmediately() {
        let w = bounds.width
        let h = bounds.height
        let count = panels.count
        track.frame = NSRect(x: -CGFloat(idx) * w, y: 0, width: w * CGFloat(count), height: h)
        for (i, p) in panels.enumerated() {
            p.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
    }

    private func animateTrack(completion: (() -> Void)? = nil) {
        let w = bounds.width
        let h = bounds.height
        for (i, p) in panels.enumerated() {
            p.frame = NSRect(x: CGFloat(i) * w, y: 0, width: w, height: h)
        }
        track.frame.size = NSSize(width: w * CGFloat(panels.count), height: h)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.36
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.4, 1)
            track.animator().setFrameOrigin(NSPoint(x: -CGFloat(idx) * w, y: 0))
        }, completionHandler: completion)
    }

    // ── Cheap post refresh ──
    func updatePost(_ id: String) {
        guard let merged = appState.resolvePost(id) else { return }
        (feed as? TimelineFeed)?.updatePost(id, merged: merged)
        refreshCells(in: self, id: id, merged: merged)
    }

    private func refreshCells(in view: NSView, id: String, merged: Post) {
        for sub in view.subviews {
            if let cell = sub as? PostCellView, cell.post.id == id {
                cell.refresh(with: merged)
            }
            refreshCells(in: sub, id: id, merged: merged)
        }
    }

    func captureVisibleAnchor() {
        guard !suppressAnchorCapture, let feed else { return }
        if col.type == "mentions" {
            appState.setNotifAnchor(for: col, feed.currentAnchor())
        } else {
            appState.setTimelineAnchor(for: col, feed.currentAnchor())
        }
    }

    /// Debug hook: open this column's reload menu (PERCH_STATE=reloadmenu).
    func debugShowReloadMenu() { (panels.first?.header as? TimelineHeaderView)?.debugShowReloadMenu() }

    /// Debug hook: open this column's title menu / list picker (PERCH_STATE=listmenu).
    func debugShowMenu() { (panels.first?.header as? TimelineHeaderView)?.debugShowMenu() }

    func restoreVisibleAnchor() {
        guard let feed else { return }
        let anchor = col.type == "mentions" ? appState.notifAnchor(for: col) : appState.timelineAnchor(for: col)
        guard let anchor else { return }
        suppressAnchorCapture = true
        feed.restore(anchor: anchor)
        DispatchQueue.main.async { [weak self] in self?.suppressAnchorCapture = false }
    }

    private func observeTimelineScroll(_ scroll: NSScrollView) {
        if let o = timelineScrollObserver { NotificationCenter.default.removeObserver(o); timelineScrollObserver = nil }
        let cv = scroll.contentView
        cv.postsBoundsChangedNotifications = true
        timelineScrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: cv, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.captureVisibleAnchor()
            self.updateTimelineUnreadFromScroll()
        }
    }

    private func updateTimelineUnreadFromScroll() {
        guard !suppressAnchorCapture,
              col.type != "mentions",
              let timelineFeed = feed as? TimelineFeed,
              let unreadIds = appState.timelineSnapshot(for: col)?.unreadIds,
              !unreadIds.isEmpty else { return }
        let reached = timelineFeed.unreadPostIdsReached(Set(unreadIds))
        if !reached.isEmpty {
            appState.markTimelineUnreadSeen(reached, for: col)
        }
    }

    // ── Panels ──
    private func makeTimelinePanel() -> ColumnPanel {
        appState.ensureListColumn(for: col)
        let header = TimelineHeaderView(appState: appState, col: col, isFirst: isFirst,
                                        onOpenProfile: { [weak self] p in
                                            guard let self else { return }
                                            self.appState.pushScreen(self.col.id, .profile(p))
                                        },
                                        onRefresh: { [weak self] in
                                            guard let self else { return }
                                            self.captureVisibleAnchor()
                                            self.appState.refreshTimeline(for: self.col, userInitiated: true)
                                        },
                                        onClearReload: { [weak self] in
                                            guard let self else { return }
                                            self.appState.clearAndReloadTimeline(for: self.col)
                                        })
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.ensureTimelineLoaded(for: self.col)
        }
        let isX = account.platform == .x
        let status = appState.timelineStatus(for: col)
        let refreshing = appState.timelineIsRefreshing(for: col)
        let feed = TimelineFeed(width: contentWidth, isX: isX, isSearch: col.type == "search",
                                type: col.type, callbacks: callbacks,
                                searchQuery: appState.searchQuery[col.id] ?? "",
                                onSearchSubmit: { [weak self] q in
                                    guard let self else { return }
                                    self.appState.setSearchQuery(self.col.id, q)
                                },
                                onRetry: { [weak self] in
                                    guard let self else { return }
                                    self.appState.refreshTimeline(for: self.col, userInitiated: true)
                                },
                                onGap: { [weak self] gapId in
                                    guard let self else { return }
                                    self.captureVisibleAnchor()
                                    self.appState.loadTimelineGap(gapId, for: self.col)
                                })
        self.feed = feed
        feed.update(rows: appState.timelineRows(for: col), status: status, refreshing: refreshing)
        let scroll = feed.scrollView
        observeTimelineScroll(scroll)
        var extras: [NSView] = []
        if refreshing { extras.append(TimelineRefreshBar()) }
        if col.type == "home" {
            extras.append(FeedTabStripView(selected: HomeFeed.normalize(col.feed), isX: isX,
                                          onSelect: { [weak self] feed in
                guard let self else { return }
                self.captureVisibleAnchor()
                self.appState.setColFeed(self.col.id, feed)
            }))
        }
        let overlay = makeNewPostsOverlay(scroll: scroll)
        let panel = TimelineColumnPanel(header: header, extras: extras, body: scroll, overlay: overlay)
        DispatchQueue.main.async { [weak self] in self?.restoreVisibleAnchor() }
        return panel
    }

    private func makeNewPostsOverlay(scroll: NSScrollView) -> (NSView & TimelineOverlay)? {
        let unread = appState.timelineUnreadCount(for: col)
        guard unread > 0 else { return nil }
        let isX = account.platform == .x
        let onClick: () -> Void = { [weak self, weak scroll] in
            guard let self else { return }
            scroll?.scrollToTop()
            self.appState.clearTimelineUnread(for: self.col)
        }
        if col.type == "home" {
            return NewPostsPillView(count: unread, authors: appState.timelineNewAuthors(for: col), isX: isX, onClick: onClick)
        }
        return NewPostsBadgeView(count: unread, isX: isX, onClick: onClick)
    }

    private func makeBookmarksPanel() -> ColumnPanel {
        let header = TimelineHeaderView(appState: appState, col: col, isFirst: isFirst,
                                        onOpenProfile: { [weak self] p in
                                            guard let self else { return }
                                            self.appState.pushScreen(self.col.id, .profile(p))
                                        },
                                        onRefresh: { [weak self] in
                                            guard let self else { return }
                                            self.appState.refreshBookmarkFolders(force: true)
                                            self.appState.refreshTimeline(for: self.col, userInitiated: true)
                                        },
                                        onClearReload: { [weak self] in
                                            guard let self else { return }
                                            self.appState.refreshBookmarkFolders(force: true)
                                            self.appState.clearAndReloadTimeline(for: self.col)
                                        })
        return BookmarksPanel(appState: appState, col: col, width: contentWidth,
                              header: header, callbacks: callbacks)
    }

    private func makeNotificationsPanel() -> ColumnPanel {
        let header = TimelineHeaderView(appState: appState, col: col, isFirst: isFirst,
                                        onOpenProfile: { [weak self] p in
                                            guard let self else { return }
                                            self.appState.pushScreen(self.col.id, .profile(p))
                                        },
                                        onRefresh: { [weak self] in
                                            guard let self else { return }
                                            self.appState.refreshNotifications(for: self.col)
                                        },
                                        onClearReload: { [weak self] in
                                            guard let self else { return }
                                            self.appState.clearAndReloadNotifications(for: self.col)
                                        })
        let colId = col.id
        var nc = NotifCallbacks()
        nc.onOpenPost = { [weak self] p in self?.appState.pushScreen(colId, .post(p.id)) }
        nc.onOpenProfile = { [weak self] p in self?.appState.pushScreen(colId, .profile(p)) }
        nc.onReply = { [weak self] p in if let p { self?.appState.openReply(p) } }
        nc.onSeen = { [weak self] id in self?.appState.markNotifSeen(colId, id) }
        nc.onAction = { [weak self] id, field in self?.appState.onAction(id, field) }
        nc.onFollow = { [weak self] person, on in self?.appState.follow(person, on: on) }
        nc.isFollowing = { [weak self] person in self?.appState.isFollowing(person) ?? false }
        let panel = NotifCenterPanel(appState: appState, col: col, width: contentWidth, header: header, callbacks: nc)
        self.feed = panel.columnFeed
        if let cf = panel.columnFeed { observeTimelineScroll(cf.scrollView) }
        DispatchQueue.main.async { [weak self] in self?.restoreVisibleAnchor() }
        return panel
    }

    private func makePushedPanel(_ s: NavScreen) -> ColumnPanel {
        let isX = account.platform == .x
        switch s.kind {
        case .post(let id):
            appState.refreshDetail(id)
            let feed = DetailFeed(width: contentWidth, isX: isX, callbacks: callbacks)
            applyDetail(feed, id: id)
            let back = BackHeader(title: isX ? "Post" : "微博正文", isX: isX,
                                  onBack: { [weak self] in guard let self else { return }; self.appState.popScreen(self.col.id) },
                                  onRefresh: { [weak feed] in feed?.scrollToTop() })
            let panel = ColumnPanel(header: back, body: feed.scrollView)
            panel.columnFeed = feed
            return panel
        case .profile(let person):
            appState.refreshProfile(person)
            let scroll = makeColumnScroll()
            scroll.documentView = profileDocument(for: person)
            let back = BackHeader(title: appState.resolvedPerson(person).name, isX: isX,
                                  onBack: { [weak self] in guard let self else { return }; self.appState.popScreen(self.col.id) },
                                  onRefresh: { [weak scroll] in scroll?.scrollToTop() })
            return ColumnPanel(header: back, body: scroll)
        }
    }

    /// Push the current detail-thread state into a `DetailFeed` (initial fill + each
    /// in-place refresh): focal post (or skeleton/unavailable), ancestors, root
    /// replies, and the "load more" capability.
    private func applyDetail(_ feed: DetailFeed, id: String) {
        let post = appState.resolvePost(id)
        let more = DetailMore(hasMore: appState.hasMoreReplies(id),
                              load: { [weak self] done in self?.appState.loadMoreReplies(id, completion: done) })
        feed.update(post: post,
                    ancestors: appState.detailAncestors(id),
                    replyRoots: post.map { appState.repliesOf($0) } ?? [],
                    more: more,
                    loading: post == nil && appState.detailLoading.contains(id))
    }

    /// Build the document view for a pushed profile panel (skeleton or profile).
    private func profileDocument(for person: Person) -> NSView {
        let isX = account.platform == .x
        let resolved = appState.resolvedPerson(person)
        if appState.liveProfiles[person.handle] == nil && appState.profileLoading.contains(person.handle) {
            return ProfileSkeletonView(width: contentWidth, isX: isX)
        }
        let ownHandle = TwitterService.shared.account?.handle
        let isOwn = ownHandle != nil && resolved.handle.caseInsensitiveCompare(ownHandle!) == .orderedSame
        let fs = FollowState()
        fs.following = appState.isFollowing(resolved)
        return Screens.profile(person: resolved, profile: appState.profileFor(resolved),
                               isOwn: isOwn, posts: appState.authorPosts(resolved),
                               width: contentWidth, callbacks: callbacks, followState: fs)
    }

    // ── In-place panel refresh (flicker-free updates) ──
    /// Rebuild just the matching pushed detail panel's document, preserving scroll.
    func refreshDetailPanel(id: String) {
        for (i, s) in screens.enumerated() {
            guard case .post(let pid) = s.kind, pid == id, i + 1 < panels.count,
                  let feed = panels[i + 1].columnFeed as? DetailFeed else { continue }
            applyDetail(feed, id: id)
        }
    }

    /// Rebuild just the matching pushed profile panel's document, preserving scroll.
    func refreshProfilePanel(handle: String) {
        for (i, s) in screens.enumerated() {
            guard case .profile(let person) = s.kind,
                  person.handle.caseInsensitiveCompare(handle) == .orderedSame,
                  i + 1 < panels.count else { continue }
            replaceDocument(in: panels[i + 1].body, with: profileDocument(for: person))
        }
    }

    /// Swap a scroll view's document while keeping the reader's scroll offset.
    private func replaceDocument(in scroll: NSScrollView, with doc: NSView) {
        let offset = scroll.contentView.bounds.origin
        scroll.documentView = doc
        scroll.contentView.scroll(to: offset)
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Re-render only the primary timeline feed in place (leaves pushed panels and
    /// their scroll untouched). mentions/bookmarks own their feeds → no-op here,
    /// they refresh on the next destructive rebuild.
    func refreshPrimaryInPlace() {
        guard let timelineFeed = feed as? TimelineFeed else { return }
        captureVisibleAnchor()
        timelineFeed.update(rows: appState.timelineRows(for: col),
                            status: appState.timelineStatus(for: col),
                            refreshing: appState.timelineIsRefreshing(for: col))
        refreshTimelineUnreadOverlay()
        restoreVisibleAnchor()
    }

    func refreshTimelineUnreadOverlay() {
        guard let panel = panels.first as? TimelineColumnPanel,
              let scroll = feed?.scrollView else { return }
        panel.setOverlay(makeNewPostsOverlay(scroll: scroll))
    }

    // ── Lists membership picker ──
    /// Show the author's owned Lists with the target's membership checked; toggling a
    /// row adds/removes the author optimistically (in-place checkmark + revert on error).
    private func presentListsPicker(post: Post, anchor: NSView) {
        let isX = post.author.platform == .x
        guard isX, let myId = TwitterService.shared.credentials?.userId,
              let targetId = post.author.id else {
            appState.showToastNow(isX ? "Lists unavailable" : "无法加载列表")
            return
        }
        let loading = presentListsContent(lists: nil, anchor: anchor, isX: isX, targetId: targetId)
        Task { [weak self, weak loading] in
            guard let self else { return }
            let lists = (try? await TwitterService.shared.listOwnerships(userId: myId, targetUserId: targetId))?.lists ?? []
            await MainActor.run {
                guard loading?.superview != nil else { return }   // user dismissed mid-load
                _ = self.presentListsContent(lists: lists, anchor: anchor, isX: isX, targetId: targetId)
            }
        }
    }

    /// Build + present the lists popover. `lists == nil` renders a loading row.
    @discardableResult
    private func presentListsContent(lists: [TwitterList]?, anchor: NSView, isX: Bool, targetId: String) -> NSView {
        let theme = self.theme
        let w: CGFloat = 268
        let inner = w - 12
        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 13
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        var y: CGFloat = 6
        let hdr = makeLabel(isX ? "Add/remove from Lists" : "从列表中添加/移除", font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        hdr.frame = NSRect(x: 16, y: y + 4, width: inner, height: 14)
        content.addSubview(hdr)
        y += 28
        if let lists {
            if lists.isEmpty {
                let empty = makeLabel(isX ? "You have no lists" : "暂无列表", font: Fonts.sans(13.5, .medium), color: theme.fgSubdued)
                empty.frame = NSRect(x: 16, y: y + 3, width: inner, height: 18)
                content.addSubview(empty)
                y += 32
            } else {
                let rowH: CGFloat = 40
                let listHeight = CGFloat(lists.count) * rowH
                let container = FlippedView(frame: NSRect(x: 0, y: 0, width: inner, height: listHeight))
                for (i, list) in lists.enumerated() {
                    let row = makeListRow(list: list, width: inner, targetId: targetId, isX: isX)
                    row.frame.origin = CGPoint(x: 0, y: CGFloat(i) * rowH)
                    container.addSubview(row)
                }
                let budget: CGFloat = 360
                if listHeight <= budget {
                    container.frame.origin = CGPoint(x: 6, y: y)
                    content.addSubview(container)
                    y += listHeight
                } else {
                    let scroll = NSScrollView(frame: NSRect(x: 6, y: y, width: inner, height: budget))
                    scroll.hasVerticalScroller = true
                    scroll.drawsBackground = false
                    scroll.documentView = container
                    content.addSubview(scroll)
                    y += budget
                }
            }
        } else {
            let loading = makeLabel(isX ? "Loading lists…" : "正在加载列表…", font: Fonts.sans(13.5, .medium), color: theme.fgSubdued)
            loading.frame = NSRect(x: 16, y: y + 3, width: inner, height: 18)
            content.addSubview(loading)
            y += 32
        }
        y += 6
        let dx = anchor.bounds.width + 4 - w
        gPopoverHost?.presentPopover(content, width: w, height: y, anchor: anchor, edge: .below, dx: dx, dy: 0)
        return content
    }

    private func makeListRow(list: TwitterList, width: CGFloat, targetId: String, isX: Bool) -> HoverControl {
        let theme = self.theme
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: 40))
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        let g = GlyphView(name: "list", size: 19, color: theme.fgSubdued)
        g.frame = NSRect(x: 10, y: 10, width: 19, height: 19)
        row.addSubview(g)
        let l = makeLabel(list.name, font: Fonts.sans(14, .semibold), color: theme.fgBody)
        l.lineBreakMode = .byTruncatingTail
        l.frame = NSRect(x: 40, y: (40 - l.intrinsicContentSize.height) / 2, width: width - 76, height: l.intrinsicContentSize.height)
        row.addSubview(l)
        let ck = GlyphView(name: "checkmark", size: 17, color: theme.accent)
        ck.frame = NSRect(x: width - 30, y: 11, width: 17, height: 17)
        ck.isHidden = !list.isMember
        row.addSubview(ck)
        row.onState = { h, _ in row.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor }
        let listId = list.id
        let name = list.name
        row.onClick = { [weak self] in
            guard let self else { return }
            let willBeMember = ck.isHidden   // hidden ⇒ not a member ⇒ click adds
            ck.isHidden = !willBeMember
            self.appState.showToastNow(willBeMember ? (isX ? "Added to \(name)" : "已添加到 \(name)")
                                                    : (isX ? "Removed from \(name)" : "已从 \(name) 移除"))
            Task {
                do {
                    if willBeMember { try await TwitterService.shared.listAddMember(listId: listId, userId: targetId) }
                    else { try await TwitterService.shared.listRemoveMember(listId: listId, userId: targetId) }
                } catch {
                    await MainActor.run {
                        ck.isHidden = willBeMember   // revert optimistic toggle
                        self.appState.showToastNow(isX ? "Couldn't update list" : "更新列表失败")
                    }
                }
            }
        }
        return row
    }
}

/// A flipped panel: 54px header pinned at top + scroll body below.
class ColumnPanel: FlippedView {
    let header: NSView
    let body: NSScrollView
    /// Set for panels whose body is a virtualized feed (detail thread), enabling
    /// in-place refresh + scroll-anchor preservation instead of a document swap.
    var columnFeed: ColumnFeed?
    init(header: NSView, body: NSScrollView) {
        self.header = header
        self.body = body
        super.init(frame: .zero)
        addSubview(body)
        addSubview(header)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 54)
        body.frame = NSRect(x: 0, y: 54, width: bounds.width, height: max(0, bounds.height - 54))
    }
}

final class TimelineColumnPanel: ColumnPanel {
    private let extras: [NSView]
    private var overlay: (NSView & TimelineOverlay)?

    init(header: NSView, extras: [NSView], body: NSScrollView, overlay: (NSView & TimelineOverlay)?) {
        self.extras = extras
        self.overlay = overlay
        super.init(header: header, body: body)
        for extra in extras { addSubview(extra) }
        if let overlay { addSubview(overlay) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setOverlay(_ next: (NSView & TimelineOverlay)?) {
        overlay?.removeFromSuperview()
        overlay = next
        if let next { addSubview(next) }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 54)
        var y: CGFloat = 54
        for extra in extras {
            let h = extra.frame.height > 0 ? extra.frame.height : 0
            extra.frame = NSRect(x: 0, y: y, width: bounds.width, height: h)
            y += h
        }
        body.frame = NSRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
        if let overlay {
            let s = overlay.overlaySize
            let x = overlay.centeredOverlay ? (bounds.width - s.width) / 2 : bounds.width - s.width - 14
            overlay.frame = NSRect(x: x, y: y + (overlay.centeredOverlay ? 12 : 10),
                                   width: s.width, height: s.height)
        }
    }
}

func makeColumnScroll(_ scroll: NSScrollView = NSScrollView()) -> NSScrollView {
    let theme = ThemeManager.shared.theme
    scroll.borderType = .noBorder
    scroll.drawsBackground = true
    scroll.backgroundColor = theme.bgBase
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.verticalScrollElasticity = .allowed
    return scroll
}

extension NSScrollView {
    func scrollToTop() {
        guard documentView != nil else { return }
        contentView.scroll(to: NSPoint(x: 0, y: 0))
        reflectScrolledClipView(contentView)
    }
}
