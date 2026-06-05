import AppKit
import WebKit

// MARK: - AddAccountView

/// Simplified add-account flow: platform picker → fake sign-in form → connected success
final class AddAccountView: FlippedView {
    private let appState: AppState
    private let onClose: () -> Void
    private let theme = ThemeManager.shared.theme
    private let isX: Bool
    private let CARD_W: CGFloat = 460
    private var eventMonitor: Any?
    private weak var panelController: PanelWindowController?

    private let card = FlippedView()
    private let contentArea = FlippedView()
    private var step: Step = .pick
    private var selectedPlatform: Platform = .x

    // X login state
    private var xUsername = ""
    private var xPassword = ""
    private var xWebView: XLoginWebView?
    private var browserAddrLabel: NSTextField?

    // Weibo login state
    private var wTab = "qr"  // "qr" or "account"
    private var wUser = ""
    private var wPass = ""
    private var qrScanned = false

    enum Step { case pick, login, authorize, success }

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        // No accounts yet (welcome / empty state) → default to X to avoid force-unwrap.
        let resolved = (appState.accounts.first(where: { $0.id == appState.activeId }) ?? appState.accounts.first)?.platform
        self.isX = resolved != .weibo
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        buildCard()
        installMonitor()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { removeMonitor() }

    private func buildCard() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = theme.bgElevated.cgColor
        card.layer?.borderColor = theme.borderDefault.cgColor
        card.layer?.borderWidth = 1
        card.layer?.masksToBounds = true
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.52
        card.layer?.shadowRadius = 32
        card.layer?.shadowOffset = CGSize(width: 0, height: -8)
        addSubview(card)

        buildHeader()
        contentArea.frame = NSRect(x: 0, y: 38, width: CARD_W, height: 0)
        card.addSubview(contentArea)
        showPickStep()
    }

    private func buildHeader() {
        let header = FlippedView(frame: NSRect(x: 0, y: 0, width: CARD_W, height: 38))
        header.wantsLayer = true
        header.layer?.backgroundColor = theme.bgLayer1.cgColor
        card.addSubview(header)
        // border bottom
        let line = NSView(frame: NSRect(x: 0, y: 37, width: CARD_W, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        header.addSubview(line)
        // traffic lights
        let dots: [(NSColor, Bool)] = [
            (NSColor(hex: "#ff5f57"), true),
            (NSColor(hex: "#febc2e"), false),
            (NSColor(hex: "#28c840"), false),
        ]
        var dx: CGFloat = 14
        for (color, closeable) in dots {
            let dot = HoverControl(frame: NSRect(x: dx, y: (38 - 12) / 2, width: 12, height: 12))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 6
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
            dot.layer?.borderWidth = 0.5
            if closeable { dot.onClick = { [weak self] in self?.close() } }
            header.addSubview(dot)
            dx += 20
        }
        // title (centered)
        let titleLabel = NSTextField(labelWithString: isX ? "Add Account" : "添加账号")
        titleLabel.font = Fonts.sans(13, .bold)
        titleLabel.textColor = theme.fgHeading
        titleLabel.isBezeled = false; titleLabel.drawsBackground = false
        titleLabel.frame = NSRect(x: 64, y: 0, width: CARD_W - 128, height: 38)
        titleLabel.alignment = .center
        header.addSubview(titleLabel)
    }

    private func clearContent() {
        contentArea.subviews.forEach { $0.removeFromSuperview() }
    }

    // MARK: - Step: Pick platform

    private func showPickStep() {
        step = .pick
        clearContent()
        var y: CGFloat = 15

        let infoTxt = isX ? "Sign in through the in-app browser to connect a new account." : "通过应用内浏览器登录以连接新账号。"
        let info = makeLabel(infoTxt, font: Fonts.sans(13), color: theme.fgSubdued)
        info.lineBreakMode = .byWordWrapping
        info.maximumNumberOfLines = 2
        info.preferredMaxLayoutWidth = CARD_W - 36
        info.frame = NSRect(x: 18, y: y, width: CARD_W - 36, height: 36)
        contentArea.addSubview(info)
        y += 44

        // X option
        let xBtn = buildPlatformChoice(platform: .x, title: "X",
                                       sub: isX ? "Sign in with your X username" : "使用 X 用户名登录")
        xBtn.frame.origin = CGPoint(x: 16, y: y)
        xBtn.onClick = { [weak self] in self?.pickPlatform(.x) }
        contentArea.addSubview(xBtn); y += xBtn.frame.height + 11

        // Weibo option
        let wBtn = buildPlatformChoice(platform: .weibo, title: isX ? "Weibo" : "微博",
                                       sub: isX ? "Scan a QR code or sign in" : "扫码或账号密码登录")
        wBtn.frame.origin = CGPoint(x: 16, y: y)
        wBtn.onClick = { [weak self] in self?.pickPlatform(.weibo) }
        contentArea.addSubview(wBtn); y += wBtn.frame.height + 18

        // Lock info row
        let lockIcon = GlyphView(name: "lock", size: 14, color: theme.fgSubdued)
        lockIcon.frame = NSRect(x: 18, y: y + 1, width: 14, height: 14)
        contentArea.addSubview(lockIcon)
        let lockLbl = makeLabel(isX ? "Perch signs in through the official site. Your password is never stored." : "Perch 通过官方网站登录，绝不存储你的密码。",
                                font: Fonts.sans(12), color: theme.fgSubdued)
        lockLbl.lineBreakMode = .byWordWrapping
        lockLbl.maximumNumberOfLines = 2
        lockLbl.preferredMaxLayoutWidth = CARD_W - 36 - 22
        lockLbl.frame = NSRect(x: 18 + 14 + 8, y: y, width: CARD_W - 36 - 22, height: 32)
        contentArea.addSubview(lockLbl)
        y += 50

        contentArea.frame.size.height = y
        card.frame.size.height = 38 + y
        needsLayout = true
    }

    private func buildPlatformChoice(platform: Platform, title: String, sub: String) -> HoverControl {
        let px = platform == .x
        let btn = HoverControl(frame: NSRect(x: 0, y: 0, width: CARD_W - 32, height: 70))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 13
        btn.layer?.borderColor = theme.borderDefault.cgColor
        btn.layer?.borderWidth = 1
        // platform badge circle
        let circle = FlippedView(frame: NSRect(x: 16, y: (70 - 46) / 2, width: 46, height: 46))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 23
        circle.layer?.backgroundColor = (px ? NSColor(hex: "#15141a") : NSColor(hex: "#e6162d")).cgColor
        let pLbl = NSTextField(labelWithString: px ? "𝕏" : "微")
        pLbl.font = NSFont.systemFont(ofSize: px ? 22 : 20, weight: .heavy)
        pLbl.textColor = .white
        pLbl.alignment = .center
        pLbl.isBezeled = false; pLbl.drawsBackground = false
        pLbl.frame = NSRect(x: 0, y: (46 - 26) / 2, width: 46, height: 26)
        circle.addSubview(pLbl)
        btn.addSubview(circle)
        // title
        let tLbl = makeLabel(title, font: Fonts.sans(16, .heavy), color: theme.fgHeading)
        tLbl.frame = NSRect(x: 16 + 46 + 14, y: (70 - 17 - 3 - 14) / 2, width: CARD_W - 32 - 16 - 46 - 14 - 30, height: 17)
        btn.addSubview(tLbl)
        let sLbl = makeLabel(sub, font: Fonts.sans(13), color: theme.fgSubdued)
        sLbl.frame = NSRect(x: 16 + 46 + 14, y: (70 - 17 - 3 - 14) / 2 + 17 + 3, width: CARD_W - 32 - 16 - 46 - 14 - 30, height: 14)
        btn.addSubview(sLbl)
        // chevron
        let chev = GlyphView(name: "chevron-down", size: 16, color: theme.fgDisabled)
        chev.rotationDegrees = -90
        chev.frame = NSRect(x: CARD_W - 32 - 18 - 8, y: (70 - 16) / 2, width: 16, height: 16)
        btn.addSubview(chev)
        btn.onState = { h, _ in
            btn.layer?.borderColor = (h ? self.theme.accent : self.theme.borderDefault).cgColor
            btn.layer?.backgroundColor = (h ? self.theme.gray75 : NSColor.clear).cgColor
            chev.color = h ? self.theme.accent : self.theme.fgDisabled
        }
        return btn
    }

    // MARK: - Step: Login

    private func pickPlatform(_ platform: Platform) {
        selectedPlatform = platform
        if platform == .x {
            // X login runs in its own resizable browser window — close the picker.
            appState.closeAddAccount()
            appState.beginXLogin()
        } else {
            showWeiboLoginStep()
        }
    }

    // MARK: - Step: Real X web login

    func debugStartXLogin() { selectedPlatform = .x; showXWebLoginStep() }

    private func showXWebLoginStep() {
        step = .login
        clearContent()
        var y: CGFloat = 0

        let toolbar = buildBrowserToolbar(url: "x.com/i/flow/login", secure: true,
                                          onBack: { [weak self] in
                                              self?.xWebView = nil
                                              self?.showPickStep()
                                          })
        toolbar.frame.origin = CGPoint(x: 0, y: y)
        contentArea.addSubview(toolbar); y += toolbar.frame.height

        let webHeight: CGFloat = 480
        let web = XLoginWebView(
            onURLChange: { [weak self] u in self?.updateAddressBar(u) },
            onCredentials: { [weak self] token, ct0 in self?.handleXCookies(token, ct0) })
        web.frame = NSRect(x: 0, y: y, width: CARD_W, height: webHeight)
        contentArea.addSubview(web)
        xWebView = web

        contentArea.frame.size.height = y + webHeight
        card.frame.size.height = 38 + y + webHeight
        needsLayout = true
    }

    private func updateAddressBar(_ url: String) {
        guard let lbl = browserAddrLabel else { return }
        var s = url
        for p in ["https://", "http://"] where s.hasPrefix(p) { s.removeFirst(p.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        lbl.stringValue = s
    }

    private func handleXCookies(_ token: String, _ ct0: String) {
        xWebView = nil
        showXConnectingStep()
        Task { [weak self] in
            guard let self else { return }
            do {
                let acct = try await TwitterService.shared.login(authToken: token, ct0: ct0)
                await MainActor.run {
                    self.showSuccessStep(account: acct)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.appState.addNewAccount(acct)
                    }
                }
            } catch {
                await MainActor.run {
                    let msg = (error as? TwitterAPIError)?.errorDescription ?? error.localizedDescription
                    self.appState.showToastNow("Login failed: \(msg)")
                    self.showXWebLoginStep()
                }
            }
        }
    }

    private func showXConnectingStep() {
        clearContent()
        let page = FlippedView(frame: NSRect(x: 0, y: 0, width: CARD_W, height: 300))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.black.cgColor
        contentArea.addSubview(page)

        let xLogo = NSTextField(labelWithString: "𝕏")
        xLogo.font = NSFont.systemFont(ofSize: 40, weight: .heavy)
        xLogo.textColor = .white; xLogo.alignment = .center
        xLogo.isBezeled = false; xLogo.drawsBackground = false
        xLogo.frame = NSRect(x: 0, y: 96, width: CARD_W, height: 48)
        page.addSubview(xLogo)

        let lbl = NSTextField(labelWithString: "Connecting your account…")
        lbl.font = Fonts.sans(15); lbl.textColor = NSColor(hex: "#71767b")
        lbl.alignment = .center; lbl.isBezeled = false; lbl.drawsBackground = false
        lbl.frame = NSRect(x: 0, y: 168, width: CARD_W, height: 20)
        page.addSubview(lbl)

        contentArea.frame.size.height = 300
        card.frame.size.height = 38 + 300
        needsLayout = true
    }

    private func showXLoginStep() {
        step = .login
        clearContent()
        var y: CGFloat = 0

        // In-app browser toolbar
        let toolbar = buildBrowserToolbar(
            url: "x.com/i/flow/login",
            secure: true,
            onBack: { [weak self] in self?.showPickStep() }
        )
        toolbar.frame.origin = CGPoint(x: 0, y: y)
        contentArea.addSubview(toolbar); y += toolbar.frame.height

        // X login page (dark background)
        let page = FlippedView(frame: NSRect(x: 0, y: y, width: CARD_W, height: 400))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.black.cgColor
        contentArea.addSubview(page)

        // X logo
        let xLogo = NSTextField(labelWithString: "𝕏")
        xLogo.font = NSFont.systemFont(ofSize: 38, weight: .heavy)
        xLogo.textColor = .white
        xLogo.alignment = .center
        xLogo.isBezeled = false; xLogo.drawsBackground = false
        xLogo.frame = NSRect(x: 0, y: 44, width: CARD_W, height: 44)
        page.addSubview(xLogo)

        let heading = NSTextField(labelWithString: "Sign in to X")
        heading.font = Fonts.sans(27, .heavy)
        heading.textColor = NSColor(hex: "#e7e9ea")
        heading.isBezeled = false; heading.drawsBackground = false
        heading.frame = NSRect(x: (CARD_W - 364) / 2, y: 102, width: 364, height: 34)
        page.addSubview(heading)

        // Username field
        let usernameField = buildXField(placeholder: "Phone, email, or username", y: 144, isPassword: false, in: page)
        _ = usernameField

        // Next button
        let nextBtn = buildXButton(label: "Next", enabled: true, y: 208, in: page)
        nextBtn.onClick = { [weak self] in
            guard let self else { return }
            self.xUsername = "alexnewuser"
            self.showXPasswordStep()
        }

        let signupLbl = NSTextField(labelWithString: "Don't have an account? Sign up")
        signupLbl.font = Fonts.sans(14.5)
        signupLbl.textColor = NSColor(hex: "#71767b")
        signupLbl.isBezeled = false; signupLbl.drawsBackground = false
        signupLbl.frame = NSRect(x: (CARD_W - 364) / 2, y: 278, width: 364, height: 18)
        page.addSubview(signupLbl)

        contentArea.frame.size.height = y + 400
        card.frame.size.height = 38 + y + 400
        needsLayout = true
    }

    private func showXPasswordStep() {
        clearContent()
        var y: CGFloat = 0
        let toolbar = buildBrowserToolbar(url: "x.com/i/flow/login", secure: true, onBack: { [weak self] in self?.showXLoginStep() })
        toolbar.frame.origin = CGPoint(x: 0, y: y)
        contentArea.addSubview(toolbar); y += toolbar.frame.height

        let page = FlippedView(frame: NSRect(x: 0, y: y, width: CARD_W, height: 400))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.black.cgColor
        contentArea.addSubview(page)

        let xLogo = NSTextField(labelWithString: "𝕏")
        xLogo.font = NSFont.systemFont(ofSize: 38, weight: .heavy)
        xLogo.textColor = .white
        xLogo.alignment = .center
        xLogo.isBezeled = false; xLogo.drawsBackground = false
        xLogo.frame = NSRect(x: 0, y: 44, width: CARD_W, height: 44)
        page.addSubview(xLogo)

        let heading = NSTextField(labelWithString: "Enter your password")
        heading.font = Fonts.sans(27, .heavy)
        heading.textColor = NSColor(hex: "#e7e9ea")
        heading.isBezeled = false; heading.drawsBackground = false
        heading.frame = NSRect(x: (CARD_W - 364) / 2, y: 102, width: 364, height: 34)
        page.addSubview(heading)

        // Show readonly username
        let userField = FlippedView(frame: NSRect(x: (CARD_W - 364) / 2, y: 144, width: 364, height: 54))
        userField.wantsLayer = true; userField.layer?.cornerRadius = 6
        userField.layer?.backgroundColor = NSColor(hex: "#16181c").cgColor
        userField.layer?.borderColor = NSColor(hex: "#333639").cgColor
        userField.layer?.borderWidth = 1
        let uLbl = makeLabel("@\(xUsername)", font: Fonts.sans(16), color: NSColor(hex: "#71767b"))
        uLbl.frame = NSRect(x: 12, y: (54 - uLbl.intrinsicContentSize.height) / 2, width: 340, height: uLbl.intrinsicContentSize.height)
        userField.addSubview(uLbl)
        page.addSubview(userField)

        _ = buildXField(placeholder: "Password", y: 208, isPassword: true, in: page)

        let loginBtn = buildXButton(label: "Log in", enabled: true, y: 274, in: page)
        loginBtn.onClick = { [weak self] in
            guard let self else { return }
            self.xPassword = "••••••••"
            self.showAuthorizeStep()
        }

        contentArea.frame.size.height = y + 400
        card.frame.size.height = 38 + y + 400
        needsLayout = true
    }

    private func showWeiboLoginStep() {
        step = .login
        clearContent()
        var y: CGFloat = 0
        let toolbar = buildBrowserToolbar(url: "passport.weibo.com/sso/signin", secure: true, onBack: { [weak self] in self?.showPickStep() })
        toolbar.frame.origin = CGPoint(x: 0, y: y)
        contentArea.addSubview(toolbar); y += toolbar.frame.height

        // Weibo top bar
        let weiboBar = FlippedView(frame: NSRect(x: 0, y: y, width: CARD_W, height: 56))
        weiboBar.wantsLayer = true
        weiboBar.layer?.backgroundColor = NSColor.white.cgColor
        let wBadge = FlippedView(frame: NSRect(x: 28, y: 15, width: 26, height: 26))
        wBadge.wantsLayer = true; wBadge.layer?.cornerRadius = 13
        wBadge.layer?.backgroundColor = NSColor(hex: "#e6162d").cgColor
        let wLbl = NSTextField(labelWithString: "微")
        wLbl.font = Fonts.sans(15, .heavy); wLbl.textColor = .white; wLbl.alignment = .center
        wLbl.isBezeled = false; wLbl.drawsBackground = false
        wLbl.frame = NSRect(x: 0, y: 4, width: 26, height: 18)
        wBadge.addSubview(wLbl)
        weiboBar.addSubview(wBadge)
        let wTitle = NSTextField(labelWithString: "微博")
        wTitle.font = Fonts.sans(18, .heavy); wTitle.textColor = NSColor(hex: "#222222")
        wTitle.isBezeled = false; wTitle.drawsBackground = false
        wTitle.frame = NSRect(x: 64, y: 16, width: 60, height: 22)
        weiboBar.addSubview(wTitle)
        let wSub = NSTextField(labelWithString: "Weibo")
        wSub.font = Fonts.sans(13); wSub.textColor = NSColor(hex: "#999999")
        wSub.isBezeled = false; wSub.drawsBackground = false
        wSub.frame = NSRect(x: 128, y: 18, width: 50, height: 18)
        weiboBar.addSubview(wSub)
        let wBorderLine = NSView(frame: NSRect(x: 0, y: 55, width: CARD_W, height: 1))
        wBorderLine.wantsLayer = true
        wBorderLine.layer?.backgroundColor = NSColor(hex: "#ececef").cgColor
        weiboBar.addSubview(wBorderLine)
        contentArea.addSubview(weiboBar); y += 56

        // Login card
        let loginCard = FlippedView(frame: NSRect(x: (CARD_W - 380) / 2, y: y + 24, width: 380, height: 360))
        loginCard.wantsLayer = true; loginCard.layer?.cornerRadius = 14
        loginCard.layer?.backgroundColor = NSColor.white.cgColor
        loginCard.layer?.borderColor = NSColor(hex: "#eeeeee").cgColor
        loginCard.layer?.borderWidth = 0.5
        loginCard.layer?.shadowColor = NSColor.black.cgColor
        loginCard.layer?.shadowOpacity = 0.08; loginCard.layer?.shadowRadius = 15
        loginCard.layer?.masksToBounds = false
        contentArea.addSubview(loginCard)

        // Tabs
        let tabLine = NSView(frame: NSRect(x: 0, y: 50, width: 380, height: 1))
        tabLine.wantsLayer = true; tabLine.layer?.backgroundColor = NSColor(hex: "#f0f0f2").cgColor
        loginCard.addSubview(tabLine)

        let qrTab = buildWeiboTab("扫码登录", active: true, x: 0, width: 190)
        qrTab.frame.origin = CGPoint(x: 0, y: 0)
        qrTab.onClick = { [weak self] in
            guard let self else { return }
            self.wTab = "qr"
            // rebuild
            self.showWeiboLoginStep()
        }
        loginCard.addSubview(qrTab)

        let acctTab = buildWeiboTab("账号登录", active: false, x: 190, width: 190)
        acctTab.frame.origin = CGPoint(x: 190, y: 0)
        acctTab.onClick = { [weak self] in
            guard let self else { return }
            self.wTab = "account"
            self.showWeiboAccountLoginStep()
        }
        loginCard.addSubview(acctTab)

        // QR code area
        let qrSize: CGFloat = 176
        let qrX = (380 - qrSize) / 2
        let qrView = buildFakeQR(size: qrSize)
        qrView.frame = NSRect(x: qrX, y: 70, width: qrSize, height: qrSize)
        loginCard.addSubview(qrView)

        let qrHint1 = NSTextField(labelWithString: "打开微博 App 扫一扫登录")
        qrHint1.font = Fonts.sans(14.5, .semibold); qrHint1.textColor = NSColor(hex: "#333333")
        qrHint1.alignment = .center; qrHint1.isBezeled = false; qrHint1.drawsBackground = false
        qrHint1.frame = NSRect(x: 20, y: 256, width: 340, height: 18)
        loginCard.addSubview(qrHint1)

        // Simulate phone action box
        let simBox = FlippedView(frame: NSRect(x: 14, y: 282, width: 352, height: 56))
        simBox.wantsLayer = true; simBox.layer?.cornerRadius = 12
        simBox.layer?.backgroundColor = NSColor(hex: "#fafafb").cgColor
        simBox.layer?.borderColor = NSColor(hex: "#e0e0e4").cgColor
        simBox.layer?.borderWidth = 1
        let phoneIcon = FlippedView(frame: NSRect(x: 10, y: 11, width: 34, height: 34))
        phoneIcon.wantsLayer = true; phoneIcon.layer?.cornerRadius = 9
        phoneIcon.layer?.backgroundColor = NSColor.white.cgColor
        phoneIcon.layer?.borderColor = NSColor(hex: "#ececef").cgColor
        phoneIcon.layer?.borderWidth = 1
        let phoneG = GlyphView(name: "user", size: 16, color: NSColor(hex: "#bbbbbb"))
        phoneG.frame = NSRect(x: 9, y: 9, width: 16, height: 16)
        phoneIcon.addSubview(phoneG)
        simBox.addSubview(phoneIcon)
        let simLbl = NSTextField(labelWithString: "模拟手机端操作")
        simLbl.font = Fonts.sans(12); simLbl.textColor = NSColor(hex: "#999999")
        simLbl.isBezeled = false; simLbl.drawsBackground = false
        simLbl.frame = NSRect(x: 54, y: 20, width: 200, height: 16)
        simBox.addSubview(simLbl)

        let scanBtn = HoverControl(frame: NSRect(x: 284, y: 11, width: 58, height: 34))
        scanBtn.wantsLayer = true; scanBtn.layer?.cornerRadius = 17
        scanBtn.layer?.borderColor = NSColor(hex: "#e6162d").cgColor
        scanBtn.layer?.borderWidth = 1
        let scanLbl = makeLabel("扫一扫", font: Fonts.sans(13, .bold), color: NSColor(hex: "#e6162d"), align: .center)
        scanLbl.frame = NSRect(x: 0, y: (34 - scanLbl.intrinsicContentSize.height) / 2, width: 58, height: scanLbl.intrinsicContentSize.height)
        scanBtn.addSubview(scanLbl)
        scanBtn.onState = { h, _ in scanBtn.layer?.backgroundColor = (h ? NSColor(hex: "#e6162d").withAlphaComponent(0.08) : NSColor.clear).cgColor }
        scanBtn.onClick = { [weak self] in
            guard let self else { return }
            self.qrScanned = true
            self.showAuthorizeStep()
        }
        simBox.addSubview(scanBtn)
        loginCard.addSubview(simBox)

        contentArea.frame.size.height = y + 24 + 360 + 24
        card.frame.size.height = 38 + contentArea.frame.size.height
        needsLayout = true
    }

    private func showWeiboAccountLoginStep() {
        clearContent()
        var y: CGFloat = 0
        let toolbar = buildBrowserToolbar(url: "passport.weibo.com/sso/signin", secure: true, onBack: { [weak self] in self?.showWeiboLoginStep() })
        toolbar.frame.origin = CGPoint(x: 0, y: y)
        contentArea.addSubview(toolbar); y += toolbar.frame.height

        let page = FlippedView(frame: NSRect(x: 0, y: y, width: CARD_W, height: 370))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor(hex: "#f7f7f9").cgColor
        contentArea.addSubview(page)

        let loginCard2 = FlippedView(frame: NSRect(x: (CARD_W - 380) / 2, y: 20, width: 380, height: 310))
        loginCard2.wantsLayer = true; loginCard2.layer?.cornerRadius = 14
        loginCard2.layer?.backgroundColor = NSColor.white.cgColor
        loginCard2.layer?.borderColor = NSColor(hex: "#eeeeee").cgColor
        loginCard2.layer?.borderWidth = 0.5
        page.addSubview(loginCard2)

        let userLbl = NSTextField(labelWithString: "账号")
        userLbl.font = Fonts.sans(13, .semibold); userLbl.textColor = NSColor(hex: "#888888")
        userLbl.isBezeled = false; userLbl.drawsBackground = false
        userLbl.frame = NSRect(x: 28, y: 26, width: 100, height: 16)
        loginCard2.addSubview(userLbl)

        let userField2 = buildWeiboField(placeholder: "手机号 / 邮箱 / 用户名", y: 46, in: loginCard2, width: 324)
        _ = userField2

        let passLbl = NSTextField(labelWithString: "密码")
        passLbl.font = Fonts.sans(13, .semibold); passLbl.textColor = NSColor(hex: "#888888")
        passLbl.isBezeled = false; passLbl.drawsBackground = false
        passLbl.frame = NSRect(x: 28, y: 112, width: 100, height: 16)
        loginCard2.addSubview(passLbl)

        let passField2 = buildWeiboField(placeholder: "请输入密码", y: 132, in: loginCard2, width: 324)
        _ = passField2

        let loginBtn2 = HoverControl(frame: NSRect(x: 28, y: 198, width: 324, height: 48))
        loginBtn2.wantsLayer = true; loginBtn2.layer?.cornerRadius = 24
        loginBtn2.layer?.backgroundColor = NSColor(hex: "#e6162d").cgColor
        let loginLbl2 = makeLabel("登录", font: Fonts.sans(16, .heavy), color: .white, align: .center)
        loginLbl2.frame = NSRect(x: 0, y: (48 - loginLbl2.intrinsicContentSize.height) / 2, width: 324, height: loginLbl2.intrinsicContentSize.height)
        loginBtn2.addSubview(loginLbl2)
        loginBtn2.onClick = { [weak self] in self?.showAuthorizeStep() }
        loginCard2.addSubview(loginBtn2)

        contentArea.frame.size.height = y + 370
        card.frame.size.height = 38 + contentArea.frame.size.height
        needsLayout = true
    }

    // MARK: - Step: Authorize

    private func showAuthorizeStep() {
        step = .authorize
        clearContent()
        var y: CGFloat = 0
        let url = selectedPlatform == .x ? "x.com/i/oauth2/authorize?client=perch" : "api.weibo.com/oauth2/authorize"
        let toolbar = buildBrowserToolbar(url: url, secure: true, onBack: { [weak self] in
            guard let self else { return }
            if self.selectedPlatform == .x { self.showXLoginStep() } else { self.showWeiboLoginStep() }
        })
        toolbar.frame.origin = CGPoint(x: 0, y: y)
        contentArea.addSubview(toolbar); y += toolbar.frame.height

        if selectedPlatform == .x {
            buildXAuthorize(y: y)
        } else {
            buildWeiboAuthorize(y: y)
        }
    }

    private func buildXAuthorize(y: CGFloat) {
        let page = FlippedView(frame: NSRect(x: 0, y: y, width: CARD_W, height: 480))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor.white.cgColor
        contentArea.addSubview(page)

        // App icon + description
        let appIcon = buildPerchIcon(size: 52)
        appIcon.frame = NSRect(x: 28, y: 20, width: 52, height: 52)
        page.addSubview(appIcon)
        let appDesc = NSTextField(labelWithString: "Perch\nwants to access your X account")
        appDesc.font = Fonts.sans(17); appDesc.textColor = NSColor(hex: "#0f1419")
        appDesc.isEditable = false; appDesc.isBezeled = false; appDesc.drawsBackground = false
        appDesc.frame = NSRect(x: 94, y: 20, width: 320, height: 52)
        appDesc.lineBreakMode = .byWordWrapping
        page.addSubview(appDesc)

        let divider = NSView(frame: NSRect(x: 0, y: 80, width: CARD_W, height: 1))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(hex: "#eff3f4").cgColor
        page.addSubview(divider)

        // Signed-in identity box
        let idBox = FlippedView(frame: NSRect(x: 28, y: 102, width: CARD_W - 56, height: 62))
        idBox.wantsLayer = true; idBox.layer?.cornerRadius = 12
        idBox.layer?.backgroundColor = NSColor(hex: "#f7f9f9").cgColor
        page.addSubview(idBox)
        let fakeUser = Person(name: xUsername.isEmpty ? "Alex New User" : xUsername, handle: xUsername.isEmpty ? "alexnewuser" : xUsername, colorToken: "indigo-700", verified: false, platform: .x)
        let av = AvatarView(person: fakeUser, size: 40)
        av.frame = NSRect(x: 13, y: 11, width: 40, height: 40)
        idBox.addSubview(av)
        let idName = makeLabel(fakeUser.name, font: Fonts.sans(15, .heavy), color: NSColor(hex: "#0f1419"))
        idName.frame = NSRect(x: 63, y: 13, width: CARD_W - 56 - 63 - 100, height: 18)
        idBox.addSubview(idName)
        let idHandle = makeLabel("@\(fakeUser.handle)", font: Fonts.sans(13.5), color: NSColor(hex: "#536471"))
        idHandle.frame = NSRect(x: 63, y: 33, width: CARD_W - 56 - 63 - 100, height: 16)
        idBox.addSubview(idHandle)
        let signedIn = makeLabel("✓ Signed in", font: Fonts.sans(12.5, .bold), color: NSColor(hex: "#00ba7c"))
        signedIn.frame = NSRect(x: CARD_W - 56 - 100 - 5, y: 24, width: 90, height: 14)
        idBox.addSubview(signedIn)

        // Permissions
        let permTitle = makeLabel("Perch will be able to", font: Fonts.sans(15, .heavy), color: NSColor(hex: "#0f1419"))
        permTitle.frame = NSRect(x: 28, y: 176, width: 400, height: 18)
        page.addSubview(permTitle)
        let perms = ["See posts from your timeline and the accounts you follow",
                     "See your profile information and account settings",
                     "Post, repost, and like on your behalf",
                     "Follow and unfollow accounts for you"]
        var py: CGFloat = 202
        for perm in perms {
            let check = FlippedView(frame: NSRect(x: 28, y: py, width: 20, height: 20))
            check.wantsLayer = true; check.layer?.cornerRadius = 10
            check.layer?.backgroundColor = NSColor(hex: "#1d9bf0").cgColor
            let ck = GlyphView(name: "checkmark", size: 11, color: .white)
            ck.frame = NSRect(x: 4.5, y: 4.5, width: 11, height: 11)
            check.addSubview(ck)
            page.addSubview(check)
            let pLbl = makeLabel(perm, font: Fonts.sans(14), color: NSColor(hex: "#1a1a1a"))
            pLbl.lineBreakMode = .byWordWrapping; pLbl.maximumNumberOfLines = 2
            pLbl.preferredMaxLayoutWidth = CARD_W - 28 - 20 - 10 - 28
            let ph = max(18, pLbl.intrinsicContentSize.height)
            pLbl.frame = NSRect(x: 58, y: py, width: CARD_W - 28 - 20 - 10 - 28, height: ph)
            page.addSubview(pLbl)
            py += ph + 8
        }

        // Authorize button
        let authBtn = HoverControl(frame: NSRect(x: 28, y: py + 14, width: CARD_W - 56, height: 50))
        authBtn.wantsLayer = true; authBtn.layer?.cornerRadius = 25
        authBtn.layer?.backgroundColor = NSColor(hex: "#0f1419").cgColor
        let authLbl = makeLabel("Authorize app", font: Fonts.sans(16, .heavy), color: .white, align: .center)
        authLbl.frame = NSRect(x: 0, y: (50 - authLbl.intrinsicContentSize.height) / 2, width: CARD_W - 56, height: authLbl.intrinsicContentSize.height)
        authBtn.addSubview(authLbl)
        authBtn.onClick = { [weak self] in self?.doAuthorize() }
        page.addSubview(authBtn)

        let cancelBtn = HoverControl(frame: NSRect(x: 28, y: py + 74, width: CARD_W - 56, height: 50))
        cancelBtn.wantsLayer = true; cancelBtn.layer?.cornerRadius = 25
        cancelBtn.layer?.borderColor = NSColor(hex: "#cfd9de").cgColor; cancelBtn.layer?.borderWidth = 1
        let cancelLbl = makeLabel("Cancel", font: Fonts.sans(16, .semibold), color: NSColor(hex: "#0f1419"), align: .center)
        cancelLbl.frame = NSRect(x: 0, y: (50 - cancelLbl.intrinsicContentSize.height) / 2, width: CARD_W - 56, height: cancelLbl.intrinsicContentSize.height)
        cancelBtn.addSubview(cancelLbl)
        cancelBtn.onClick = { [weak self] in self?.close() }
        page.addSubview(cancelBtn)

        let note = makeLabel("Perch won't see your password. You can revoke access anytime in your X settings.", font: Fonts.sans(12.5), color: NSColor(hex: "#536471"), align: .center)
        note.frame = NSRect(x: 28, y: py + 136, width: CARD_W - 56, height: 32)
        note.lineBreakMode = .byWordWrapping; note.maximumNumberOfLines = 2
        page.addSubview(note)

        page.frame.size.height = py + 180
        contentArea.frame.size.height = y + page.frame.size.height
        card.frame.size.height = 38 + contentArea.frame.size.height
        needsLayout = true
    }

    private func buildWeiboAuthorize(y: CGFloat) {
        let RED = "#e6162d"
        let page = FlippedView(frame: NSRect(x: 0, y: y, width: CARD_W, height: 480))
        page.wantsLayer = true
        page.layer?.backgroundColor = NSColor(hex: "#f7f7f9").cgColor
        contentArea.addSubview(page)

        let authCard = FlippedView(frame: NSRect(x: (CARD_W - 400) / 2, y: 24, width: 400, height: 440))
        authCard.wantsLayer = true; authCard.layer?.cornerRadius = 14
        authCard.layer?.backgroundColor = NSColor.white.cgColor; authCard.layer?.masksToBounds = true
        page.addSubview(authCard)

        let hdr = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 52))
        hdr.wantsLayer = true; hdr.layer?.backgroundColor = NSColor(hex: RED).cgColor
        let hBadge = FlippedView(frame: NSRect(x: 22, y: 14, width: 24, height: 24))
        hBadge.wantsLayer = true; hBadge.layer?.cornerRadius = 12
        hBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        let hBL = NSTextField(labelWithString: "微")
        hBL.font = Fonts.sans(14, .heavy); hBL.textColor = .white; hBL.alignment = .center
        hBL.isBezeled = false; hBL.drawsBackground = false; hBL.frame = NSRect(x: 0, y: 4, width: 24, height: 16)
        hBadge.addSubview(hBL)
        hdr.addSubview(hBadge)
        let hTitle = NSTextField(labelWithString: "微博授权")
        hTitle.font = Fonts.sans(15.5, .heavy); hTitle.textColor = .white
        hTitle.isBezeled = false; hTitle.drawsBackground = false; hTitle.frame = NSRect(x: 56, y: 15, width: 120, height: 20)
        hdr.addSubview(hTitle)
        let hAPI = NSTextField(labelWithString: "api.weibo.com")
        hAPI.font = Fonts.sans(12.5); hAPI.textColor = NSColor.white.withAlphaComponent(0.85)
        hAPI.isBezeled = false; hAPI.drawsBackground = false; hAPI.frame = NSRect(x: 260, y: 18, width: 120, height: 16)
        hdr.addSubview(hAPI)
        authCard.addSubview(hdr)

        var cy: CGFloat = 76
        let fakeWUser = Person(name: "云岫", handle: "yunxiu_film", colorToken: "magenta-700", verified: true, platform: .weibo)
        let wAv = AvatarView(person: fakeWUser, size: 50)
        wAv.frame = NSRect(x: (400 - 120) / 2, y: cy, width: 50, height: 50)
        authCard.addSubview(wAv)
        let wBadge2 = FlippedView(frame: NSRect(x: (400 - 120) / 2 + 36, y: cy + 36, width: 18, height: 18))
        wBadge2.wantsLayer = true; wBadge2.layer?.cornerRadius = 9
        wBadge2.layer?.backgroundColor = NSColor(hex: RED).cgColor
        let wBL2 = NSTextField(labelWithString: "微"); wBL2.font = Fonts.sans(10, .heavy); wBL2.textColor = .white
        wBL2.alignment = .center; wBL2.isBezeled = false; wBL2.drawsBackground = false; wBL2.frame = NSRect(x: 0, y: 3, width: 18, height: 12)
        wBadge2.addSubview(wBL2)
        authCard.addSubview(wBadge2)
        cy += 62

        let wAuthTitle = NSTextField(labelWithString: "Perch 请求访问你的微博账号")
        wAuthTitle.font = Fonts.sans(16); wAuthTitle.textColor = NSColor(hex: "#222222")
        wAuthTitle.isBezeled = false; wAuthTitle.drawsBackground = false; wAuthTitle.alignment = .center
        wAuthTitle.frame = NSRect(x: 20, y: cy, width: 360, height: 20)
        authCard.addSubview(wAuthTitle); cy += 24

        let wSub2 = NSTextField(labelWithString: "云岫 · @yunxiu_film")
        wSub2.font = Fonts.sans(13.5); wSub2.textColor = NSColor(hex: "#999999"); wSub2.alignment = .center
        wSub2.isBezeled = false; wSub2.drawsBackground = false; wSub2.frame = NSRect(x: 20, y: cy, width: 360, height: 18)
        authCard.addSubview(wSub2); cy += 30

        let permBox = FlippedView(frame: NSRect(x: 20, y: cy, width: 360, height: 140))
        permBox.wantsLayer = true; permBox.layer?.cornerRadius = 10
        permBox.layer?.backgroundColor = NSColor(hex: "#fafafb").cgColor
        authCard.addSubview(permBox)
        let wPerms = ["查看你的微博与时间线", "获取你的公开资料信息", "代你发布、转发与点赞", "代你关注或取消关注用户"]
        var wpy: CGFloat = 8
        for perm in wPerms {
            let check2 = FlippedView(frame: NSRect(x: 16, y: wpy, width: 20, height: 20))
            check2.wantsLayer = true; check2.layer?.cornerRadius = 10
            check2.layer?.backgroundColor = NSColor(hex: RED).cgColor
            let ck2 = GlyphView(name: "checkmark", size: 11, color: .white)
            ck2.frame = NSRect(x: 4.5, y: 4.5, width: 11, height: 11)
            check2.addSubview(ck2); permBox.addSubview(check2)
            let pLbl2 = makeLabel(perm, font: Fonts.sans(14), color: NSColor(hex: "#1a1a1a"))
            pLbl2.frame = NSRect(x: 46, y: wpy + 2, width: 300, height: 16); permBox.addSubview(pLbl2)
            wpy += 28
        }
        cy += 150

        let authBtn2 = HoverControl(frame: NSRect(x: 20, y: cy, width: 360, height: 48))
        authBtn2.wantsLayer = true; authBtn2.layer?.cornerRadius = 24
        authBtn2.layer?.backgroundColor = NSColor(hex: RED).cgColor
        let a2Lbl = makeLabel("授权", font: Fonts.sans(16, .heavy), color: .white, align: .center)
        a2Lbl.frame = NSRect(x: 0, y: (48 - a2Lbl.intrinsicContentSize.height) / 2, width: 360, height: a2Lbl.intrinsicContentSize.height)
        authBtn2.addSubview(a2Lbl); authBtn2.onClick = { [weak self] in self?.doAuthorize() }
        authCard.addSubview(authBtn2); cy += 58

        let cancelBtn2 = HoverControl(frame: NSRect(x: 20, y: cy, width: 360, height: 48))
        cancelBtn2.wantsLayer = true; cancelBtn2.layer?.cornerRadius = 24
        cancelBtn2.layer?.borderColor = NSColor(hex: "#e3e3e6").cgColor; cancelBtn2.layer?.borderWidth = 1
        let c2Lbl = makeLabel("取消", font: Fonts.sans(16, .semibold), color: NSColor(hex: "#555555"), align: .center)
        c2Lbl.frame = NSRect(x: 0, y: (48 - c2Lbl.intrinsicContentSize.height) / 2, width: 360, height: c2Lbl.intrinsicContentSize.height)
        cancelBtn2.addSubview(c2Lbl); cancelBtn2.onClick = { [weak self] in self?.close() }
        authCard.addSubview(cancelBtn2)

        authCard.frame.size.height = cy + 68
        page.frame.size.height = authCard.frame.size.height + 48
        contentArea.frame.size.height = y + page.frame.size.height
        card.frame.size.height = 38 + contentArea.frame.size.height
        needsLayout = true
    }

    private func doAuthorize() {
        let id = selectedPlatform == .x
            ? "axn\(Int(Date().timeIntervalSince1970 * 100) % 10000)"
            : "awn\(Int(Date().timeIntervalSince1970 * 100) % 10000)"
        let tokens = ["cyan-800", "purple-700", "seafoam-700", "magenta-700", "orange-700"]
        let colorToken = tokens[Int(Date().timeIntervalSince1970 * 7) % tokens.count]
        let acct: Account
        if selectedPlatform == .x {
            let name = xUsername.isEmpty ? "New User" : xUsername.prefix(1).uppercased() + xUsername.dropFirst()
            acct = Account(id: id, name: String(name), handle: xUsername.isEmpty ? "newuser" : xUsername,
                           colorToken: colorToken, verified: false, platform: .x,
                           followers: "128", following: "312", unreadSeed: 0)
        } else {
            acct = Account(id: id, name: "云岫", handle: "yunxiu_film",
                           colorToken: colorToken, verified: true, platform: .weibo,
                           followers: "2.3万", following: "186", unreadSeed: 0)
        }
        showSuccessStep(account: acct)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.appState.addNewAccount(acct)
        }
    }

    private func showSuccessStep(account: Account) {
        step = .success
        clearContent()
        let px = account.platform == .x

        let page = FlippedView(frame: NSRect(x: 0, y: 0, width: CARD_W, height: 360))
        page.wantsLayer = true
        page.layer?.backgroundColor = px ? NSColor.black.cgColor : NSColor(hex: "#f7f7f9").cgColor
        contentArea.addSubview(page)

        let circleSize: CGFloat = 66
        let circle = FlippedView(frame: NSRect(x: (CARD_W - circleSize) / 2, y: 60, width: circleSize, height: circleSize))
        circle.wantsLayer = true; circle.layer?.cornerRadius = circleSize / 2
        circle.layer?.backgroundColor = (px ? NSColor(hex: "#16181c") : NSColor(hex: "#e8faf0")).cgColor
        let ck = GlyphView(name: "checkmark-circle", size: 38, color: theme.positive)
        ck.frame = NSRect(x: 14, y: 14, width: 38, height: 38)
        circle.addSubview(ck); page.addSubview(circle)

        let connTitle = NSTextField(labelWithString: isX ? "Connected" : "连接成功")
        connTitle.font = Fonts.sans(19, .heavy)
        connTitle.textColor = px ? NSColor(hex: "#e7e9ea") : NSColor(hex: "#222222")
        connTitle.alignment = .center; connTitle.isBezeled = false; connTitle.drawsBackground = false
        connTitle.frame = NSRect(x: 0, y: 140, width: CARD_W, height: 24); page.addSubview(connTitle)

        let nameTag = FlippedView(frame: NSRect(x: (CARD_W - 160) / 2, y: 178, width: 160, height: 36))
        nameTag.wantsLayer = true; nameTag.layer?.cornerRadius = 18
        nameTag.layer?.backgroundColor = (px ? NSColor(hex: "#16181c") : NSColor.white).cgColor
        let tAv = AvatarView(person: account, size: 24)
        tAv.frame = NSRect(x: 6, y: 6, width: 24, height: 24); nameTag.addSubview(tAv)
        let handleStr = px ? "@\(account.handle)" : account.name
        let tLbl = makeLabel(handleStr, font: Fonts.sans(14, .bold), color: px ? NSColor(hex: "#e7e9ea") : NSColor(hex: "#222222"))
        tLbl.frame = NSRect(x: 36, y: (36 - tLbl.intrinsicContentSize.height) / 2, width: 120, height: tLbl.intrinsicContentSize.height)
        nameTag.addSubview(tLbl)
        nameTag.frame.size.width = 36 + tLbl.intrinsicContentSize.width + 14
        nameTag.frame.origin.x = (CARD_W - nameTag.frame.width) / 2
        page.addSubview(nameTag)

        let returning = NSTextField(labelWithString: isX ? "Returning to Perch…" : "正在返回 Perch…")
        returning.font = Fonts.sans(13)
        returning.textColor = px ? NSColor(hex: "#71767b") : NSColor(hex: "#999999")
        returning.alignment = .center; returning.isBezeled = false; returning.drawsBackground = false
        returning.frame = NSRect(x: 0, y: 228, width: CARD_W, height: 18); page.addSubview(returning)

        contentArea.frame.size.height = 360
        card.frame.size.height = 38 + 360
        needsLayout = true
    }

    // MARK: - Helper builders

    private func buildBrowserToolbar(url: String, secure: Bool, onBack: @escaping () -> Void) -> FlippedView {
        let toolbar = FlippedView(frame: NSRect(x: 0, y: 0, width: CARD_W, height: 46))
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = theme.bgBase.cgColor
        // bottom border
        let tLine = NSView(frame: NSRect(x: 0, y: 45, width: CARD_W, height: 1))
        tLine.wantsLayer = true; tLine.layer?.backgroundColor = theme.borderDefault.cgColor
        toolbar.addSubview(tLine)
        // back button
        let backBtn = HoverControl(frame: NSRect(x: 10, y: 9, width: 28, height: 28))
        backBtn.wantsLayer = true; backBtn.layer?.cornerRadius = 7
        let chev = GlyphView(name: "chevron-down", size: 17, color: theme.fgSubdued)
        chev.rotationDegrees = 90
        chev.frame = NSRect(x: 5.5, y: 5.5, width: 17, height: 17)
        backBtn.addSubview(chev)
        backBtn.onState = { h, _ in backBtn.layer?.backgroundColor = (h ? self.theme.gray200 : NSColor.clear).cgColor }
        backBtn.onClick = onBack
        toolbar.addSubview(backBtn)
        // reload button
        let reloadBtn = HoverControl(frame: NSRect(x: 44, y: 9, width: 28, height: 28))
        reloadBtn.wantsLayer = true; reloadBtn.layer?.cornerRadius = 7
        let rlG = GlyphView(name: "refresh", size: 17, color: theme.fgSubdued)
        rlG.frame = NSRect(x: 5.5, y: 5.5, width: 17, height: 17)
        reloadBtn.addSubview(rlG)
        reloadBtn.onState = { h, _ in reloadBtn.layer?.backgroundColor = (h ? self.theme.gray200 : NSColor.clear).cgColor }
        toolbar.addSubview(reloadBtn)
        // address bar
        let addrBar = FlippedView(frame: NSRect(x: 78, y: 7, width: CARD_W - 78 - 90, height: 32))
        addrBar.wantsLayer = true; addrBar.layer?.cornerRadius = 16
        addrBar.layer?.backgroundColor = theme.bgLayer1.cgColor
        addrBar.layer?.borderColor = theme.borderDefault.cgColor; addrBar.layer?.borderWidth = 1
        let lockG = GlyphView(name: secure ? "lock" : "globe", size: 13, color: secure ? theme.positive : theme.fgSubdued)
        lockG.frame = NSRect(x: 12, y: (32 - 13) / 2, width: 13, height: 13)
        addrBar.addSubview(lockG)
        let addrLbl = makeLabel(url, font: Fonts.sans(13), color: theme.fgBody)
        addrLbl.frame = NSRect(x: 31, y: (32 - addrLbl.intrinsicContentSize.height) / 2, width: CARD_W - 78 - 90 - 43, height: addrLbl.intrinsicContentSize.height)
        addrLbl.lineBreakMode = .byTruncatingTail
        addrBar.addSubview(addrLbl)
        browserAddrLabel = addrLbl
        toolbar.addSubview(addrBar)
        // "In-app" pill
        let pill = FlippedView(frame: NSRect(x: CARD_W - 82, y: 11, width: 72, height: 24))
        pill.wantsLayer = true; pill.layer?.cornerRadius = 12
        pill.layer?.backgroundColor = theme.gray100.cgColor
        let pillLockG = GlyphView(name: "lock", size: 12, color: theme.fgSubdued)
        pillLockG.frame = NSRect(x: 9, y: 6, width: 12, height: 12)
        pill.addSubview(pillLockG)
        let pillLbl = makeLabel(isX ? "In‑app" : "内置", font: Fonts.sans(11, .bold), color: theme.fgSubdued)
        pillLbl.frame = NSRect(x: 25, y: (24 - pillLbl.intrinsicContentSize.height) / 2, width: pillLbl.intrinsicContentSize.width, height: pillLbl.intrinsicContentSize.height)
        pill.addSubview(pillLbl)
        toolbar.addSubview(pill)
        return toolbar
    }

    private func buildPerchIcon(size: CGFloat) -> FlippedView {
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true; v.layer?.cornerRadius = size * 0.26; v.layer?.masksToBounds = true
        let g = CAGradientLayer()
        g.frame = NSRect(x: 0, y: 0, width: size, height: size)
        let accent = AccentOption.find(ThemeManager.shared.accentId)
        g.colors = [accent.dotColor.cgColor, NSColor(hex: "#17002d").cgColor]
        g.startPoint = CGPoint(x: 0.1, y: 0); g.endPoint = CGPoint(x: 0.9, y: 1)
        v.layer?.addSublayer(g)
        let pLbl = NSTextField(labelWithString: "P")
        pLbl.font = NSFont(name: "Georgia", size: size * 0.56) ?? Fonts.sans(size * 0.56, .heavy)
        pLbl.textColor = .white; pLbl.alignment = .center
        pLbl.isBezeled = false; pLbl.drawsBackground = false
        pLbl.frame = NSRect(x: 0, y: size * 0.04, width: size, height: size)
        v.addSubview(pLbl)
        return v
    }

    private func buildFakeQR(size: CGFloat) -> FlippedView {
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true; v.layer?.cornerRadius = 10
        v.layer?.backgroundColor = NSColor.white.cgColor
        v.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor; v.layer?.borderWidth = 1
        // Draw simple QR-like pattern using NSView cells
        let pad: CGFloat = 10
        let n: Int = 21
        let cellSize = (size - pad * 2) / CGFloat(n)
        // deterministic "random" fill
        var seed: UInt64 = 20260601
        func rnd() -> Bool {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (seed >> 33) & 1 == 1
        }
        func isFinderSquare(_ r: Int, _ c: Int) -> Bool? {
            func inBox(_ br: Int, _ bc: Int) -> Bool? {
                if r < br || r >= br + 7 || c < bc || c >= bc + 7 { return nil }
                let lr = r - br, lc = c - bc
                return (lr == 0 || lr == 6 || lc == 0 || lc == 6) || (lr >= 2 && lr <= 4 && lc >= 2 && lc <= 4)
            }
            if let v = inBox(0, 0) { return v }
            if let v = inBox(0, n - 7) { return v }
            if let v = inBox(n - 7, 0) { return v }
            return nil
        }
        for row in 0..<n {
            for col in 0..<n {
                let on: Bool
                if let f = isFinderSquare(row, col) { on = f } else { on = rnd() }
                if on {
                    let cell = NSView(frame: NSRect(x: pad + CGFloat(col) * cellSize, y: pad + CGFloat(row) * cellSize, width: cellSize - 0.5, height: cellSize - 0.5))
                    cell.wantsLayer = true; cell.layer?.backgroundColor = NSColor(hex: "#15141a").cgColor
                    v.addSubview(cell)
                }
            }
        }
        // Weibo logo overlay
        let logoSize = size * 0.22
        let logo = FlippedView(frame: NSRect(x: (size - logoSize) / 2, y: (size - logoSize) / 2, width: logoSize, height: logoSize))
        logo.wantsLayer = true; logo.layer?.cornerRadius = logoSize * 0.18
        logo.layer?.backgroundColor = NSColor(hex: "#e6162d").cgColor
        let wL = NSTextField(labelWithString: "微")
        wL.font = Fonts.sans(logoSize * 0.54, .heavy); wL.textColor = .white; wL.alignment = .center
        wL.isBezeled = false; wL.drawsBackground = false
        wL.frame = NSRect(x: 0, y: logoSize * 0.14, width: logoSize, height: logoSize * 0.7)
        logo.addSubview(wL)
        v.addSubview(logo)
        return v
    }

    private func buildWeiboTab(_ title: String, active: Bool, x: CGFloat, width: CGFloat) -> HoverControl {
        let RED = "#e6162d"
        let btn = HoverControl(frame: NSRect(x: x, y: 0, width: width, height: 50))
        let lbl = NSTextField(labelWithString: title)
        lbl.font = Fonts.sans(15, active ? .heavy : .semibold)
        lbl.textColor = active ? NSColor(hex: RED) : NSColor(hex: "#888888")
        lbl.alignment = .center; lbl.isBezeled = false; lbl.drawsBackground = false
        lbl.frame = NSRect(x: 0, y: 0, width: width, height: 50)
        btn.addSubview(lbl)
        if active {
            let underline = NSView(frame: NSRect(x: (width - 28) / 2, y: 47, width: 28, height: 3))
            underline.wantsLayer = true; underline.layer?.cornerRadius = 1.5
            underline.layer?.backgroundColor = NSColor(hex: RED).cgColor
            btn.addSubview(underline)
        }
        return btn
    }

    private func buildXField(placeholder: String, y: CGFloat, isPassword: Bool, in view: FlippedView) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: (CARD_W - 364) / 2, y: y, width: 364, height: 54))
        field.font = Fonts.sans(16); field.textColor = NSColor(hex: "#e7e9ea")
        field.placeholderString = placeholder
        field.isBezeled = false; field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.backgroundColor = NSColor.black.cgColor
        field.layer?.borderColor = NSColor(hex: "#333639").cgColor; field.layer?.borderWidth = 1
        field.drawsBackground = false
        view.addSubview(field)
        return field
    }

    private func buildXButton(label: String, enabled: Bool, y: CGFloat, in view: FlippedView) -> HoverControl {
        let btn = HoverControl(frame: NSRect(x: (CARD_W - 364) / 2, y: y, width: 364, height: 52))
        btn.wantsLayer = true; btn.layer?.cornerRadius = 26
        btn.layer?.backgroundColor = (enabled ? NSColor(hex: "#eff3f4") : NSColor(hex: "#3a3a3c")).cgColor
        let lbl = makeLabel(label, font: Fonts.sans(16, .bold), color: enabled ? NSColor(hex: "#0f1419") : NSColor(hex: "#71767b"), align: .center)
        lbl.frame = NSRect(x: 0, y: (52 - lbl.intrinsicContentSize.height) / 2, width: 364, height: lbl.intrinsicContentSize.height)
        btn.addSubview(lbl)
        view.addSubview(btn)
        return btn
    }

    private func buildWeiboField(placeholder: String, y: CGFloat, in view: FlippedView, width: CGFloat) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 28, y: y, width: width, height: 46))
        field.font = Fonts.sans(15); field.textColor = NSColor(hex: "#222222")
        field.placeholderString = placeholder
        field.isBezeled = false; field.wantsLayer = true; field.layer?.cornerRadius = 8
        field.layer?.backgroundColor = NSColor(hex: "#fafafb").cgColor
        field.layer?.borderColor = NSColor(hex: "#e3e3e6").cgColor; field.layer?.borderWidth = 1
        field.drawsBackground = false
        view.addSubview(field)
        return field
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        card.frame = NSRect(x: 0, y: 0, width: bounds.width, height: card.frame.height)
        contentArea.frame.size.width = bounds.width
        panelController?.setContentHeight(card.frame.height)
    }

    private func close() { onClose() }

    private func installMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { self.close(); return nil }
            return event
        }
    }
    private func removeMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }
}

extension AddAccountView: PanelContentView {
    var panelPreferredSize: CGSize { CGSize(width: CARD_W, height: card.frame.height) }
    var panelTitle: String { isX ? "Add Account" : "添加账号" }
    func attach(to panel: PanelWindowController) { panelController = panel }
}
