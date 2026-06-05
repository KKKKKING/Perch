import AppKit

/// Virtualized timeline list backed by an `NSTableView`. Only on-screen rows
/// instantiate a full `PostCellView`; off-screen rows cost a cheap cached height
/// measurement. Replaces the old all-views-at-once `FeedDocument` stacking.
final class TimelineFeed: NSObject, NSTableViewDataSource, NSTableViewDelegate, ColumnFeed {
    let scrollView: NSScrollView
    private let table = NSTableView()
    private let theme = ThemeManager.shared.theme

    private let width: CGFloat
    private let isX: Bool
    private let isSearch: Bool
    private let type: String
    private var callbacks: PostCallbacks
    private let searchQuery: String
    private let onSearchSubmit: ((String) -> Void)?
    private let onRetry: () -> Void
    private let onGap: (String) -> Void

    private enum Item {
        case searchHeader
        case status(TimelineStatus)   // skeleton / empty / error shown beneath the search header
        case post(Post)
        case gap(TimelineGap)
        var postId: String? { if case .post(let p) = self { return p.id }; return nil }
    }
    private var items: [Item] = []
    private var status: TimelineStatus = .loading
    private var refreshing = false

    /// Height cache keyed by post id (width is fixed per feed instance).
    private var heightCache: [String: CGFloat] = [:]
    /// One reusable cell used only for off-screen height measurement (no image loads).
    private var sizer: PostCellView?
    /// The search field + trending list is one persistent view (preserves typed text
    /// across reloads). Its height is fixed for a given width.
    private var searchHeaderView: NSView?
    private var searchHeaderHeight: CGFloat = 0
    /// The status placeholder shown beneath the search field when a query has no posts.
    private var statusView: NSView?
    private var statusHeight: CGFloat = 0

    private var hasActiveQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static let postId = NSUserInterfaceItemIdentifier("post")

    init(width: CGFloat, isX: Bool, isSearch: Bool, type: String, callbacks: PostCallbacks,
         searchQuery: String = "", onSearchSubmit: ((String) -> Void)? = nil,
         onRetry: @escaping () -> Void, onGap: @escaping (String) -> Void) {
        self.scrollView = makeColumnScroll()
        self.width = width
        self.isX = isX
        self.isSearch = isSearch
        self.type = type
        self.callbacks = callbacks
        self.searchQuery = searchQuery
        self.onSearchSubmit = onSearchSubmit
        self.onRetry = onRetry
        self.onGap = onGap
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

    func update(rows: [TimelineRow], status: TimelineStatus, refreshing: Bool) {
        self.status = status
        self.refreshing = refreshing
        // Drop height-cache entries for posts no longer present.
        let live = Set(rows.compactMap { $0.postId })
        heightCache = heightCache.filter { live.contains($0.key) }
        let hasContent = rows.contains { $0.postId != nil || $0.gapId != nil }

        // The search column always keeps its field + trending list visible (设计稿
        // renders SearchHeader above the feed), so it never falls back to the bare
        // placeholder — loading/empty/error appear as a row beneath the field instead.
        if isSearch {
            var next: [Item] = [.searchHeader]
            if hasContent {
                for row in rows {
                    switch row {
                    case .post(let p): next.append(.post(p))
                    case .gap(let g): next.append(.gap(g))
                    }
                }
            } else if hasActiveQuery {
                next.append(.status(status))
            }
            prepareSearchViews(showStatus: !hasContent && hasActiveQuery, status: status)
            items = next
            if scrollView.documentView !== table { scrollView.documentView = table }
            table.reloadData()
            return
        }

        var next: [Item] = []
        for row in rows {
            switch row {
            case .post(let p): next.append(.post(p))
            case .gap(let g): next.append(.gap(g))
            }
        }
        items = next

        if hasContent {
            if scrollView.documentView !== table { scrollView.documentView = table }
            table.reloadData()
        } else {
            showPlaceholder()
        }
    }

    /// Build (once) the persistent search-field view and, when needed, the status
    /// placeholder, caching both heights so `heightOfRow` has them before `viewFor`.
    private func prepareSearchViews(showStatus: Bool, status: TimelineStatus) {
        if searchHeaderView == nil {
            let v = Screens.searchHeader(isX: isX, width: width, query: searchQuery,
                                         onSubmit: { [weak self] q in self?.onSearchSubmit?(q) })
            searchHeaderView = v
            searchHeaderHeight = v.frame.height
        }
        guard showStatus else { statusView = nil; statusHeight = 0; return }
        let v: NSView
        switch status {
        case .loading:
            v = TimelineSkeletonView(width: width, isX: isX, count: 3)
        case .error:
            v = TimelineErrorView(width: width, isX: isX, retrying: refreshing, onRetry: onRetry)
        default:
            v = Screens.timelineEmptyState(isX: isX, type: type, width: width)
        }
        statusView = v
        statusHeight = v.frame.height
    }

    private func showPlaceholder() {
        let placeholder: NSView
        if status == .loading {
            placeholder = TimelineSkeletonView(width: width, isX: isX)
        } else if status == .error {
            placeholder = TimelineErrorView(width: width, isX: isX, retrying: refreshing, onRetry: onRetry)
        } else {
            placeholder = Screens.timelineEmptyState(isX: isX, type: type, width: width)
        }
        scrollView.documentView = placeholder
    }

    func scrollToTop() { scrollView.scrollToTop() }

    /// Cheap action-bar refresh for a single post (no height change). Updates the
    /// backing item too so off-screen rows re-display with the merged state.
    func updatePost(_ id: String, merged: Post) {
        guard scrollView.documentView === table else { return }
        let visible = table.rows(in: table.visibleRect)
        for (idx, item) in items.enumerated() where item.postId == id {
            items[idx] = .post(merged)
            guard visible.length > 0, idx >= visible.location, idx < visible.location + visible.length else { continue }
            if let cell = table.view(atColumn: 0, row: idx, makeIfNecessary: false) as? PostCellView {
                cell.refresh(with: merged)
            }
        }
    }

    // ── Anchor (scroll position preservation) ──

    func currentAnchor() -> TimelineAnchor {
        let visibleY = scrollView.contentView.bounds.origin.y
        guard scrollView.documentView === table else {
            return TimelineAnchor(postId: nil, offset: 0, fallbackY: visibleY)
        }
        let row = table.row(at: NSPoint(x: 2, y: visibleY + 1))
        if row >= 0, row < items.count, let postId = items[row].postId {
            let rect = table.rect(ofRow: row)
            return TimelineAnchor(postId: postId, offset: visibleY - rect.minY, fallbackY: visibleY)
        }
        return TimelineAnchor(postId: nil, offset: 0, fallbackY: visibleY)
    }

    func unreadPostIdsReached(_ unreadIds: Set<String>) -> [String] {
        guard !unreadIds.isEmpty, scrollView.documentView === table else { return [] }
        table.layoutSubtreeIfNeeded()
        let visibleTop = scrollView.contentView.bounds.origin.y
        var reached: [String] = []
        for (idx, item) in items.enumerated() {
            guard let postId = item.postId, unreadIds.contains(postId) else { continue }
            let rect = table.rect(ofRow: idx)
            if rect.maxY > visibleTop + 1 {
                reached.append(postId)
            }
        }
        return reached
    }

    func restore(anchor: TimelineAnchor) {
        guard scrollView.documentView === table else { return }
        table.layoutSubtreeIfNeeded()
        let targetY: CGFloat
        if let id = anchor.postId, let row = rowForPost(id) {
            targetY = table.rect(ofRow: row).minY + anchor.offset
        } else {
            targetY = anchor.fallbackY
        }
        let maxY = max(0, table.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, targetY), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func rowForPost(_ id: String) -> Int? {
        items.firstIndex { $0.postId == id }
    }

    // ── NSTableViewDataSource / Delegate ──

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < items.count else { return 1 }
        switch items[row] {
        case .searchHeader:
            return searchHeaderHeight > 0 ? searchHeaderHeight : 1
        case .status:
            return statusHeight > 0 ? statusHeight : 1
        case .gap:
            return TimelineGapView.rowHeight
        case .post(let p):
            if let h = heightCache[p.id] { return h }
            if sizer == nil { sizer = PostCellView(post: p, width: width, callbacks: callbacks) }
            let h = sizer!.measuredHeight(for: p)
            heightCache[p.id] = h
            return h
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        switch items[row] {
        case .searchHeader:
            return searchHeaderView ?? Screens.searchHeader(isX: isX, width: width, query: searchQuery,
                                                             onSubmit: { [weak self] q in self?.onSearchSubmit?(q) })
        case .status:
            return statusView ?? NSView()
        case .gap(let gap):
            return TimelineGapView(gap: gap, width: width, isX: isX) { [onGap] in onGap(gap.id) }
        case .post(let p):
            let cell: PostCellView
            if let reused = table.makeView(withIdentifier: Self.postId, owner: self) as? PostCellView {
                cell = reused
                cell.configure(post: p)
            } else {
                cell = PostCellView(post: p, width: width, callbacks: callbacks)
                cell.identifier = Self.postId
            }
            cell.onHeightChanged = { [weak self, weak cell] in
                guard let self, let cell else { return }
                let id = cell.post.id
                self.heightCache[id] = nil
                let anchor = self.currentAnchor()
                if let r = self.rowForPost(id) {
                    self.table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: r))
                }
                self.restore(anchor: anchor)
            }
            return cell
        }
    }

    /// Disable the default selection/hover row background.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
