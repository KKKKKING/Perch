import AppKit

/// Generic 44×44 rail icon button.
final class RailIconButton: HoverControl {
    private let glyph: GlyphView
    private let accent: Bool
    private let active: Bool
    private let theme = ThemeManager.shared.theme

    init(icon: String, active: Bool, accent: Bool, title: String, badge: Int?, dot: Bool = false,
         onClick: @escaping () -> Void) {
        self.accent = accent
        self.active = active
        self.glyph = GlyphView(name: icon, size: 22, color: accent ? .white : (active ? theme.fgHeading : theme.fgSubdued))
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 12
        toolTip = title
        glyph.frame = NSRect(x: 11, y: 11, width: 22, height: 22)
        addSubview(glyph)
        applyBg(hover: false)
        if let b = badge, let nb = NotifBadge(count: b, ring: theme.bgLayer1, mini: false) {
            nb.frame.origin = CGPoint(x: 44 - nb.frame.width + 1, y: -1)
            addSubview(nb)
        }
        if dot {
            let d = FlippedView(frame: NSRect(x: 32, y: 8, width: 8, height: 8))
            d.wantsLayer = true
            d.layer?.cornerRadius = 4
            d.layer?.backgroundColor = theme.accentBg.cgColor
            d.layer?.borderColor = theme.bgLayer1.cgColor
            d.layer?.borderWidth = 1.5
            addSubview(d)
        }
        self.onClick = onClick
        self.onState = { [weak self] h, _ in self?.applyBg(hover: h) }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyBg(hover: Bool) {
        let bg: NSColor
        if accent { bg = theme.accentBg }
        else if active { bg = theme.gray200 }
        else if hover { bg = theme.gray100 }
        else { bg = .clear }
        layer?.backgroundColor = bg.cgColor
    }
}

/// Left icon rail: account switcher, nav, compose FAB, columns, settings.
final class IconRailView: FlippedView {
    private let appState: AppState
    private let onToggleColumns: () -> Void
    private let theme = ThemeManager.shared.theme

    private var accountButton: HoverControl!
    private var navButtons: [RailIconButton] = []
    private var fab: HoverControl!
    private var columnsBtn: RailIconButton!
    private var settingsBtn: RailIconButton!
    private var inspectorBtn: RailIconButton?
    private var moreBtn: RailIconButton!

    init(appState: AppState, onToggleColumns: @escaping () -> Void) {
        self.appState = appState
        self.onToggleColumns = onToggleColumns
        super.init(frame: NSRect(x: 0, y: 0, width: UI.railW, height: 800))
        bgColor = theme.bgLayer1
        autoresizingMask = [.height]
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var isX: Bool { appState.active.platform == .x }

    // ── Per-destination rail behavior (drives both the rail icons and the ⋯ menu) ──
    private struct RailItem {
        let glyph: String
        let active: Bool
        let title: String
        let badge: Int?
        let dot: Bool
        let action: () -> Void
    }

    private func railItem(for id: String) -> RailItem? {
        guard let meta = NAV_ITEMS[id] else { return nil }
        let primary = appState.primaryType
        let title = isX ? meta.labelX : meta.labelW
        switch id {
        case "home":
            return RailItem(glyph: meta.glyph, active: primary == "home", title: title, badge: nil,
                            dot: appState.timelineUnreadCount(type: "home") > 0,
                            action: { [weak self] in self?.appState.setPrimaryType("home") })
        case "mentions":
            return RailItem(glyph: meta.glyph, active: primary == "mentions", title: title,
                            badge: appState.unread[appState.activeId], dot: false,
                            action: { [weak self] in self?.appState.viewMentions() })
        case "search":
            return RailItem(glyph: meta.glyph, active: primary == "search", title: title, badge: nil,
                            dot: appState.timelineUnreadCount(type: "search") > 0,
                            action: { [weak self] in self?.appState.setPrimaryType("search") })
        case "profile":
            return RailItem(glyph: meta.glyph, active: false, title: title, badge: nil, dot: false,
                            action: { [weak self] in self?.appState.openOwnProfile() })
        default: // bookmarks, likes, lists
            return RailItem(glyph: meta.glyph, active: primary == id, title: title, badge: nil,
                            dot: appState.timelineUnreadCount(type: id) > 0,
                            action: { [weak self] in self?.appState.setPrimaryType(id) })
        }
    }

    private func build() {
        // right border
        let border = NSView(frame: NSRect(x: UI.railW - 1, y: 0, width: 1, height: bounds.height))
        border.wantsLayer = true
        border.layer?.backgroundColor = theme.borderDefault.cgColor
        border.autoresizingMask = [.height]
        addSubview(border)

        // account switcher (below reserved traffic-light area)
        let acct = appState.active
        let btn = HoverControl(frame: NSRect(x: (UI.railW - 46) / 2, y: 48, width: 46, height: 46))
        let ring = FlippedView(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
        ring.wantsLayer = true
        ring.layer?.cornerRadius = 23
        ring.layer?.backgroundColor = theme.accent.cgColor
        let av = AvatarView(person: acct, size: 42)
        av.frame = NSRect(x: 2, y: 2, width: 42, height: 42)
        ring.addSubview(av)
        btn.addSubview(ring)
        // chevron chip bottom-right
        let chip = FlippedView(frame: NSRect(x: 46 - 16 + 2, y: 46 - 16 + 2, width: 16, height: 16))
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 8
        chip.layer?.backgroundColor = theme.bgLayer1.cgColor
        chip.layer?.borderColor = theme.borderDefault.cgColor
        chip.layer?.borderWidth = 1
        let chev = GlyphView(name: "chevron-down", size: 13, color: theme.fgSubdued)
        chev.frame = NSRect(x: 1.5, y: 1.5, width: 13, height: 13)
        chip.addSubview(chev)
        btn.addSubview(chip)
        // other-account unread dot
        if appState.othersHaveUnread {
            let dot = FlippedView(frame: NSRect(x: 46 - 9 - 2, y: 2, width: 9, height: 9))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4.5
            dot.layer?.backgroundColor = theme.accent.cgColor
            dot.layer?.borderColor = theme.bgLayer1.cgColor
            dot.layer?.borderWidth = 2
            btn.addSubview(dot)
        }
        btn.toolTip = acct.name + (appState.othersHaveUnread ? (isX ? " · unread on other accounts" : " · 其他账号有未读") : (isX ? " · click to switch" : " · 点击切换账号"))
        btn.onClick = { [weak self] in self?.showAccountPopover() }
        addSubview(btn)
        accountButton = btn

        // divider
        let div = NSView(frame: NSRect(x: (UI.railW - 34) / 2, y: 104, width: 34, height: 1))
        div.wantsLayer = true
        div.layer?.backgroundColor = theme.borderDefault.cgColor
        addSubview(div)

        // nav group
        let primary = appState.primaryType
        let cx = (UI.railW - 44) / 2
        var ny: CGFloat = 112
        func addNav(_ icon: String, active: Bool, title: String, badge: Int?, dot: Bool = false,
                    onClick: @escaping () -> Void) {
            let b = RailIconButton(icon: icon, active: active, accent: false, title: title, badge: badge,
                                   dot: dot, onClick: onClick)
            b.frame.origin = CGPoint(x: cx, y: ny)
            addSubview(b)
            navButtons.append(b)
            ny += 48
        }
        for id in appState.navConfig.bar {
            guard let it = railItem(for: id) else { continue }
            addNav(it.glyph, active: it.active, title: it.title, badge: it.badge, dot: it.dot, onClick: it.action)
        }
        let menu = appState.navConfig.menu
        let moreActive = menu.contains(primary)
        let moreDot = menu.contains { id in
            guard let it = railItem(for: id) else { return false }
            return it.dot || (it.badge ?? 0) > 0
        }
        let more = RailIconButton(icon: "more", active: moreActive, accent: false,
                                  title: isX ? "More" : "更多", badge: nil, dot: moreDot) { [weak self] in self?.showMorePopover() }
        more.frame.origin = CGPoint(x: cx, y: ny)
        addSubview(more)
        moreBtn = more

        // bottom group
        fab = HoverControl(frame: NSRect(x: (UI.railW - 48) / 2, y: 0, width: 48, height: 48))
        fab.wantsLayer = true
        fab.layer?.cornerRadius = 24
        fab.layer?.backgroundColor = theme.accentBg.cgColor
        let pencil = GlyphView(name: "pencil", size: 22, color: .white)
        pencil.frame = NSRect(x: 13, y: 13, width: 22, height: 22)
        fab.addSubview(pencil)
        fab.toolTip = isX ? "New post (c)" : "发新微博 (c)"
        fab.onClick = { [weak self] in self?.appState.openCompose() }
        addSubview(fab)

        columnsBtn = RailIconButton(icon: "columns", active: false, accent: false, title: isX ? "Columns" : "分栏设置", badge: nil) { [weak self] in self?.onToggleColumns() }
        addSubview(columnsBtn)
        settingsBtn = RailIconButton(icon: "settings", active: appState.settingsOpen, accent: false, title: "Settings", badge: nil) { [weak self] in self?.appState.openSettings() }
        addSubview(settingsBtn)

        if appState.debugEnabled {
            let insp = RailIconButton(icon: "code", active: appState.inspectorOpen, accent: false,
                                      title: isX ? "Inspector" : "调试检查器", badge: nil,
                                      dot: !DebugLog.shared.entries.isEmpty) { [weak self] in self?.appState.openInspector() }
            addSubview(insp)
            inspectorBtn = insp
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let H = bounds.height
        let cx = (UI.railW - 44) / 2
        // Bottom-up running offset so the cluster stays correct with or without the inspector button.
        var y = H - 14 - 44
        settingsBtn.frame.origin = CGPoint(x: cx, y: y)
        if let insp = inspectorBtn {
            y -= 8 + 44
            insp.frame.origin = CGPoint(x: cx, y: y)
        }
        y -= 8 + 44
        columnsBtn.frame.origin = CGPoint(x: cx, y: y)
        y -= 8 + 48
        fab.frame.origin = CGPoint(x: (UI.railW - 48) / 2, y: y)
    }

    // ── Account popover ──
    func debugShowAccount() { showAccountPopover() }
    func debugShowMore() { showMorePopover() }

    private func showAccountPopover() {
        let theme = self.theme
        let isX = self.isX
        let w: CGFloat = 268
        let inner = w - 12
        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        var y: CGFloat = 6

        // header
        let hdr = makeLabel(isX ? "Accounts" : "账号", font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        hdr.frame = NSRect(x: 16, y: y + 4, width: inner - 60, height: 14)
        content.addSubview(hdr)
        let totalUnread = appState.totalUnread
        if totalUnread > 0, let nb = NotifBadge(count: totalUnread, ring: theme.bgElevated, mini: true) {
            nb.frame.origin = CGPoint(x: w - 16 - nb.frame.width - 48, y: y)
            content.addSubview(nb)
            let u = makeLabel(isX ? "unread" : "条未读", font: Fonts.sans(11.5, .semibold), color: theme.fgSubdued)
            u.frame = NSRect(x: w - 16 - 46, y: y + 3, width: 46, height: 14)
            content.addSubview(u)
        }
        y += 26

        for a in appState.accounts {
            let on = a.id == appState.activeId
            let row = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 46))
            row.wantsLayer = true
            row.layer?.cornerRadius = 9
            if on { row.layer?.backgroundColor = theme.gray100.cgColor }
            let av = AvatarView(person: a, size: 32)
            av.frame = NSRect(x: 10, y: 7, width: 32, height: 32)
            row.addSubview(av)
            let badge = PlatformBadge(platform: a.platform, size: 15)
            badge.frame = NSRect(x: 10 + 20, y: 7 + 20, width: 15, height: 15)
            row.addSubview(badge)
            let unread = appState.unread[a.id!] ?? 0
            if let nb = NotifBadge(count: unread, ring: theme.bgElevated, mini: true) {
                nb.frame.origin = CGPoint(x: 2, y: 0)
                row.addSubview(nb)
            }
            let nm = makeLabel(a.name, font: Fonts.sans(14, .bold), color: theme.fgHeading)
            nm.frame = NSRect(x: 52, y: 8, width: inner - 52 - 26, height: 17)
            row.addSubview(nm)
            let subT: String
            if unread > 0 {
                subT = isX ? "\(unread) new notification\(unread > 1 ? "s" : "")" : "\(unread) 条新通知"
            } else {
                subT = a.platform == .x ? "@\(a.handle) · X" : "微博"
            }
            let sub = makeLabel(subT, font: Fonts.sans(12), color: theme.fgSubdued)
            sub.frame = NSRect(x: 52, y: 25, width: inner - 52 - 26, height: 15)
            row.addSubview(sub)
            if on {
                let ck = GlyphView(name: "checkmark", size: 17, color: theme.accent)
                ck.frame = NSRect(x: inner - 27, y: 15, width: 17, height: 17)
                row.addSubview(ck)
            }
            row.onState = { h, _ in if !on { row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor } }
            row.onClick = { [weak self] in
                gPopoverHost?.dismissPopover()
                self?.appState.setActive(a.id!)
            }
            content.addSubview(row)
            y += 46
        }

        // add account (noop)
        let add = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 46))
        add.wantsLayer = true
        add.layer?.cornerRadius = 9
        let circ = FlippedView(frame: NSRect(x: 10, y: 7, width: 32, height: 32))
        circ.wantsLayer = true
        circ.layer?.cornerRadius = 16
        circ.layer?.borderColor = theme.gray400.cgColor
        circ.layer?.borderWidth = 1.5
        let plus = GlyphView(name: "add", size: 15, color: theme.fgSubdued)
        plus.frame = NSRect(x: 8.5, y: 8.5, width: 15, height: 15)
        circ.addSubview(plus)
        add.addSubview(circ)
        let addLbl = makeLabel(isX ? "Add account" : "添加账号", font: Fonts.sans(14, .semibold), color: theme.fgSubdued)
        addLbl.frame = NSRect(x: 52, y: 15, width: inner - 60, height: 17)
        add.addSubview(addLbl)
        add.onState = { h, _ in add.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor }
        add.onClick = { [weak self] in
            gPopoverHost?.dismissPopover()
            self?.appState.openAddAccount()
        }
        content.addSubview(add)
        y += 46

        // divider
        let div = NSView(frame: NSRect(x: 8, y: y + 6, width: inner - 4, height: 1))
        div.wantsLayer = true
        div.layer?.backgroundColor = theme.borderDefault.cgColor
        content.addSubview(div)
        y += 13

        // appearance segmented
        let apLbl = makeLabel(isX ? "Appearance" : "外观", font: Fonts.sans(13, .semibold), color: theme.fgSubdued)
        apLbl.frame = NSRect(x: 16, y: y + 8, width: 100, height: 17)
        content.addSubview(apLbl)
        let seg = FlippedView(frame: NSRect(x: w - 16 - 132, y: y + 4, width: 132, height: 28))
        seg.wantsLayer = true
        seg.layer?.cornerRadius = 14
        seg.layer?.backgroundColor = theme.gray100.cgColor
        let modes: [(ThemeMode, String)] = [(.light, isX ? "Light" : "浅色"), (.dark, isX ? "Dark" : "深色")]
        for (i, m) in modes.enumerated() {
            let selected = appState.mode == m.0
            let sel = HoverControl(frame: NSRect(x: 2 + CGFloat(i) * 64, y: 2, width: 62, height: 24))
            sel.wantsLayer = true
            sel.layer?.cornerRadius = 12
            if selected { sel.layer?.backgroundColor = theme.bgElevated.cgColor }
            let l = makeLabel(m.1, font: Fonts.sans(12.5, .semibold), color: selected ? theme.fgHeading : theme.fgSubdued, align: .center)
            l.frame = NSRect(x: 0, y: (24 - l.intrinsicContentSize.height) / 2, width: 62, height: l.intrinsicContentSize.height)
            sel.addSubview(l)
            sel.onClick = { [weak self] in
                gPopoverHost?.dismissPopover()
                self?.appState.setMode(m.0, root: nil)
            }
            seg.addSubview(sel)
        }
        content.addSubview(seg)
        y += 40

        content.frame = NSRect(x: 0, y: 0, width: w, height: y)
        gPopoverHost?.presentPopover(content, width: w, height: y, anchor: accountButton, edge: .right, dx: 0, dy: 0)
    }

    // ── More-lists popover ──
    private func showMorePopover() {
        let theme = self.theme
        let isX = self.isX
        let w: CGFloat = 190
        let inner = w - 12
        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 12
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        var y: CGFloat = 6
        let hdr = makeLabel(isX ? "More" : "更多", font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        hdr.frame = NSRect(x: 16, y: y + 4, width: inner, height: 14)
        content.addSubview(hdr)
        y += 26
        for id in appState.navConfig.menu {
            guard let it = railItem(for: id) else { continue }
            let on = it.active
            let row = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 36))
            row.wantsLayer = true
            row.layer?.cornerRadius = 9
            if on { row.layer?.backgroundColor = theme.gray100.cgColor }
            let g = GlyphView(name: it.glyph, size: 19, color: theme.fgSubdued)
            g.frame = NSRect(x: 10, y: 8, width: 19, height: 19)
            row.addSubview(g)
            let l = makeLabel(it.title, font: Fonts.sans(14, .semibold), color: theme.fgBody)
            l.frame = NSRect(x: 40, y: (36 - l.intrinsicContentSize.height) / 2, width: inner - 70, height: l.intrinsicContentSize.height)
            row.addSubview(l)
            if on {
                let ck = GlyphView(name: "checkmark", size: 16, color: theme.accent)
                ck.frame = NSRect(x: inner - 26, y: 10, width: 16, height: 16)
                row.addSubview(ck)
            }
            row.onState = { h, _ in if !on { row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor } }
            row.onClick = {
                gPopoverHost?.dismissPopover()
                it.action()
            }
            content.addSubview(row)
            y += 36
        }
        // divider + Configure row (always present — the only entry point to the dialog)
        let cdiv = NSView(frame: NSRect(x: 8, y: y + 6, width: inner - 4, height: 1))
        cdiv.wantsLayer = true
        cdiv.layer?.backgroundColor = theme.borderDefault.cgColor
        content.addSubview(cdiv)
        y += 13
        let cfg = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 36))
        cfg.wantsLayer = true
        cfg.layer?.cornerRadius = 9
        let cg = GlyphView(name: "gear", size: 19, color: theme.fgSubdued)
        cg.frame = NSRect(x: 10, y: 8, width: 19, height: 19)
        cfg.addSubview(cg)
        let cl = makeLabel(isX ? "Configure…" : "自定义…", font: Fonts.sans(14, .semibold), color: theme.fgBody)
        cl.frame = NSRect(x: 40, y: (36 - cl.intrinsicContentSize.height) / 2, width: inner - 50, height: cl.intrinsicContentSize.height)
        cfg.addSubview(cl)
        cfg.onState = { h, _ in cfg.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor }
        cfg.onClick = { [weak self] in
            gPopoverHost?.dismissPopover()
            self?.appState.openNavConfig()
        }
        content.addSubview(cfg)
        y += 36
        y += 6
        content.frame = NSRect(x: 0, y: 0, width: w, height: y)
        gPopoverHost?.presentPopover(content, width: w, height: y, anchor: moreBtn, edge: .right, dx: 0, dy: -6)
    }
}
