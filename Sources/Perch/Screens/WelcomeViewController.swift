import AppKit

/// First-launch / empty-state Welcome window. Shown when Perch has no connected
/// accounts. Introduces the app and launches the real in-app X login flow.
/// Port of design/project/app/welcome.jsx (centered card layout).
final class WelcomeViewController: NSViewController, AppStateDelegate {
    private let appState: AppState
    private let onOpenApp: () -> Void
    private var welcomeView: WelcomeView!
    private var addAccountPanel: PanelWindowController?
    private var addAccountView: AddAccountView?

    init(appState: AppState, onOpenApp: @escaping () -> Void) {
        self.appState = appState
        self.onOpenApp = onOpenApp
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        welcomeView = WelcomeView(
            onConnectX: { [weak self] in self?.appState.beginXLogin() },
            onOpenApp: { [weak self] in self?.onOpenApp() },
            onAddAnother: { [weak self] in self?.appState.openAddAccount() })
        welcomeView.frame = NSRect(x: 0, y: 0, width: 560, height: 584)
        view = welcomeView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        appState.delegate = self
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        welcomeView.rebuild()
    }

    // ── AddAccount panel (mirrors RootViewController) ──
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

    // ── AppStateDelegate ──
    func appStateDidChangeAddAccount(_ s: AppState) {
        if appState.addAccountOpen {
            if addAccountPanel == nil { mountAddAccount() }
        } else {
            unmountAddAccount()
        }
    }

    func appStateDidConnectFirstAccount(_ s: AppState) {
        unmountAddAccount()
        if let acct = appState.accounts.first {
            welcomeView.showSuccess(account: acct)
        }
    }

    // Unused in the welcome context — no-ops.
    func appStateDidChangeTheme(_ s: AppState) {}
    func appStateDidChangeColumns(_ s: AppState) {}
    func appStateDidChangeActive(_ s: AppState) {}
    func appState(_ s: AppState, didUpdatePost id: String) {}
    func appState(_ s: AppState, didChangeNavForColumn colId: String) {}
    func appStateDidChangeCompose(_ s: AppState) {}
    func appState(_ s: AppState, showToast text: String) {}
    func appState(_ s: AppState, didAddReplyTo postId: String) {}
    func appStateDidChangeSettings(_ s: AppState) {}
    func appStateDidChangeMediaViewer(_ s: AppState) {}
    func appStateRequestsWelcome(_ s: AppState) {}
    func appStateDidChangeNavConfig(_ s: AppState) {}
    func appStateDidChangeNavConfigOpen(_ s: AppState) {}
}

// ── The welcome card view (centered layout) ──
final class WelcomeView: FlippedView {
    private let onConnectX: () -> Void
    private let onOpenApp: () -> Void
    private let onAddAnother: () -> Void
    private var connected: Account?
    private let contentW: CGFloat = 420   // content column (matches design maxWidth)

    init(onConnectX: @escaping () -> Void, onOpenApp: @escaping () -> Void, onAddAnother: @escaping () -> Void) {
        self.onConnectX = onConnectX
        self.onOpenApp = onOpenApp
        self.onAddAnother = onAddAnother
        super.init(frame: .zero)
        bgColor = ThemeManager.shared.theme.bgBase
    }
    required init?(coder: NSCoder) { fatalError() }

    func showSuccess(account: Account) {
        connected = account
        rebuild()
    }

    /// While Appearance is set to "system", track live macOS light/dark flips.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard ThemeManager.shared.mode == .system else { return }
        ThemeManager.shared.setMode(.system, root: nil, persist: false)
        window?.backgroundColor = ThemeManager.shared.theme.bgBase
        rebuild()
    }

    func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        let theme = ThemeManager.shared.theme
        bgColor = theme.bgBase

        let content = connected.map { buildSuccess(account: $0, theme: theme) }
            ?? buildConnect(theme: theme)
        let W = bounds.width, H = bounds.height
        content.frame.origin = CGPoint(x: (W - content.frame.width) / 2,
                                       y: max(40, (H - content.frame.height) / 2))
        addSubview(content)
    }

    // ── Connect panel (centered) ──
    private func buildConnect(theme: Theme) -> FlippedView {
        let CW = contentW
        let c = FlippedView()
        var y: CGFloat = 0

        // brand lockup — mark over serif wordmark, centered
        let mark = perchMark(size: 60)
        mark.frame = NSRect(x: (CW - 60) / 2, y: y, width: 60, height: 60)
        c.addSubview(mark)
        let brand = makeLabel("Perch", font: serif(30), color: theme.fgHeading, align: .center)
        brand.frame = NSRect(x: 0, y: y + 72, width: CW, height: 36)
        c.addSubview(brand)
        y += 60 + 12 + 36 + 22

        let h1 = makeLabel("Welcome to Perch", font: Fonts.sans(28, .heavy), color: theme.fgHeading, align: .center)
        h1.frame = NSRect(x: 0, y: y, width: CW, height: 34)
        c.addSubview(h1)
        y += 34 + 11

        let subW: CGFloat = 384
        let subText = "Read X and Weibo together — calm, dense, and native to your Mac. Connect an account to get started."
        let sub = makeLabel(subText, font: Fonts.sans(15), color: theme.fgBody, align: .center)
        sub.usesSingleLineMode = false
        sub.maximumNumberOfLines = 0
        sub.lineBreakMode = .byWordWrapping
        sub.preferredMaxLayoutWidth = subW
        let subH = ceil(sub.intrinsicContentSize.height)
        sub.frame = NSRect(x: (CW - subW) / 2, y: y, width: subW, height: subH)
        c.addSubview(sub)
        y += subH + 26

        let xRow = connectRow(theme: theme, platform: .x, title: "X", subtitle: "Sign in with your X account", enabled: true, width: CW)
        xRow.frame.origin = CGPoint(x: 0, y: y)
        c.addSubview(xRow)
        y += 74 + 11

        let wRow = connectRow(theme: theme, platform: .weibo, title: "微博 Weibo", subtitle: "Scan a QR code or sign in", enabled: false, width: CW)
        wRow.frame.origin = CGPoint(x: 0, y: y)
        c.addSubview(wRow)
        y += 74 + 22

        // reassurance — lock + copy, centered as a block
        let reW: CGFloat = 360
        let reText = "Perch signs in through the official site. Your password is never stored."
        let re = makeLabel(reText, font: Fonts.sans(12), color: theme.fgSubdued)
        re.usesSingleLineMode = false
        re.maximumNumberOfLines = 0
        re.lineBreakMode = .byWordWrapping
        re.preferredMaxLayoutWidth = reW
        let reH = ceil(re.intrinsicContentSize.height)
        let blockW = 14 + 8 + reW
        let x0 = (CW - blockW) / 2
        let lock = GlyphView(name: "lock", size: 14, color: theme.fgSubdued)
        lock.frame = NSRect(x: x0, y: y + 1, width: 14, height: 14)
        c.addSubview(lock)
        re.frame = NSRect(x: x0 + 22, y: y, width: reW, height: reH)
        c.addSubview(re)
        y += reH

        c.frame = NSRect(x: 0, y: 0, width: CW, height: y)
        return c
    }

    private func connectRow(theme: Theme, platform: Platform, title: String, subtitle: String, enabled: Bool, width: CGFloat) -> HoverControl {
        let isX = platform == .x
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: 74))
        row.wantsLayer = true
        row.layer?.cornerRadius = 14
        row.layer?.borderColor = theme.borderDefault.cgColor
        row.layer?.borderWidth = 1
        row.layer?.backgroundColor = theme.bgBase.cgColor
        row.enabledControl = enabled
        row.alphaValue = enabled ? 1.0 : 0.55

        let circ = FlippedView(frame: NSRect(x: 16, y: 14, width: 46, height: 46))
        circ.wantsLayer = true; circ.layer?.cornerRadius = 23
        circ.layer?.backgroundColor = NSColor(hex: isX ? "#15141a" : "#e6162d").cgColor
        let mk = makeLabel(isX ? "𝕏" : "微", font: Fonts.sans(isX ? 22 : 20, .heavy), color: .white, align: .center)
        mk.frame = NSRect(x: 0, y: 11, width: 46, height: 24)
        circ.addSubview(mk)
        row.addSubview(circ)

        let t = makeLabel(title, font: Fonts.sans(16, .heavy), color: theme.fgHeading)
        t.frame = NSRect(x: 76, y: 16, width: width - 76 - 36, height: 20)
        row.addSubview(t)
        let s = makeLabel(subtitle, font: Fonts.sans(13), color: theme.fgSubdued)
        s.frame = NSRect(x: 76, y: 38, width: width - 76 - 36, height: 18)
        row.addSubview(s)

        if enabled {
            let chev = GlyphView(name: "chevron-down", size: 18, color: theme.fgDisabled)
            chev.rotationDegrees = -90   // ↓ → → (rotates around its own center)
            chev.frame = NSRect(x: width - 34, y: 28, width: 18, height: 18)
            row.addSubview(chev)
            row.onState = { [weak row] h, _ in
                row?.layer?.borderColor = (h ? theme.accent : theme.borderDefault).cgColor
                row?.layer?.backgroundColor = (h ? theme.gray75 : theme.bgBase).cgColor
                chev.color = h ? theme.accent : theme.fgDisabled
            }
            row.onClick = { [weak self] in self?.onConnectX() }
        }
        return row
    }

    // ── Success panel (centered) ──
    private func buildSuccess(account: Account, theme: Theme) -> FlippedView {
        let CW = contentW
        let c = FlippedView()
        var y: CGFloat = 0

        let circle = FlippedView(frame: NSRect(x: (CW - 64) / 2, y: y, width: 64, height: 64))
        circle.wantsLayer = true; circle.layer?.cornerRadius = 32
        circle.layer?.backgroundColor = theme.positive.withAlphaComponent(0.16).cgColor
        let ck = GlyphView(name: "checkmark-circle", size: 40, color: theme.positive)
        ck.frame = NSRect(x: 12, y: 12, width: 40, height: 40)
        circle.addSubview(ck)
        c.addSubview(circle)
        y += 64 + 18

        let h1 = makeLabel("You're all set", font: Fonts.sans(27, .heavy), color: theme.fgHeading, align: .center)
        h1.frame = NSRect(x: 0, y: y, width: CW, height: 34)
        c.addSubview(h1)
        y += 34 + 10

        // "{name} is connected. Your timeline is ready." — name emphasized
        let line = NSMutableAttributedString()
        let para = NSMutableParagraphStyle(); para.alignment = .center
        line.append(NSAttributedString(string: account.name, attributes: [
            .font: Fonts.sans(15, .heavy), .foregroundColor: theme.fgHeading, .paragraphStyle: para]))
        line.append(NSAttributedString(string: " is connected. Your timeline is ready.", attributes: [
            .font: Fonts.sans(15), .foregroundColor: theme.fgBody, .paragraphStyle: para]))
        let sub = NSTextField(labelWithAttributedString: line)
        sub.isBezeled = false; sub.drawsBackground = false; sub.isEditable = false; sub.isSelectable = false
        sub.usesSingleLineMode = false; sub.maximumNumberOfLines = 0; sub.lineBreakMode = .byWordWrapping
        sub.preferredMaxLayoutWidth = CW
        let subH = ceil(sub.intrinsicContentSize.height)
        sub.frame = NSRect(x: 0, y: y, width: CW, height: subH)
        c.addSubview(sub)
        y += subH + 20

        // account chip: avatar (+ platform badge) · name (+ verified) · status
        let chip = makeAccountChip(account: account, theme: theme)
        chip.frame.origin = CGPoint(x: (CW - chip.frame.width) / 2, y: y)
        c.addSubview(chip)
        y += 44 + 26

        // Open Perch button
        let openLbl = "Open Perch"
        let openFont = Fonts.sans(16, .heavy)
        let openTextW = (openLbl as NSString).size(withAttributes: [.font: openFont]).width
        let btnW = ceil(26 + openTextW + 9 + 18 + 26)
        let btn = HoverControl(frame: NSRect(x: (CW - btnW) / 2, y: y, width: btnW, height: 50))
        btn.wantsLayer = true; btn.layer?.cornerRadius = 25
        btn.layer?.backgroundColor = theme.accentBg.cgColor
        let btnLbl = makeLabel(openLbl, font: openFont, color: .white)
        btnLbl.frame = NSRect(x: 26, y: 14, width: ceil(openTextW), height: 22)
        btn.addSubview(btnLbl)
        let btnChev = GlyphView(name: "chevron-down", size: 18, color: .white)
        btnChev.rotationDegrees = -90
        btnChev.frame = NSRect(x: 26 + ceil(openTextW) + 9, y: 16, width: 18, height: 18)
        btn.addSubview(btnChev)
        btn.onState = { [weak btn] h, _ in btn?.layer?.backgroundColor = (h ? theme.accentBgHover : theme.accentBg).cgColor }
        btn.onClick = { [weak self] in self?.onOpenApp() }
        c.addSubview(btn)
        y += 50 + 8

        let add = HoverControl(frame: NSRect(x: (CW - 220) / 2, y: y, width: 220, height: 40))
        let addLbl = makeLabel("Add another account", font: Fonts.sans(14, .bold), color: theme.fgSubdued, align: .center)
        addLbl.frame = NSRect(x: 0, y: 10, width: 220, height: 20)
        add.addSubview(addLbl)
        add.onClick = { [weak self] in self?.onAddAnother() }
        c.addSubview(add)
        y += 40

        c.frame = NSRect(x: 0, y: 0, width: CW, height: y)
        return c
    }

    private func makeAccountChip(account: Account, theme: Theme) -> FlippedView {
        let chip = FlippedView(frame: NSRect(x: 0, y: 0, width: 0, height: 44))
        chip.wantsLayer = true; chip.layer?.cornerRadius = 22
        chip.layer?.backgroundColor = theme.bgLayer1.cgColor
        chip.layer?.borderColor = theme.borderDefault.cgColor; chip.layer?.borderWidth = 1

        var x: CGFloat = 8
        let av = AvatarView(person: account, size: 28)
        av.frame = NSRect(x: x, y: 8, width: 28, height: 28)
        chip.addSubview(av)
        let badge = platformBadge(platform: account.platform, size: 14, theme: theme)
        badge.frame = NSRect(x: x + 28 - 11, y: 8 + 28 - 11, width: 14, height: 14)
        chip.addSubview(badge)
        x += 28 + 9

        let nm = makeLabel(account.name, font: Fonts.sans(14, .bold), color: theme.fgHeading)
        let nmW = ceil(nm.intrinsicContentSize.width)
        nm.frame = NSRect(x: x, y: 13, width: nmW, height: 18)
        chip.addSubview(nm)
        x += nmW
        if account.verified {
            let vb = VerifiedBadge(size: 13)
            vb.frame = NSRect(x: x + 4, y: 15, width: 13, height: 13)
            chip.addSubview(vb)
            x += 4 + 13
        }
        x += 8

        let dot = FlippedView(frame: NSRect(x: x, y: 19, width: 7, height: 7))
        dot.wantsLayer = true; dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = theme.positive.cgColor
        chip.addSubview(dot)
        x += 7 + 5
        let statusText = account.platform == .x ? "Signed in" : "已连接"
        let st = makeLabel(statusText, font: Fonts.sans(12.5, .bold), color: theme.positive)
        let stW = ceil(st.intrinsicContentSize.width)
        st.frame = NSRect(x: x, y: 14, width: stW, height: 16)
        chip.addSubview(st)
        x += stW + 15

        chip.frame = NSRect(x: 0, y: 0, width: x, height: 44)
        return chip
    }

    private func platformBadge(platform: Platform, size: CGFloat, theme: Theme) -> FlippedView {
        let isX = platform == .x
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true
        v.layer?.cornerRadius = size / 2
        v.layer?.backgroundColor = NSColor(hex: isX ? "#15141a" : "#e6162d").cgColor
        v.layer?.borderWidth = 2
        v.layer?.borderColor = theme.bgLayer1.cgColor
        let l = makeLabel(isX ? "𝕏" : "微", font: Fonts.sans(size * 0.58, .heavy), color: .white, align: .center)
        l.frame = NSRect(x: 0, y: (size - size * 0.72) / 2, width: size, height: size * 0.72)
        v.addSubview(l)
        return v
    }

    private func perchMark(size: CGFloat) -> FlippedView {
        // Shared PerchIcon brand mark (white bird on the sky→ocean squircle) over the
        // design's ocean drop-shadow glow.
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        v.wantsLayer = true; v.layer?.masksToBounds = false
        v.layer?.shadowColor = PerchAppIcon.brandGlow.cgColor
        v.layer?.shadowOpacity = 0.34
        v.layer?.shadowRadius = size * 0.16
        v.layer?.shadowOffset = CGSize(width: 0, height: -size * 0.07)

        let icon = NSImageView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        icon.image = PerchAppIcon.brandImage()
        icon.imageScaling = .scaleProportionallyUpOrDown
        v.addSubview(icon)
        return v
    }

    private func serif(_ size: CGFloat) -> NSFont {
        NSFont(name: "Georgia", size: size) ?? Fonts.sans(size, .heavy)
    }
}
