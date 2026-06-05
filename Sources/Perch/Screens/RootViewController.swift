import AppKit

final class RootViewController: NSViewController {
    let appState: AppState

    private var railView: IconRailView!
    private let canvasScroll = NSScrollView()
    private let canvasDoc = FlippedView()
    private var columnViews: [ColumnView] = []

    private let overlayContainer = FlippedView()       // popovers
    private var composeView: ComposeView?
    private var settingsView: SettingsView?
    private var addAccountView: AddAccountView?
    private var navConfigView: NavConfigDialogView?
    /// Set by AppDelegate; invoked when the last account is disconnected.
    var onRequestWelcome: (() -> Void)?
    private var composePanel: PanelWindowController?
    private var settingsPanel: PanelWindowController?
    private var addAccountPanel: PanelWindowController?
    private var mediaViewerPanel: PanelWindowController?
    private var mediaViewerView: MediaViewerView?
    private var inspectorPanel: PanelWindowController?
    private weak var inspectorView: DebugInspectorView?
    private var jsonViewerPanels: [PanelWindowController] = []
    private var trayDim: HoverControl?
    private var trayView: ColumnManagerView?
    private var toastView: ToastView?
    private var toastTimer: Timer?

    // popover state
    private var popoverDim: HoverControl?
    private var popoverContent: NSView?

    private var keyMonitor: Any?
    private var lastComputedColW: CGFloat = 0
    private var lastColumnCount: Int = 0
    private var lastColumnSignature = ""
    private var lastRebuildTime: TimeInterval = -.infinity
    private var rebuildWorkItem: DispatchWorkItem?
    private let rebuildThrottle: TimeInterval = 0.08  // ~12fps max during live resize
    // Set during add/remove-column animation to pin column widths
    private var targetColumnWidth: CGFloat?
    private var suppressColumnLayout = false
    private var suppressReleaseTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var theme: Theme { ThemeManager.shared.theme }

    override func loadView() {
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: UI.railW + 552, height: 872))
        v.bgColor = theme.bgBase
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        appState.delegate = self
        gPopoverHost = self
        buildAll()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyMonitor()
        appState.startAutoRefresh()
        if let first = columnViews.first { _ = first }
        updateMinWindowSize()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        appState.stopAutoRefresh()
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func updateMinWindowSize() {
        let count = max(1, appState.columns.count)
        let minW = UI.railW + CGFloat(count) * UI.columnMinW
        view.window?.minSize = NSSize(width: minW, height: 500)
    }

    private func buildAll() {
        view.subviews.forEach { $0.removeFromSuperview() }
        view.wantsLayer = true
        (view as? FlippedView)?.bgColor = theme.bgBase

        // canvas scroll
        canvasScroll.borderType = .noBorder
        canvasScroll.drawsBackground = true
        canvasScroll.backgroundColor = theme.bgBase
        canvasScroll.hasHorizontalScroller = false
        canvasScroll.hasVerticalScroller = false
        canvasScroll.autohidesScrollers = true
        canvasScroll.scrollerStyle = .overlay
        canvasScroll.horizontalScrollElasticity = .none
        // Don't reserve a top strip for the titlebar — columns run to the window top
        // (the rail does too); the traffic lights only overlap the rail.
        canvasScroll.automaticallyAdjustsContentInsets = false
        canvasScroll.documentView = canvasDoc
        canvasDoc.bgColor = theme.bgBase
        view.addSubview(canvasScroll)

        rebuildCanvas()

        // rail
        railView = IconRailView(appState: appState, onToggleColumns: { [weak self] in self?.toggleTray() })
        view.addSubview(railView)

        // overlay container for popovers (top-most)
        overlayContainer.frame = view.bounds
        overlayContainer.autoresizingMask = [.width, .height]
        view.addSubview(overlayContainer)

        relayout()
    }

    private func computeColumnWidth(count: Int) -> CGFloat {
        if let target = targetColumnWidth { return target }
        guard count > 0 else { return UI.columnW }
        let availableW = view.bounds.width - UI.railW
        return max(UI.columnMinW, availableW / CGFloat(count))
    }

    /// Identity of the current column layout. Uses the *effective* account id
    /// (`colAccount`) so switching the active account changes the signature and
    /// forces a full rebuild, while same-structure content refreshes do not.
    private func columnSignature() -> String {
        appState.columns.map { "\($0.id)|\($0.type)|\($0.feed)|\(appState.colAccount($0).id ?? "")" }
            .joined(separator: ",")
    }

    private func rebuildCanvas() {
        let count = appState.columns.count
        let colW = computeColumnWidth(count: count)
        let signature = columnSignature()
        // Reconcile in place when nothing structural changed: refresh each column's
        // primary feed but leave any pushed detail/profile panel (and its scroll)
        // untouched — this is what keeps an open detail from flickering on a
        // background timeline tick / avatar backfill.
        if !columnViews.isEmpty, count == columnViews.count,
           abs(colW - lastComputedColW) < 0.5, signature == lastColumnSignature {
            for cv in columnViews { cv.refreshPrimaryInPlace() }
            return
        }
        captureColumnAnchors()
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        lastRebuildTime = CACurrentMediaTime()
        columnViews.forEach { $0.removeFromSuperview() }
        columnViews.removeAll()
        lastComputedColW = colW
        lastColumnCount = count
        lastColumnSignature = signature
        for (i, col) in appState.columns.enumerated() {
            let cv = ColumnView(appState: appState, col: col, contentWidth: colW,
                                isLast: i == count - 1, isFirst: i == 0)
            canvasDoc.addSubview(cv)
            columnViews.append(cv)
        }
        layoutCanvas()
        restoreColumnAnchors()
    }

    private func captureColumnAnchors() {
        for cv in columnViews { cv.captureVisibleAnchor() }
    }

    private func restoreColumnAnchors() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for cv in self.columnViews { cv.restoreVisibleAnchor() }
        }
    }

    private func layoutCanvas() {
        guard !suppressColumnLayout else { return }
        let h = canvasScroll.contentView.bounds.height
        let count = columnViews.count
        guard count > 0 else { return }
        let colW = computeColumnWidth(count: count)
        canvasDoc.frame = NSRect(x: 0, y: 0, width: colW * CGFloat(count), height: h)
        for (i, cv) in columnViews.enumerated() {
            cv.frame = NSRect(x: CGFloat(i) * colW, y: 0, width: colW, height: h)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        relayout()
        scheduleRebuildIfNeeded()
    }

    private func scheduleRebuildIfNeeded() {
        guard !suppressColumnLayout, !columnViews.isEmpty else { return }
        let newColW = computeColumnWidth(count: columnViews.count)
        guard abs(newColW - lastComputedColW) > 0.5 else { return }
        rebuildWorkItem?.cancel()
        let elapsed = CACurrentMediaTime() - lastRebuildTime
        let delay = max(0, rebuildThrottle - elapsed)
        let item = DispatchWorkItem { [weak self] in self?.rebuildCanvas() }
        rebuildWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func relayout() {
        let b = view.bounds
        railView?.frame = NSRect(x: 0, y: 0, width: UI.railW, height: b.height)
        canvasScroll.frame = NSRect(x: UI.railW, y: 0, width: b.width - UI.railW, height: b.height)
        layoutCanvas()
        overlayContainer.frame = b
        composeView?.frame = b
        navConfigView?.frame = b
        if let tray = trayView {
            trayDim?.frame = b
            tray.frame = NSRect(x: 0, y: b.height - ColumnManagerView.trayHeight, width: b.width, height: ColumnManagerView.trayHeight)
        }
        positionToast()
    }

    // ── Tray ──
    private func toggleTray() {
        if trayView != nil { dismissTray() } else { showTray() }
    }

    private func showTray() {
        let b = view.bounds
        let dim = HoverControl(frame: b)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = theme.gray1000.withAlphaComponent(0.28).cgColor
        dim.onClick = { [weak self] in self?.dismissTray() }
        view.addSubview(dim)
        trayDim = dim
        let tray = ColumnManagerView(appState: appState, onDone: { [weak self] in self?.dismissTray() })
        let h = ColumnManagerView.trayHeight
        tray.frame = NSRect(x: 0, y: b.height, width: b.width, height: h)
        view.addSubview(tray)
        trayView = tray
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.4, 1)
            tray.animator().setFrameOrigin(NSPoint(x: 0, y: b.height - h))
        }
    }

    private func dismissTray() {
        trayDim?.removeFromSuperview(); trayDim = nil
        trayView?.removeFromSuperview(); trayView = nil
    }

    // ── Compose ──
    private func mountCompose() {
        guard composePanel == nil else { return }
        let cv = ComposeView(appState: appState, fromId: appState.composeFrom, context: appState.composeCtx,
                             onClose: { [weak self] in self?.appState.closeCompose() },
                             onPost: { [weak self] from, text, media, ctx in self?.appState.onPost(from: from, text: text, media: media, context: ctx) })
        composeView = cv
        let panel = PanelWindowController(content: cv, relativeTo: view.window) { [weak self] in
            self?.composePanel = nil
            self?.composeView = nil
            if self?.appState.composeOpen == true { self?.appState.closeCompose() }
        }
        composePanel = panel
        panel.present()
    }

    private func unmountCompose() {
        composePanel?.dismiss()
        composePanel = nil
        composeView = nil
    }

    // ── Settings ──
    private func mountSettings() {
        guard settingsPanel == nil else { return }
        let sv = SettingsView(appState: appState, onClose: { [weak self] in self?.appState.closeSettings() })
        settingsView = sv
        let panel = PanelWindowController(content: sv, relativeTo: view.window) { [weak self] in
            self?.settingsPanel = nil
            self?.settingsView = nil
            if self?.appState.settingsOpen == true { self?.appState.closeSettings() }
        }
        settingsPanel = panel
        panel.present()
    }

    private func unmountSettings() {
        settingsPanel?.dismiss()
        settingsPanel = nil
        settingsView = nil
    }

    // ── AddAccount ──
    private func mountAddAccount() {
        guard addAccountPanel == nil else { return }
        let av = AddAccountView(appState: appState, onClose: { [weak self] in self?.appState.closeAddAccount() })
        addAccountView = av
        let panel = PanelWindowController(content: av, relativeTo: view.window) { [weak self] in
            self?.addAccountPanel = nil
            self?.addAccountView = nil
            if self?.appState.addAccountOpen == true { self?.appState.closeAddAccount() }
        }
        addAccountPanel = panel
        panel.present()
    }

    private func unmountAddAccount() {
        addAccountPanel?.dismiss()
        addAccountPanel = nil
        addAccountView = nil
    }

    // ── Media viewer ──
    private func mountMediaViewer() {
        guard mediaViewerPanel == nil, let ctx = appState.mediaViewerCtx else { return }
        let mv = MediaViewerView(context: ctx, onClose: { [weak self] in self?.appState.closeMediaViewer() })
        mediaViewerView = mv
        let panel = PanelWindowController(content: mv, relativeTo: view.window) { [weak self] in
            self?.mediaViewerPanel = nil
            self?.mediaViewerView = nil
            if self?.appState.mediaViewerOpen == true { self?.appState.closeMediaViewer() }
        }
        mediaViewerPanel = panel
        panel.present()
    }

    private func unmountMediaViewer() {
        mediaViewerPanel?.dismiss()
        mediaViewerPanel = nil
        mediaViewerView = nil
    }

    // ── Debug inspector (single window) ──
    private func mountInspector() {
        guard inspectorPanel == nil else { return }
        let iv = DebugInspectorView(appState: appState, isX: appState.active.platform == .x)
        inspectorView = iv
        let panel = PanelWindowController(content: iv, relativeTo: view.window) { [weak self] in
            self?.inspectorPanel = nil
            self?.inspectorView = nil
            if self?.appState.inspectorOpen == true { self?.appState.closeInspector() }
        }
        inspectorPanel = panel
        panel.present()
    }

    private func unmountInspector() {
        inspectorPanel?.dismiss()
        inspectorPanel = nil
    }

    // ── JSON viewer (multiple coexisting windows) ──
    private func openJsonViewerWindow(_ ctx: JsonViewerContext) {
        let jv = JsonViewerView(ctx: ctx, isX: appState.active.platform == .x)
        var panelRef: PanelWindowController?
        let panel = PanelWindowController(content: jv, relativeTo: view.window) { [weak self] in
            guard let self, let panelRef else { return }
            self.jsonViewerPanels.removeAll { $0 === panelRef }
        }
        panelRef = panel
        jsonViewerPanels.append(panel)
        panel.present()
    }

    // ── Configure navigation ──
    private func mountNavConfig() {
        guard navConfigView == nil else { return }
        let d = NavConfigDialogView(appState: appState, onClose: { [weak self] in self?.appState.closeNavConfig() })
        d.frame = view.bounds
        d.autoresizingMask = [.width, .height]
        view.addSubview(d, positioned: .above, relativeTo: overlayContainer)
        navConfigView = d
        view.window?.makeFirstResponder(d)
    }

    private func unmountNavConfig() {
        navConfigView?.removeFromSuperview()
        navConfigView = nil
    }

    // ── Toast ──
    private func showToast(_ text: String) {
        toastView?.removeFromSuperview()
        toastTimer?.invalidate()
        let t = ToastView(text: text)
        view.addSubview(t)
        toastView = t
        positionToast()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.toastView?.removeFromSuperview()
            self?.toastView = nil
        }
    }

    private func positionToast() {
        guard let t = toastView else { return }
        let b = view.bounds
        t.frame.origin = CGPoint(x: (b.width - t.frame.width) / 2, y: b.height - 24 - t.frame.height)
    }

    private var debugStubPerson: Person {
        Person(name: "Lena Wolfe", handle: "lenawolfe", colorToken: "magenta-800", verified: true, platform: .x)
    }

    private func debugPost(_ id: String, text: String, author: Person? = nil) -> Post {
        Post(id: id,
             author: author ?? debugStubPerson,
             time: "\(max(1, Int(id.filter(\.isNumber)) ?? 1))m",
             text: text,
             media: nil,
             stats: Stats(replies: 2, reposts: 4, likes: 18, views: "1.2K"),
             createdAt: Date().addingTimeInterval(-Double(max(1, Int(id.filter(\.isNumber)) ?? 1)) * 60))
    }

    private func debugQuotedVideoPost() -> Post {
        let source = Person(name: "The Type Files", handle: "typefiles",
                            colorToken: "orange-700", verified: true, platform: .x)
        var media = Media(type: .video)
        media.dur = "0:30"
        media.item = MediaItem(Gradients.steel)
        media.source = source
        let p = debugPost("dbg7", text: "this 30-second teardown of native vs web-view text rendering should be required watching. watch the subpixel hinting at the very end.")
        p.media = media
        p.stats = Stats(replies: 24, reposts: 138, likes: 1620, views: "214K")
        return p
    }

    private func debugSetTimeline(status: TimelineStatus, rows: [TimelineRow], unread: [String] = [],
                                  newAuthors: [Person] = []) {
        guard let acctId = appState.active.id else { return }
        if appState.columns.isEmpty {
            appState.columns = [ColumnSpec(id: "c1", type: "home", accountId: acctId)]
        }
        let col = appState.columns[0]
        col.type = "home"
        col.accountId = acctId
        let identity = TimelineIdentity(accountId: acctId, kind: .home,
                                        variant: HomeFeed.normalize(col.feed).storageComponent)
        var snapshot = TimelineSnapshot(identity: identity, rows: rows, status: status,
                                        refreshing: status == .loading,
                                        unreadIds: unread,
                                        bottomCursor: "debug-bottom",
                                        loadedFromDisk: true)
        if status != .loading && status != .error { snapshot.normalizeStatus() }
        appState.timelineSnapshots[identity.key] = snapshot
        appState.timelineNewAuthors[identity.key] = newAuthors.isEmpty ? nil : newAuthors
        rebuildCanvas()
        rebuildRail()
    }

    /// Seed the network log with deterministic, redaction-exercising entries so the
    /// Inspector renders the same way every snapshot (bypasses the live-capture guard).
    private func debugSeedNetwork() {
        func body(_ s: String) -> Data { Data(s.utf8) }
        let auth: [String: String] = [
            "authorization": "Bearer AAAAAAAAAAAAAAAAAAAAANRILgARZ8sample",
            "cookie": "auth_token=1a2b3c; ct0=deadbeefcafe; guest_id=v1%3A170",
            "x-csrf-token": "deadbeefcafe",
            "x-client-transaction-id": "sJ9k2mNpQr7signedXOR",
            "content-type": "application/json",
            "accept": "*/*",
        ]
        let gql = "https://x.com/i/api/graphql"
        let timelineVars = "?variables=%7B%22count%22%3A20%2C%22includePromotedContent%22%3Atrue%7D&features=%7B%22responsive_web_graphql_timeline_navigation_enabled%22%3Atrue%7D"
        let seed: [DebugLogEntry] = [
            DebugLog.makeEntry(id: "req-1", platform: .x, method: "GET",
                url: URL(string: "\(gql)/HBjzYn3If3o0c5qX/HomeTimeline\(timelineVars)"),
                requestHeaders: auth, requestBody: nil, status: 200,
                responseBody: body(#"{"data":{"home":{"home_timeline_urt":{"instructions":[{"type":"TimelineAddEntries","entries":[{"entryId":"tweet-1893"},{"entryId":"tweet-1894"}]}]}}}}"#),
                durationMs: 412, error: nil, timeLabel: "09:40:55"),
            DebugLog.makeEntry(id: "req-2", platform: .x, method: "GET",
                url: URL(string: "https://x.com/i/api/2/notifications/all.json?count=40&ext=mediaStats"),
                requestHeaders: auth, requestBody: nil, status: 200,
                responseBody: body(#"{"globalObjects":{"tweets":{},"users":{}},"timeline":{"instructions":[{"addEntries":{"entries":[]}}]}}"#),
                durationMs: 321, error: nil, timeLabel: "09:41:10"),
            DebugLog.makeEntry(id: "req-3", platform: .x, method: "POST",
                url: URL(string: "\(gql)/lI07N6OtwFgzd7/FavoriteTweet"),
                requestHeaders: auth, requestBody: body(#"{"variables":{"tweet_id":"1893774120"},"queryId":"lI07N6OtwFgzd7"}"#),
                status: 200, responseBody: body(#"{"data":{"favorite_tweet":"Done"}}"#),
                durationMs: 138, error: nil, timeLabel: "09:41:32"),
            DebugLog.makeEntry(id: "req-4", platform: .x, method: "GET",
                url: URL(string: "\(gql)/HBjzYn3If3o0c5qX/HomeTimeline\(timelineVars)"),
                requestHeaders: auth, requestBody: nil, status: 429,
                responseBody: body(#"{"errors":[{"code":88,"message":"Rate limit exceeded"}]}"#),
                durationMs: 96, error: "rate limited", timeLabel: "09:42:05"),
            DebugLog.makeEntry(id: "req-5", platform: .x, method: "POST",
                url: URL(string: "\(gql)/ojPdsZsimiJ8sU/CreateRetweet"),
                requestHeaders: auth, requestBody: body(#"{"variables":{"tweet_id":"1893774120"},"queryId":"ojPdsZsimiJ8sU"}"#),
                status: 403, responseBody: body(#"{"errors":[{"code":353,"message":"This request requires a matching csrf cookie and header."}]}"#),
                durationMs: 74, error: "auth expired", timeLabel: "09:42:48"),
            DebugLog.makeEntry(id: "req-6", platform: .x, method: "POST",
                url: URL(string: "\(gql)/SoVnbfCyc7fkv4/CreateTweet"),
                requestHeaders: auth, requestBody: body(#"{"variables":{"tweet_text":"shipping the inspector today 🛠️","media":{"media_entities":[],"possibly_sensitive":false},"semantic_annotation_ids":[]},"queryId":"SoVnbfCyc7fkv4"}"#),
                status: 200, responseBody: body(#"{"data":{"create_tweet":{"tweet_results":{"result":{"rest_id":"1893999001","legacy":{"full_text":"shipping the inspector today 🛠️","favorite_count":0}}}}}}"#),
                durationMs: 263, error: nil, timeLabel: "09:43:20"),
        ]
        DebugLog.shared.debugSeed(seed)
    }

    // ── Keyboard 'c' ──
    func debugApply(_ state: String) {
        switch state {
        case "compose": appState.openCompose()
        case "compose-media":
            appState.openCompose()
            composeView?.debugSeedSampleMedia()
        case "tray": showTray()
        case "detail":
            if let c = appState.columns.first { appState.pushScreen(c.id, .post("x1")) }
        case "detailmock":
            let maxAI = Person(name: "Max For AI", handle: "MaxForAI", colorToken: "blue-900", verified: true, platform: .x)
            let arvin = Person(name: "空谷 Arvin Xu", handle: "arvin17x", colorToken: "magenta-800", verified: true, platform: .x)
            let rene = Person(name: "Rene Wang", handle: "realDonandTrump", colorToken: "seafoam-800", verified: true, platform: .x)
            let quote = Quote(author: maxAI, time: "1h",
                              text: "个人情况更新：\n我没有加入 @AnthropicAI\n而是选择加入了 @lobehub 担任 MAS&Head of growth",
                              media: nil)
            let focal = Post(id: "mockd1", author: arvin, time: "34m",
                             text: "咱要被 Max 要带起飞了🤗",
                             stats: Stats(replies: 2, reposts: 0, likes: 8, views: "536"),
                             quote: quote)
            appState.injected[.x] = (appState.injected[.x] ?? []) + [focal]
            let child = Comment(id: "mockc1c", author: maxAI, time: "5m", text: "冲冲冲",
                                stats: Stats(replies: 0, reposts: 0, likes: 0))
            let r1 = Comment(id: "mockc1", author: rene, time: "21m",
                             text: "之前你拒绝被 Google 收购我是不同意的",
                             stats: Stats(replies: 1, reposts: 0, likes: 1), children: [child])
            let r2 = Comment(id: "mockc2", author: maxAI, time: "5m", text: "冲冲冲",
                             stats: Stats(replies: 0, reposts: 0, likes: 0))
            appState.replies["mockd1"] = [r1, r2]
            if let c = appState.columns.first { appState.pushScreen(c.id, .post("mockd1")) }
        case "profile":
            if let c = appState.columns.first { appState.pushScreen(c.id, .profile(debugStubPerson)) }
        case "reply":
            if let p = appState.resolvePost("x1") { appState.openReply(p) }
        case "notif": appState.viewMentions()
        case "notifbadge", "badge":
            if let id = appState.active.id { appState.unread[id] = 5 }
            rebuildRail()
        case "acctmenu": railView.debugShowAccount()
        case "morepopover", "moremenu": railView.debugShowMore()
        case "settings": appState.openSettings()
        case "navconfig": appState.openNavConfig()
        case "addaccount": appState.openAddAccount()
        case "loading", "force-loading":
            debugSetTimeline(status: .loading, rows: [])
        case "error", "force-error":
            debugSetTimeline(status: .error, rows: [])
        case "empty", "force-empty":
            debugSetTimeline(status: .empty, rows: [])
        case "unread", "new":
            let rows = [
                TimelineRow.post(debugPost("dbg1", text: "A freshly merged post is sitting above your current reading position.")),
                TimelineRow.post(debugPost("dbg2", text: "The unread pill and rail dot both reflect the new items waiting at the top.")),
                TimelineRow.post(debugPost("dbg3", text: "Scroll position should stay anchored while this list updates."))
            ]
            debugSetTimeline(status: .ready, rows: rows, unread: ["dbg1", "dbg2"])
        case "newposts", "pill":
            let rows = [
                TimelineRow.post(debugPost("dbg1", text: "Three people you follow just posted — their faces ride the centered pill above this list.")),
                TimelineRow.post(debugPost("dbg2", text: "Avatars come straight from the HomeTimeline alert's usersResults, not the merged posts.")),
                TimelineRow.post(debugPost("dbg3", text: "Click the pill to scroll to top and clear the unread state."))
            ]
            let faces = [
                Person(name: "DanielW", handle: "dddanielwang", colorToken: "blue-700", verified: true, platform: .x,
                       avatarURL: "https://pbs.twimg.com/profile_images/2060696098373812224/snUCizcD_normal.jpg"),
                Person(name: "属鼠蜀黍", handle: "_naiVe_2", colorToken: "magenta-800", verified: false, platform: .x,
                       avatarURL: "https://pbs.twimg.com/profile_images/1967072505522503680/DwBdgYh8_normal.jpg"),
                Person(name: "antirez", handle: "antirez", colorToken: "seafoam-800", verified: true, platform: .x,
                       avatarURL: "https://pbs.twimg.com/profile_images/1779914746159882240/v6h2w9g0_normal.jpg")
            ]
            debugSetTimeline(status: .ready, rows: rows, unread: ["dbg1", "dbg2", "dbg3"], newAuthors: faces)
        case "gap":
            let rows = [
                TimelineRow.post(debugPost("dbg1", text: "Newest segment loaded from an automatic refresh.")),
                TimelineRow.gap(TimelineGap(cursor: "debug-gap")),
                TimelineRow.post(debugPost("dbg5", text: "Older segment from the cached timeline remains below the gap.")),
                TimelineRow.post(debugPost("dbg6", text: "Click the gap row to simulate filling the missing range."))
            ]
            debugSetTimeline(status: .ready, rows: rows)
        case "hometabs", "home-tabs":
            debugSetTimeline(status: .ready, rows: [
                TimelineRow.post(debugPost("dbg1", text: "For you and Following are now separate Home feeds with independent storage.")),
                TimelineRow.post(debugPost("dbg2", text: "Switching tabs changes the timeline identity and JSONL key."))
            ])
        case "quotedvideo", "quotevideo":
            debugSetTimeline(status: .ready, rows: [
                TimelineRow.post(debugQuotedVideoPost()),
                TimelineRow.post(debugPost("dbg8", text: "A normal post below confirms the attributed video row does not disturb timeline spacing."))
            ])
        case "xlogin":
            appState.openAddAccount()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.addAccountView?.debugStartXLogin()
            }
        case "detailvideo":
            if let c = appState.columns.first { appState.pushScreen(c.id, .post("x5")) }
        case "mediavideo":
            appState.openMediaViewer(MediaViewerContext(
                items: [MediaItem(Gradients.ocean)], initialIndex: 0,
                author: debugStubPerson, type: .video, dur: "0:41"))
        case "mediaimages":
            appState.openMediaViewer(MediaViewerContext(
                items: [MediaItem(Gradients.plum), MediaItem(Gradients.ember),
                        MediaItem(Gradients.steel), MediaItem(Gradients.dusk)],
                initialIndex: 0, author: debugStubPerson, type: .images, dur: nil))
        case "detailskel":
            if let c = appState.columns.first {
                let fakeId = "skel_nonexistent"
                appState.detailLoading.insert(fakeId)
                appState.pushScreen(c.id, .post(fakeId))
            }
        case "profileskel":
            if let c = appState.columns.first {
                let p = Person(name: "Loading…", handle: "skel_nonexistent", colorToken: "gray-500", verified: false, platform: .x)
                appState.profileLoading.insert(p.handle)
                appState.pushScreen(c.id, .profile(p))
            }
        case "colmenu":
            if let cv = columnViews.first { _ = cv }
        case "reloadmenu":
            columnViews.first?.debugShowReloadMenu()
        case "bookmarks":
            debugSetBookmarks()
        case "bmfolder":
            debugSetBookmarks(scope: "f_design")
        case "bmselect", "bmdialog":
            debugSetBookmarks()
        case "search":
            debugSetSearch(query: "")
        case "searchresults", "searchquery":
            debugSetSearch(query: "native rendering")
        case "lists":
            debugSetLists()
        case "listmenu":
            debugSetLists()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.columnViews.first?.debugShowMenu()
            }
        case "developer":
            appState.debugEnabled = true
            appState.openSettings()
            settingsView?.debugSwitchCat("developer")
        case "developeroff":
            appState.debugEnabled = false
            appState.openSettings()
            settingsView?.debugSwitchCat("developer")
        case "inspector":
            appState.debugEnabled = true
            debugSeedNetwork()
            appState.openInspector()
        case "inspectordetail":
            appState.debugEnabled = true
            debugSeedNetwork()
            appState.openInspector()
            inspectorView?.debugSelectFirstNetwork()
        case "inspectordata":
            appState.debugEnabled = true
            debugSeedNetwork()
            debugSetTimeline(status: .ready, rows: [
                TimelineRow.post(debugPost("dbg1", text: "Column data is mirrored into the inspector's Data tab as ordered JSON.")),
                TimelineRow.post(debugPost("dbg2", text: "Each open column is a selectable snapshot with its own Copy button."))
            ])
            appState.openInspector()
            inspectorView?.debugShowDataTab()
        case "debugrail":
            appState.debugEnabled = true
            debugSeedNetwork()
            debugSetTimeline(status: .ready, rows: [
                TimelineRow.post(debugPost("dbg1", text: "With debug tools on, the rail gains an Inspector entry and the column header gains a code button.")),
                TimelineRow.post(debugPost("dbg2", text: "Hovering a post reveals its own code glyph next to the more button.")),
                TimelineRow.post(debugPost("dbg3", text: "Toggling debug off removes every affordance and re-flows the rail cluster."))
            ])
        case "tweetjson":
            appState.debugEnabled = true
            let p = debugPost("dbg42", text: "The code glyph on a post opens this window — the tweet's raw underlying data.")
            let isXPost = p.author.platform == .x
            appState.openJsonViewer(JsonViewerContext(
                title: (isXPost ? "Tweet · " : "微博 · ") + p.author.name,
                subtitle: (isXPost ? "@" + p.author.handle : p.author.name) + " · id " + p.id,
                json: DebugJSON.from(post: p)))
        default: break
        }
    }

    private func debugSetBookmarks(scope: String = "__all__") {
        guard let acctId = appState.active.id else { return }
        if appState.columns.isEmpty {
            appState.columns = [ColumnSpec(id: "c1", type: "bookmarks", accountId: acctId)]
        }
        let col = appState.columns[0]
        col.type = "bookmarks"
        col.accountId = acctId

        appState.liveBookmarkFolders = [
            BookmarkFolder(id: "f_read", name: "Read later", colorToken: "blue-900"),
            BookmarkFolder(id: "f_design", name: "Design", colorToken: "magenta-800"),
            BookmarkFolder(id: "f_code", name: "Code", colorToken: "orange-800"),
            BookmarkFolder(id: "f_inspo", name: "Inspiration", colorToken: "purple-800"),
        ]
        let maya = Person(name: "Maya Chen", handle: "mayacodes", colorToken: "seafoam-800", verified: true, platform: .x)
        let all: [Post] = [
            debugPost("bm1", text: "A crisp note on type scales and vertical rhythm in dense reading UIs."),
            debugPost("bm2", text: "Thread: shipping a GraphQL client without an SDK — every gotcha we hit.", author: maya),
            debugPost("bm3", text: "Saving this for the weekend read on perceptual color systems."),
            debugPost("bm4", text: "Great breakdown of optimistic UI patterns and rollback on failure.", author: maya),
            debugPost("bm5", text: "Folder organization for bookmarks finally feels native."),
        ]
        appState.bmFolderPosts = [
            "f_design": [all[0], all[3]],
            "f_code": [all[1]],
            "f_read": [all[2], all[4]],
        ]
        let identity = TimelineIdentity(accountId: acctId, kind: .bookmarks, variant: "")
        var snapshot = TimelineSnapshot(identity: identity, rows: all.map { .post($0) }, status: .ready,
                                        bottomCursor: "debug-bottom", loadedFromDisk: true)
        snapshot.normalizeStatus()
        appState.timelineSnapshots[identity.key] = snapshot
        appState.bmScope[col.id] = scope
        rebuildCanvas()
        rebuildRail()
    }

    /// Seed a search column. An empty query shows the always-visible search field +
    /// trending list (设计稿 SearchHeader); a non-empty query seeds matching results.
    private func debugSetSearch(query: String) {
        guard let acctId = appState.active.id else { return }
        if appState.columns.isEmpty {
            appState.columns = [ColumnSpec(id: "c1", type: "search", accountId: acctId)]
        }
        let col = appState.columns[0]
        col.type = "search"
        col.accountId = acctId
        appState.searchQuery[col.id] = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let dev = Person(name: "Lena Park", handle: "lenarenders", colorToken: "teal-800", verified: true, platform: .x)
            let rows: [TimelineRow] = [
                .post(debugPost("sr1", text: "native rendering wins on text crispness every single time — here's the subpixel proof.", author: dev)),
                .post(debugPost("sr2", text: "spent the weekend porting the renderer to Metal. native text rendering latency dropped to ~2ms.")),
                .post(debugPost("sr3", text: "hot take: web-view rendering is fine until you put two columns of dense text side by side.", author: dev)),
            ]
            let identity = TimelineIdentity(accountId: acctId, kind: .search, variant: trimmed)
            var snapshot = TimelineSnapshot(identity: identity, rows: rows, status: .ready,
                                            bottomCursor: "debug-bottom", loadedFromDisk: true)
            snapshot.normalizeStatus()
            appState.timelineSnapshots[identity.key] = snapshot
        }
        rebuildCanvas()
        rebuildRail()
    }

    /// Seed a lists column: a few live-style lists, a selection, and that list's timeline.
    private func debugSetLists() {
        guard let acctId = appState.active.id else { return }
        if appState.columns.isEmpty {
            appState.columns = [ColumnSpec(id: "c1", type: "lists", accountId: acctId)]
        }
        let col = appState.columns[0]
        col.type = "lists"
        col.accountId = acctId

        appState.liveLists = [
            TwitterList(id: "l_ios", name: "iOS & macOS devs", description: nil, memberCount: 142,
                        subscriberCount: 38, isFollowing: true, isMember: false, mode: "Public",
                        createdById: nil, createdAt: nil),
            TwitterList(id: "l_design", name: "Design systems", description: nil, memberCount: 67,
                        subscriberCount: 12, isFollowing: true, isMember: true, mode: "Private",
                        createdById: nil, createdAt: nil),
            TwitterList(id: "l_swift", name: "Swift evolution", description: nil, memberCount: 29,
                        subscriberCount: 5, isFollowing: false, isMember: true, mode: "Public",
                        createdById: nil, createdAt: nil),
        ]
        appState.listSelection[col.id] = "l_ios"

        let kai = Person(name: "Kai Sterling", handle: "kaibuilds", colorToken: "orange-800", verified: true, platform: .x)
        let rows: [TimelineRow] = [
            .post(debugPost("ls1", text: "AppKit table-view virtualization is criminally underrated for dense reading UIs.", author: kai)),
            .post(debugPost("ls2", text: "shipping a multi-column reader entirely in frame-based layout — no Auto Layout, no SwiftUI.")),
            .post(debugPost("ls3", text: "the trick to buttery scrolling: cache row heights and never measure on the main thread twice.", author: kai)),
            .post(debugPost("ls4", text: "macOS 13 makes NSTableView.style = .plain finally behave the way you'd expect.")),
        ]
        let identity = TimelineIdentity(accountId: acctId, kind: .lists, variant: "l_ios")
        var snapshot = TimelineSnapshot(identity: identity, rows: rows, status: .ready,
                                        bottomCursor: "debug-bottom", loadedFromDisk: true)
        snapshot.normalizeStatus()
        appState.timelineSnapshots[identity.key] = snapshot
        rebuildCanvas()
        rebuildRail()
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseUp]) { [weak self] event in
            guard let self, self.view.window?.isKeyWindow == true else { return event }
            if self.composeView != nil { return event }

            switch event.type {
            case .keyDown:
                if self.handleKeyDown(event) { return nil }
            case .otherMouseUp:
                if self.handleOtherMouseUp(event) { return nil }
            default:
                break
            }
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let fr = view.window?.firstResponder
        if fr is NSText || fr is NSTextView { return false }

        let chars = event.charactersIgnoringModifiers
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandOnly = flags.contains(.command)
            && !flags.contains(.control)
            && !flags.contains(.option)
            && !flags.contains(.shift)

        if commandOnly {
            if chars == "[" { return appState.navigateBack() }
            if chars == "]" { return appState.navigateForward() }
        }

        if chars == "c",
           !flags.contains(.command),
           !flags.contains(.control) {
            appState.openCompose()
            return true
        }

        return false
    }

    private func handleOtherMouseUp(_ event: NSEvent) -> Bool {
        switch event.buttonNumber {
        case 3:
            return appState.navigateBack()
        case 4:
            return appState.navigateForward()
        default:
            return false
        }
    }
}

// ── PopoverHost ──
extension RootViewController: PopoverHost {
    func presentPopover(_ content: NSView, width: CGFloat, height: CGFloat, anchor: NSView, edge: PopoverEdge, dx: CGFloat, dy: CGFloat) {
        dismissPopover()
        let dim = HoverControl(frame: overlayContainer.bounds)
        dim.onClick = { [weak self] in self?.dismissPopover() }
        overlayContainer.addSubview(dim)
        popoverDim = dim

        // anchor rect in overlay coordinates
        let rect = overlayContainer.convert(anchor.bounds, from: anchor)
        var x: CGFloat
        var y: CGFloat
        let gap: CGFloat = 6
        switch edge {
        case .below:
            x = rect.minX + dx
            y = rect.maxY + gap + dy
        case .above:
            x = rect.minX + dx
            y = rect.minY - gap - height + dy
        case .right:
            x = rect.maxX + dx
            y = rect.minY + dy
        case .custom:
            x = rect.minX + dx
            y = rect.maxY + dy
        }
        // clamp inside overlay
        let maxX = overlayContainer.bounds.width - width - 8
        let maxY = overlayContainer.bounds.height - height - 8
        x = min(max(8, x), max(8, maxX))
        y = min(max(8, y), max(8, maxY))
        content.frame = NSRect(x: x, y: y, width: width, height: height)
        // shadow
        content.wantsLayer = true
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = theme.isDark ? 0.5 : 0.16
        content.layer?.shadowRadius = 12
        content.layer?.shadowOffset = CGSize(width: 0, height: -3)
        content.layer?.masksToBounds = false
        overlayContainer.addSubview(content)
        popoverContent = content
    }

    func dismissPopover() {
        popoverDim?.removeFromSuperview(); popoverDim = nil
        popoverContent?.removeFromSuperview(); popoverContent = nil
    }
}

// ── AppStateDelegate ──
extension RootViewController: AppStateDelegate {
    func appStateDidChangeTheme(_ s: AppState) {
        dismissPopover()
        let trayWasOpen = trayView != nil
        let composeWasOpen = composePanel != nil
        let settingsWasOpen = settingsPanel != nil
        let addAccountWasOpen = addAccountPanel != nil
        dismissTray()
        unmountCompose()
        unmountSettings()
        unmountAddAccount()
        view.window?.backgroundColor = theme.bgBase
        buildAll()
        railView.needsLayout = true
        if trayWasOpen { showTray() }
        if composeWasOpen { mountCompose() }
        if settingsWasOpen { mountSettings() }
        if addAccountWasOpen { mountAddAccount() }
    }

    func appStateDidChangeColumns(_ s: AppState) {
        dismissPopover()
        let newCount = appState.columns.count

        guard newCount != lastColumnCount, lastColumnCount > 0,
              let window = view.window else {
            rebuildCanvas()
            updateMinWindowSize()
            rebuildRail()
            trayView?.refresh()
            return
        }

        // Keep each column at its current width; the window edge is the only thing that moves.
        let oldColW = lastComputedColW > 0 ? lastComputedColW : UI.columnW
        let minW = UI.railW + CGFloat(newCount) * UI.columnMinW
        let newW = max(minW, UI.railW + CGFloat(newCount) * oldColW)

        // Rebuild at oldColW so existing columns are not disturbed.
        targetColumnWidth = oldColW
        rebuildCanvas()
        targetColumnWidth = nil

        updateMinWindowSize()
        rebuildRail()
        trayView?.refresh()

        // Animate only the window edge; suppress column layout during the animation
        // so the canvas stays pinned at newCount × oldColW while the window catches up.
        suppressReleaseTimer?.invalidate()
        suppressColumnLayout = true
        var f = window.frame
        f.size.width = newW
        window.setFrame(f, display: true, animate: true)
        suppressReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.28, repeats: false) { [weak self] _ in
            self?.suppressColumnLayout = false
            self?.relayout()
        }
    }

    func appStateDidChangeActive(_ s: AppState) {
        dismissPopover()
        settingsView?.refreshAccountsPaneIfNeeded()
        rebuildCanvas()
        rebuildRail()
        trayView?.refresh()
    }

    func appState(_ s: AppState, didChangeTimelineUnreadForColumn colId: String) {
        guard let idx = appState.columns.firstIndex(where: { $0.id == colId }),
              idx < columnViews.count else {
            rebuildRail()
            return
        }
        columnViews[idx].refreshTimelineUnreadOverlay()
        rebuildRail()
    }

    private func rebuildRail() {
        railView?.removeFromSuperview()
        railView = IconRailView(appState: appState, onToggleColumns: { [weak self] in self?.toggleTray() })
        // insert below overlayContainer
        view.addSubview(railView, positioned: .below, relativeTo: overlayContainer)
        relayout()
    }

    func appState(_ s: AppState, didUpdatePost id: String) {
        for cv in columnViews { cv.updatePost(id) }
    }

    func appState(_ s: AppState, didChangeDetailFor id: String) {
        for cv in columnViews { cv.refreshDetailPanel(id: id) }
    }

    func appState(_ s: AppState, didChangeProfileFor handle: String) {
        for cv in columnViews { cv.refreshProfilePanel(handle: handle) }
    }

    func appState(_ s: AppState, didChangeNavForColumn colId: String) {
        guard let idx = appState.columns.firstIndex(where: { $0.id == colId }), idx < columnViews.count else { return }
        columnViews[idx].updateStack(appState.colNav[colId] ?? [])
    }

    func appStateDidChangeCompose(_ s: AppState) {
        if appState.composeOpen {
            if composePanel == nil { mountCompose() }
        } else {
            unmountCompose()
        }
    }

    func appState(_ s: AppState, showToast text: String) {
        showToast(text)
    }

    func appState(_ s: AppState, didAddReplyTo postId: String) {
        for cv in columnViews { cv.reload() }
    }

    func appStateDidChangeSettings(_ s: AppState) {
        if appState.settingsOpen {
            if settingsPanel == nil { mountSettings() }
        } else {
            unmountSettings()
            rebuildRail()
        }
    }

    func appStateDidChangeAddAccount(_ s: AppState) {
        if appState.addAccountOpen {
            if addAccountPanel == nil { mountAddAccount() }
        } else {
            unmountAddAccount()
        }
    }

    func appStateDidChangeNavConfigOpen(_ s: AppState) {
        if appState.navConfigOpen {
            if navConfigView == nil { mountNavConfig() }
        } else {
            unmountNavConfig()
        }
    }

    func appStateDidChangeNavConfig(_ s: AppState) {
        rebuildRail()
    }

    func appStateDidChangeMediaViewer(_ s: AppState) {
        if appState.mediaViewerOpen {
            if mediaViewerPanel == nil { mountMediaViewer() }
        } else {
            unmountMediaViewer()
        }
    }

    func appStateDidChangeDebug(_ s: AppState) {
        // Toggling debug (or its sub-flags) re-gates the rail entry and the inline
        // code buttons on every post cell + column header.
        rebuildRail()
        rebuildCanvas()
        if !appState.debugEnabled {
            unmountInspector()
            jsonViewerPanels.forEach { $0.dismiss() }
            jsonViewerPanels.removeAll()
        }
    }

    func appStateDidChangeInspector(_ s: AppState) {
        if appState.inspectorOpen {
            if inspectorPanel == nil { mountInspector() }
        } else {
            unmountInspector()
        }
        rebuildRail()
    }

    func appState(_ s: AppState, openJsonViewer ctx: JsonViewerContext) {
        openJsonViewerWindow(ctx)
    }

    func appStateRequestsWelcome(_ s: AppState) {
        onRequestWelcome?()
    }

    func appStateDidConnectFirstAccount(_ s: AppState) {
        // Inside the main app this path is unexpected (it fires from the Welcome
        // window); treat it as a normal account change so the canvas refreshes.
        appStateDidChangeActive(s)
    }
}
