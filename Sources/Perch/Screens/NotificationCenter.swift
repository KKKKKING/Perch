import AppKit

/// Segmented filter strip atop the notification center: 6 pills in a rounded
/// track + a mark-all-read button. The selected pill expands to show its label.
final class NotifTabStrip: FlippedView {
    static let height: CGFloat = 54
    var onSelect: ((String) -> Void)?
    var onMarkRead: (() -> Void)?
    private let theme = ThemeManager.shared.theme

    init(width: CGFloat, isX: Bool, selected: String, unreadFilters: Set<String>, hasUnread: Bool) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        bgColor = theme.bgBase
        autoresizingMask = [.width]

        let padX: CGFloat = 12, padY: CGFloat = 8
        let markW: CGFloat = 34
        let trackX = padX
        let trackW = width - padX - markW - 8 - trackX

        let track = FlippedView(frame: NSRect(x: trackX, y: padY, width: trackW, height: 38))
        track.wantsLayer = true
        track.layer?.cornerRadius = 19
        track.layer?.backgroundColor = theme.gray100.cgColor
        track.autoresizingMask = [.width]
        addSubview(track)

        var x: CGFloat = 3
        for f in NOTIF_FILTERS {
            let sel = f.id == selected
            let labelText = isX ? f.labelX : f.labelW
            let lw = sel ? makeLabel(labelText, font: Fonts.sans(13, .bold), color: theme.fgHeading).intrinsicContentSize.width : 0
            let pillW: CGFloat = sel ? (14 + 15 + 6 + lw + 14) : 34
            let pill = HoverControl(frame: NSRect(x: x, y: 3, width: pillW, height: 32))
            pill.wantsLayer = true
            pill.layer?.cornerRadius = 16
            let iconColor = sel ? theme.fgHeading : theme.fgSubdued
            if sel {
                pill.layer?.backgroundColor = theme.bgElevated.cgColor
                pill.layer?.shadowColor = NSColor.black.cgColor
                pill.layer?.shadowOpacity = 0.12
                pill.layer?.shadowRadius = 3
                pill.layer?.shadowOffset = CGSize(width: 0, height: 1)
                let icon = KindIconView(glyph: f.glyph, char: f.char, size: 15, color: iconColor)
                icon.frame = NSRect(x: 14, y: (32 - 15) / 2, width: 15, height: 15)
                pill.addSubview(icon)
                let l = makeLabel(labelText, font: Fonts.sans(13, .bold), color: theme.fgHeading)
                l.frame = NSRect(x: 14 + 15 + 6, y: (32 - l.intrinsicContentSize.height) / 2, width: lw, height: l.intrinsicContentSize.height)
                pill.addSubview(l)
            } else {
                let icon = KindIconView(glyph: f.glyph, char: f.char, size: 15, color: iconColor)
                icon.frame = NSRect(x: (34 - 15) / 2, y: (32 - 15) / 2, width: 15, height: 15)
                pill.addSubview(icon)
                pill.onState = { [weak pill] h, _ in pill?.layer?.backgroundColor = (h ? self.theme.gray400.withAlphaComponent(0.38) : NSColor.clear).cgColor }
                if unreadFilters.contains(f.id) {
                    let dot = FlippedView(frame: NSRect(x: 34 - 11, y: 5, width: 6, height: 6))
                    dot.wantsLayer = true; dot.layer?.cornerRadius = 3
                    dot.layer?.backgroundColor = theme.accent.cgColor
                    pill.addSubview(dot)
                }
            }
            pill.onClick = { [weak self] in self?.onSelect?(f.id) }
            track.addSubview(pill)
            x += pillW + 3
        }

        // mark-all-read button
        let mark = HoverControl(frame: NSRect(x: width - padX - markW, y: padY + 2, width: markW, height: markW))
        mark.autoresizingMask = [.minXMargin]
        mark.wantsLayer = true
        mark.layer?.cornerRadius = 9
        let mg = GlyphView(name: "checkmark-circle", size: 19, color: hasUnread ? theme.fgSubdued : theme.fgDisabled)
        mg.frame = NSRect(x: (markW - 19) / 2, y: (markW - 19) / 2, width: 19, height: 19)
        mark.addSubview(mg)
        mark.toolTip = isX ? "Mark all as read" : "全部标为已读"
        if hasUnread {
            mark.onState = { [weak mark] h, _ in mark?.layer?.backgroundColor = (h ? self.theme.gray100 : NSColor.clear).cgColor }
            mark.onClick = { [weak self] in self?.onMarkRead?() }
        } else {
            mark.enabledControl = false
        }
        addSubview(mark)

        let line = NSView(frame: NSRect(x: 0, y: Self.height - 1, width: width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        line.autoresizingMask = [.width]
        addSubview(line)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The bell-column panel: pinned header + filter strip + virtualized feed.
/// Symmetric with timeline columns — the rows live in a `NotificationFeed`
/// (`NSTableView`), and auto-refresh runs on the shared 5-minute tick.
final class NotifCenterPanel: ColumnPanel {
    private let appState: AppState
    private let col: ColumnSpec
    private let width: CGFloat
    private let callbacks: NotifCallbacks
    private let theme = ThemeManager.shared.theme
    private let feed: NotificationFeed
    private var strip: NotifTabStrip?
    private var refreshBar: TimelineRefreshBar?

    init(appState: AppState, col: ColumnSpec, width: CGFloat, header: NSView, callbacks: NotifCallbacks) {
        self.appState = appState
        self.col = col
        self.width = width
        self.callbacks = callbacks
        self.feed = NotificationFeed(width: width, callbacks: callbacks)
        super.init(header: header, body: feed.scrollView)
        // Expose the virtualized feed to `ColumnView` for anchor/scroll plumbing.
        columnFeed = feed
        feed.onNearBottom = { [weak self] in self?.maybeLoadMore() }
        refresh()
        // First-open load for the current tab — deferred so we don't re-enter the canvas
        // rebuild that created this panel. No-op if the tab already loaded; arriving data
        // rebuilds the canvas with live rows.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.ensureNotificationsLoaded(for: self.col)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func maybeLoadMore() {
        guard appState.notifHasMore(for: col), !appState.notifIsLoading(for: col) else { return }
        appState.loadMoreNotifications(for: col) { [weak self] in self?.refreshFeed() }
    }

    private func refresh() {
        rebuildStrip()
        refreshFeed()
        needsLayout = true
    }

    private func rebuildStrip() {
        strip?.removeFromSuperview()
        let isX = appState.colAccount(col).platform == .x
        // Tabs are server feeds — we can only judge unread for the loaded (current) tab.
        let hasUnread = appState.notificationsFor(col).contains { appState.notifIsUnread(col.id, $0) }
        let s = NotifTabStrip(width: width, isX: isX, selected: appState.notifFilterFor(col.id),
                              unreadFilters: [], hasUnread: hasUnread)
        s.onSelect = { [weak self] f in
            guard let self else { return }
            guard f != self.appState.notifFilterFor(self.col.id) else { return }
            self.appState.setNotifFilter(self.col.id, f)
            self.appState.ensureNotificationsLoaded(for: self.col)   // fetch only if this tab unloaded
            self.refresh()
        }
        s.onMarkRead = { [weak self] in
            guard let self else { return }
            self.appState.markAllNotifsRead(self.col)
        }
        strip = s
        addSubview(s)
    }

    /// Recompute the feed's rows + status from app state and hand them to the table.
    private func refreshFeed() {
        let isX = appState.colAccount(col).platform == .x
        let env = ProcessInfo.processInfo.environment["PERCH_NOTIF"]   // dev snapshot override
        let rows = env == "sample" ? NotifSample.items(isX: isX) : appState.notificationsFor(col)
        let status = appState.notificationStatus(for: col)
        let unreadIds: Set<String>
        if env == "sample" {
            unreadIds = Set(rows.filter { $0.unread }.map { $0.id })
        } else {
            unreadIds = Set(rows.filter { appState.notifIsUnread(col.id, $0) }.map { $0.id })
        }
        feed.update(items: rows, unreadIds: unreadIds, status: status, isX: isX)
        updateRefreshBar()
    }

    private func updateRefreshBar() {
        let refreshing = appState.notificationIsRefreshing(for: col)
        if refreshing, refreshBar == nil {
            let bar = TimelineRefreshBar()
            refreshBar = bar
            addSubview(bar)
            needsLayout = true
        } else if !refreshing, let bar = refreshBar {
            bar.removeFromSuperview()
            refreshBar = nil
            needsLayout = true
        }
    }

    override func layout() {
        let stripH = NotifTabStrip.height
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 54)
        strip?.frame = NSRect(x: 0, y: 54, width: bounds.width, height: stripH)
        var y: CGFloat = 54 + stripH
        if let bar = refreshBar {
            bar.frame = NSRect(x: 0, y: y, width: bounds.width, height: 2)
            y += 2
        }
        body.frame = NSRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
    }
}

/// Static sample notifications for `PERCH_NOTIF=sample` snapshots — covers all six
/// kinds (aggregated + engagement). Used only on the debug path; live columns never
/// see this (`notificationsFor` still returns `[]` off a real session).
enum NotifSample {
    static func items(isX: Bool) -> [NotifItem] {
        let alice = Person(name: "Alice Chen", handle: "alicechen", colorToken: "indigo-700", verified: true, platform: .x)
        let bob = Person(name: "Bob Rivera", handle: "brivera", colorToken: "seafoam-800", verified: false, platform: .x)
        let carol = Person(name: "Carol Ng", handle: "carolng", colorToken: "magenta-800", verified: true, platform: .x)
        let dave = Person(name: "Dave Park", handle: "davepark", colorToken: "orange-800", verified: false, platform: .x)
        let me = Person(name: "You", handle: "you", colorToken: "purple-800", verified: false, platform: .x)

        let myPost = Post(id: "s_my1", author: me, time: "2h",
                          text: "Shipping the redesigned notification column today — virtualized rows, unified refresh. Feels good.",
                          stats: Stats(reposts: 2, likes: 14))
        let myPhoto = Post(id: "s_my2", author: me, time: "6h", text: "Sunset over the bay tonight.",
                           media: Media(type: .images, items: [MediaItem(Gradient("#f59e0b", "#ef4444"))]),
                           stats: Stats(reposts: 5, likes: 40))
        let mentionPost = Post(id: "s_men1", author: bob, time: "3h",
                               text: "Look what @you just shipped — buttery smooth scrolling.",
                               media: Media(type: .images, items: [MediaItem(Gradient("#6366f1", "#a855f7"))]),
                               stats: Stats(reposts: 1, likes: 8))
        let quotePost = Post(id: "s_q1", author: carol, time: "4h", text: "This is the way. 👏",
                             stats: Stats(reposts: 3, likes: 21))
        quotePost.quote = Quote(author: me, time: "5h",
                                text: "Native AppKit, no SwiftUI, pixel-for-pixel with the prototype.", media: nil)

        return [
            NotifItem(id: "s1", kind: .like, actors: [alice, bob, carol, dave], count: 12, time: "1h", unread: true, post: myPost),
            NotifItem(id: "s2", kind: .reply, actors: [bob], time: "2h", unread: true, post: myPost,
                      text: "Congrats! Does it keep the scroll position across an auto-refresh?"),
            NotifItem(id: "s3", kind: .follow, actors: [dave], count: 1, time: "3h",
                      bio: "Building developer tools. Coffee enthusiast. Occasional runner.", single: true),
            NotifItem(id: "s4", kind: .mention, actors: [bob], time: "3h", post: mentionPost),
            NotifItem(id: "s5", kind: .repost, actors: [carol, alice], count: 2, time: "5h", post: myPhoto),
            NotifItem(id: "s6", kind: .quote, actors: [carol], time: "4h", post: quotePost),
        ]
    }
}
