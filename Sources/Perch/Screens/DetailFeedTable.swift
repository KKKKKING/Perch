import AppKit

/// Virtualized tweet-detail list backed by **one** `NSTableView` — first row to
/// last. The conversation is a single flat sequence of rows that merely differ by
/// which post is focused: each ancestor is a recycled `PostCellView`, the focal
/// post is one persistent (large, distinct) `Screens.focalPost` row, and each
/// top-level reply is a recycled, tappable `CommentNodeView`. Tapping any ancestor
/// or reply re-focuses it (X-style drill-in). Off-screen rows cost only a cached,
/// view-free height measurement. Mirrors `TimelineFeed`'s sizer/recycle/anchor
/// pattern.
final class DetailFeed: NSObject, NSTableViewDataSource, NSTableViewDelegate, ColumnFeed {
    let scrollView: NSScrollView
    private let table = NSTableView()
    private let theme = ThemeManager.shared.theme

    private let width: CGFloat
    private let isX: Bool
    private var callbacks: PostCallbacks

    private enum Item {
        case ancestor(Post)         // a conversation parent (compact, PostCellView)
        case focal(Post)            // THE focused post (large, distinct layout)
        case comment(Comment)       // one flat top-level reply
        case status                 // skeleton (loading) or "Post unavailable"
        case showMore
        /// Post / comment id, for scroll anchoring across re-focus and reloads.
        var rowId: String? {
            switch self {
            case .ancestor(let p): return p.id
            case .focal(let p): return p.id
            case .comment(let c): return c.id
            case .status, .showMore: return nil
            }
        }
    }
    private var items: [Item] = []

    private var post: Post?
    private var ancestors: [Post] = []
    private var replyRoots: [Comment] = []
    private var more: DetailMore?
    private var loading = false

    /// Row-height cache keyed by ancestor post id **and** reply comment id (ids are
    /// unique; width is fixed per feed).
    private var heightCache: [String: CGFloat] = [:]
    /// One reusable cell used only for off-screen ancestor height measurement.
    private var sizer: PostCellView?
    /// Focal-post row: built once per `update`, then re-laid in place for async
    /// media / Follow toggles. Persistent (never recycled), height cached.
    private var focalView: RebuildableDocument?
    private var focalHeight: CGFloat = 0
    /// Skeleton / "unavailable" placeholder shown when `post == nil`.
    private var statusView: NSView?
    private var statusHeight: CGFloat = 0
    private var showMoreLoading = false

    private static let ancestorId = NSUserInterfaceItemIdentifier("ancestor")

    init(width: CGFloat, isX: Bool, callbacks: PostCallbacks) {
        self.scrollView = makeColumnScroll()
        self.width = width
        self.isX = isX
        self.callbacks = callbacks
        super.init()

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = width
        col.minWidth = width
        col.maxWidth = width
        table.addTableColumn(col)
        table.headerView = nil
        table.backgroundColor = theme.bgBase
        table.gridStyleMask = []
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.usesAutomaticRowHeights = false
        table.allowsColumnResizing = false
        table.allowsColumnReordering = false
        if #available(macOS 11.0, *) { table.style = .plain }
        table.dataSource = self
        table.delegate = self
        scrollView.documentView = table
    }

    // ── Public surface ──

    func update(post: Post?, ancestors: [Post], replyRoots: [Comment], more: DetailMore?, loading: Bool) {
        let anchor = currentAnchor()
        self.post = post
        self.ancestors = ancestors
        self.replyRoots = replyRoots
        self.more = more
        self.loading = loading
        self.showMoreLoading = false
        var live = Set(replyRoots.map { $0.id })
        live.formUnion(ancestors.map { $0.id })
        heightCache = heightCache.filter { live.contains($0.key) }

        if let post {
            rebuildFocal(post: post, hasAncestors: !ancestors.isEmpty)
            statusView = nil; statusHeight = 0
        } else {
            focalView = nil; focalHeight = 0
            buildStatus(loading: loading)
        }
        rebuildItems()
        table.reloadData()
        restore(anchor: anchor)
    }

    func scrollToTop() { scrollView.scrollToTop() }

    private func rebuildItems() {
        var next: [Item] = []
        if let post {
            for anc in ancestors { next.append(.ancestor(anc)) }
            next.append(.focal(post))
            for c in replyRoots { next.append(.comment(c)) }
            if let more, more.hasMore { next.append(.showMore) }
        } else {
            next.append(.status)
        }
        items = next
    }

    private func rebuildFocal(post: Post, hasAncestors: Bool) {
        let v = Screens.focalPost(post: post, hasAncestors: hasAncestors, width: width, callbacks: callbacks,
                                  onMediaHeightChanged: { [weak self] in self?.refreshFocalHeight() },
                                  onFollowToggled: { [weak self] in self?.refreshFocalHeight() })
        focalView = v
        focalHeight = v.frame.height
    }

    private func buildStatus(loading: Bool) {
        let v: NSView
        if loading {
            v = DetailSkeletonView(width: width, isX: isX)
        } else {
            let container = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 150))
            container.bgColor = theme.bgBase
            let l = makeLabel("Post unavailable", font: Fonts.sans(15), color: theme.fgSubdued, align: .center)
            l.frame = NSRect(x: 28, y: 64, width: width - 56, height: 22)
            container.addSubview(l)
            v = container
        }
        statusView = v
        statusHeight = v.frame.height
    }

    /// The focal media resolved its height (or Follow toggled): the focal row's
    /// `doc.rebuild` already re-laid it, so re-read its height and reflow around it.
    private func refreshFocalHeight() {
        guard let focalView,
              let row = items.firstIndex(where: { if case .focal = $0 { return true }; return false }) else { return }
        let anchor = currentAnchor()
        focalHeight = focalView.frame.height
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
        restore(anchor: anchor)
    }

    /// Page in more replies below the loaded ones, refreshing in place so the
    /// reader's scroll position is kept.
    private func loadMore() {
        guard let more, more.hasMore, !showMoreLoading else { return }
        showMoreLoading = true
        if let r = items.firstIndex(where: { if case .showMore = $0 { return true }; return false }) {
            table.reloadData(forRowIndexes: IndexSet(integer: r), columnIndexes: IndexSet(integer: 0))
        }
        more.load { [weak self] roots, hasMore in
            guard let self else { return }
            self.showMoreLoading = false
            self.replyRoots = roots
            self.more = DetailMore(hasMore: hasMore, load: more.load)
            var live = Set(roots.map { $0.id })
            live.formUnion(self.ancestors.map { $0.id })
            self.heightCache = self.heightCache.filter { live.contains($0.key) }
            let anchor = self.currentAnchor()
            self.rebuildItems()
            self.table.reloadData()
            self.restore(anchor: anchor)
        }
    }

    private func makeShowMoreRow() -> NSView {
        let theme = self.theme
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        row.wantsLayer = true
        let title = showMoreLoading ? (isX ? "Loading…" : "加载中…")
                                    : (isX ? "Show more replies" : "显示更多回复")
        let lbl = makeLabel(title, font: Fonts.sans(14.5, .semibold), color: theme.accent, align: .center)
        lbl.frame = NSRect(x: 16, y: (52 - lbl.intrinsicContentSize.height) / 2,
                           width: width - 32, height: lbl.intrinsicContentSize.height)
        row.addSubview(lbl)
        if !showMoreLoading {
            row.onState = { [weak row] h, _ in row?.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor }
            row.onClick = { [weak self] in self?.loadMore() }
        }
        Screens.addBottomBorder(row, theme: theme)
        return row
    }

    // ── Anchor (scroll position preservation) ──

    func currentAnchor() -> TimelineAnchor {
        let visibleY = scrollView.contentView.bounds.origin.y
        guard scrollView.documentView === table else {
            return TimelineAnchor(postId: nil, offset: 0, fallbackY: visibleY)
        }
        let row = table.row(at: NSPoint(x: 2, y: visibleY + 1))
        if row >= 0, row < items.count, let id = items[row].rowId {
            let rect = table.rect(ofRow: row)
            return TimelineAnchor(postId: id, offset: visibleY - rect.minY, fallbackY: visibleY)
        }
        return TimelineAnchor(postId: nil, offset: 0, fallbackY: visibleY)
    }

    func restore(anchor: TimelineAnchor) {
        guard scrollView.documentView === table else { return }
        table.layoutSubtreeIfNeeded()
        let targetY: CGFloat
        if let id = anchor.postId, let row = rowForId(id) {
            targetY = table.rect(ofRow: row).minY + anchor.offset
        } else {
            targetY = anchor.fallbackY
        }
        let maxY = max(0, table.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, targetY), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func rowForId(_ id: String) -> Int? {
        items.firstIndex { $0.rowId == id }
    }

    // ── NSTableViewDataSource / Delegate ──

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < items.count else { return 1 }
        switch items[row] {
        case .ancestor(let p):
            if let h = heightCache[p.id] { return h }
            if sizer == nil { sizer = PostCellView(post: p, width: width, callbacks: callbacks) }
            let h = sizer!.measuredHeight(for: p)
            heightCache[p.id] = h
            return h
        case .focal:
            return focalHeight > 0 ? focalHeight : 1
        case .status:
            return statusHeight > 0 ? statusHeight : 1
        case .showMore:
            return 52
        case .comment(let c):
            if let h = heightCache[c.id] { return h }
            let h = CommentNodeView.contentHeight(comment: c, width: width)
            heightCache[c.id] = h
            return h
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        switch items[row] {
        case .ancestor(let p):
            let cell: PostCellView
            if let reused = table.makeView(withIdentifier: Self.ancestorId, owner: self) as? PostCellView {
                cell = reused
                cell.configure(post: p)
            } else {
                cell = PostCellView(post: p, width: width, callbacks: callbacks)
                cell.identifier = Self.ancestorId
            }
            cell.onHeightChanged = { [weak self, weak cell] in
                guard let self, let cell else { return }
                let id = cell.post.id
                self.heightCache[id] = nil
                let anchor = self.currentAnchor()
                if let r = self.rowForId(id) {
                    self.table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: r))
                }
                self.restore(anchor: anchor)
            }
            return cell
        case .focal:
            return focalView
        case .status:
            return statusView
        case .showMore:
            return makeShowMoreRow()
        case .comment(let c):
            let cell: CommentNodeView
            if let reused = table.makeView(withIdentifier: CommentNodeView.reuseId, owner: self) as? CommentNodeView {
                cell = reused
                cell.configure(comment: c)
            } else {
                cell = CommentNodeView(comment: c, width: width,
                    onOpenProfile: { [weak self] p in self?.callbacks.onOpenProfile(p) },
                    onMention: { [weak self] h in self?.callbacks.onMention(h) },
                    onReply: { [weak self] c in self?.callbacks.onReply(Self.postFrom(c)) },
                    onOpenPost: { [weak self] c in self?.callbacks.onOpenPost(Self.postFrom(c)) })
                cell.identifier = CommentNodeView.reuseId
            }
            return cell
        }
    }

    /// A lightweight `Post` carrying only what navigation / reply need: its `id`
    /// drives `pushScreen`/`resolvePost` (which then returns the real cached post),
    /// the author/text/stats render the brief pre-refresh focal state.
    private static func postFrom(_ c: Comment) -> Post {
        Post(id: c.id, author: c.author, time: c.time, text: c.text, media: nil, stats: c.stats)
    }

    /// Disable the default selection/hover row background.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
