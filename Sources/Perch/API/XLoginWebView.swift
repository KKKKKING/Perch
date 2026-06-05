import AppKit
import WebKit

/// Hosts a real `WKWebView` pointed at x.com's login flow and watches the cookie
/// store for `auth_token` + `ct0`. Fires `onCredentials` exactly once when both
/// cookies appear (i.e. login succeeded).
final class XLoginWebView: FlippedView, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    let webView: WKWebView
    private let onCredentials: (_ authToken: String, _ ct0: String) -> Void
    private let onURLChange: (String) -> Void
    private var fired = false
    private var urlObservation: NSKeyValueObservation?
    private var popupWindows: [XLoginPopupWindowController] = []

    init(onURLChange: @escaping (String) -> Void,
         onCredentials: @escaping (_ authToken: String, _ ct0: String) -> Void) {
        self.onCredentials = onCredentials
        self.onURLChange = onURLChange
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        config.applicationNameForUserAgent = "Version/17.0 Safari/605.1.15"
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        addSubview(webView)
        config.websiteDataStore.httpCookieStore.add(self)

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            if let u = wv.url?.absoluteString { self?.onURLChange(u) }
        }

        if let url = URL(string: "https://x.com/i/flow/login") {
            webView.load(URLRequest(url: url))
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        urlObservation?.invalidate()
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        let popups = popupWindows
        popupWindows.removeAll()
        popups.forEach { $0.close() }
    }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    func reload() { webView.reload() }

    // MARK: - New windows

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }

        configuration.websiteDataStore = webView.configuration.websiteDataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let popup = XLoginPopupWindowController(
            configuration: configuration,
            parentWindow: window,
            customUserAgent: webView.customUserAgent
        )
        popup.onClose = { [weak self, weak popup] in
            guard let popup else { return }
            self?.popupWindows.removeAll { $0 === popup }
        }
        popupWindows.append(popup)
        popup.present()
        return popup.webView
    }

    // MARK: - Cookie extraction

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let u = webView.url?.absoluteString { onURLChange(u) }
        checkCookies()
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        checkCookies()
    }

    private func checkCookies() {
        guard !fired else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.fired else { return }
            var authToken: String?
            var ct0: String?
            for c in cookies {
                let host = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                guard host == "x.com" || host == "twitter.com" else { continue }
                if c.name == "auth_token", !c.value.isEmpty { authToken = c.value }
                if c.name == "ct0", !c.value.isEmpty { ct0 = c.value }
            }
            if let authToken, let ct0 {
                self.fired = true
                self.onCredentials(authToken, ct0)
            }
        }
    }
}

private final class XLoginPopupWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onClose: (() -> Void)?

    private var chrome: BrowserChromeView?
    private var urlObservation: NSKeyValueObservation?

    init(configuration: WKWebViewConfiguration, parentWindow: NSWindow?, customUserAgent: String?) {
        webView = WKWebView(frame: .zero, configuration: configuration)

        let size = NSSize(width: 640, height: 720)
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Sign in"
        win.minSize = NSSize(width: 420, height: 480)
        win.isReleasedWhenClosed = false

        let content = FlippedView(frame: NSRect(origin: .zero, size: size))
        win.contentView = content

        super.init(window: win)

        win.delegate = self
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if let customUserAgent {
            webView.customUserAgent = customUserAgent
        }

        build(in: content)
        position(relativeTo: parentWindow)

        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            self?.updateChrome(wv.url?.absoluteString)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        urlObservation?.invalidate()
    }

    func present() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func build(in content: NSView) {
        let chromeH = BrowserChromeView.height
        let chromeBar = BrowserChromeView(webView: webView)
        chromeBar.frame = NSRect(x: 0, y: 0, width: content.bounds.width, height: chromeH)
        content.addSubview(chromeBar)
        chrome = chromeBar

        webView.frame = NSRect(x: 0, y: chromeH, width: content.bounds.width, height: content.bounds.height - chromeH)
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
    }

    private func position(relativeTo parentWindow: NSWindow?) {
        guard let win = window else { return }
        guard let parentWindow else {
            win.center()
            return
        }

        let screenFrame = parentWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        var origin = NSPoint(x: parentWindow.frame.midX - win.frame.width / 2,
                             y: parentWindow.frame.midY - win.frame.height / 2)

        if let screenFrame {
            origin.x = min(max(origin.x, screenFrame.minX), screenFrame.maxX - win.frame.width)
            origin.y = min(max(origin.y, screenFrame.minY), screenFrame.maxY - win.frame.height)
        }

        win.setFrameOrigin(origin)
    }

    private func updateChrome(_ url: String?) {
        chrome?.setAddress(url)

        var title = url ?? ""
        for prefix in ["https://", "http://"] where title.hasPrefix(prefix) {
            title.removeFirst(prefix.count)
        }
        if title.hasPrefix("www.") { title.removeFirst(4) }
        if let slash = title.firstIndex(of: "/") {
            title = String(title[..<slash])
        }
        window?.title = title.isEmpty ? "Sign in" : title
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateChrome(webView.url?.absoluteString)
    }

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
