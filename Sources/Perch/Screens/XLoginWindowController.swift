import AppKit

/// Real X login in its own resizable browser window (800×600 default). Hosts the
/// `XLoginWebView`, watches for the auth cookies, exchanges them for an account,
/// then closes. Used by both the Welcome screen and the in-app Add Account picker.
final class XLoginWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState
    private let onClose: () -> Void
    private var dismissing = false
    private var webView: XLoginWebView?
    private var chrome: BrowserChromeView?

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Sign in to X"
        win.minSize = NSSize(width: 520, height: 440)
        win.isReleasedWhenClosed = false
        win.contentView = FlippedView()
        super.init(window: win)
        win.delegate = self
        startLogin()
        win.center()
    }
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func startLogin() {
        guard let content = window?.contentView else { return }
        content.subviews.forEach { $0.removeFromSuperview() }
        window?.title = "Sign in to X"
        let web = XLoginWebView(
            onURLChange: { [weak self] u in self?.updateTitle(u) },
            onCredentials: { [weak self] token, ct0 in self?.handleCookies(token, ct0) })

        let chromeH = BrowserChromeView.height
        let chromeBar = BrowserChromeView(webView: web.webView)
        chromeBar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: chromeH)
        content.addSubview(chromeBar)
        chrome = chromeBar

        web.frame = NSRect(x: 0, y: chromeH, width: content.bounds.width, height: content.bounds.height - chromeH)
        web.autoresizingMask = [.width, .height]
        content.addSubview(web)
        webView = web
    }

    private func updateTitle(_ url: String) {
        chrome?.setAddress(url)
        var s = url
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        window?.title = s.isEmpty ? "Sign in to X" : s
    }

    private func handleCookies(_ token: String, _ ct0: String) {
        webView = nil
        showConnecting()
        Task { [weak self] in
            guard let self else { return }
            do {
                let acct = try await TwitterService.shared.login(authToken: token, ct0: ct0)
                await MainActor.run {
                    self.appState.addNewAccount(acct)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    let msg = (error as? TwitterAPIError)?.errorDescription ?? error.localizedDescription
                    self.appState.showToastNow("Login failed: \(msg)")
                    self.startLogin()
                }
            }
        }
    }

    private func showConnecting() {
        guard let content = window?.contentView else { return }
        chrome = nil
        content.subviews.forEach { $0.removeFromSuperview() }
        window?.title = "Connecting…"
        let page = FlippedView(frame: content.bounds)
        page.autoresizingMask = [.width, .height]
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.black.cgColor
        content.addSubview(page)

        let logo = makeLabel("𝕏", font: .systemFont(ofSize: 44, weight: .heavy), color: .white, align: .center)
        logo.frame = NSRect(x: 0, y: content.bounds.height / 2 - 50, width: content.bounds.width, height: 52)
        logo.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        page.addSubview(logo)

        let lbl = makeLabel("Connecting your account…", font: Fonts.sans(15), color: NSColor(hex: "#71767b"), align: .center)
        lbl.frame = NSRect(x: 0, y: content.bounds.height / 2 + 16, width: content.bounds.width, height: 20)
        lbl.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        page.addSubview(lbl)
    }

    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
