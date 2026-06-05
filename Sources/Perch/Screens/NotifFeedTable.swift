import AppKit

/// Load state for the notification feed (mirrors `TimelineStatus`).
enum NotifStatus { case loading, error, empty, ready }

private final class NotificationFeedScrollView: NSScrollView {
    var onUserScroll: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        DispatchQueue.main.async { [weak self] in
            self?.onUserScroll?()
        }
    }
}

/// Virtualized notification list backed by an `NSTableView`, symmetric with
/// `TimelineFeed`: only on-screen rows instantiate a full `NotifCellView`;
/// off-screen rows cost a cheap cached height measurement. Replaces the old
/// all-views-at-once `FeedDocument` stacking in `NotifCenterPanel`.
final class NotificationFeed: NSObject, NSTableViewDataSource, NSTableViewDelegate, ColumnFeed {
    let scrollView: NSScrollView
    private let table = NSTableView()
    private let theme = ThemeManager.shared.theme

    private let width: CGFloat
    private let callbacks: NotifCallbacks

    private var items: [NotifItem] = []
    private var unreadIds: Set<String> = []
    private var status: NotifStatus = .loading
    private var isX = true

    /// Height cache keyed by notif id (width is fixed per feed instance).
    private var heightCache: [String: CGFloat] = [:]
    /// One reusable cell used only for off-screen height measurement (no image loads).
    private var sizer: NotifCellView?

    /// Fired after the user scrolls near the bottom (older-page paging).
    var onNearBottom: (() -> Void)?

    private static let cellId = NSUserInterfaceItemIdentifier("notif")

    init(width: CGFloat, callbacks: NotifCallbacks) {
        let scroll = NotificationFeedScrollView()
        self.scrollView = makeColumnScroll(scroll)
        self.width = width
        self.callbacks = callbacks
        super.init()
        scroll.onUserScroll = { [weak self] in self?.checkNearBottomAfterUserScroll() }

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

    func update(items: [NotifItem], unreadIds: Set<String>, status: NotifStatus, isX: Bool) {
        self.unreadIds = unreadIds
        self.status = status
        self.isX = isX
        // Drop height-cache entries for notifs no longer present.
        let live = Set(items.map { $0.id })
        heightCache = heightCache.filter { live.contains($0.key) }
        self.items = items

        if !items.isEmpty {
            if scrollView.documentView !== table { scrollView.documentView = table }
            table.reloadData()
        } else {
            showPlaceholder()
        }
    }

    private func showPlaceholder() {
        let placeholder: NSView
        switch status {
        case .loading:
            placeholder = NotifSkeletonView(width: width, isX: isX)
        case .error:
            placeholder = Screens.emptyState(
                title: isX ? "Couldn’t load notifications" : "无法加载通知",
                sub: isX ? "Pull to try again." : "下拉重试。", width: width, top: 64)
        default:
            placeholder = Screens.emptyState(
                title: isX ? "Nothing here yet" : "这里还什么都没有",
                sub: isX ? "New activity will show up here." : "新的互动会显示在这里。",
                width: width, top: 64)
        }
        scrollView.documentView = placeholder
    }

    func scrollToTop() { scrollView.scrollToTop() }

    // ── Anchor (scroll position preservation) ──

    func currentAnchor() -> TimelineAnchor {
        let visibleY = scrollView.contentView.bounds.origin.y
        guard scrollView.documentView === table else {
            return TimelineAnchor(postId: nil, offset: 0, fallbackY: visibleY)
        }
        let row = table.row(at: NSPoint(x: 2, y: visibleY + 1))
        if row >= 0, row < items.count {
            let rect = table.rect(ofRow: row)
            return TimelineAnchor(postId: items[row].id, offset: visibleY - rect.minY, fallbackY: visibleY)
        }
        return TimelineAnchor(postId: nil, offset: 0, fallbackY: visibleY)
    }

    func restore(anchor: TimelineAnchor) {
        guard scrollView.documentView === table else { return }
        table.layoutSubtreeIfNeeded()
        let targetY: CGFloat
        if let id = anchor.postId, let row = rowForNotif(id) {
            targetY = table.rect(ofRow: row).minY + anchor.offset
        } else {
            targetY = anchor.fallbackY
        }
        let maxY = max(0, table.frame.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, targetY), maxY)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func rowForNotif(_ id: String) -> Int? {
        items.firstIndex { $0.id == id }
    }

    private func checkNearBottomAfterUserScroll() {
        guard scrollView.documentView === table, !items.isEmpty else { return }
        table.layoutSubtreeIfNeeded()
        let visible = scrollView.contentView.bounds
        let remaining = table.bounds.height - visible.maxY
        if remaining <= 240 {
            onNearBottom?()
        }
    }

    // ── NSTableViewDataSource / Delegate ──

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= 0, row < items.count else { return 1 }
        let n = items[row]
        if let h = heightCache[n.id] { return h }
        let unread = unreadIds.contains(n.id)
        if sizer == nil { sizer = NotifCellView(notif: n, unread: unread, width: width, isX: isX, callbacks: callbacks) }
        let h = sizer!.measuredHeight(for: n, unread: unread)
        heightCache[n.id] = h
        return h
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < items.count else { return nil }
        let n = items[row]
        let unread = unreadIds.contains(n.id)
        let cell: NotifCellView
        if let reused = table.makeView(withIdentifier: Self.cellId, owner: self) as? NotifCellView {
            cell = reused
            cell.configure(notif: n, unread: unread)
        } else {
            cell = NotifCellView(notif: n, unread: unread, width: width, isX: isX, callbacks: callbacks)
            cell.identifier = Self.cellId
        }
        cell.onHeightChanged = { [weak self, weak cell] in
            guard let self, let cell else { return }
            let id = cell.notif.id
            self.heightCache[id] = nil
            let anchor = self.currentAnchor()
            if let r = self.rowForNotif(id) {
                self.table.noteHeightOfRows(withIndexesChanged: IndexSet(integer: r))
            }
            self.restore(anchor: anchor)
        }
        return cell
    }

    /// Disable the default selection/hover row background.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}
