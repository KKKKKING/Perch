import AppKit

// MARK: - Settings Controls

final class ToggleView: NSView {
    var isOn: Bool { didSet { render() } }
    var onChange: ((Bool) -> Void)?
    private let thumb = NSView()

    init(on: Bool) {
        self.isOn = on
        super.init(frame: NSRect(x: 0, y: 0, width: 42, height: 25))
        wantsLayer = true
        layer?.cornerRadius = 12.5
        layer?.masksToBounds = true
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 9.5
        thumb.layer?.backgroundColor = NSColor.white.cgColor
        thumb.layer?.shadowColor = NSColor.black.cgColor
        thumb.layer?.shadowOpacity = 0.18
        thumb.layer?.shadowRadius = 2
        thumb.layer?.shadowOffset = CGSize(width: 0, height: -1)
        addSubview(thumb)
        render()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if bounds.contains(pt) {
            isOn.toggle()
            onChange?(isOn)
        }
    }

    private func render() {
        let theme = ThemeManager.shared.theme
        layer?.backgroundColor = (isOn ? theme.accentBg : theme.gray400).cgColor
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            thumb.animator().frame = NSRect(x: isOn ? 20 : 3, y: 3, width: 19, height: 19)
        }
    }
}

final class SegmentedPill: FlippedView {
    var value: String { didSet { renderButtons() } }
    private let options: [(value: String, label: String, icon: String?)]
    var onChange: ((String) -> Void)?
    private var buttons: [HoverControl] = []

    init(value: String, options: [(String, String, String?)]) {
        self.value = value
        self.options = options.map { (value: $0.0, label: $0.1, icon: $0.2) }
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        let theme = ThemeManager.shared.theme
        layer?.backgroundColor = theme.gray100.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let theme = ThemeManager.shared.theme
        let ph: CGFloat = 28
        var x: CGFloat = 2
        for opt in options {
            let btn = HoverControl(frame: NSRect(x: x, y: 2, width: 10, height: ph - 4))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = (ph - 4) / 2
            if let icon = opt.icon {
                let g = GlyphView(name: icon, size: 13, color: theme.fgHeading)
                g.frame = NSRect(x: 7, y: (ph - 4 - 13) / 2, width: 13, height: 13)
                btn.addSubview(g)
                let lbl = makeLabel(opt.label, font: Fonts.sans(12.5, .semibold), color: theme.fgHeading)
                lbl.frame = NSRect(x: 25, y: (ph - 4 - lbl.intrinsicContentSize.height) / 2, width: lbl.intrinsicContentSize.width, height: lbl.intrinsicContentSize.height)
                btn.addSubview(lbl)
                btn.frame.size.width = 7 + 13 + 5 + lbl.intrinsicContentSize.width + 7
            } else {
                let lbl = makeLabel(opt.label, font: Fonts.sans(12.5, .semibold), color: theme.fgHeading, align: .center)
                let tw = lbl.intrinsicContentSize.width + 24
                btn.frame.size.width = tw
                lbl.frame = NSRect(x: 0, y: (ph - 4 - lbl.intrinsicContentSize.height) / 2, width: tw, height: lbl.intrinsicContentSize.height)
                btn.addSubview(lbl)
            }
            let val = opt.value
            btn.onClick = { [weak self] in
                self?.value = val
                self?.onChange?(val)
            }
            addSubview(btn)
            buttons.append(btn)
            x += btn.frame.width + 2
        }
        frame = NSRect(x: 0, y: 0, width: x + 2, height: ph)
        renderButtons()
    }

    private func renderButtons() {
        let theme = ThemeManager.shared.theme
        for (i, btn) in buttons.enumerated() {
            let on = options[i].value == value
            btn.layer?.backgroundColor = on ? theme.bgElevated.cgColor : NSColor.clear.cgColor
            if on {
                btn.layer?.shadowColor = NSColor.black.cgColor
                btn.layer?.shadowOpacity = theme.isDark ? 0.4 : 0.12
                btn.layer?.shadowRadius = 3
                btn.layer?.shadowOffset = CGSize(width: 0, height: -1)
                btn.layer?.masksToBounds = false
            } else {
                btn.layer?.shadowOpacity = 0
            }
            for sub in btn.subviews {
                if let lbl = sub as? NSTextField { lbl.textColor = on ? theme.fgHeading : theme.fgSubdued }
                if let g = sub as? GlyphView { g.color = on ? theme.fgHeading : theme.fgSubdued }
            }
        }
    }
}

final class AccentPickerView: FlippedView {
    var value: String { didSet { renderCircles() } }
    var onChange: ((String) -> Void)?
    private var circles: [(HoverControl, AccentOption)] = []

    init(value: String) {
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: 206, height: 26))
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let theme = ThemeManager.shared.theme
        var x: CGFloat = 0
        for opt in AccentOption.all {
            let btn = HoverControl(frame: NSRect(x: x, y: 0, width: 26, height: 26))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 13
            btn.layer?.masksToBounds = true
            btn.layer?.backgroundColor = opt.dotColor.cgColor
            let ck = GlyphView(name: "checkmark", size: 13, color: .white)
            ck.frame = NSRect(x: 6.5, y: 6.5, width: 13, height: 13)
            ck.alphaValue = 0
            btn.addSubview(ck)
            let id = opt.id
            btn.onClick = { [weak self] in
                self?.value = id
                self?.onChange?(id)
            }
            addSubview(btn)
            circles.append((btn, opt))
            x += 26 + 11
        }
        frame.size.width = x - 11
        renderCircles()
        _ = theme
    }

    private func renderCircles() {
        let theme = ThemeManager.shared.theme
        for (btn, opt) in circles {
            let on = opt.id == value
            if on {
                btn.layer?.borderColor = theme.fgHeading.cgColor
                btn.layer?.borderWidth = 2
                btn.layer?.shadowColor = theme.fgHeading.cgColor
                btn.layer?.shadowOpacity = 0.0
                btn.layer?.masksToBounds = false
                // use box-shadow via sublayer
                if let outline = btn.layer?.sublayers?.first(where: { $0.name == "ring" }) {
                    outline.removeFromSuperlayer()
                }
                let ring = CALayer()
                ring.name = "ring"
                ring.frame = NSRect(x: -3, y: -3, width: 32, height: 32)
                ring.cornerRadius = 16
                ring.borderColor = theme.fgHeading.cgColor
                ring.borderWidth = 2
                ring.masksToBounds = false
                btn.layer?.addSublayer(ring)
                btn.layer?.borderWidth = 0
                btn.layer?.borderColor = NSColor.clear.cgColor
                btn.subviews.compactMap { $0 as? GlyphView }.first?.alphaValue = 1
            } else {
                btn.layer?.sublayers?.filter { $0.name == "ring" }.forEach { $0.removeFromSuperlayer() }
                btn.layer?.borderWidth = 0
                btn.subviews.compactMap { $0 as? GlyphView }.first?.alphaValue = 0
            }
        }
    }
}

// MARK: - Settings Row / Group builders

private func settingsGroup(title: String?, rows: [NSView], width: CGFloat) -> (view: FlippedView, height: CGFloat) {
    let theme = ThemeManager.shared.theme
    let v = FlippedView()
    var y: CGFloat = 0
    if let title {
        let lbl = makeLabel(title.uppercased(), font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        lbl.frame = NSRect(x: 4, y: 12, width: width, height: 14)
        v.addSubview(lbl)
        y = 34
    }
    let card = FlippedView(frame: NSRect(x: 0, y: y, width: width, height: 0))
    card.wantsLayer = true
    card.layer?.cornerRadius = 12
    card.layer?.borderColor = theme.borderDefault.cgColor
    card.layer?.borderWidth = 1
    card.layer?.backgroundColor = theme.bgBase.cgColor
    card.layer?.masksToBounds = true
    var cy: CGFloat = 0
    for (i, row) in rows.enumerated() {
        row.frame.origin = CGPoint(x: 0, y: cy)
        card.addSubview(row)
        cy += row.frame.height
        if i < rows.count - 1 {
            let line = NSView(frame: NSRect(x: 14, y: cy - 0.5, width: width - 28, height: 0.5))
            line.wantsLayer = true
            line.layer?.backgroundColor = theme.borderDefault.cgColor
            card.addSubview(line)
        }
    }
    card.frame.size.height = cy
    v.addSubview(card)
    y += cy
    v.frame = NSRect(x: 0, y: 0, width: width, height: y + 8)
    return (v, y + 8)
}

private func settingsRow(label: String, desc: String?, control: NSView, width: CGFloat) -> (view: FlippedView, height: CGFloat) {
    let theme = ThemeManager.shared.theme
    let padX: CGFloat = 14
    let padY: CGFloat = 13
    let labelW = width - padX * 2 - control.frame.width - 16
    let lbl = makeLabel(label, font: Fonts.sans(14, .semibold), color: theme.fgHeading)
    lbl.frame = NSRect(x: padX, y: padY, width: labelW, height: 17)
    var descH: CGFloat = 0
    var descV: NSTextField?
    if let desc {
        let d = makeLabel(desc, font: Fonts.sans(12.5), color: theme.fgSubdued)
        d.lineBreakMode = .byWordWrapping
        d.maximumNumberOfLines = 2
        d.preferredMaxLayoutWidth = labelW
        let h = max(14, d.intrinsicContentSize.height)
        d.frame = NSRect(x: padX, y: padY + 17 + 3, width: labelW, height: h)
        descH = h + 3
        descV = d
    }
    let rowH = padY + 17 + descH + padY
    let v = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
    v.addSubview(lbl)
    if let dv = descV { v.addSubview(dv) }
    control.frame.origin = CGPoint(x: width - padX - control.frame.width, y: (rowH - control.frame.height) / 2)
    v.addSubview(control)
    return (v, rowH)
}

// MARK: - SettingsView

final class SettingsView: FlippedView {
    private let appState: AppState
    private let onClose: () -> Void
    private let theme = ThemeManager.shared.theme
    private let isX: Bool

    private let card = FlippedView()
    private var catButtons: [String: HoverControl] = [:]
    private var catLabels: [String: NSTextField] = [:]
    private var catIcons: [String: GlyphView] = [:]
    private var activeCat = "general"
    private var accountsPaneSignature = ""
    private let contentTitleLabel: NSTextField
    private let contentScroll: NSScrollView
    private var eventMonitor: Any?
    private weak var panelController: PanelWindowController?

    private var prefs: [String: Any] = [
        "launchAtLogin": true,
        "openLinks": "app",
        "refreshEvery": "5",
        "markRead": true,
        "reduceMotion": false,
        "notifMentions": true,
        "notifReposts": true,
        "notifLikes": false,
        "notifFollowers": true,
        "notifSound": true,
        "dockBadge": true,
        "autoplay": true,
        "sensitive": false,
        "linkPreviews": true,
        "detailPane": true,
    ]

    private let CARD_W: CGFloat = 720
    private let CARD_H: CGFloat = 560
    private let SIDEBAR_W: CGFloat = 196
    private let HEADER_H: CGFloat = 52
    private var refreshOptions: [(String, String)] {
        [("off", isX ? "Manually" : "手动"),
         ("1", isX ? "Every 1 min" : "每 1 分钟"),
         ("5", isX ? "Every 5 min" : "每 5 分钟"),
         ("15", isX ? "Every 15 min" : "每 15 分钟")]
    }

    private struct CatMeta {
        let id: String; let icon: String; let labelX: String; let labelW: String
    }
    private let cats: [CatMeta] = [
        CatMeta(id: "general",       icon: "settings", labelX: "General",       labelW: "通用"),
        CatMeta(id: "accounts",      icon: "user",     labelX: "Accounts",      labelW: "账号"),
        CatMeta(id: "appearance",    icon: "sun",      labelX: "Appearance",    labelW: "外观"),
        CatMeta(id: "notifications", icon: "bell",     labelX: "Notifications", labelW: "通知"),
        CatMeta(id: "timeline",      icon: "list",     labelX: "Timeline",      labelW: "时间线"),
        CatMeta(id: "developer",     icon: "code",     labelX: "Developer",     labelW: "开发者"),
        CatMeta(id: "about",         icon: "info",     labelX: "About",         labelW: "关于"),
    ]

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
        self.onClose = onClose
        self.isX = appState.active.platform == .x
        self.contentTitleLabel = makeLabel("", font: Fonts.sans(16, .heavy), color: ThemeManager.shared.theme.fgHeading)
        self.contentScroll = NSScrollView()
        super.init(frame: .zero)
        prefs["refreshEvery"] = appState.refreshEveryMinutes
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        buildCard()
        installMonitor()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { removeMonitor() }

    private func buildCard() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = theme.bgElevated.cgColor
        card.layer?.borderColor = theme.borderDefault.cgColor
        card.layer?.borderWidth = 1
        card.layer?.masksToBounds = true
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.45
        card.layer?.shadowRadius = 28
        card.layer?.shadowOffset = CGSize(width: 0, height: -8)
        addSubview(card)

        buildSidebar()
        buildContentArea()
        switchCat("general")
    }

    private func buildSidebar() {
        let sidebar = FlippedView(frame: NSRect(x: 0, y: 0, width: SIDEBAR_W, height: CARD_H))
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = theme.bgLayer1.cgColor
        card.addSubview(sidebar)

        // right border
        let border = NSView(frame: NSRect(x: SIDEBAR_W - 1, y: 0, width: 1, height: CARD_H))
        border.wantsLayer = true
        border.layer?.backgroundColor = theme.borderDefault.cgColor
        sidebar.addSubview(border)

        // traffic lights header
        let header = FlippedView(frame: NSRect(x: 0, y: 0, width: SIDEBAR_W, height: HEADER_H))
        sidebar.addSubview(header)
        let dots: [(NSColor, Bool)] = [
            (NSColor(hex: "#ff5f57"), true),
            (NSColor(hex: "#febc2e"), false),
            (NSColor(hex: "#28c840"), false),
        ]
        var dx: CGFloat = 14
        for (color, closeable) in dots {
            let dot = HoverControl(frame: NSRect(x: dx, y: (HEADER_H - 12) / 2, width: 12, height: 12))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 6
            dot.layer?.backgroundColor = color.cgColor
            dot.layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
            dot.layer?.borderWidth = 0.5
            if closeable { dot.onClick = { [weak self] in self?.close() } }
            header.addSubview(dot)
            dx += 20
        }

        // category buttons
        var cy: CGFloat = HEADER_H + 4
        for cat in cats {
            let label = isX ? cat.labelX : cat.labelW
            let btn = HoverControl(frame: NSRect(x: 10, y: cy, width: SIDEBAR_W - 20, height: 38))
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 9
            let icon = GlyphView(name: cat.icon, size: 19, color: theme.fgSubdued)
            icon.frame = NSRect(x: 10, y: (38 - 19) / 2, width: 19, height: 19)
            btn.addSubview(icon)
            let lbl = makeLabel(label, font: Fonts.sans(14, .semibold), color: theme.fgBody)
            lbl.frame = NSRect(x: 10 + 19 + 11, y: (38 - lbl.intrinsicContentSize.height) / 2, width: SIDEBAR_W - 20 - 10 - 19 - 11, height: lbl.intrinsicContentSize.height)
            btn.addSubview(lbl)
            let id = cat.id
            btn.onClick = { [weak self] in self?.switchCat(id) }
            sidebar.addSubview(btn)
            catButtons[cat.id] = btn
            catLabels[cat.id] = lbl
            catIcons[cat.id] = icon
            cy += 40
        }
    }

    private func buildContentArea() {
        let contentW = CARD_W - SIDEBAR_W
        // header
        let header = FlippedView(frame: NSRect(x: SIDEBAR_W, y: 0, width: contentW, height: HEADER_H))
        header.wantsLayer = true
        header.layer?.backgroundColor = theme.bgElevated.cgColor
        card.addSubview(header)
        contentTitleLabel.frame = NSRect(x: 18, y: (HEADER_H - contentTitleLabel.intrinsicContentSize.height) / 2, width: 300, height: contentTitleLabel.intrinsicContentSize.height)
        header.addSubview(contentTitleLabel)
        // done button
        let done = HoverControl()
        done.wantsLayer = true
        done.layer?.cornerRadius = 8
        let doneLabel = makeLabel(isX ? "Done" : "完成", font: Fonts.sans(13.5, .semibold), color: theme.fgSubdued)
        let dw = doneLabel.intrinsicContentSize.width + 28
        done.frame = NSRect(x: CARD_W - SIDEBAR_W - dw - 18, y: (HEADER_H - 30) / 2, width: dw, height: 30)
        doneLabel.frame = NSRect(x: 0, y: (30 - doneLabel.intrinsicContentSize.height) / 2, width: dw, height: doneLabel.intrinsicContentSize.height)
        done.addSubview(doneLabel)
        done.onState = { h, _ in done.layer?.backgroundColor = (h ? self.theme.gray100 : NSColor.clear).cgColor }
        done.onClick = { [weak self] in self?.close() }
        header.addSubview(done)
        // bottom border
        let line = NSView(frame: NSRect(x: 0, y: HEADER_H - 1, width: contentW, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        header.addSubview(line)

        // scroll view
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.autohidesScrollers = true
        contentScroll.scrollerStyle = .overlay
        contentScroll.frame = NSRect(x: SIDEBAR_W, y: HEADER_H, width: contentW, height: CARD_H - HEADER_H)
        card.addSubview(contentScroll)
    }

    private func switchCat(_ id: String) {
        activeCat = id
        let meta = cats.first { $0.id == id }
        let label = isX ? (meta?.labelX ?? id) : (meta?.labelW ?? id)
        contentTitleLabel.stringValue = label
        for (catId, btn) in catButtons {
            let on = catId == id
            btn.layer?.backgroundColor = on ? theme.accentBg.cgColor : NSColor.clear.cgColor
            catLabels[catId]?.textColor = on ? .white : theme.fgBody
            catIcons[catId]?.color = on ? .white : theme.fgSubdued
        }
        let pane = buildPane(id)
        contentScroll.documentView = pane
        contentScroll.contentView.scroll(to: .zero)
        pane.frame.size.width = CARD_W - SIDEBAR_W - 44
    }

    func refreshAccountsPaneIfNeeded() {
        guard activeCat == "accounts" else { return }
        let signature = makeAccountsPaneSignature()
        guard signature != accountsPaneSignature else { return }

        let paneW = CARD_W - SIDEBAR_W - 44
        let scrollOrigin = contentScroll.contentView.bounds.origin
        let pane = buildAccountsPane(width: paneW)
        contentScroll.documentView = pane
        pane.frame.size.width = paneW
        let maxY = max(0, pane.frame.height - contentScroll.contentView.bounds.height)
        contentScroll.contentView.scroll(to: NSPoint(x: scrollOrigin.x, y: min(scrollOrigin.y, maxY)))
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
    }

    // MARK: - Pane builders

    private func buildPane(_ id: String) -> FlippedView {
        let paneW = CARD_W - SIDEBAR_W - 44
        switch id {
        case "general": return buildGeneralPane(width: paneW)
        case "accounts": return buildAccountsPane(width: paneW)
        case "appearance": return buildAppearancePane(width: paneW)
        case "notifications": return buildNotificationsPane(width: paneW)
        case "timeline": return buildTimelinePane(width: paneW)
        case "developer": return buildDeveloperPane(width: paneW)
        case "about": return buildAboutPane(width: paneW)
        default: return FlippedView()
        }
    }

    private func buildGeneralPane(width: CGFloat) -> FlippedView {
        let v = FlippedView()
        var y: CGFloat = 20
        let isX = self.isX

        let g1 = settingsGroup(title: isX ? "Startup" : "启动", rows: [
            settingsRow(label: isX ? "Launch at login" : "登录时启动",
                        desc: isX ? "Open Perch automatically when you sign in to your Mac." : "登录 Mac 后自动打开 Perch。",
                        control: makeToggle("launchAtLogin"), width: width).view,
            settingsRow(label: isX ? "Restore columns on launch" : "启动时恢复分栏",
                        desc: isX ? "Reopen your last column layout each time." : "每次打开时恢复上次的分栏布局。",
                        control: makeToggle("markRead"), width: width).view,
        ], width: width)
        g1.view.frame.origin = CGPoint(x: 0, y: y)
        v.addSubview(g1.view); y += g1.height

        let openSeg = SegmentedPill(value: prefs["openLinks"] as? String ?? "app",
                                    options: [("app", isX ? "In Perch" : "应用内", nil), ("browser", isX ? "Browser" : "浏览器", nil)])
        openSeg.onChange = { [weak self] val in self?.prefs["openLinks"] = val }

        let refreshPop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 140, height: 28))
        let rOpts = refreshOptions
        for (_, lbl) in rOpts { refreshPop.addItem(withTitle: lbl) }
        if let idx = rOpts.firstIndex(where: { $0.0 == (prefs["refreshEvery"] as? String ?? "5") }) { refreshPop.selectItem(at: idx) }
        refreshPop.target = self
        refreshPop.action = #selector(refreshEveryChanged(_:))

        let g2 = settingsGroup(title: isX ? "Browsing" : "浏览", rows: [
            settingsRow(label: isX ? "Open links in" : "链接打开方式",
                        desc: isX ? "Where posts and articles open when you click a link." : "点击链接时帖子和文章的打开位置。",
                        control: openSeg, width: width).view,
            settingsRow(label: isX ? "Refresh timeline" : "刷新时间线",
                        desc: isX ? "How often columns pull in new posts." : "分栏自动拉取新帖子的频率。",
                        control: refreshPop, width: width).view,
        ], width: width)
        g2.view.frame.origin = CGPoint(x: 0, y: y)
        v.addSubview(g2.view); y += g2.height

        v.frame = NSRect(x: 22, y: 0, width: width, height: y + 8)
        return v
    }

    private func buildAccountsPane(width: CGFloat) -> FlippedView {
        let v = FlippedView()
        let isX = self.isX
        var y: CGFloat = 20
        accountsPaneSignature = makeAccountsPaneSignature()

        let countTitle = isX ? "Connected accounts · \(appState.accounts.count)" : "已连接账号 · \(appState.accounts.count)"
        var rows: [NSView] = []
        for a in appState.accounts {
            let (row, _) = buildAccountRow(account: a, width: width)
            rows.append(row)
        }
        // Add account row
        let addRow = buildAddAccountRow(isX: isX, width: width)
        rows.append(addRow)
        let g = settingsGroup(title: countTitle, rows: rows, width: width)
        g.view.frame.origin = CGPoint(x: 0, y: y)
        v.addSubview(g.view); y += g.height

        v.frame = NSRect(x: 22, y: 0, width: width, height: y + 8)
        return v
    }

    private func makeAccountsPaneSignature() -> String {
        let accounts = appState.accounts.map { account in
            [
                account.id ?? "",
                account.name,
                account.handle,
                account.platform.rawValue,
                account.avatarURL ?? "",
            ].joined(separator: ":")
        }.joined(separator: "|")
        return "\(appState.activeId)#\(accounts)"
    }

    private func buildAccountRow(account: Account, width: CGFloat) -> (view: FlippedView, height: CGFloat) {
        let padX: CGFloat = 14; let padY: CGFloat = 12
        let h: CGFloat = 58
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: h))
        // avatar
        let av = AvatarView(person: account, size: 34)
        av.frame = NSRect(x: padX, y: (h - 34) / 2, width: 34, height: 34)
        v.addSubview(av)
        let badge = PlatformBadge(platform: account.platform, size: 15)
        badge.frame = NSRect(x: padX + 34 - 5, y: (h - 34) / 2 + 34 - 5 - 1, width: 15, height: 15)
        v.addSubview(badge)
        // name row
        var nx: CGFloat = padX + 34 + 11
        let name = makeLabel(account.name, font: Fonts.sans(14, .bold), color: theme.fgHeading)
        name.frame = NSRect(x: nx, y: padY + 1, width: name.intrinsicContentSize.width, height: 17)
        v.addSubview(name)
        nx += name.intrinsicContentSize.width + 7
        if account.id == appState.activeId {
            let chip = FlippedView(frame: NSRect(x: nx, y: padY + 2, width: 0, height: 17))
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 5
            chip.layer?.backgroundColor = theme.accentBg.withAlphaComponent(0.14).cgColor
            let cl = makeLabel(isX ? "Active" : "当前", font: Fonts.sans(10, .heavy), color: theme.accent)
            cl.frame = NSRect(x: 6, y: 1, width: cl.intrinsicContentSize.width, height: 15)
            chip.addSubview(cl)
            chip.frame.size.width = cl.intrinsicContentSize.width + 12
            v.addSubview(chip)
        }
        // subtitle
        let subTxt = account.platform == .x ? "@\(account.handle) · X" : "微博 · \(account.followers ?? "") 粉丝"
        let sub = makeLabel(subTxt, font: Fonts.sans(12.5), color: theme.fgSubdued)
        sub.frame = NSRect(x: padX + 34 + 11, y: padY + 17 + 4, width: width - padX * 2 - 34 - 11 - 90, height: 15)
        v.addSubview(sub)
        // sign out button
        let signBtn = HoverControl(frame: NSRect(x: 0, y: 0, width: 80, height: 30))
        signBtn.wantsLayer = true
        signBtn.layer?.cornerRadius = 8
        signBtn.layer?.borderColor = theme.borderDefault.cgColor
        signBtn.layer?.borderWidth = 1
        let glyph = GlyphView(name: "signout", size: 13, color: theme.fgBody)
        glyph.frame = NSRect(x: 10, y: 8.5, width: 13, height: 13)
        signBtn.addSubview(glyph)
        let signLbl = makeLabel(isX ? "Sign out" : "退出", font: Fonts.sans(13, .semibold), color: theme.fgBody)
        signLbl.frame = NSRect(x: 27, y: (30 - signLbl.intrinsicContentSize.height) / 2, width: signLbl.intrinsicContentSize.width, height: signLbl.intrinsicContentSize.height)
        signBtn.addSubview(signLbl)
        signBtn.frame.size.width = 27 + signLbl.intrinsicContentSize.width + 12
        signBtn.frame.origin = CGPoint(x: width - padX - signBtn.frame.width, y: (h - 30) / 2)
        signBtn.onState = { [weak self] h, _ in
            guard let self else { return }
            signBtn.layer?.borderColor = (h ? self.theme.negative : self.theme.borderDefault).cgColor
            signBtn.layer?.backgroundColor = (h ? self.theme.negative.withAlphaComponent(0.12) : NSColor.clear).cgColor
            signLbl.textColor = h ? self.theme.negative : self.theme.fgBody
            glyph.color = h ? self.theme.negative : self.theme.fgBody
        }
        signBtn.onClick = { [weak self] in
            guard let self, let aid = account.id else { return }
            self.appState.removeAccount(aid)
        }
        v.addSubview(signBtn)
        _ = padY
        return (v, h)
    }

    private func buildAddAccountRow(isX: Bool, width: CGFloat) -> HoverControl {
        let padX: CGFloat = 14; let h: CGFloat = 54
        let v = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: h))
        v.wantsLayer = true
        let desc = makeLabel(isX ? "Connect another X or Weibo account." : "连接另一个 X 或微博账号。", font: Fonts.sans(12.5), color: theme.fgSubdued)
        desc.frame = NSRect(x: padX, y: h/2 + 2, width: width - padX * 2 - 40, height: 15)
        v.addSubview(desc)
        let lbl = makeLabel(isX ? "Add account" : "添加账号", font: Fonts.sans(14, .semibold), color: theme.accent)
        lbl.frame = NSRect(x: padX, y: h/2 - 17, width: width - padX * 2 - 40, height: 17)
        v.addSubview(lbl)
        let circle = FlippedView(frame: NSRect(x: width - padX - 28, y: (h - 28) / 2, width: 28, height: 28))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 14
        circle.layer?.borderColor = theme.gray400.cgColor
        circle.layer?.borderWidth = 1.5
        let plus = GlyphView(name: "add", size: 13, color: theme.fgSubdued)
        plus.frame = NSRect(x: 7.5, y: 7.5, width: 13, height: 13)
        circle.addSubview(plus)
        v.addSubview(circle)
        v.onState = { h, _ in
            v.layer?.backgroundColor = (h ? self.theme.gray75 : NSColor.clear).cgColor
            circle.layer?.borderColor = (h ? self.theme.accent : self.theme.gray400).cgColor
            plus.color = h ? self.theme.accent : self.theme.fgSubdued
        }
        v.onClick = { [weak self] in self?.appState.openAddAccount() }
        return v
    }

    private func buildAppearancePane(width: CGFloat) -> FlippedView {
        let v = FlippedView(); var y: CGFloat = 20; let isX = self.isX
        let currentMode = ThemeManager.shared.mode
        let modeVal: String
        switch currentMode {
        case .light: modeVal = "light"
        case .dark: modeVal = "dark"
        case .system: modeVal = "system"
        }
        let modeSeg = SegmentedPill(value: modeVal, options: [
            ("light", isX ? "Light" : "浅色", "sun"),
            ("dark",  isX ? "Dark"  : "深色", "moon"),
            ("system", isX ? "System" : "系统", nil),
        ])
        modeSeg.onChange = { [weak self] val in
            guard let self else { return }
            let newMode: ThemeMode = val == "light" ? .light : val == "dark" ? .dark : .system
            self.appState.setMode(newMode, root: nil)
        }

        let accentPick = AccentPickerView(value: ThemeManager.shared.accentId)
        accentPick.onChange = { [weak self] id in self?.appState.setAccent(id) }

        let g1 = settingsGroup(title: isX ? "Theme" : "主题", rows: [
            settingsRow(label: isX ? "Appearance" : "外观",
                        desc: isX ? "System follows your macOS light or dark setting." : "\u{201C}跟随系统\u{201D}将匹配 macOS 的浅色或深色设置。",
                        control: modeSeg, width: width).view,
            settingsRow(label: isX ? "Accent color" : "强调色",
                        desc: isX ? "Used for the primary action, links, and selection." : "用于主要操作、链接和选中状态。",
                        control: accentPick, width: width).view,
        ], width: width)
        g1.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g1.view); y += g1.height

        let g2 = settingsGroup(title: isX ? "Motion" : "动效", rows: [
            settingsRow(label: isX ? "Reduce motion" : "减弱动态效果",
                        desc: isX ? "Turn off sliding panels and transitions throughout the app." : "关闭应用内的面板滑动与过渡动画。",
                        control: makeToggle("reduceMotion"), width: width).view,
        ], width: width)
        g2.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g2.view); y += g2.height

        v.frame = NSRect(x: 22, y: 0, width: width, height: y + 8)
        return v
    }

    private func buildNotificationsPane(width: CGFloat) -> FlippedView {
        let v = FlippedView(); var y: CGFloat = 20; let isX = self.isX
        let g1 = settingsGroup(title: isX ? "Notify me about" : "通知我", rows: [
            settingsRow(label: isX ? "Mentions & replies" : "提及与回复", desc: nil, control: makeToggle("notifMentions"), width: width).view,
            settingsRow(label: isX ? "Reposts" : "转发", desc: nil, control: makeToggle("notifReposts"), width: width).view,
            settingsRow(label: isX ? "Likes" : "点赞", desc: nil, control: makeToggle("notifLikes"), width: width).view,
            settingsRow(label: isX ? "New followers" : "新粉丝", desc: nil, control: makeToggle("notifFollowers"), width: width).view,
        ], width: width)
        g1.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g1.view); y += g1.height

        let g2 = settingsGroup(title: isX ? "Delivery" : "提醒方式", rows: [
            settingsRow(label: isX ? "Play sound" : "播放提示音",
                        desc: isX ? "A subtle chime when a new notification arrives." : "新通知到达时播放轻柔提示音。",
                        control: makeToggle("notifSound"), width: width).view,
            settingsRow(label: isX ? "Show unread badge on Dock" : "在程序坞显示未读角标",
                        desc: isX ? "Display the total unread count on the app icon." : "在应用图标上显示未读总数。",
                        control: makeToggle("dockBadge"), width: width).view,
        ], width: width)
        g2.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g2.view); y += g2.height

        v.frame = NSRect(x: 22, y: 0, width: width, height: y + 8)
        return v
    }

    private func buildTimelinePane(width: CGFloat) -> FlippedView {
        let v = FlippedView(); var y: CGFloat = 20; let isX = self.isX
        let g = settingsGroup(title: isX ? "Content" : "内容", rows: [
            settingsRow(label: isX ? "Autoplay videos" : "自动播放视频",
                        desc: isX ? "Play videos as they scroll into view, muted." : "视频滚动到可见区域时静音自动播放。",
                        control: makeToggle("autoplay"), width: width).view,
            settingsRow(label: isX ? "Show link previews" : "显示链接预览",
                        desc: isX ? "Expand cards for shared articles and pages." : "为分享的文章和页面展开预览卡片。",
                        control: makeToggle("linkPreviews"), width: width).view,
            settingsRow(label: isX ? "Display sensitive media" : "显示敏感内容",
                        desc: isX ? "Show media that may contain sensitive content without a warning." : "直接显示可能含敏感内容的媒体，不再提示。",
                        control: makeToggle("sensitive"), width: width).view,
            settingsRow(label: isX ? "Open posts in a side pane" : "在侧栏中打开帖子",
                        desc: isX ? "Push post details within the column instead of a new window." : "在分栏内推入帖子详情，而非新窗口。",
                        control: makeToggle("detailPane"), width: width).view,
        ], width: width)
        g.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g.view); y += g.height

        v.frame = NSRect(x: 22, y: 0, width: width, height: y + 8)
        return v
    }

    private func buildDeveloperPane(width: CGFloat) -> FlippedView {
        let v = FlippedView(); var y: CGFloat = 20; let isX = self.isX

        let master = ToggleView(on: appState.debugEnabled)
        master.onChange = { [weak self] val in
            guard let self else { return }
            self.appState.debugEnabled = val
            self.switchCat("developer")
        }
        let g1 = settingsGroup(title: isX ? "Debugging" : "调试", rows: [
            settingsRow(label: isX ? "Debug tools" : "调试工具",
                        desc: isX ? "Expose raw data and a network log for inspecting the app." : "显示原始数据与网络请求日志，用于检查应用。",
                        control: master, width: width).view,
        ], width: width)
        g1.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g1.view); y += g1.height

        if appState.debugEnabled {
            let jsonToggle = ToggleView(on: appState.debugJsonInline)
            jsonToggle.onChange = { [weak self] val in self?.appState.debugJsonInline = val }
            let netToggle = ToggleView(on: appState.debugNetLog)
            netToggle.onChange = { [weak self] val in self?.appState.debugNetLog = val }
            let g2 = settingsGroup(title: isX ? "What to expose" : "调试内容", rows: [
                settingsRow(label: isX ? "Raw JSON on posts & timelines" : "帖子与时间线的原始 JSON",
                            desc: isX ? "Adds a code button to each tweet and column header to view its data." : "为每条帖子和分栏标题添加查看原始数据的按钮。",
                            control: jsonToggle, width: width).view,
                settingsRow(label: isX ? "Log network requests" : "记录网络请求",
                            desc: isX ? "Record every API call — URL and payload — with cookies and tokens stripped." : "记录每个接口调用（URL 与提交数据），并剔除 Cookie 与令牌。",
                            control: netToggle, width: width).view,
            ], width: width)
            g2.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g2.view); y += g2.height

            let g3 = settingsGroup(title: isX ? "Inspector" : "检查器", rows: [
                settingsRow(label: isX ? "Network & data inspector" : "网络与数据检查器",
                            desc: isX ? "Open the floating window. Also reachable from the sidebar." : "打开悬浮窗口，也可从侧边栏进入。",
                            control: makeInspectorOpenButton(), width: width).view,
            ], width: width)
            g3.view.frame.origin = CGPoint(x: 0, y: y); v.addSubview(g3.view); y += g3.height
        }

        v.frame = NSRect(x: 22, y: 0, width: width, height: y + 8)
        return v
    }

    private func makeInspectorOpenButton() -> HoverControl {
        let lbl = makeLabel(isX ? "Open" : "打开", font: Fonts.sans(13, .bold), color: .white, align: .center)
        let w = lbl.intrinsicContentSize.width + 32
        let btn = HoverControl(frame: NSRect(x: 0, y: 0, width: w, height: 32))
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 8
        btn.layer?.backgroundColor = theme.accentBg.cgColor
        lbl.frame = NSRect(x: 0, y: (32 - lbl.intrinsicContentSize.height) / 2, width: w, height: lbl.intrinsicContentSize.height)
        btn.addSubview(lbl)
        btn.onState = { h, p in btn.layer?.backgroundColor = (p ? self.theme.accentBgDown : h ? self.theme.accentBgHover : self.theme.accentBg).cgColor }
        btn.onClick = { [weak self] in
            guard let self else { return }
            self.appState.openInspector()
            self.close()
        }
        return btn
    }

    /// Snapshot hook — drive the pane selection from `debugApply`.
    func debugSwitchCat(_ id: String) { switchCat(id) }

    private func buildAboutPane(width: CGFloat) -> FlippedView {
        let v = FlippedView()
        let isX = self.isX
        let paneH: CGFloat = CARD_H - HEADER_H - 20
        v.frame = NSRect(x: 22, y: 0, width: width, height: paneH)

        // App icon — shared PerchIcon brand mark (white bird on the sky→ocean squircle)
        let iconSize: CGFloat = 80
        let iconX = (width - iconSize) / 2
        let iconY: CGFloat = 28
        let iconView = FlippedView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        iconView.wantsLayer = true
        iconView.layer?.masksToBounds = false
        iconView.layer?.shadowColor = PerchAppIcon.brandGlow.cgColor
        iconView.layer?.shadowOpacity = 0.30
        iconView.layer?.shadowRadius = iconSize * 0.14
        iconView.layer?.shadowOffset = CGSize(width: 0, height: -iconSize * 0.06)
        let iconImg = NSImageView(frame: NSRect(x: 0, y: 0, width: iconSize, height: iconSize))
        iconImg.image = PerchAppIcon.brandImage()
        iconImg.imageScaling = .scaleProportionallyUpOrDown
        iconView.addSubview(iconImg)
        v.addSubview(iconView)

        var ay = iconY + iconSize + 16
        let appName = makeLabel("Perch", font: Fonts.sans(24, .heavy), color: theme.fgHeading, align: .center)
        appName.frame = NSRect(x: 0, y: ay, width: width, height: 30)
        v.addSubview(appName); ay += 30

        let sub = makeLabel(isX ? "A calm multi-column reader for X & Weibo" : "X 与微博的多列阅读器", font: Fonts.sans(13.5), color: theme.fgSubdued, align: .center)
        sub.frame = NSRect(x: 0, y: ay + 3, width: width, height: 18)
        v.addSubview(sub); ay += 22

        let ver = makeLabel(isX ? "Version 2.4.1 (1840)" : "版本 2.4.1 (1840)", font: Fonts.sans(12.5), color: theme.fgDisabled, align: .center)
        ver.frame = NSRect(x: 0, y: ay + 10, width: width, height: 16)
        v.addSubview(ver); ay += 30

        let links = isX
            ? ["What\u{2019}s new", "Help & support", "Privacy policy", "Acknowledgements"]
            : ["更新内容", "帮助与支持", "隐私政策", "开源致谢"]
        var lx: CGFloat = 0
        var linkRow: [HoverControl] = []
        for link in links {
            let btn = HoverControl()
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 16
            btn.layer?.borderColor = theme.borderDefault.cgColor
            btn.layer?.borderWidth = 1
            let lbl = makeLabel(link, font: Fonts.sans(13, .semibold), color: theme.fgBody)
            lbl.frame = NSRect(x: 14, y: (30 - lbl.intrinsicContentSize.height) / 2, width: lbl.intrinsicContentSize.width, height: lbl.intrinsicContentSize.height)
            btn.addSubview(lbl)
            btn.frame = NSRect(x: lx, y: 0, width: lbl.intrinsicContentSize.width + 28, height: 32)
            btn.onState = { h, _ in btn.layer?.backgroundColor = (h ? self.theme.gray100 : NSColor.clear).cgColor }
            linkRow.append(btn)
            lx += btn.frame.width + 8
        }
        // center the link row
        let rowW = lx - 8
        let rowX = (width - rowW) / 2
        ay += 22
        for btn in linkRow {
            btn.frame.origin.x += rowX
            btn.frame.origin.y = ay
            v.addSubview(btn)
        }
        ay += 42

        let copy = makeLabel("© 2026 Riverside Studio", font: Fonts.sans(11.5), color: theme.fgDisabled, align: .center)
        copy.frame = NSRect(x: 0, y: ay, width: width, height: 14)
        v.addSubview(copy)

        return v
    }

    private func makeToggle(_ key: String) -> ToggleView {
        let on = prefs[key] as? Bool ?? false
        let t = ToggleView(on: on)
        t.onChange = { [weak self] val in self?.prefs[key] = val }
        return t
    }

    @objc private func refreshEveryChanged(_ sender: NSPopUpButton) {
        let opts = refreshOptions
        guard sender.indexOfSelectedItem >= 0, sender.indexOfSelectedItem < opts.count else { return }
        let val = opts[sender.indexOfSelectedItem].0
        prefs["refreshEvery"] = val
        appState.refreshEveryMinutes = val
    }

    // MARK: - Layout & Interaction

    override func layout() {
        super.layout()
        card.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
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

extension SettingsView: PanelContentView {
    var panelPreferredSize: CGSize { CGSize(width: CARD_W, height: CARD_H) }
    var panelTitle: String { isX ? "Settings" : "设置" }
    func attach(to panel: PanelWindowController) { panelController = panel }
}
