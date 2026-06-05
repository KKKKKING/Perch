import AppKit

protocol AppStateDelegate: AnyObject {
    func appStateDidChangeTheme(_ s: AppState)
    func appStateDidChangeColumns(_ s: AppState)
    func appStateDidChangeActive(_ s: AppState)
    func appState(_ s: AppState, didChangeTimelineUnreadForColumn colId: String)
    func appState(_ s: AppState, didUpdatePost id: String)
    /// A specific detail thread / profile finished (re)loading — refresh only that
    /// pushed panel in place rather than rebuilding the whole canvas (no flicker).
    func appState(_ s: AppState, didChangeDetailFor id: String)
    func appState(_ s: AppState, didChangeProfileFor handle: String)
    func appState(_ s: AppState, didChangeNavForColumn colId: String)
    func appStateDidChangeCompose(_ s: AppState)
    func appState(_ s: AppState, showToast text: String)
    func appState(_ s: AppState, didAddReplyTo postId: String)
    func appStateDidChangeSettings(_ s: AppState)
    func appStateDidChangeAddAccount(_ s: AppState)
    func appStateDidChangeMediaViewer(_ s: AppState)
    func appStateRequestsWelcome(_ s: AppState)
    func appStateDidConnectFirstAccount(_ s: AppState)
    func appStateDidChangeNavConfig(_ s: AppState)
    func appStateDidChangeNavConfigOpen(_ s: AppState)
    func appStateDidChangeDebug(_ s: AppState)
    func appStateDidChangeInspector(_ s: AppState)
    func appState(_ s: AppState, openJsonViewer ctx: JsonViewerContext)
}

/// No-op defaults so a conformer (e.g. WelcomeViewController) needn't implement the
/// debug hooks it doesn't use.
extension AppStateDelegate {
    func appState(_ s: AppState, didChangeTimelineUnreadForColumn colId: String) {}
    func appStateDidChangeDebug(_ s: AppState) {}
    func appStateDidChangeInspector(_ s: AppState) {}
    func appState(_ s: AppState, openJsonViewer ctx: JsonViewerContext) {}
    func appState(_ s: AppState, didChangeDetailFor id: String) {}
    func appState(_ s: AppState, didChangeProfileFor handle: String) {}
}

/// Centralized, observable app state — mirrors the React state in shell.jsx.
final class AppState {
    private struct NavHistoryEntry {
        let colId: String
        let fromStack: [NavScreen]
        let toStack: [NavScreen]
    }

    weak var delegate: AppStateDelegate?

    private(set) var mode: ThemeMode = .system
    var accounts: [Account] = []
    var activeId: String = ""
    var columns: [ColumnSpec] = []
    /// One stable ColumnSpec per primary (sidebar) content type, so each sidebar
    /// timeline owns its own colNav push stack (keyed by the spec's id).
    private var primarySpecs: [String: ColumnSpec] = [:]
    var unread: [String: Int] = [:]
    var overrides: [String: [String: Bool]] = [:]
    var injected: [Platform: [Post]] = [.x: [], .weibo: []]
    var liveTimelines: [String: [Post]] = [:]   // accountId → live X posts
    var timelineNewAuthors: [String: [Person]] = [:]   // identity.key → TimelineShowAlert avatars
    var timelineTopCursor: [String: String] = [:]   // identity.key → fetch-newer (pull-to-refresh) cursor
    var timelineSnapshots: [String: TimelineSnapshot] = [:]
    private var loadingTimelineKeys: Set<String> = []
    private var refreshingTimelineKeys: Set<String> = []
    private var anchorPersistWork: [String: DispatchWorkItem] = [:]
    private let timelineStore = PersistentTimelineStore.shared
    var refreshEveryMinutes: String {
        get { UserDefaults.standard.string(forKey: "Perch.refreshEvery") ?? "5" }
        set {
            UserDefaults.standard.set(newValue, forKey: "Perch.refreshEvery")
            restartAutoRefresh()
        }
    }
    // ── Developer / debug tools (persisted; mirrored into DebugLog.shared) ──
    var debugEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "Perch.debugEnabled") as? Bool ?? false }
        set {
            UserDefaults.standard.set(newValue, forKey: "Perch.debugEnabled")
            DebugLog.shared.enabled = newValue
            delegate?.appStateDidChangeDebug(self)
        }
    }
    var debugJsonInline: Bool {
        get { UserDefaults.standard.object(forKey: "Perch.debugJsonInline") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "Perch.debugJsonInline")
            DebugLog.shared.jsonInline = newValue
            delegate?.appStateDidChangeDebug(self)
        }
    }
    var debugNetLog: Bool {
        get { UserDefaults.standard.object(forKey: "Perch.debugNetLog") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "Perch.debugNetLog")
            DebugLog.shared.netLog = newValue
            delegate?.appStateDidChangeDebug(self)
        }
    }
    /// Experimental: on user-initiated home refresh, pull *newer* via the stored
    /// top cursor (with seenTweetIds) so X may return its `TimelineShowAlert` and
    /// the new-posts pill shows real author avatars. Off → fresh launch refresh.
    /// Toggle live: `defaults write Perch perch.ptrRefresh -bool true`.
    var ptrRefresh: Bool {
        get { UserDefaults.standard.object(forKey: "perch.ptrRefresh") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "perch.ptrRefresh") }
    }
    private var autoRefreshTimer: Timer?
    private var autoRefreshActive = false
    private var badgeActiveRefreshTimer: Timer?
    private var badgeInactiveRefreshTimer: Timer?
    private var badgeInactiveRefreshStartWork: DispatchWorkItem?
    private static let badgeActiveRefreshInterval: TimeInterval = 30
    private static let badgeInactiveRefreshInterval: TimeInterval = 60
    private static let badgeInactiveRefreshStartupDelay: TimeInterval = 15
    private static let badgeRequestDedupeInterval: TimeInterval = 25
    // Notifications are keyed by "accountId|tab" — each of the 3 X tabs
    // (all / verified / mention) is an independent server feed.
    var liveNotifications: [String: [NotifItem]] = [:]   // accountId|tab → live X notifications
    var liveNotifCursor: [String: String] = [:]          // accountId|tab → bottom paging cursor
    var liveNotifLoadedAt: [String: Date] = [:]          // accountId|tab → last successful fetch (staleness)
    var notifLoading: Set<String> = []                   // accountId|tab keys with an in-flight fetch
    var notifErrored: Set<String> = []                   // accountId|tab keys whose last fetch failed (no cache)
    var notifAnchors: [String: TimelineAnchor] = [:]     // colId → scroll anchor (survives canvas rebuilds)
    private var badgeLoading: Set<String> = []            // accountIds with an in-flight badge_count fetch
    private var badgeLastRequestedAt: [String: Date] = [:] // suppress near-simultaneous lifecycle/timer duplicates
    private var badgeReadEpoch: [String: Int] = [:]       // bumped when local read clears should beat old responses

    // likes / bookmarks / search / lists columns — keyed by column id
    var liveColumns: [String: [Post]] = [:]
    var liveColCursor: [String: String] = [:]
    var colLoading: Set<String> = []
    var colErrored: Set<String> = []
    var searchQuery: [String: String] = [:]             // column id → search query

    // ── Lists (live X) ──
    var liveLists: [TwitterList] = []                   // the active account's lists
    var listSelection: [String: String] = [:]          // column id → selected list id
    private var listsLoading = false
    private var listsLoaded = false

    // ── Bookmark folders (live X) + Perch-local colors ──
    /// Curated folder palette (Spectrum tokens) — colors are a Perch-only cosmetic.
    static let bmPalette = ["blue-900", "magenta-800", "green-800", "orange-800",
                            "purple-800", "seafoam-800", "red-800", "cyan-800",
                            "indigo-700", "celery-800", "turquoise-800", "pink-700"]
    var liveBookmarkFolders: [BookmarkFolder] = []      // live X folders (name from X, color local)
    var bmFolderPosts: [String: [Post]] = [:]           // folderId → posts (live)
    var bmScope: [String: String] = [:]                 // colId → "__all__" | folderId
    private var bmFoldersLoading = false
    private var bmFoldersLoaded = false
    private var bmFolderLoading: Set<String> = []
    private var bmFolderColors: [String: String] = [:]  // folderId → colorToken (persisted)
    private let bmColorsKey = "Perch.bmFolderColors"

    // ── Configurable left-rail navigation (persisted) ──
    private(set) var navConfig = NavConfig.DEFAULT
    private let navConfigKey = "Perch.navConfig"

    // profile (keyed by handle) + author posts
    var liveProfiles: [String: Profile] = [:]
    var liveProfilePerson: [String: Person] = [:]
    var liveAuthorPosts: [String: [Post]] = [:]
    var profileLoading: Set<String> = []
    private var profileFetchedAt: [String: Date] = [:]

    // detail thread (keyed by root post id)
    var liveReplies: [String: [Comment]] = [:]
    var liveAncestors: [String: [Post]] = [:]   // conversation parents above the focal post
    var detailPosts: [String: Post] = [:]
    var detailLoading: Set<String> = []
    private var detailFetchedAt: [String: Date] = [:]
    /// Cached detail/profile older than this is re-fetched in the background on entry.
    private let detailStaleAfter: TimeInterval = 240
    // detail reply pagination
    private var detailRawPosts: [String: [Post]] = [:]   // focal id → all conversation posts fetched so far
    private var detailCursor: [String: String] = [:]     // focal id → bottom cursor for more replies
    private var detailLoadingMore: Set<String> = []
    var colNav: [String: [NavScreen]] = [:]
    private var backHistory: [NavHistoryEntry] = []
    private var forwardHistory: [NavHistoryEntry] = []
    var replies: [String: [Comment]] = [:]

    // local relationship state (keyed by user rest id) — drives menu labels
    var following: Set<String> = []
    var muted: Set<String> = []
    var blocked: Set<String> = []
    /// User ids with an in-flight follow/mute/block request — seeding skips these so
    /// fresh server data can't clobber an optimistic toggle mid-request.
    private var pendingRelationship: Set<String> = []

    // notification center state, keyed by column id (survives column reloads)
    var notifFilter: [String: String] = [:]
    var notifRead: [String: Set<String>] = [:]

    var composeOpen = false
    var composeFrom: String = ""
    var composeCtx: ComposeContext?

    var settingsOpen = false
    var addAccountOpen = false
    var navConfigOpen = false
    var inspectorOpen = false

    var mediaViewerOpen = false
    var mediaViewerCtx: MediaViewerContext?

    var theme: Theme { ThemeManager.shared.theme }

    init() {
        columns = [primarySpec(for: "home")]
        mode = ThemeManager.savedMode()
        let envOverride = ProcessInfo.processInfo.environment["PERCH_THEME"] == "light"
        if envOverride { mode = .light }
        // Don't persist the launch-time resolution: a first-launch `.system` stays
        // unpinned, and the snapshot env override never clobbers the real pref.
        ThemeManager.shared.setMode(mode, root: nil, persist: false)
        bmFolderColors = UserDefaults.standard.dictionary(forKey: bmColorsKey) as? [String: String] ?? [:]
        if let data = UserDefaults.standard.data(forKey: navConfigKey),
           let decoded = try? JSONDecoder().decode(NavConfig.self, from: data) {
            navConfig = normalizeNav(decoded)
        }
        DebugLog.shared.enabled = debugEnabled
        DebugLog.shared.jsonInline = debugJsonInline
        DebugLog.shared.netLog = debugNetLog
    }

    /// Populate the connected-accounts list from the restored live X session (if any).
    func seedAccounts() {
        for a in TwitterService.shared.accounts {
            if !accounts.contains(where: { $0.id == a.id }) { accounts.append(a) }
            unread[a.id!] = 0
            if activeId.isEmpty { activeId = a.id! }
            if composeFrom.isEmpty { composeFrom = a.id! }
        }
        TwitterService.shared.onAvatarBackfill = { [weak self] aid, url in
            guard let self, let acct = self.accounts.first(where: { $0.id == aid }) else { return }
            acct.avatarURL = url
            self.delegate?.appStateDidChangeActive(self)
        }
    }

    var hasAccounts: Bool { !accounts.isEmpty }
    func account(_ id: String) -> Account? { accounts.first { $0.id == id } }

    var active: Account { accounts.first { $0.id == activeId } ?? accounts.first! }

    // ── Theme ──
    func setMode(_ newMode: ThemeMode, root: NSView?) {
        guard newMode != mode else { return }
        mode = newMode
        ThemeManager.shared.setMode(newMode, root: root)
        delegate?.appStateDidChangeTheme(self)
    }

    func setAccent(_ id: String) {
        ThemeManager.shared.setAccent(id, root: nil)
        delegate?.appStateDidChangeTheme(self)
    }

    // ── Settings ──
    func openSettings() {
        settingsOpen = true
        delegate?.appStateDidChangeSettings(self)
    }

    func closeSettings() {
        settingsOpen = false
        delegate?.appStateDidChangeSettings(self)
    }

    // ── Developer Inspector + per-tweet JSON viewer ──
    func openInspector() {
        inspectorOpen = true
        delegate?.appStateDidChangeInspector(self)
    }

    func closeInspector() {
        inspectorOpen = false
        delegate?.appStateDidChangeInspector(self)
    }

    /// One-shot pass-through: RootViewController opens a fresh window per call so
    /// several tweet/column JSON viewers can coexist side by side.
    func openJsonViewer(_ ctx: JsonViewerContext) {
        delegate?.appState(self, openJsonViewer: ctx)
    }

    func openAddAccount() {
        addAccountOpen = true
        delegate?.appStateDidChangeAddAccount(self)
    }

    // ── Navigation config ──
    func openNavConfig() {
        navConfigOpen = true
        delegate?.appStateDidChangeNavConfigOpen(self)
    }

    func closeNavConfig() {
        navConfigOpen = false
        delegate?.appStateDidChangeNavConfigOpen(self)
    }

    /// Persist a new rail config (after normalize + ≥1-bar enforcement) and rebuild
    /// the rail. No-op when unchanged so live drags don't thrash persistence/redraw.
    func setNavConfig(_ next: NavConfig) {
        let normalized = normalizeNav(next)
        guard normalized != navConfig else { return }
        navConfig = normalized
        if let data = try? JSONEncoder().encode(normalized) {
            UserDefaults.standard.set(data, forKey: navConfigKey)
        }
        delegate?.appStateDidChangeNavConfig(self)
    }

    // ── Media viewer ──
    func openMediaViewer(_ ctx: MediaViewerContext) {
        guard !ctx.items.isEmpty else { return }
        mediaViewerCtx = ctx
        mediaViewerOpen = true
        delegate?.appStateDidChangeMediaViewer(self)
    }

    func closeMediaViewer() {
        mediaViewerOpen = false
        mediaViewerCtx = nil
        delegate?.appStateDidChangeMediaViewer(self)
    }

    func closeAddAccount() {
        addAccountOpen = false
        delegate?.appStateDidChangeAddAccount(self)
    }

    // ── X login window (own resizable browser) ──
    private var xLoginWC: XLoginWindowController?
    func beginXLogin() {
        if let wc = xLoginWC { wc.present(); return }
        let wc = XLoginWindowController(appState: self, onClose: { [weak self] in self?.xLoginWC = nil })
        xLoginWC = wc
        wc.present()
    }

    func addNewAccount(_ acct: Account) {
        let wasEmpty = accounts.isEmpty
        if !accounts.contains(where: { $0.id == acct.id }) { accounts.append(acct) }
        unread[acct.id!] = 0
        if composeFrom.isEmpty { composeFrom = acct.id! }
        closeAddAccount()
        let isLive = acct.platform == .x && TwitterService.shared.hasSession(accountId: acct.id)
        if isLive { activeId = acct.id! }
        if wasEmpty {
            delegate?.appStateDidConnectFirstAccount(self)
        } else {
            delegate?.appStateDidChangeActive(self)
            showToastNow(acct.platform == .x ? "Connected @\(acct.handle)" : "已连接 \(acct.name)")
        }
        if isLive {
            refreshLiveTimeline(for: acct)
            refreshBadgeCount(for: acct)
        }
    }

    /// Disconnect an account. When the last one is removed, request the Welcome window.
    func removeAccount(_ id: String) {
        accounts.removeAll { $0.id == id }
        liveTimelines[id] = nil
        let notifPrefix = "\(id)|"
        liveNotifications = liveNotifications.filter { !$0.key.hasPrefix(notifPrefix) }
        liveNotifCursor = liveNotifCursor.filter { !$0.key.hasPrefix(notifPrefix) }
        liveNotifLoadedAt = liveNotifLoadedAt.filter { !$0.key.hasPrefix(notifPrefix) }
        notifLoading.subtract(notifLoading.filter { $0.hasPrefix(notifPrefix) })
        notifErrored.subtract(notifErrored.filter { $0.hasPrefix(notifPrefix) })
        badgeLoading.remove(id)
        badgeLastRequestedAt[id] = nil
        badgeReadEpoch[id] = nil
        timelineSnapshots = timelineSnapshots.filter { $0.value.identity.accountId != id }
        timelineNewAuthors = timelineNewAuthors.filter { !$0.key.hasPrefix("\(id)|") }
        timelineTopCursor = timelineTopCursor.filter { !$0.key.hasPrefix("\(id)|") }
        unread[id] = nil
        Task { await timelineStore.clearAccount(id) }
        if TwitterService.shared.hasSession(accountId: id) {
            TwitterService.shared.logout(accountId: id)
        }
        if accounts.isEmpty {
            if settingsOpen { closeSettings() }
            if composeOpen { closeCompose() }
            delegate?.appStateRequestsWelcome(self)
        } else {
            if activeId == id { activeId = accounts.first!.id! }
            if composeFrom == id { composeFrom = accounts.first!.id! }
            delegate?.appStateDidChangeActive(self)
        }
    }

    // ── Live X timeline ──
    func updateLiveTimeline(for accountId: String, posts: [Post]) {
        liveTimelines[accountId] = posts
        delegate?.appStateDidChangeActive(self)
    }

    func refreshLiveTimeline(for acct: Account) {
        for col in columns where col.type == "home" && colAccount(col).id == acct.id {
            ensureTimelineLoaded(for: col)
            refreshTimeline(for: col, userInitiated: false)
        }
    }

    func timelineIdentity(for col: ColumnSpec) -> TimelineIdentity? {
        TimelineIdentity.forColumn(col, account: colAccount(col),
                                   searchQuery: searchQuery[col.id], listId: listSelection[col.id])
    }

    func timelineSnapshot(for col: ColumnSpec) -> TimelineSnapshot? {
        guard let identity = timelineIdentity(for: col) else { return nil }
        return timelineSnapshots[identity.key]
    }

    func timelineRows(for col: ColumnSpec) -> [TimelineRow] {
        guard let snapshot = timelineSnapshot(for: col) else { return [] }
        return displayRowsWithReplyContext(snapshot.rows)
    }

    func displayRowsWithReplyContext(_ rows: [TimelineRow]) -> [TimelineRow] {
        var out: [TimelineRow] = []
        var displayedPostIds = Set<String>()
        var injectedParentIds = Set<String>()

        for row in rows {
            switch row {
            case .gap:
                out.append(row)
            case .post(let post):
                let merged = mergePost(post)
                if injectedParentIds.contains(merged.id) { continue }

                let parents = replyParents(for: merged, displayedPostIds: displayedPostIds)
                for parent in parents where displayedPostIds.insert(parent.id).inserted {
                    injectedParentIds.insert(parent.id)
                    out.append(.post(parent))
                }

                if displayedPostIds.insert(merged.id).inserted {
                    out.append(.post(merged))
                }
            }
        }

        return normalizeDisplayThreadConnections(out)
    }

    private func replyParents(for post: Post, displayedPostIds: Set<String>) -> [Post] {
        var chain: [Post] = []
        var seen = Set([post.id])
        var nextId = post.replyToId
        while let id = nextId,
              !displayedPostIds.contains(id),
              !seen.contains(id),
              let parent = resolvePost(id) {
            let copy = parent.copy()
            chain.append(copy)
            seen.insert(copy.id)
            nextId = copy.replyToId
        }
        return chain.reversed()
    }

    private func normalizeDisplayThreadConnections(_ rows: [TimelineRow]) -> [TimelineRow] {
        rows.enumerated().map { index, row in
            guard case .post(let post) = row else { return row }
            let copy = post.copy()
            let prev = index > 0 ? rows[index - 1].postValue : nil
            let next = index + 1 < rows.count ? rows[index + 1].postValue : nil
            copy.connectTop = prev.map { displayCanConnect($0, copy) } == true
            copy.connectBottom = next.map { displayCanConnect(copy, $0) } == true
            return .post(copy)
        }
    }

    private func displayCanConnect(_ upper: Post, _ lower: Post) -> Bool {
        if lower.replyToId == upper.id { return true }
        guard let uc = upper.conversationId, let lc = lower.conversationId else { return false }
        return uc == lc
    }

    func timelineStatus(for col: ColumnSpec) -> TimelineStatus {
        if col.type == "lists", timelineIdentity(for: col) == nil {
            // No list chosen yet: show the skeleton while the list-of-lists loads,
            // then auto-selection swaps in a real list timeline.
            return (isLiveAccount(colAccount(col)) && listsLoading) ? .loading : .empty
        }
        guard isLiveAccount(colAccount(col)) || timelineSnapshot(for: col) != nil else { return .empty }
        guard timelineIdentity(for: col) != nil else { return .empty }
        return timelineSnapshot(for: col)?.status ?? .loading
    }

    func timelineIsRefreshing(for col: ColumnSpec) -> Bool {
        timelineSnapshot(for: col)?.refreshing ?? false
    }

    func timelineUnreadCount(for col: ColumnSpec) -> Int {
        timelineSnapshot(for: col)?.unreadCount ?? 0
    }

    /// Avatars for the home column's new-posts pill, sourced from the most recent
    /// `TimelineShowAlert.usersResults`. Empty when X sent no alert.
    func timelineNewAuthors(for col: ColumnSpec) -> [Person] {
        guard let identity = timelineIdentity(for: col) else { return [] }
        return timelineNewAuthors[identity.key] ?? []
    }

    func timelineUnreadCount(type: String) -> Int {
        let activeAccountId = activeId
        return timelineSnapshots.values.reduce(0) { total, snapshot in
            guard snapshot.identity.accountId == activeAccountId else { return total }
            switch type {
            case "home":
                return snapshot.identity.kind == .home ? total + snapshot.unreadCount : total
            case "search":
                return snapshot.identity.kind == .search ? total + snapshot.unreadCount : total
            case "bookmarks":
                return snapshot.identity.kind == .bookmarks ? total + snapshot.unreadCount : total
            case "likes":
                return snapshot.identity.kind == .likes ? total + snapshot.unreadCount : total
            case "lists":
                return snapshot.identity.kind == .lists ? total + snapshot.unreadCount : total
            default:
                return total
            }
        }
    }

    func ensureTimelineLoaded(for col: ColumnSpec) {
        guard let identity = timelineIdentity(for: col), isLiveAccount(colAccount(col)) else { return }
        if timelineSnapshots[identity.key] != nil || loadingTimelineKeys.contains(identity.key) { return }
        loadingTimelineKeys.insert(identity.key)
        timelineSnapshots[identity.key] = TimelineSnapshot(identity: identity, status: .loading)
        Task { [weak self] in
            guard let self else { return }
            let payload = await self.timelineStore.load(identity)
            await MainActor.run {
                self.loadingTimelineKeys.remove(identity.key)
                if let payload {
                    var snapshot = TimelineSnapshot(identity: identity,
                                                    rows: payload.rows,
                                                    status: payload.rows.isEmpty ? .empty : .ready,
                                                    unreadIds: payload.unreadIds,
                                                    bottomCursor: payload.bottomCursor,
                                                    anchor: payload.anchor,
                                                    loadedFromDisk: true)
                    snapshot.normalizeStatus()
                    self.timelineSnapshots[identity.key] = snapshot
                    self.syncTimelineCaches(snapshot, colId: col.id)
                    self.delegate?.appStateDidChangeActive(self)
                    self.refreshTimeline(for: col, userInitiated: false)
                } else {
                    self.timelineSnapshots[identity.key] = TimelineSnapshot(identity: identity, status: .loading)
                    self.delegate?.appStateDidChangeActive(self)
                    self.refreshTimeline(for: col, userInitiated: false)
                }
            }
        }
    }

    func refreshTimeline(for col: ColumnSpec, userInitiated: Bool) {
        guard let identity = timelineIdentity(for: col), isLiveAccount(colAccount(col)) else { return }
        if refreshingTimelineKeys.contains(identity.key) { return }
        if identity.kind == .search, identity.variant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        refreshingTimelineKeys.insert(identity.key)
        var snapshot = timelineSnapshots[identity.key] ?? TimelineSnapshot(identity: identity, status: .loading)
        snapshot.refreshing = true
        if snapshot.rows.isEmpty { snapshot.status = .loading }
        snapshot.errorMessage = nil
        timelineSnapshots[identity.key] = snapshot
        delegate?.appStateDidChangeActive(self)

        // Experimental fetch-newer (pull-to-refresh): on a user-initiated home
        // refresh, pull above the current top via the stored top cursor with the
        // seen tweet ids — the request shape that makes X emit `TimelineShowAlert`.
        let useNewer = userInitiated && identity.kind == .home && ptrRefresh
        let newerCursor = useNewer ? timelineTopCursor[identity.key] : nil
        let seen = newerCursor != nil ? Self.seenTweetIds(from: snapshot.rows) : []

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fetchTimelinePage(identity: identity, col: col,
                                                              cursor: newerCursor,
                                                              seenTweetIds: seen,
                                                              fetchNewer: newerCursor != nil)
                await MainActor.run {
                    self.refreshingTimelineKeys.remove(identity.key)
                    var current = self.timelineSnapshots[identity.key] ?? TimelineSnapshot(identity: identity)
                    let merge = TimelineMerge.mergeLatest(existing: current.rows,
                                                           incoming: result.posts,
                                                           bottomCursor: result.cursor,
                                                           policy: self.timelineMergePolicy(for: identity))
                    current.rows = merge.rows
                    // On fetch-newer, `result.cursor` is the delta's bottom (the gap
                    // cursor inserted by the merge) — keep the real bottom cursor.
                    if newerCursor == nil { current.bottomCursor = result.cursor ?? current.bottomCursor }
                    current.refreshing = false
                    current.errorMessage = nil
                    if !current.loadedFromDisk && current.rows.count == result.posts.count {
                        current.unreadIds.removeAll()
                    } else {
                        for id in merge.unreadIds where !current.unreadIds.contains(id) {
                            current.unreadIds.append(id)
                        }
                    }
                    current.loadedFromDisk = true
                    current.normalizeStatus()
                    self.timelineSnapshots[identity.key] = current
                    if !result.newAuthors.isEmpty { self.timelineNewAuthors[identity.key] = result.newAuthors }
                    if let tc = result.topCursor { self.timelineTopCursor[identity.key] = tc }
                    self.syncTimelineCaches(current, colId: col.id)
                    self.persistTimeline(current)
                    self.persistRawGraphQL(result.rawCapture)
                    self.delegate?.appStateDidChangeActive(self)
                }
            } catch {
                await MainActor.run {
                    self.refreshingTimelineKeys.remove(identity.key)
                    var current = self.timelineSnapshots[identity.key] ?? TimelineSnapshot(identity: identity)
                    current.refreshing = false
                    current.errorMessage = (error as? TwitterAPIError)?.errorDescription ?? error.localizedDescription
                    current.status = current.rows.isEmpty ? .error : .ready
                    self.timelineSnapshots[identity.key] = current
                    self.persistTimeline(current)
                    self.delegate?.appStateDidChangeActive(self)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Chrome-style "Clear and reload": discard the column's cached rows and reload
    /// from the top. The normal refresh merges new posts onto the existing view and
    /// keeps your place; this wipes the column to a skeleton first, then refetches.
    func clearAndReloadTimeline(for col: ColumnSpec) {
        guard let identity = timelineIdentity(for: col), isLiveAccount(colAccount(col)) else { return }
        var snapshot = TimelineSnapshot(identity: identity, status: .loading)
        snapshot.refreshing = refreshingTimelineKeys.contains(identity.key)
        timelineSnapshots[identity.key] = snapshot
        syncTimelineCaches(snapshot, colId: col.id)
        persistTimeline(snapshot)
        delegate?.appStateDidChangeActive(self)
        refreshTimeline(for: col, userInitiated: true)
    }

    func loadTimelineGap(_ gapId: String, for col: ColumnSpec) {
        guard let identity = timelineIdentity(for: col),
              var snapshot = timelineSnapshots[identity.key],
              let gap = snapshot.rows.compactMap({ row -> TimelineGap? in
                  if case .gap(let g) = row, g.id == gapId { return g }
                  return nil
              }).first,
              !gap.cursor.isEmpty else { return }

        snapshot.rows = TimelineMerge.markGap(snapshot.rows, id: gapId, status: .loading)
        timelineSnapshots[identity.key] = snapshot
        delegate?.appStateDidChangeActive(self)
        let fallbackSnapshot = snapshot

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.fetchTimelinePage(identity: identity, col: col, cursor: gap.cursor)
                await MainActor.run {
                    var current = self.timelineSnapshots[identity.key] ?? fallbackSnapshot
                    let merge = TimelineMerge.fillGap(existing: current.rows, gapId: gapId,
                                                      incoming: result.posts, nextCursor: result.cursor,
                                                      policy: self.timelineMergePolicy(for: identity))
                    current.rows = merge.rows
                    current.bottomCursor = result.cursor ?? current.bottomCursor
                    current.normalizeStatus()
                    self.timelineSnapshots[identity.key] = current
                    self.syncTimelineCaches(current, colId: col.id)
                    self.persistTimeline(current)
                    self.persistRawGraphQL(result.rawCapture)
                    self.delegate?.appStateDidChangeActive(self)
                }
            } catch {
                await MainActor.run {
                    var current = self.timelineSnapshots[identity.key] ?? fallbackSnapshot
                    current.rows = TimelineMerge.markGap(current.rows, id: gapId, status: .error,
                                                         message: (error as? TwitterAPIError)?.errorDescription ?? error.localizedDescription)
                    self.timelineSnapshots[identity.key] = current
                    self.persistTimeline(current)
                    self.delegate?.appStateDidChangeActive(self)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    func setTimelineAnchor(for col: ColumnSpec, _ anchor: TimelineAnchor) {
        guard let identity = timelineIdentity(for: col), var snapshot = timelineSnapshots[identity.key],
              snapshot.anchor != anchor else { return }
        snapshot.anchor = anchor
        timelineSnapshots[identity.key] = snapshot
        scheduleAnchorPersist(key: identity.key, snapshot: snapshot)
    }

    /// Debounce disk writes: the anchor changes on every scroll tick, but we only
    /// need the latest on disk for restart-position restore.
    private func scheduleAnchorPersist(key: String, snapshot: TimelineSnapshot) {
        anchorPersistWork[key]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.anchorPersistWork[key] = nil
            self?.persistTimelineState(snapshot)
        }
        anchorPersistWork[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func timelineAnchor(for col: ColumnSpec) -> TimelineAnchor? {
        timelineSnapshot(for: col)?.anchor
    }

    /// Notification scroll anchor — keyed by column id, in-memory only (must survive
    /// the per-refresh canvas rebuild, not app restart). Separate from the timeline
    /// anchor because notif rows aren't `Post`s and aren't persisted to disk.
    func setNotifAnchor(for col: ColumnSpec, _ anchor: TimelineAnchor) {
        notifAnchors[col.id] = anchor
    }

    func notifAnchor(for col: ColumnSpec) -> TimelineAnchor? {
        notifAnchors[col.id]
    }

    func clearTimelineUnread(for col: ColumnSpec) {
        guard let identity = timelineIdentity(for: col), var snapshot = timelineSnapshots[identity.key],
              !snapshot.unreadIds.isEmpty else { return }
        snapshot.unreadIds.removeAll()
        timelineSnapshots[identity.key] = snapshot
        timelineNewAuthors[identity.key] = nil
        persistTimelineState(snapshot)
        delegate?.appState(self, didChangeTimelineUnreadForColumn: col.id)
    }

    func markTimelineUnreadSeen(_ ids: [String], for col: ColumnSpec) {
        guard !ids.isEmpty,
              let identity = timelineIdentity(for: col),
              var snapshot = timelineSnapshots[identity.key],
              !snapshot.unreadIds.isEmpty else { return }
        let seen = Set(ids)
        let before = snapshot.unreadIds.count
        snapshot.unreadIds.removeAll { seen.contains($0) }
        guard snapshot.unreadIds.count != before else { return }
        timelineSnapshots[identity.key] = snapshot
        if snapshot.unreadIds.isEmpty {
            timelineNewAuthors[identity.key] = nil
        }
        persistTimelineState(snapshot)
        delegate?.appState(self, didChangeTimelineUnreadForColumn: col.id)
    }

    func startAutoRefresh() {
        let shouldRefreshBadgeNow = !autoRefreshActive
        autoRefreshActive = true
        if shouldRefreshBadgeNow {
            refreshActiveBadgeCount()
        }
        restartBadgeRefresh()
        restartAutoRefresh()
    }

    func stopAutoRefresh() {
        autoRefreshActive = false
        stopTimelineAutoRefresh()
        stopBadgeRefresh()
    }

    /// App moved to the background → halt polling. The RootVC view-lifecycle
    /// `start/stopAutoRefresh` and these app-level hooks gate the same timers;
    /// invalidate-before-schedule makes interleaving them safe.
    func pauseAutoRefresh() {
        stopAutoRefresh()
    }

    /// App returned to the foreground → restart polling and run one immediate tick so
    /// returning shows fresh content without waiting up to the full interval.
    func resumeAutoRefresh() {
        let shouldRunImmediateTimelineTick = !autoRefreshActive
        startAutoRefresh()
        if shouldRunImmediateTimelineTick {
            runAutoRefreshTick()
        }
    }

    private func restartAutoRefresh() {
        stopTimelineAutoRefresh()
        guard refreshEveryMinutes != "off",
              let minutes = Double(refreshEveryMinutes), minutes > 0 else { return }
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: minutes * 60, repeats: true) { [weak self] _ in
            self?.runAutoRefreshTick()
        }
        autoRefreshTimer?.tolerance = min(30, minutes * 60 * 0.2)
    }

    private func stopTimelineAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    private func restartBadgeRefresh() {
        stopBadgeRefresh()
        badgeActiveRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.badgeActiveRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshActiveBadgeCount()
        }
        badgeActiveRefreshTimer?.tolerance = 5

        let startWork = DispatchWorkItem { [weak self] in
            guard let self, self.autoRefreshActive else { return }
            self.refreshInactiveBadgeCounts()
            self.badgeInactiveRefreshTimer?.invalidate()
            self.badgeInactiveRefreshTimer = Timer.scheduledTimer(withTimeInterval: Self.badgeInactiveRefreshInterval, repeats: true) { [weak self] _ in
                self?.refreshInactiveBadgeCounts()
            }
            self.badgeInactiveRefreshTimer?.tolerance = 10
        }
        badgeInactiveRefreshStartWork = startWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.badgeInactiveRefreshStartupDelay, execute: startWork)
    }

    private func stopBadgeRefresh() {
        badgeActiveRefreshTimer?.invalidate()
        badgeActiveRefreshTimer = nil
        badgeInactiveRefreshTimer?.invalidate()
        badgeInactiveRefreshTimer = nil
        badgeInactiveRefreshStartWork?.cancel()
        badgeInactiveRefreshStartWork = nil
    }

    private func runAutoRefreshTick() {
        refreshVisibleReadyTimelines()
        refreshLoadedNotifications()
    }

    private func refreshVisibleReadyTimelines() {
        for col in columns where col.type != "mentions" {
            guard let snapshot = timelineSnapshot(for: col), snapshot.status == .ready else { continue }
            refreshTimeline(for: col, userInitiated: false)
        }
    }

    /// Auto-refresh tick for the bell column(s) — the notif analogue of
    /// `refreshVisibleReadyTimelines`. A loaded tab (even an empty-but-loaded one)
    /// polls its top page; an unloaded or in-flight tab is skipped.
    private func refreshLoadedNotifications() {
        for col in columns where col.type == "mentions" {
            guard notifHasLoaded(for: col), !notifIsLoading(for: col) else { continue }
            refreshNotifications(for: col)
        }
    }

    private func fetchTimelinePage(identity: TimelineIdentity, col: ColumnSpec,
                                   cursor: String?, seenTweetIds: [String] = [],
                                   fetchNewer: Bool = false) async throws -> TimelineFetchPage {
        guard let uid = TwitterService.shared.credentials(forAccountId: identity.accountId)?.userId
        else { throw TwitterAPIError.authExpired }
        switch identity.kind {
        case .home:
            return try await TwitterService.shared.fetchHomeTimelinePage(accountId: identity.accountId,
                                                                         identity: identity,
                                                                         cursor: cursor,
                                                                         feed: HomeFeed.normalize(identity.variant),
                                                                         seenTweetIds: seenTweetIds,
                                                                         fetchNewer: fetchNewer)
        case .likes:
            return try await TwitterService.shared.likesPage(accountId: identity.accountId,
                                                             identity: identity,
                                                             userId: uid,
                                                             cursor: cursor)
        case .bookmarks:
            return try await TwitterService.shared.bookmarksPage(accountId: identity.accountId,
                                                                 identity: identity,
                                                                 cursor: cursor)
        case .search:
            return try await TwitterService.shared.searchPage(accountId: identity.accountId,
                                                              identity: identity,
                                                              query: identity.variant,
                                                              cursor: cursor)
        case .lists:
            return try await TwitterService.shared.listTweetsPage(accountId: identity.accountId,
                                                                  identity: identity,
                                                                  id: identity.variant,
                                                                  cursor: cursor)
        case .profile:
            return try await TwitterService.shared.userTweetsPage(accountId: identity.accountId,
                                                                  identity: identity,
                                                                  userId: identity.variant,
                                                                  cursor: cursor)
        }
    }

    /// Already-rendered tweet ids (display order, capped) for a fetch-newer pull's
    /// `seenTweetIds` — X uses them to decide which top tweets are genuinely new.
    private static func seenTweetIds(from rows: [TimelineRow], limit: Int = 100) -> [String] {
        Array(rows.compactMap(\.postId).prefix(limit))
    }

    private func timelineMergePolicy(for identity: TimelineIdentity) -> TimelineMergePolicy {
        if identity.kind == .home, HomeFeed.normalize(identity.variant) == .forYou {
            return .unorderedById
        }
        return .ordered
    }

    private func syncTimelineCaches(_ snapshot: TimelineSnapshot, colId: String) {
        let posts = snapshot.posts
        seedRelationships(fromPosts: posts)
        switch snapshot.identity.kind {
        case .home:
            liveTimelines[snapshot.identity.accountId] = posts
        case .likes, .bookmarks, .search, .lists:
            liveColumns[colId] = posts
            liveColCursor[colId] = snapshot.bottomCursor ?? ""
        case .profile:
            liveAuthorPosts[snapshot.identity.variant] = posts
        }
    }

    private func persistTimeline(_ snapshot: TimelineSnapshot) {
        Task { await timelineStore.save(snapshot) }
    }

    private func persistTimelineState(_ snapshot: TimelineSnapshot) {
        Task { await timelineStore.saveState(snapshot) }
    }

    private func persistRawGraphQL(_ capture: RawGraphQLCapture?) {
        guard let capture else { return }
        Task { await timelineStore.saveRawGraphQL(capture) }
    }

    // ── Live X notifications ──
    /// The live X account id, if a column maps to the logged-in session.
    private func liveAccountId(for acct: Account) -> String? {
        guard acct.platform == .x, let aid = acct.id,
              TwitterService.shared.hasSession(accountId: aid) else { return nil }
        return aid
    }

    func isLiveAccount(_ acct: Account) -> Bool { liveAccountId(for: acct) != nil }

    private func notifKey(_ aid: String, _ tab: String) -> String { "\(aid)|\(tab)" }

    /// (live account id, current tab, cache key) for a column — nil when it isn't a
    /// logged-in X column. The tab is the column's selected sub-tab (defaults to "all").
    private func notifContext(_ col: ColumnSpec) -> (aid: String, tab: String, key: String)? {
        guard let aid = liveAccountId(for: colAccount(col)) else { return nil }
        let tab = notifFilterFor(col.id)
        return (aid, tab, notifKey(aid, tab))
    }

    /// First-open / unloaded-tab fetch: load the column's current tab once if it has
    /// never loaded. A loaded tab (even an empty one) is left alone — the shared 5-min
    /// tick keeps it fresh, exactly like timelines. Mirrors `ensureTimelineLoaded`;
    /// safe from panel init (no synchronous delegate fire) and idempotent across the
    /// per-refresh canvas rebuilds that recreate the panel.
    ///
    /// Bails when the tab is already errored. A failed first load fires the active-
    /// change delegate (to show the error view), which rebuilds the canvas and re-inits
    /// this panel; without this guard the re-init would refetch immediately and loop a
    /// transient failure (e.g. HTTP 503 "Over capacity") into a request storm. Timelines
    /// avoid this by persisting a `.error` snapshot — `notifErrored` is the equivalent
    /// record here. Recovery is the header refresh / clear-and-reload (both clear it).
    func ensureNotificationsLoaded(for col: ColumnSpec) {
        guard let ctx = notifContext(col), !notifLoading.contains(ctx.key) else { return }
        if liveNotifications[ctx.key] != nil || notifErrored.contains(ctx.key) { return }
        fetchNotifFirstPage(ctx)
    }

    /// Force-refresh the column's current tab (header refresh button + auto tick):
    /// refetch the top page and merge it over the cached items (non-disruptive).
    func refreshNotifications(for col: ColumnSpec) {
        guard let ctx = notifContext(col), !notifLoading.contains(ctx.key) else { return }
        fetchNotifFirstPage(ctx)
    }

    /// Chrome-style "Clear and reload" for the notification center: drop the cached
    /// items for the column's current tab and refetch from the top (skeleton first).
    func clearAndReloadNotifications(for col: ColumnSpec) {
        guard let ctx = notifContext(col) else { return }
        liveNotifications[ctx.key] = nil
        liveNotifCursor[ctx.key] = nil
        liveNotifLoadedAt[ctx.key] = nil
        notifErrored.remove(ctx.key)
        delegate?.appStateDidChangeActive(self)
        guard !notifLoading.contains(ctx.key) else { return }
        fetchNotifFirstPage(ctx, merge: false)
    }

    /// Fetch the top page of a tab. When `merge` is true (header refresh + auto tick)
    /// the fresh page is layered over the cached items so new notifs prepend while the
    /// existing tail + bottom cursor survive (load-more keeps working); when false
    /// (first open / "Clear and reload") it hard-replaces. On completion the canvas
    /// rebuilds (via the active-change delegate), recreating the panel with live rows.
    /// No synchronous delegate call — safe to invoke from panel init.
    private func fetchNotifFirstPage(_ ctx: (aid: String, tab: String, key: String), merge: Bool = true) {
        notifLoading.insert(ctx.key)
        notifErrored.remove(ctx.key)
        // Refresh over already-loaded content → surface the refresh bar now (content
        // stays on screen). A first load shows the skeleton instead, so don't fire.
        if merge, liveNotifications[ctx.key] != nil {
            delegate?.appStateDidChangeActive(self)
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let (items, cursor) = try await TwitterService.shared.fetchNotifications(accountId: ctx.aid, tab: ctx.tab, cursor: nil)
                await MainActor.run {
                    self.notifLoading.remove(ctx.key)
                    let old = merge ? (self.liveNotifications[ctx.key] ?? []) : []
                    if old.isEmpty {
                        // First load / clear-reload / empty-but-loaded tab → hard set + cursor.
                        self.liveNotifications[ctx.key] = items
                        self.liveNotifCursor[ctx.key] = cursor ?? ""   // "" → no further pages
                    } else {
                        let freshIds = Set(items.map { $0.id })
                        let tail = old.filter { !freshIds.contains($0.id) }
                        if old.contains(where: { freshIds.contains($0.id) }) {
                            // Overlap → the fresh page reconnects to the cache: prepend the
                            // new items, keep the existing tail + bottom cursor intact.
                            self.liveNotifications[ctx.key] = items + tail
                        } else {
                            // Disjoint burst (more new notifs than one page) → avoid a hole:
                            // replace with the fresh page and reset the cursor.
                            self.liveNotifications[ctx.key] = items
                            self.liveNotifCursor[ctx.key] = cursor ?? ""
                        }
                    }
                    self.liveNotifLoadedAt[ctx.key] = Date()
                    self.delegate?.appStateDidChangeActive(self)
                }
            } catch {
                await MainActor.run {
                    self.notifLoading.remove(ctx.key)
                    if self.liveNotifications[ctx.key] == nil { self.notifErrored.insert(ctx.key) }
                    self.delegate?.appStateDidChangeActive(self)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Append the next page (older notifications) of the column's current tab using the
    /// stored bottom cursor. `completion` runs on the main thread after the store is
    /// updated, letting the panel re-flow its rows in place (preserving scroll).
    func loadMoreNotifications(for col: ColumnSpec, completion: @escaping () -> Void) {
        guard let ctx = notifContext(col), !notifLoading.contains(ctx.key) else { return }
        let cursor = liveNotifCursor[ctx.key] ?? ""
        guard !cursor.isEmpty else { return }   // no more pages
        notifLoading.insert(ctx.key)
        Task { [weak self] in
            guard let self else { return }
            do {
                let (items, next) = try await TwitterService.shared.fetchNotifications(accountId: ctx.aid, tab: ctx.tab, cursor: cursor)
                await MainActor.run {
                    self.notifLoading.remove(ctx.key)
                    var existing = self.liveNotifications[ctx.key] ?? []
                    let known = Set(existing.map { $0.id })
                    existing.append(contentsOf: items.filter { !known.contains($0.id) })
                    self.liveNotifications[ctx.key] = existing
                    self.liveNotifCursor[ctx.key] = next ?? ""
                    completion()
                }
            } catch {
                await MainActor.run {
                    self.notifLoading.remove(ctx.key)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// True when more notification pages remain for the column's current tab.
    func notifHasMore(for col: ColumnSpec) -> Bool {
        guard let ctx = notifContext(col) else { return false }
        let c = liveNotifCursor[ctx.key]
        return c != nil && !(c!.isEmpty)
    }

    func notifIsLoading(for col: ColumnSpec) -> Bool {
        guard let ctx = notifContext(col) else { return false }
        return notifLoading.contains(ctx.key)
    }

    func notifHasErrored(for col: ColumnSpec) -> Bool {
        guard let ctx = notifContext(col) else { return false }
        return notifErrored.contains(ctx.key)
    }

    /// True once the column's current tab has completed ≥1 fetch (even if it returned
    /// nothing). Distinguishes "still loading → skeleton" from "loaded → empty state".
    func notifHasLoaded(for col: ColumnSpec) -> Bool {
        guard let ctx = notifContext(col) else { return false }
        return liveNotifications[ctx.key] != nil
    }

    /// Load state for the column's current tab, mapped to the feed's `NotifStatus`
    /// (symmetric with `timelineSnapshot(for:).status`). Honors the `PERCH_NOTIF` dev
    /// override (skeleton / error / sample) so snapshots render deterministically.
    func notificationStatus(for col: ColumnSpec) -> NotifStatus {
        switch ProcessInfo.processInfo.environment["PERCH_NOTIF"] {
        case "skeleton": return .loading
        case "error": return .error
        case "sample": return .ready
        default: break
        }
        guard notifContext(col) != nil else { return .empty }
        if !notifHasLoaded(for: col) {
            return notifHasErrored(for: col) ? .error : .loading
        }
        return notificationsFor(col).isEmpty ? .empty : .ready
    }

    /// True while a background refresh runs over already-shown content (drives the thin
    /// refresh bar). False on a first load — that surfaces the skeleton instead.
    func notificationIsRefreshing(for col: ColumnSpec) -> Bool {
        guard let ctx = notifContext(col) else { return false }
        return notifLoading.contains(ctx.key) && liveNotifications[ctx.key] != nil
    }

    private func refreshActiveBadgeCount() {
        guard let acct = accounts.first(where: { $0.id == activeId }) else { return }
        refreshBadgeCount(for: acct)
    }

    private func refreshInactiveBadgeCounts() {
        var seenAccountIds: Set<String> = []
        for acct in accounts where acct.id != activeId {
            guard let aid = liveAccountId(for: acct), !seenAccountIds.contains(aid) else { continue }
            seenAccountIds.insert(aid)
            refreshBadgeCount(for: acct)
        }
    }

    func refreshBadgeCount(for acct: Account) {
        guard let aid = liveAccountId(for: acct), !badgeLoading.contains(aid) else { return }
        let now = Date()
        if let last = badgeLastRequestedAt[aid],
           now.timeIntervalSince(last) < Self.badgeRequestDedupeInterval {
            return
        }
        badgeLastRequestedAt[aid] = now
        badgeLoading.insert(aid)
        let epoch = badgeReadEpoch[aid] ?? 0
        Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await TwitterService.shared.badgeNotificationCount(accountId: aid)
                await MainActor.run {
                    self.badgeLoading.remove(aid)
                    guard self.accounts.contains(where: { $0.id == aid }),
                          (self.badgeReadEpoch[aid] ?? 0) == epoch else { return }
                    if (self.unread[aid] ?? 0) != count {
                        self.unread[aid] = count
                        self.delegate?.appStateDidChangeActive(self)
                    }
                }
            } catch {
                await MainActor.run {
                    self.badgeLoading.remove(aid)
                    if case TwitterAPIError.authExpired = error {
                        self.handleTimelineError(error)
                    }
                }
            }
        }
    }

    // ── Live likes / bookmarks / search columns ──
    /// Fetch a likes/bookmarks/search column for the live X account. `force` re-fetches
    /// even when a cache already exists (refresh button).
    func refreshLiveColumn(_ col: ColumnSpec, force: Bool = false) {
        ensureTimelineLoaded(for: col)
        if force || timelineSnapshot(for: col) == nil {
            refreshTimeline(for: col, userInitiated: force)
        }
    }

    func setSearchQuery(_ colId: String, _ query: String) {
        searchQuery[colId] = query
        liveColumns[colId] = nil
        if let col = columns.first(where: { $0.id == colId }) {
            if let identity = timelineIdentity(for: col) {
                timelineSnapshots[identity.key] = nil
            }
            refreshTimeline(for: col, userInitiated: true)
        }
    }

    // ── Lists ──

    /// Lists available to a column's account. Gated on platform (X-only) rather
    /// than a live session so debug snapshots render; `liveLists` is only ever
    /// populated for the logged-in account anyway.
    func lists(for col: ColumnSpec) -> [TwitterList] {
        colAccount(col).platform == .x ? liveLists : []
    }

    /// The display name of the list currently selected in a column, if any.
    func listSelectionName(for col: ColumnSpec) -> String? {
        guard let lid = listSelection[col.id] else { return nil }
        return liveLists.first { $0.id == lid }?.name
    }

    var listsAreLoading: Bool { listsLoading }

    /// Switch a lists column to a different list; reuses the cached timeline if present.
    func setListSelection(_ colId: String, _ listId: String) {
        guard listSelection[colId] != listId else { return }
        listSelection[colId] = listId
        delegate?.appStateDidChangeActive(self)
    }

    /// Lazily load the user's lists and auto-select the first one for a lists column
    /// that has no selection yet. Called when a lists column is built.
    func ensureListColumn(for col: ColumnSpec) {
        guard col.type == "lists", isLiveAccount(colAccount(col)) else { return }
        refreshLists()
        if listSelection[col.id] == nil, let first = liveLists.first {
            listSelection[col.id] = first.id
        }
    }

    /// Fetch the active account's lists (guards against re-entrancy; `force` re-fetches).
    func refreshLists(force: Bool = false) {
        guard TwitterService.shared.isLoggedIn else { return }
        if listsLoading { return }
        if listsLoaded && !force { return }
        listsLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let (raw, _) = try await TwitterService.shared.lists()
                await MainActor.run {
                    self.listsLoading = false
                    self.listsLoaded = true
                    self.liveLists = raw
                    self.delegate?.appStateDidChangeActive(self)
                }
            } catch {
                await MainActor.run {
                    self.listsLoading = false
                    self.handleTimelineError(error)
                }
            }
        }
    }

    // ── Bookmark folders ──

    /// The resolved (id/name/local-color) posts for the bookmarks column at a given
    /// scope. `__all__` reads the flat Bookmarks timeline; a folder id reads its
    /// cached folder timeline. Not gated on live-account so debug snapshots render.
    func bookmarkPosts(for col: ColumnSpec, scope: String) -> [Post] {
        if scope == "__all__" {
            return (timelineSnapshot(for: col)?.posts ?? liveColumns[col.id] ?? []).map { mergePost($0) }
        }
        return (bmFolderPosts[scope] ?? []).map { mergePost($0) }
    }

    /// Load status for the "All" bookmarks list (drives skeleton/error in the panel).
    func bookmarkAllStatus(for col: ColumnSpec) -> TimelineStatus {
        if let s = timelineSnapshot(for: col)?.status { return s }
        return isLiveAccount(colAccount(col)) ? .loading : .empty
    }

    /// Number of posts currently known to live in a folder (nil → not loaded yet).
    func bookmarkFolderCount(_ folderId: String) -> Int? {
        bmFolderPosts[folderId]?.count
    }

    /// The folder a post is assigned to (scans cached folder timelines), or nil.
    func bookmarkFolder(of postId: String) -> String? {
        for (fid, posts) in bmFolderPosts where posts.contains(where: { $0.id == postId }) { return fid }
        return nil
    }

    /// Perch-local color token for a folder; assigns + persists one on first use.
    func bookmarkColor(_ folderId: String) -> String {
        if let c = bmFolderColors[folderId] { return c }
        let used = Set(bmFolderColors.values)
        let next = AppState.bmPalette.first { !used.contains($0) }
            ?? AppState.bmPalette[abs(folderId.hashValue) % AppState.bmPalette.count]
        bmFolderColors[folderId] = next
        UserDefaults.standard.set(bmFolderColors, forKey: bmColorsKey)
        return next
    }

    private func setBookmarkColor(_ folderId: String, _ token: String) {
        bmFolderColors[folderId] = token
        UserDefaults.standard.set(bmFolderColors, forKey: bmColorsKey)
    }

    /// Fetch the live folder list, then eagerly load each folder's posts (for chip
    /// counts + assignment). Guards against re-entrancy; `force` re-fetches.
    func refreshBookmarkFolders(force: Bool = false) {
        guard TwitterService.shared.isLoggedIn else { return }
        if bmFoldersLoading { return }
        if bmFoldersLoaded && !force { return }
        bmFoldersLoading = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let raw = try await TwitterService.shared.bookmarkFolders()
                await MainActor.run {
                    self.bmFoldersLoading = false
                    self.bmFoldersLoaded = true
                    self.liveBookmarkFolders = raw.map {
                        BookmarkFolder(id: $0.id, name: $0.name, colorToken: self.bookmarkColor($0.id))
                    }
                    self.delegate?.appStateDidChangeActive(self)
                    for f in self.liveBookmarkFolders { self.loadBookmarkFolder(f.id, force: force) }
                }
            } catch {
                await MainActor.run {
                    self.bmFoldersLoading = false
                    self.handleTimelineError(error)
                }
            }
        }
    }

    func loadBookmarkFolder(_ folderId: String, force: Bool = false) {
        guard TwitterService.shared.isLoggedIn else { return }
        if bmFolderLoading.contains(folderId) { return }
        if bmFolderPosts[folderId] != nil && !force { return }
        bmFolderLoading.insert(folderId)
        Task { [weak self] in
            guard let self else { return }
            do {
                let (posts, _) = try await TwitterService.shared.bookmarkFolderTimeline(folderId: folderId)
                await MainActor.run {
                    self.bmFolderLoading.remove(folderId)
                    self.bmFolderPosts[folderId] = posts
                    self.delegate?.appStateDidChangeActive(self)
                }
            } catch {
                await MainActor.run {
                    self.bmFolderLoading.remove(folderId)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Create a folder (live), store its local color, select it on success.
    func addBookmarkFolder(name: String, colorToken: String, selectIn colId: String? = nil,
                           assign postIds: [String] = []) {
        guard TwitterService.shared.isLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let newId = try await TwitterService.shared.createBookmarkFolder(name: name)
                let id = newId ?? "bf_\(UUID().uuidString.prefix(8))"
                await MainActor.run {
                    self.setBookmarkColor(id, colorToken)
                    let folder = BookmarkFolder(id: id, name: name, colorToken: colorToken)
                    if !self.liveBookmarkFolders.contains(where: { $0.id == id }) {
                        self.liveBookmarkFolders.append(folder)
                    }
                    self.bmFolderPosts[id] = self.bmFolderPosts[id] ?? []
                    if let colId { self.bmScope[colId] = id }
                    self.delegate?.appStateDidChangeActive(self)
                    for pid in postIds { self.moveBookmark(pid, to: id) }
                    if newId == nil { self.refreshBookmarkFolders(force: true) }   // reconcile real id
                }
            } catch {
                await MainActor.run { self.handleTimelineError(error) }
            }
        }
    }

    /// Rename / recolor a folder. Color is local; the name change syncs to X.
    func updateBookmarkFolder(id: String, name: String, colorToken: String) {
        setBookmarkColor(id, colorToken)
        if let idx = liveBookmarkFolders.firstIndex(where: { $0.id == id }) {
            liveBookmarkFolders[idx].name = name
            liveBookmarkFolders[idx].colorToken = colorToken
        }
        delegate?.appStateDidChangeActive(self)
        guard TwitterService.shared.isLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            do { try await TwitterService.shared.editBookmarkFolder(id: id, name: name) }
            catch { await MainActor.run { self.handleTimelineError(error) } }
        }
    }

    /// Delete a folder. The bookmarks themselves stay in "All".
    func deleteBookmarkFolder(id: String) {
        liveBookmarkFolders.removeAll { $0.id == id }
        bmFolderPosts[id] = nil
        for (colId, scope) in bmScope where scope == id { bmScope[colId] = "__all__" }
        delegate?.appStateDidChangeActive(self)
        guard TwitterService.shared.isLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            do { try await TwitterService.shared.deleteBookmarkFolder(id: id) }
            catch { await MainActor.run { self.handleTimelineError(error) } }
        }
    }

    /// Move a post into a folder (`nil` → remove from its current folder, keep bookmarked).
    /// Treated as single-folder membership: the post leaves any other folder.
    func moveBookmark(_ postId: String, to folderId: String?) {
        let from = bookmarkFolder(of: postId)
        // Optimistic local update.
        let base = findBase(postId)
        for (fid, posts) in bmFolderPosts {
            if fid != folderId { bmFolderPosts[fid] = posts.filter { $0.id != postId } }
        }
        if let folderId, let base, !(bmFolderPosts[folderId] ?? []).contains(where: { $0.id == postId }) {
            bmFolderPosts[folderId, default: []].insert(base, at: 0)
        }
        delegate?.appStateDidChangeActive(self)

        guard TwitterService.shared.isLoggedIn else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                if let folderId {
                    try await TwitterService.shared.bookmarkTweetToFolder(tweetId: postId, folderId: folderId)
                } else if let from {
                    try await TwitterService.shared.removeTweetFromBookmarkFolder(tweetId: postId, folderId: from)
                }
            } catch {
                await MainActor.run { self.handleTimelineError(error) }
            }
        }
    }

    // ── Live profile + author posts ──
    func profileFor(_ person: Person) -> Profile {
        liveProfiles[person.handle] ?? Profile(bio: "", location: "", joined: "",
                                               followers: "—", following: "—",
                                               banner: Gradients.forSeed(person.handle))
    }

    func refreshProfile(_ person: Person, force: Bool = false) {
        guard TwitterService.shared.isLoggedIn else { return }
        let handle = person.handle
        guard !profileLoading.contains(handle) else { return }
        if liveProfiles[handle] != nil, !force,
           let t = profileFetchedAt[handle], Date().timeIntervalSince(t) < detailStaleAfter { return }
        let wasCold = liveProfiles[handle] == nil
        let cacheIdentity = active.id.map { TimelineIdentity.profile(accountId: $0, person: person) }
        profileLoading.insert(handle)
        Task { [weak self] in
            guard let self else { return }
            if wasCold, let cacheIdentity, let payload = await self.timelineStore.load(cacheIdentity) {
                await MainActor.run {
                    var cached = TimelineSnapshot(identity: cacheIdentity,
                                                  rows: payload.rows,
                                                  status: payload.rows.isEmpty ? .empty : .ready,
                                                  unreadIds: payload.unreadIds,
                                                  bottomCursor: payload.bottomCursor,
                                                  anchor: payload.anchor,
                                                  loadedFromDisk: true)
                    cached.normalizeStatus()
                    self.timelineSnapshots[cacheIdentity.key] = cached
                    self.liveAuthorPosts[handle] = cached.posts
                    self.delegate?.appState(self, didChangeProfileFor: handle)
                }
            }
            do {
                let (resolved, profile) = try await TwitterService.shared.profile(screenName: handle)
                var posts: [Post] = []
                var cursor: String?
                if let uid = resolved.id {
                    if let result = try? await TwitterService.shared.userTweets(userId: uid) {
                        posts = result.posts
                        cursor = result.cursor
                    }
                }
                let fetchedPosts = posts
                let fetchedCursor = cursor
                await MainActor.run {
                    self.profileLoading.remove(handle)
                    self.liveProfiles[handle] = profile
                    self.liveProfilePerson[handle] = resolved
                    self.liveAuthorPosts[handle] = fetchedPosts
                    self.profileFetchedAt[handle] = Date()
                    self.seedRelationships(from: [resolved] + fetchedPosts.map { $0.author })
                    if let cacheIdentity {
                        var snapshot = TimelineSnapshot(identity: cacheIdentity,
                                                        rows: fetchedPosts.map { .post($0) },
                                                        status: fetchedPosts.isEmpty ? .empty : .ready,
                                                        bottomCursor: fetchedCursor,
                                                        loadedFromDisk: true)
                        snapshot.normalizeStatus()
                        self.timelineSnapshots[snapshot.identity.key] = snapshot
                        self.persistTimeline(snapshot)
                    }
                    self.delegate?.appState(self, didChangeProfileFor: handle)
                }
            } catch {
                await MainActor.run {
                    self.profileLoading.remove(handle)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// The resolved (id/name/avatar-filled) person for a handle, if fetched.
    func resolvedPerson(_ person: Person) -> Person { liveProfilePerson[person.handle] ?? person }

    // ── Live detail thread ──
    /// Cache-first + refresh-if-stale: a fresh cache is reused; a stale one stays
    /// visible while a background fetch updates it in place (via the targeted
    /// `didChangeDetailFor` delegate, so the open panel refreshes without a flicker).
    func refreshDetail(_ id: String, force: Bool = false) {
        guard TwitterService.shared.isLoggedIn, !detailLoading.contains(id) else { return }
        if liveReplies[id] != nil, !force,
           let t = detailFetchedAt[id], Date().timeIntervalSince(t) < detailStaleAfter { return }
        detailLoading.insert(id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let (posts, cursor) = try await TwitterService.shared.tweetDetail(id: id)
                await MainActor.run {
                    self.detailLoading.remove(id)
                    self.detailRawPosts[id] = posts
                    self.detailCursor[id] = cursor
                    self.detailFetchedAt[id] = Date()
                    self.seedRelationships(fromPosts: posts)
                    self.rebuildDetailTree(id: id)
                    self.delegate?.appState(self, didChangeDetailFor: id)
                }
            } catch {
                await MainActor.run {
                    self.detailLoading.remove(id)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Whether more replies remain to be paged in below the focal post.
    func hasMoreReplies(_ id: String) -> Bool {
        guard let c = detailCursor[id], !c.isEmpty else { return false }
        return liveReplies[id] != nil
    }

    /// Page in the next batch of replies. Updates the live caches and calls
    /// `completion` on the main thread with the rebuilt root replies + whether more
    /// remain — deliberately WITHOUT firing the global delegate, so the open detail
    /// document can refresh itself in place (preserving the reader's scroll position).
    func loadMoreReplies(_ id: String, completion: @escaping (_ roots: [Comment], _ hasMore: Bool) -> Void) {
        guard TwitterService.shared.isLoggedIn,
              !detailLoadingMore.contains(id),
              let cursor = detailCursor[id], !cursor.isEmpty else { return }
        detailLoadingMore.insert(id)
        Task { [weak self] in
            guard let self else { return }
            do {
                let (posts, next) = try await TwitterService.shared.tweetDetail(id: id, cursor: cursor)
                await MainActor.run {
                    self.detailLoadingMore.remove(id)
                    let existing = self.detailRawPosts[id] ?? []
                    let existingIds = Set(existing.map { $0.id })
                    let fresh = posts.filter { !existingIds.contains($0.id) }
                    self.detailRawPosts[id] = existing + fresh
                    // Stop paging when a page yields nothing new (avoids a dead "show more").
                    self.detailCursor[id] = fresh.isEmpty ? nil : next
                    self.rebuildDetailTree(id: id)
                    completion(self.liveReplies[id] ?? [], self.hasMoreReplies(id))
                }
            } catch {
                await MainActor.run {
                    self.detailLoadingMore.remove(id)
                    completion(self.liveReplies[id] ?? [], self.hasMoreReplies(id))
                }
            }
        }
    }

    /// Derive ancestors + a nested reply tree from every conversation post fetched so
    /// far (page 1 plus any "show more replies" pages), so paging only accumulates.
    private func rebuildDetailTree(id: String) {
        let posts = detailRawPosts[id] ?? []
        var byId: [String: Post] = [:]
        for p in posts { byId[p.id] = p; detailPosts[p.id] = p }
        guard let root = byId[id] else {
            liveReplies[id] = []
            liveAncestors[id] = []
            return
        }
        // Ancestors: walk up the reply chain from the focal post (oldest first).
        var ancestors: [Post] = []
        var cur = root.replyToId
        var guardSet: Set<String> = [id]
        while let pid = cur, let p = byId[pid], guardSet.insert(pid).inserted {
            ancestors.insert(p, at: 0)
            cur = p.replyToId
        }
        for (i, p) in ancestors.enumerated() {
            p.connectTop = i > 0
            p.connectBottom = true
        }
        liveAncestors[id] = ancestors

        // Replies: everything else, nested into a tree by reply-to.
        let usedIds = Set(ancestors.map { $0.id }).union([id])
        let replyPosts = posts.filter { !usedIds.contains($0.id) }
        var comments: [String: Comment] = [:]
        for p in replyPosts {
            comments[p.id] = Comment(id: p.id, author: p.author, time: p.time, text: p.text,
                                     stats: p.stats, liked: p.liked, replyToId: p.replyToId)
        }
        var roots: [Comment] = []
        for p in replyPosts {
            guard let c = comments[p.id] else { continue }
            if let parent = p.replyToId, parent != id, let pc = comments[parent] {
                pc.children.append(c)
            } else {
                roots.append(c)
            }
        }
        liveReplies[id] = roots
    }

    func detailAncestors(_ id: String) -> [Post] { liveAncestors[id] ?? [] }

    // ── User relationships (follow / mute / block) ──
    private enum Relationship { case follow, mute, block }

    func follow(_ person: Person, on: Bool) { toggleRelationship(.follow, person, on: on) }
    func mute(_ person: Person, on: Bool) { toggleRelationship(.mute, person, on: on) }
    func block(_ person: Person, on: Bool) { toggleRelationship(.block, person, on: on) }

    func isFollowing(_ person: Person) -> Bool { person.id.map { following.contains($0) } ?? false }
    func isMuted(_ person: Person) -> Bool { person.id.map { muted.contains($0) } ?? false }
    func isBlocked(_ person: Person) -> Bool { person.id.map { blocked.contains($0) } ?? false }

    private func toggleRelationship(_ rel: Relationship, _ person: Person, on: Bool) {
        guard let uid = person.id else { return }
        switch rel {
        case .follow: if on { following.insert(uid) } else { following.remove(uid) }
        case .mute: if on { muted.insert(uid) } else { muted.remove(uid) }
        case .block: if on { blocked.insert(uid) } else { blocked.remove(uid) }
        }
        guard TwitterService.shared.isLoggedIn else { return }
        pendingRelationship.insert(uid)
        Task { [weak self] in
            guard let self else { return }
            do {
                switch rel {
                case .follow: try await TwitterService.shared.follow(uid, on: on)
                case .mute: try await TwitterService.shared.mute(uid, on: on)
                case .block: try await TwitterService.shared.block(uid, on: on)
                }
                await MainActor.run { _ = self.pendingRelationship.remove(uid) }
            } catch {
                await MainActor.run {
                    self.pendingRelationship.remove(uid)
                    switch rel {
                    case .follow: if on { self.following.remove(uid) } else { self.following.insert(uid) }
                    case .mute: if on { self.muted.remove(uid) } else { self.muted.insert(uid) }
                    case .block: if on { self.blocked.remove(uid) } else { self.blocked.insert(uid) }
                    }
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Seed the local relationship Sets from authed API data. Skips ids with an
    /// in-flight toggle so optimistic state isn't clobbered. No-op when a person
    /// carries no relationship (mock / unauthed data).
    func seedRelationships(fromPosts posts: [Post]) {
        seedRelationships(from: posts.map { $0.author })
    }

    func seedRelationships(from people: [Person]) {
        for p in people {
            guard let uid = p.id, let rel = p.relationship, !pendingRelationship.contains(uid) else { continue }
            if let f = rel.following { if f { following.insert(uid) } else { following.remove(uid) } }
            if let m = rel.muting { if m { muted.insert(uid) } else { muted.remove(uid) } }
            if let b = rel.blocking { if b { blocked.insert(uid) } else { blocked.remove(uid) } }
        }
    }

    /// Copy a post's canonical web link to the pasteboard.
    func copyPostLink(_ post: Post) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(canonicalURL(post), forType: .string)
        showToastNow(post.author.platform == .x ? "Link copied" : "已复制链接")
    }

    /// A post's canonical web URL (x.com / weibo.com).
    func canonicalURL(_ post: Post) -> String {
        post.author.platform == .x
            ? "https://x.com/\(post.author.handle)/status/\(post.id)"
            : "https://weibo.com/\(post.author.handle)"
    }

    /// Open a URL in the user's default browser.
    func openExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copy X's standard embed blockquote HTML for a post to the pasteboard.
    func copyEmbed(_ post: Post) {
        let isX = post.author.platform == .x
        let url = canonicalURL(post)
        let html = """
        <blockquote class="twitter-tweet"><a href="\(url)"></a></blockquote>
        <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(html, forType: .string)
        showToastNow(isX ? "Embed code copied" : "已复制嵌入代码")
    }

    /// Mute a conversation (best-effort — the REST endpoint is unverified). Toasts
    /// immediately; the request is fired and any failure is logged, not surfaced.
    func muteConversation(_ post: Post) {
        let isX = post.author.platform == .x
        showToastNow(isX ? "Conversation muted" : "已隐藏对话")
        guard isX, TwitterService.shared.isLoggedIn else { return }
        let convId = post.conversationId ?? post.id
        Task { try? await TwitterService.shared.muteConversation(conversationId: convId, on: true) }
    }

    private func handleTimelineError(_ error: Error) {
        if case TwitterAPIError.authExpired = error {
            TwitterService.shared.logout()
            showToastNow("Session expired")
            return
        }
        let msg = (error as? TwitterAPIError)?.errorDescription ?? error.localizedDescription
        showToastNow(msg)
    }

    // ── Post resolution / merge ──
    func findBase(_ id: String) -> Post? {
        for snapshot in timelineSnapshots.values {
            for row in snapshot.rows {
                if case .post(let p) = row, p.id == id { return p }
            }
        }
        for posts in liveTimelines.values {
            for p in posts where p.id == id { return p }
        }
        for posts in liveColumns.values {
            for p in posts where p.id == id { return p }
        }
        for posts in bmFolderPosts.values {
            for p in posts where p.id == id { return p }
        }
        for posts in liveAuthorPosts.values {
            for p in posts where p.id == id { return p }
        }
        if let p = detailPosts[id] { return p }
        for items in liveNotifications.values {
            for n in items where n.post?.id == id { if let p = n.post { return p } }
        }
        for plat in [Platform.x, .weibo] {
            for p in injected[plat] ?? [] where p.id == id { return p }
        }
        return nil
    }

    func mergePost(_ p: Post) -> Post {
        let o = overrides[p.id] ?? [:]
        let liked = o["liked"] ?? p.liked
        let reposted = o["reposted"] ?? p.reposted
        let bookmarked = o["bookmarked"] ?? p.bookmarked
        func adj(_ v: Int, _ now: Bool, _ was: Bool) -> Int { v + ((now ? 1 : 0) - (was ? 1 : 0)) }
        let repliesAdded = (replies[p.id] ?? []).count
        let allInjected = (injected[.x] ?? []) + (injected[.weibo] ?? [])
        let quotesAdded = allInjected.filter { $0.quoteSrcId == p.id }.count
        let m = p.copy()
        m.liked = liked
        m.reposted = reposted
        m.bookmarked = bookmarked
        m.stats.likes = adj(p.stats.likes, liked, p.liked)
        m.stats.reposts = adj(p.stats.reposts, reposted, p.reposted) + quotesAdded
        if let r = p.stats.replies { m.stats.replies = r + repliesAdded }
        return m
    }

    func onAction(_ id: String, _ field: String) {
        var cur = overrides[id] ?? [:]
        let base = findBase(id)
        let curVal = cur[field] ?? (base?.value(for: field) ?? false)
        let newVal = !curVal
        cur[field] = newVal
        overrides[id] = cur
        delegate?.appState(self, didUpdatePost: id)
        syncLiveAction(id: id, field: field, on: newVal)
    }

    /// True when `id` is a tweet from a logged-in live X timeline (so write ops should hit the network).
    private func isLiveXPost(_ id: String) -> Bool {
        timelineSnapshots.values.contains { snapshot in
            snapshot.rows.contains { row in
                if case .post(let p) = row { return p.id == id && p.author.platform == .x }
                return false
            }
        } || liveTimelines.values.contains { $0.contains { $0.id == id } }
            || liveColumns.values.contains { $0.contains { $0.id == id } }
            || bmFolderPosts.values.contains { $0.contains { $0.id == id } }
            || liveNotifications.values.contains { items in
                items.contains { n in
                    n.post?.id == id || (n.id.hasPrefix("t_") && String(n.id.dropFirst(2)) == id)
                }
            }
    }

    /// Mirror a like/repost/bookmark toggle to X. Optimistic: reverts the override on failure.
    private func syncLiveAction(id: String, field: String, on: Bool) {
        guard TwitterService.shared.isLoggedIn, isLiveXPost(id) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                switch field {
                case "liked": try await TwitterService.shared.like(id, on: on)
                case "reposted": try await TwitterService.shared.repost(id, on: on)
                case "bookmarked": try await TwitterService.shared.bookmark(id, on: on)
                default: return
                }
            } catch {
                await MainActor.run {
                    var cur = self.overrides[id] ?? [:]
                    cur[field] = !on
                    self.overrides[id] = cur
                    self.delegate?.appState(self, didUpdatePost: id)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    func colAccount(_ col: ColumnSpec) -> Account {
        if let aid = col.accountId, let a = account(aid) { return a }
        return active
    }

    func postsFor(_ col: ColumnSpec) -> [Post] {
        let acct = colAccount(col)
        guard isLiveAccount(acct) else { return [] }
        let plat = acct.platform
        switch col.type {
        case "home":
            let live = timelineSnapshot(for: col)?.posts ?? acct.id.flatMap { liveTimelines[$0] } ?? []
            return ((injected[plat] ?? []) + live).map { mergePost($0) }
        case "mentions":
            return []   // the mentions column uses the notification center, not postsFor
        default:        // likes / bookmarks / search
            return (timelineSnapshot(for: col)?.posts ?? liveColumns[col.id] ?? []).map { mergePost($0) }
        }
    }

    func resolvePost(_ id: String) -> Post? {
        guard let b = findBase(id) else { return nil }
        return mergePost(b)
    }

    /// Snapshot of every open column for the Inspector's Data tab.
    func dataTabSnapshots() -> [DebugColumnSnapshot] {
        columns.map { col in
            let acct = colAccount(col)
            // Show the column's backing data. `postsFor` is live-account-gated; fall back to the
            // cached snapshot so the Data tab reflects whatever the column is actually rendering.
            var posts = postsFor(col)
            if posts.isEmpty { posts = timelineSnapshot(for: col)?.posts.map(mergePost) ?? [] }
            let meta = colMeta(col.type)
            let isX = acct.platform == .x
            let json: DebugJSON = .object([
                ("column", .object([
                    ("id", .string(col.id)),
                    ("type", .string(col.type)),
                    ("feed", .string(col.feed)),
                    ("accountId", col.accountId.map { DebugJSON.string($0) } ?? .null),
                ])),
                ("account", .object([
                    ("id", acct.id.map { DebugJSON.string($0) } ?? .null),
                    ("name", .string(acct.name)),
                    ("handle", .string(acct.handle)),
                    ("platform", .string(acct.platform.rawValue)),
                ])),
                ("posts", .array(posts.map { DebugJSON.from(post: $0) })),
            ])
            return DebugColumnSnapshot(id: col.id, icon: meta.icon, platform: acct.platform,
                                       label: isX ? meta.labelX : meta.labelW,
                                       sub: "@\(acct.handle)", count: posts.count, json: json)
        }
    }

    func repliesOf(_ post: Post) -> [Comment] {
        return (replies[post.id] ?? []) + (liveReplies[post.id] ?? [])
    }

    func authorPosts(_ person: Person) -> [Post] {
        let plat = person.platform
        let injectedByAuthor = (injected[plat] ?? []).filter { $0.author.handle == person.handle }
        let live = liveAuthorPosts[person.handle] ?? []
        return (injectedByAuthor + live).map { mergePost($0) }
    }

    // ── Column nav ──
    func pushScreen(_ colId: String, _ kind: NavScreen.Kind) {
        let key = "s\(Date().timeIntervalSince1970)\(Int.random(in: 0..<10000))"
        var stack = colNav[colId] ?? []
        stack.append(NavScreen(key: key, kind: kind))
        applyNavChange(colId, to: stack, recordHistory: true)
    }

    func popScreen(_ colId: String) {
        var stack = colNav[colId] ?? []
        guard !stack.isEmpty else { return }
        stack.removeLast()
        applyNavChange(colId, to: stack, recordHistory: true)
    }

    @discardableResult
    func navigateBack() -> Bool {
        guard let entry = backHistory.popLast(),
              columns.contains(where: { $0.id == entry.colId }) else { return false }
        applyNavChange(entry.colId, to: entry.fromStack, recordHistory: false)
        forwardHistory.append(entry)
        return true
    }

    @discardableResult
    func navigateForward() -> Bool {
        guard let entry = forwardHistory.popLast(),
              columns.contains(where: { $0.id == entry.colId }) else { return false }
        applyNavChange(entry.colId, to: entry.toStack, recordHistory: false)
        backHistory.append(entry)
        return true
    }

    private func applyNavChange(_ colId: String, to newStack: [NavScreen], recordHistory: Bool) {
        let oldStack = colNav[colId] ?? []
        guard !sameNavStack(oldStack, newStack) else { return }
        colNav[colId] = newStack
        if recordHistory {
            backHistory.append(NavHistoryEntry(colId: colId, fromStack: oldStack, toStack: newStack))
            forwardHistory.removeAll()
        }
        delegate?.appState(self, didChangeNavForColumn: colId)
    }

    private func sameNavStack(_ lhs: [NavScreen], _ rhs: [NavScreen]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { $0.key == $1.key }
    }

    func openOwnProfile() {
        guard let c = columns.first else { return }
        pushScreen(c.id, .profile(active))
    }

    // ── Compose ──
    func openCompose() {
        composeFrom = activeId
        composeCtx = nil
        composeOpen = true
        delegate?.appStateDidChangeCompose(self)
    }

    func closeCompose() {
        composeOpen = false
        composeCtx = nil
        delegate?.appStateDidChangeCompose(self)
    }

    func openReply(_ post: Post) {
        composeFrom = activeId
        composeCtx = ComposeContext(mode: .reply, post: post)
        composeOpen = true
        delegate?.appStateDidChangeCompose(self)
    }

    func openQuote(_ post: Post) {
        composeFrom = activeId
        composeCtx = ComposeContext(mode: .quote, post: post)
        composeOpen = true
        delegate?.appStateDidChangeCompose(self)
    }

    func openRepost(_ post: Post) {
        composeFrom = activeId
        composeCtx = ComposeContext(mode: .repost, post: post)
        composeOpen = true
        delegate?.appStateDidChangeCompose(self)
    }

    func directRepost(_ post: Post) {
        let wasReposted = post.reposted
        onAction(post.id, "reposted")
        let msg = post.author.platform == .x ? (wasReposted ? "Repost removed" : "Reposted") : "转发成功"
        delegate?.appState(self, showToast: msg)
    }

    func setComposeFrom(_ id: String) {
        composeFrom = id
        delegate?.appStateDidChangeCompose(self)
    }

    @discardableResult
    func addReply(_ postId: String, from: Account, text: String) -> String {
        let author = Person(name: from.name, handle: from.handle, colorToken: from.colorToken,
                            verified: from.verified, platform: from.platform)
        let cid = "rp\(Int(Date().timeIntervalSince1970 * 1000))"
        let c = Comment(id: cid,
                        author: author,
                        time: from.platform == .x ? "now" : "刚刚",
                        text: text,
                        stats: Stats(replies: 0, reposts: 0, likes: 0),
                        liked: false)
        var arr = replies[postId] ?? []
        arr.insert(c, at: 0)
        replies[postId] = arr
        delegate?.appState(self, didAddReplyTo: postId)
        return cid
    }

    /// True when posting as the logged-in live X account.
    private func isLiveXAccount(_ account: Account) -> Bool {
        account.platform == .x && TwitterService.shared.hasSession(accountId: account.id)
    }

    /// Live network write for a new/quote post. On success the mapped server Post replaces the
    /// optimistic placeholder (real id/time/stats); on failure the placeholder is reverted.
    private func sendLiveTweet(tempId: String, plat: Platform, text: String, media: [PickedMedia] = [],
                              replyTo: String? = nil, quote: String? = nil) {
        Task { [weak self] in
            do {
                let real = try await TwitterService.shared.postTweet(text: text, media: media, replyTo: replyTo, quote: quote)
                guard let self else { return }
                await MainActor.run { self.reconcileInjected(tempId: tempId, plat: plat, with: real) }
            } catch {
                guard let self else { return }
                await MainActor.run {
                    self.removeInjected(tempId: tempId, plat: plat)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Live network write for a reply. Keeps the optimistic comment on success; reverts it on failure.
    private func sendLiveReply(commentId: String, rootId: String, text: String, media: [PickedMedia] = [], replyTo: String) {
        Task { [weak self] in
            do {
                _ = try await TwitterService.shared.postTweet(text: text, media: media, replyTo: replyTo)
            } catch {
                guard let self else { return }
                await MainActor.run {
                    self.removeReply(rootId: rootId, commentId: commentId)
                    self.handleTimelineError(error)
                }
            }
        }
    }

    /// Replace the temp optimistic post with the mapped server post, preserving the quote card if the
    /// mapper didn't carry one.
    private func reconcileInjected(tempId: String, plat: Platform, with real: Post?) {
        guard let real, var arr = injected[plat], let idx = arr.firstIndex(where: { $0.id == tempId }) else { return }
        if real.quote == nil, let q = arr[idx].quote { real.quote = q; real.quoteSrcId = arr[idx].quoteSrcId }
        arr[idx] = real
        injected[plat] = arr
        delegate?.appStateDidChangeActive(self)
    }

    private func removeInjected(tempId: String, plat: Platform) {
        guard var arr = injected[plat] else { return }
        arr.removeAll { $0.id == tempId }
        injected[plat] = arr
        delegate?.appStateDidChangeActive(self)
    }

    private func removeReply(rootId: String, commentId: String) {
        guard var arr = replies[rootId] else { return }
        arr.removeAll { $0.id == commentId }
        replies[rootId] = arr
        delegate?.appState(self, didAddReplyTo: rootId)
    }

    func onPost(from: Account, text: String, media: [PickedMedia] = [], context: ComposeContext?) {
        let live = isLiveXAccount(from)
        if let ctx = context, ctx.mode == .reply, let orig = ctx.post {
            let cid = addReply(orig.id, from: from, text: text)
            if live { sendLiveReply(commentId: cid, rootId: orig.id, text: text, media: media, replyTo: orig.id) }
            closeCompose()
            showToastNow(from.platform == .x ? "Reply sent" : "评论已发布")
            return
        }
        let author = Person(name: from.name, handle: from.handle, colorToken: from.colorToken,
                            verified: from.verified, platform: from.platform)
        let baseStats = Stats(replies: 0, reposts: 0, likes: 0, views: from.platform == .x ? "12" : "阅读 12")
        let newId = "np\(Int(Date().timeIntervalSince1970 * 1000))"
        let optMedia = optimisticMedia(media)

        if let ctx = context, (ctx.mode == .quote || ctx.mode == .repost), let o = ctx.post {
            let pureRepost = ctx.mode == .repost && text.isEmpty && media.isEmpty
            if live {
                if pureRepost {
                    Task { try? await TwitterService.shared.repost(o.id, on: true) }
                } else {
                    sendLiveTweet(tempId: newId, plat: from.platform, text: text, media: media, quote: o.id)
                }
            }
            let np = Post(id: newId, author: author, time: from.platform == .x ? "now" : "刚刚",
                          text: text.isEmpty ? (from.platform == .x ? "" : "转发微博") : text,
                          media: optMedia, stats: baseStats,
                          quote: Quote(author: o.author, time: o.time, text: o.text, media: o.media),
                          quoteSrcId: o.id)
            var arr = injected[from.platform] ?? []
            arr.insert(np, at: 0)
            injected[from.platform] = arr
            activeId = from.id ?? activeId
            closeCompose()
            delegate?.appStateDidChangeActive(self)
            showToastNow(from.platform == .x ? "Reposted" : "转发成功")
            return
        }

        if live { sendLiveTweet(tempId: newId, plat: from.platform, text: text, media: media) }
        let np = Post(id: newId, author: author, time: from.platform == .x ? "now" : "刚刚",
                      text: text, media: optMedia, stats: baseStats)
        var arr = injected[from.platform] ?? []
        arr.insert(np, at: 0)
        injected[from.platform] = arr
        activeId = from.id ?? activeId
        closeCompose()
        delegate?.appStateDidChangeActive(self)
        showToastNow(from.platform == .x ? "Posted to X" : "已发布到微博")
    }

    /// Build an optimistic image grid from picked local media (renders instantly from thumbnails).
    private func optimisticMedia(_ picks: [PickedMedia]) -> Media? {
        guard !picks.isEmpty else { return nil }
        let grad = Gradient("#3b3b46", "#26262e")
        let items = picks.map { MediaItem(url: nil, grad: grad, alt: $0.alt, localImage: $0.thumbnail) }
        return Media(type: .images, items: items)
    }

    func showToastNow(_ text: String) {
        delegate?.appState(self, showToast: text)
    }

    // ── Column operations ──
    func closeColumn(_ id: String) {
        guard let idx = columns.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        columns.remove(at: idx)
        colNav[id] = nil
        backHistory.removeAll { $0.colId == id }
        forwardHistory.removeAll { $0.colId == id }
        delegate?.appStateDidChangeColumns(self)
    }

    func addColumn(_ type: String) {
        columns.append(ColumnSpec(id: "c\(Int(Date().timeIntervalSince1970 * 1000))", type: type, accountId: activeId))
        delegate?.appStateDidChangeColumns(self)
    }

    func setColType(_ id: String, _ type: String) {
        guard let c = columns.first(where: { $0.id == id }), c.type != type else { return }
        c.type = type
        colNav[id] = nil
        backHistory.removeAll { $0.colId == id }
        forwardHistory.removeAll { $0.colId == id }
        delegate?.appStateDidChangeColumns(self)
    }

    func setColAccount(_ id: String, _ accountId: String) {
        if let c = columns.first(where: { $0.id == id }) { c.accountId = accountId }
        delegate?.appStateDidChangeColumns(self)
    }

    func setColFeed(_ id: String, _ feed: HomeFeed) {
        guard let c = columns.first(where: { $0.id == id }), c.feed != feed.rawValue else { return }
        c.feed = feed.rawValue
        delegate?.appStateDidChangeColumns(self)
    }

    func reorderColumns(_ from: Int, _ insertIdx: Int) {
        guard from > 0, from < columns.count else { return }
        let to = max(1, min(insertIdx, columns.count))
        var target = to > from ? to - 1 : to
        if target < 1 { target = 1 }
        if target == from { return }
        let it = columns.remove(at: from)
        columns.insert(it, at: target)
        delegate?.appStateDidChangeColumns(self)
    }

    /// The single ColumnSpec backing a given primary (sidebar) content type.
    /// Stable id per type → each sidebar timeline owns its own colNav stack.
    private func primarySpec(for type: String) -> ColumnSpec {
        if let s = primarySpecs[type] { return s }
        let s = ColumnSpec(id: "primary-\(type)", type: type)   // accountId nil → follows active
        primarySpecs[type] = s
        return s
    }

    func setPrimaryType(_ type: String) {
        let spec = primarySpec(for: type)
        if columns.isEmpty { columns = [spec] } else { columns[0] = spec }
        delegate?.appStateDidChangeColumns(self)
    }

    func setActive(_ id: String) {
        TwitterService.shared.activate(accountId: id)
        activeId = id
        delegate?.appStateDidChangeActive(self)
        if let acct = account(id) {
            refreshBadgeCount(for: acct)
        }
    }

    // ── Notifications ──
    func markRead(_ id: String) {
        badgeReadEpoch[id] = (badgeReadEpoch[id] ?? 0) + 1
        if (unread[id] ?? 0) != 0 { unread[id] = 0 }
    }

    func viewMentions() {
        markRead(activeId)
        setPrimaryType("mentions")
    }

    // ── Notification center ──
    func notificationsFor(_ col: ColumnSpec) -> [NotifItem] {
        // For the logged-in live X account, only ever show live data for the current tab
        // (empty until the first fetch lands) — never flash mock notifications.
        guard let ctx = notifContext(col) else { return [] }
        return liveNotifications[ctx.key] ?? []
    }
    func notifFilterFor(_ colId: String) -> String { notifFilter[colId] ?? "all" }
    func setNotifFilter(_ colId: String, _ f: String) { notifFilter[colId] = f }
    func notifIsUnread(_ colId: String, _ n: NotifItem) -> Bool {
        n.unread && !(notifRead[colId]?.contains(n.id) ?? false)
    }
    func markNotifSeen(_ colId: String, _ id: String) {
        var s = notifRead[colId] ?? []
        s.insert(id)
        notifRead[colId] = s
    }
    /// Mark every notification in the column read and clear the rail badge.
    func markAllNotifsRead(_ col: ColumnSpec) {
        notifRead[col.id] = Set(notificationsFor(col).map { $0.id })
        markRead(colAccount(col).id ?? activeId)
        delegate?.appStateDidChangeActive(self)
    }

    var primaryType: String { columns.first?.type ?? "home" }
    var totalUnread: Int {
        accounts.reduce(0) { $0 + (unread[$1.id!] ?? 0) }
    }
    var othersHaveUnread: Bool {
        accounts.contains { $0.id != activeId && (unread[$0.id!] ?? 0) > 0 }
    }
}

private extension Post {
    func value(for field: String) -> Bool {
        switch field {
        case "liked": return liked
        case "reposted": return reposted
        case "bookmarked": return bookmarked
        default: return false
        }
    }
}
