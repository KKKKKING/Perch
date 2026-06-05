import AppKit
import WebKit

/// Reusable in-app browser chrome: a 46px toolbar with back / forward / reload
/// nav buttons, a lock + address bar (with busy spinner), and an optional pill.
/// Drives an attached `WKWebView` and disables the back/forward buttons when the
/// web view can't navigate that way.
final class BrowserChromeView: FlippedView {
    static let height: CGFloat = 46

    private let theme = ThemeManager.shared.theme
    private let webView: WKWebView
    private let pillText: String?

    private let backBtn = HoverControl()
    private let forwardBtn = HoverControl()
    private let reloadBtn = HoverControl()
    private let backGlyph: GlyphView
    private let forwardGlyph: GlyphView
    private let reloadGlyph: GlyphView

    private let addrBar = FlippedView()
    private let lockGlyph: GlyphView
    private let addrLabel: NSTextField
    private let spinner = NSProgressIndicator()

    private var pill: FlippedView?
    private var observations: [NSKeyValueObservation] = []

    private var currentURL = ""

    /// `pill` shows a small trailing badge (e.g. "In-app" / "内置浏览器"); pass nil to hide.
    init(webView: WKWebView, pill: String? = "In‑app") {
        self.webView = webView
        self.pillText = pill
        backGlyph = GlyphView(name: "chevron-down", size: 17, color: theme.fgSubdued)
        forwardGlyph = GlyphView(name: "chevron-down", size: 17, color: theme.fgSubdued)
        reloadGlyph = GlyphView(name: "refresh", size: 17, color: theme.fgSubdued)
        lockGlyph = GlyphView(name: "globe", size: 13, color: theme.fgSubdued)
        addrLabel = makeLabel("", font: Fonts.sans(13), color: theme.fgBody)
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: Self.height))
        build()
        observe()
        syncNavState()
        syncAddress()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { observations.forEach { $0.invalidate() } }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = theme.bgBase.cgColor
        autoresizingMask = [.width]

        let line = NSView(frame: NSRect(x: 0, y: Self.height - 1, width: bounds.width, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        line.autoresizingMask = [.width]
        addSubview(line)

        backGlyph.rotationDegrees = 90      // chevron-down → points left
        forwardGlyph.rotationDegrees = -90  // chevron-down → points right
        configureNavButton(backBtn, glyph: backGlyph, x: 10) { [weak self] in self?.webView.goBack() }
        configureNavButton(forwardBtn, glyph: forwardGlyph, x: 42) { [weak self] in self?.webView.goForward() }
        configureNavButton(reloadBtn, glyph: reloadGlyph, x: 74) { [weak self] in self?.webView.reload() }

        addrBar.wantsLayer = true
        addrBar.layer?.cornerRadius = 16
        addrBar.layer?.backgroundColor = theme.bgLayer1.cgColor
        addrBar.layer?.borderColor = theme.borderDefault.cgColor
        addrBar.layer?.borderWidth = 1
        addrBar.autoresizingMask = [.width]
        lockGlyph.frame = NSRect(x: 12, y: (32 - 13) / 2, width: 13, height: 13)
        addrBar.addSubview(lockGlyph)
        addrLabel.lineBreakMode = .byTruncatingTail
        addrBar.addSubview(addrLabel)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isIndeterminate = true
        addrBar.addSubview(spinner)

        addSubview(addrBar)
        buildPill()
        layoutBar()
    }

    private func configureNavButton(_ btn: HoverControl, glyph: GlyphView, x: CGFloat, action: @escaping () -> Void) {
        btn.frame = NSRect(x: x, y: 9, width: 28, height: 28)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 7
        glyph.frame = NSRect(x: 5.5, y: 5.5, width: 17, height: 17)
        btn.addSubview(glyph)
        btn.onState = { [weak self, weak btn] h, _ in
            guard let self, let btn, btn.enabledControl else { return }
            btn.layer?.backgroundColor = (h ? self.theme.gray200 : NSColor.clear).cgColor
        }
        btn.onClick = action
        addSubview(btn)
    }

    private func buildPill() {
        guard let pillText else { return }
        let p = FlippedView()
        p.wantsLayer = true
        p.layer?.cornerRadius = 12
        p.layer?.backgroundColor = theme.gray100.cgColor
        let g = GlyphView(name: "lock", size: 12, color: theme.fgSubdued)
        g.frame = NSRect(x: 9, y: 6, width: 12, height: 12)
        p.addSubview(g)
        let lbl = makeLabel(pillText, font: Fonts.sans(11, .bold), color: theme.fgSubdued)
        let w = lbl.intrinsicContentSize.width
        lbl.frame = NSRect(x: 25, y: (24 - lbl.intrinsicContentSize.height) / 2, width: w, height: lbl.intrinsicContentSize.height)
        p.addSubview(lbl)
        p.frame.size = NSSize(width: 25 + w + 10, height: 24)
        addSubview(p)
        pill = p
    }

    private func layoutBar() {
        let pillW = pill?.frame.width ?? 0
        let pillGap: CGFloat = pillText == nil ? 0 : pillW + 8
        let barX: CGFloat = 110
        let barW = max(40, bounds.width - barX - 10 - pillGap)
        addrBar.frame = NSRect(x: barX, y: 7, width: barW, height: 32)
        let labelRight: CGFloat = barW - 12 - (webView.isLoading ? 20 : 0)
        addrLabel.frame = NSRect(x: 31, y: (32 - addrLabel.intrinsicContentSize.height) / 2,
                                 width: max(10, labelRight - 31), height: addrLabel.intrinsicContentSize.height)
        spinner.frame = NSRect(x: barW - 28, y: (32 - 16) / 2, width: 16, height: 16)
        if let pill { pill.frame.origin = CGPoint(x: bounds.width - 10 - pill.frame.width, y: 11) }
    }

    override func layout() {
        super.layout()
        layoutBar()
    }

    // MARK: - WKWebView binding

    private func observe() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial]) { [weak self] _, _ in self?.syncNavState() },
            webView.observe(\.canGoForward, options: [.initial]) { [weak self] _, _ in self?.syncNavState() },
            webView.observe(\.isLoading, options: [.initial]) { [weak self] _, _ in self?.syncLoading() },
            webView.observe(\.url, options: [.initial]) { [weak self] wv, _ in self?.setAddress(wv.url?.absoluteString) },
        ]
    }

    /// Public entry point so the host can also push URLs from its navigation
    /// delegate (e.g. `didFinish`), covering same-document changes KVO may miss.
    func setAddress(_ urlString: String?) {
        let next = urlString ?? ""
        guard next != currentURL else { return }
        currentURL = next
        syncAddress()
    }

    private func syncNavState() {
        setEnabled(backBtn, glyph: backGlyph, on: webView.canGoBack)
        setEnabled(forwardBtn, glyph: forwardGlyph, on: webView.canGoForward)
    }

    private func setEnabled(_ btn: HoverControl, glyph: GlyphView, on: Bool) {
        btn.enabledControl = on
        glyph.color = on ? theme.fgSubdued : theme.fgDisabled
        if !on { btn.layer?.backgroundColor = NSColor.clear.cgColor }
    }

    private func syncLoading() {
        if webView.isLoading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        layoutBar()
    }

    private func syncAddress() {
        let secure = currentURL.hasPrefix("https")
        lockGlyph.setName(secure ? "lock" : "globe")
        lockGlyph.color = secure ? theme.positive : theme.fgSubdued
        addrLabel.stringValue = Self.display(currentURL)
        layoutBar()
    }

    /// host + path, scheme / `www.` / query / fragment stripped so the host stays
    /// front-and-center — e.g. `https://x.com/i/flow/login?lang=en` → `x.com/i/flow/login`.
    static func display(_ urlString: String) -> String {
        var s = urlString
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        if s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
