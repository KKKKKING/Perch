import AppKit

/// iOS-style back nav bar for a pushed screen.
final class BackHeader: FlippedView {
    private let refreshGlyph: GlyphView

    init(title: String, isX: Bool, onBack: @escaping () -> Void, onRefresh: @escaping () -> Void) {
        let theme = ThemeManager.shared.theme
        self.refreshGlyph = GlyphView(name: "refresh", size: 18, color: theme.fgSubdued)
        super.init(frame: NSRect(x: 0, y: 0, width: UI.columnW, height: 54))
        bgColor = theme.bgBase

        let back = HoverControl(frame: NSRect(x: 4, y: 10, width: 40, height: 34))
        back.wantsLayer = true
        back.layer?.cornerRadius = 9
        let chev = GlyphView(name: "chevron-down", size: 23, color: theme.accent)
        chev.rotationDegrees = 90
        chev.frame = NSRect(x: 6, y: 5.5, width: 23, height: 23)
        back.addSubview(chev)
        back.onClick = onBack
        back.onState = { h, _ in back.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor }
        addSubview(back)

        let titleLabel = makeLabel(title, font: Fonts.sans(16, .heavy), color: theme.fgHeading, align: .center)
        titleLabel.placeSingleLine(x: 52, y: 0, width: UI.columnW - 104, height: 54)
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)

        let refreshBtn = HoverControl(frame: NSRect(x: UI.columnW - 8 - 30, y: 12, width: 30, height: 30))
        refreshBtn.autoresizingMask = [.minXMargin]
        refreshBtn.wantsLayer = true
        refreshBtn.layer?.cornerRadius = 8
        refreshGlyph.frame = NSRect(x: 6, y: 6, width: 18, height: 18)
        refreshBtn.addSubview(refreshGlyph)
        refreshBtn.toolTip = isX ? "Refresh" : "刷新"
        refreshBtn.onState = { h, _ in
            refreshBtn.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor
            self.refreshGlyph.color = h ? theme.fgHeading : theme.fgSubdued
        }
        refreshBtn.onClick = { [weak self] in self?.spin(); onRefresh() }
        addSubview(refreshBtn)

        // bottom border
        let line = NSView(frame: NSRect(x: 0, y: 53, width: UI.columnW, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        line.autoresizingMask = [.width]
        addSubview(line)
        autoresizingMask = [.width]
    }
    required init?(coder: NSCoder) { fatalError() }

    private func spin() {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0
        anim.toValue = -CGFloat.pi * 2
        anim.duration = 0.7
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.4, 1)
        refreshGlyph.wantsLayer = true
        refreshGlyph.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let f = refreshGlyph.frame
        refreshGlyph.layer?.position = CGPoint(x: f.midX, y: f.midY)
        refreshGlyph.layer?.add(anim, forKey: "spin")
    }
}

private final class HeaderTitleButton: HoverControl {
    private let icon: GlyphView
    private let titleLabel: NSTextField
    private let chevron: GlyphView
    private let titleW: CGFloat
    private static let gap: CGFloat = 8
    private static let iconSize: CGFloat = 19
    private static let chevSize: CGFloat = 14

    init(iconName: String, title: String, theme: Theme) {
        self.icon = GlyphView(name: iconName, size: Self.iconSize, color: theme.fgHeading)
        self.titleLabel = makeLabel(title, font: Fonts.sans(16, .heavy), color: theme.fgHeading)
        self.chevron = GlyphView(name: "chevron-down", size: Self.chevSize, color: theme.fgSubdued)
        self.titleW = titleLabel.perchSingleLineWidth
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        addSubview(icon)
        addSubview(titleLabel)
        addSubview(chevron)
    }
    required init?(coder: NSCoder) { fatalError() }

    func preferredWidth(maxWidth: CGFloat) -> CGFloat {
        let contentW = Self.iconSize + Self.gap + titleW + Self.gap + Self.chevSize
        return min(contentW, max(0, maxWidth))
    }

    override func layout() {
        super.layout()
        let gap = Self.gap
        let iconSize = Self.iconSize
        let chevSize = Self.chevSize
        let availableTitleW = max(0, bounds.width - iconSize - chevSize - gap * 2)
        let labelW = min(titleW, availableTitleW)
        let groupW = iconSize + gap + labelW + gap + chevSize
        var x = floor((bounds.width - groupW) / 2)
        if x < 0 { x = 0 }
        icon.frame = NSRect(x: x, y: floor((bounds.height - iconSize) / 2), width: iconSize, height: iconSize)
        x += iconSize + gap
        titleLabel.placeSingleLine(x: x, y: 0, width: labelW, height: bounds.height)
        x += labelW + gap
        chevron.frame = NSRect(x: x, y: floor((bounds.height - chevSize) / 2), width: chevSize, height: chevSize)
    }
}

/// Timeline header: account avatar + title/account switcher menu + refresh.
final class TimelineHeaderView: FlippedView {
    private let appState: AppState
    private let col: ColumnSpec
    private let isFirst: Bool
    private let onOpenProfile: (Person) -> Void
    private let onRefresh: () -> Void
    private let onClearReload: () -> Void
    private let theme = ThemeManager.shared.theme
    private let refreshGlyph: GlyphView
    private var titleButton: HeaderTitleButton!
    private var refreshButton: HoverControl!
    private var jsonButton: HoverControl?
    private var bottomLine: NSView!

    init(appState: AppState, col: ColumnSpec, isFirst: Bool, onOpenProfile: @escaping (Person) -> Void, onRefresh: @escaping () -> Void, onClearReload: @escaping () -> Void) {
        self.appState = appState
        self.col = col
        self.isFirst = isFirst
        self.onOpenProfile = onOpenProfile
        self.onRefresh = onRefresh
        self.onClearReload = onClearReload
        self.refreshGlyph = GlyphView(name: "refresh", size: 18, color: theme.fgSubdued)
        super.init(frame: NSRect(x: 0, y: 0, width: UI.columnW, height: 54))
        bgColor = theme.bgBase
        autoresizingMask = [.width]
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var account: Account { appState.colAccount(col) }

    private func build() {
        let theme = self.theme
        let isX = account.platform == .x
        let meta = colMeta(col.type)
        var title = isX ? meta.labelX : meta.labelW
        if col.type == "lists", let name = appState.listSelectionName(for: col) { title = name }
        let padX: CGFloat = 8

        let hideAvatar = isFirst || account.id == appState.active.id
        if !hideAvatar {
            let wrap = HoverControl(frame: NSRect(x: padX, y: 14, width: 26, height: 26))
            let avatar = AvatarView(person: account, size: 26)
            avatar.frame = NSRect(x: 0, y: 0, width: 26, height: 26)
            wrap.addSubview(avatar)
            let badge = PlatformBadge(platform: account.platform, size: 12)
            badge.frame = NSRect(x: 17, y: 17, width: 12, height: 12)
            wrap.addSubview(badge)
            wrap.onClick = { [weak self] in guard let self else { return }; self.onOpenProfile(self.account) }
            addSubview(wrap)
        }

        let refreshX = bounds.width - padX - 30

        let btn = HeaderTitleButton(iconName: meta.icon, title: title, theme: theme)
        btn.onClick = { [weak self] in self?.showMenu() }
        addSubview(btn)
        titleButton = btn

        let refreshBtn = HoverControl(frame: NSRect(x: refreshX, y: 12, width: 30, height: 30))
        refreshBtn.wantsLayer = true
        refreshBtn.layer?.cornerRadius = 8
        refreshGlyph.frame = NSRect(x: 6, y: 6, width: 18, height: 18)
        refreshBtn.addSubview(refreshGlyph)
        refreshBtn.toolTip = isX ? "Refresh — right-click for more" : "刷新 · 右键查看更多"
        refreshBtn.onState = { h, _ in
            refreshBtn.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor
            self.refreshGlyph.color = h ? theme.fgHeading : theme.fgSubdued
        }
        refreshBtn.onClick = { [weak self] in self?.spin(); self?.onRefresh() }
        refreshBtn.onRightClick = { [weak self] in self?.showReloadMenu() }
        addSubview(refreshBtn)
        refreshButton = refreshBtn

        // debug: whole-column raw-JSON button, left of refresh
        if DebugLog.shared.inline {
            let jb = HoverControl(frame: NSRect(x: refreshX - 6 - 30, y: 12, width: 30, height: 30))
            jb.wantsLayer = true
            jb.layer?.cornerRadius = 8
            let jg = GlyphView(name: "code", size: 17, color: theme.fgSubdued)
            jg.frame = NSRect(x: 6.5, y: 6.5, width: 17, height: 17)
            jb.addSubview(jg)
            jb.toolTip = isX ? "View column data" : "查看分栏数据"
            jb.onState = { h, _ in
                jb.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor
                jg.color = h ? theme.fgHeading : theme.fgSubdued
            }
            jb.onClick = { [weak self] in self?.openColumnJson() }
            addSubview(jb)
            jsonButton = jb
        }

        let line = NSView(frame: NSRect(x: 0, y: 53, width: UI.columnW, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        addSubview(line)
        bottomLine = line
        layoutHeaderControls()
    }

    override func layout() {
        super.layout()
        layoutHeaderControls()
    }

    private func layoutHeaderControls() {
        guard let titleButton, let refreshButton, let bottomLine else { return }
        let padX: CGFloat = 8
        let refreshW: CGFloat = 30
        let refreshGap: CGFloat = 6
        let leftLimit = padX + 34 + 6
        var rightLimit = bounds.width - padX - refreshW - refreshGap
        if let jsonButton {
            jsonButton.frame = NSRect(x: bounds.width - padX - refreshW - 6 - 30, y: 12, width: 30, height: 30)
            rightLimit -= 30 + 6
        }
        let availableW = max(0, rightLimit - leftLimit)
        let titleW = titleButton.preferredWidth(maxWidth: availableW)
        let centeredX = floor((bounds.width - titleW) / 2)
        let maxX = rightLimit - titleW
        let x = maxX >= leftLimit ? min(max(centeredX, leftLimit), maxX) : leftLimit

        titleButton.frame = NSRect(x: x, y: 7, width: titleW, height: 40)
        refreshButton.frame = NSRect(x: bounds.width - padX - refreshW, y: 12, width: refreshW, height: 30)
        bottomLine.frame = NSRect(x: 0, y: 53, width: bounds.width, height: 1)
    }

    private func spin() {
        let anim = CABasicAnimation(keyPath: "transform.rotation.z")
        anim.fromValue = 0; anim.toValue = -CGFloat.pi * 2; anim.duration = 0.7
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.4, 1)
        refreshGlyph.wantsLayer = true
        refreshGlyph.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        let f = refreshGlyph.frame
        refreshGlyph.layer?.position = CGPoint(x: f.midX, y: f.midY)
        refreshGlyph.layer?.add(anim, forKey: "spin")
    }

    private func showMenu() {
        let theme = self.theme
        let isX = account.platform == .x
        let w: CGFloat = 264
        let inner = w - 12
        let multiAccount = appState.accounts.count > 1
        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 14
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true

        var y: CGFloat = 6
        func sectionLabel(_ text: String) {
            let l = makeLabel(text, font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
            l.frame = NSRect(x: 16, y: y + 4, width: inner, height: 14)
            content.addSubview(l)
            y += 26
        }
        sectionLabel(isX ? "Show" : "显示")
        for t in COL_TYPES {
            let m = colMeta(t)
            let on = t == col.type
            let row = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 34))
            row.wantsLayer = true
            row.layer?.cornerRadius = 9
            if on { row.layer?.backgroundColor = theme.gray100.cgColor }
            let g = GlyphView(name: m.icon, size: 19, color: theme.fgSubdued)
            g.frame = NSRect(x: 10, y: 7, width: 19, height: 19)
            row.addSubview(g)
            let l = makeLabel(isX ? m.labelX : m.labelW, font: Fonts.sans(14, .semibold), color: theme.fgBody)
            l.placeSingleLine(x: 40, y: 0, width: inner - 70, height: 34)
            row.addSubview(l)
            if on {
                let ck = GlyphView(name: "checkmark", size: 16, color: theme.accent)
                ck.frame = NSRect(x: inner - 26, y: 9, width: 16, height: 16)
                row.addSubview(ck)
            }
            row.onState = { h, _ in if !on { row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor } }
            row.onClick = { [weak self] in
                gPopoverHost?.dismissPopover()
                self?.appState.setColType(self!.col.id, t)
            }
            content.addSubview(row)
            y += 34
        }

        if col.type == "lists" {
            let div = NSView(frame: NSRect(x: 8, y: y + 6, width: inner - 4, height: 1))
            div.wantsLayer = true
            div.layer?.backgroundColor = theme.borderDefault.cgColor
            content.addSubview(div)
            y += 13
            sectionLabel(isX ? "Lists" : "列表")
            let lists = appState.lists(for: col)
            let selected = appState.listSelection[col.id]
            if lists.isEmpty {
                let msg = appState.listsAreLoading
                    ? (isX ? "Loading lists…" : "正在加载列表…")
                    : (isX ? "No lists yet" : "暂无列表")
                let l = makeLabel(msg, font: Fonts.sans(13.5, .medium), color: theme.fgSubdued)
                l.frame = NSRect(x: 16, y: y + 4, width: inner - 24, height: 18)
                content.addSubview(l)
                y += 30
            }
            for list in lists {
                let on = list.id == selected
                let row = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 44))
                row.wantsLayer = true
                row.layer?.cornerRadius = 9
                if on { row.layer?.backgroundColor = theme.gray100.cgColor }
                let g = GlyphView(name: "list", size: 18, color: theme.fgSubdued)
                g.frame = NSRect(x: 11, y: 13, width: 18, height: 18)
                row.addSubview(g)
                let nm = makeLabel(list.name, font: Fonts.sans(14, .semibold), color: theme.fgBody)
                nm.placeSingleLine(x: 40, y: 6, width: inner - 40 - 30, height: 17)
                row.addSubview(nm)
                let subT = isX ? "\(list.memberCount) members" : "\(list.memberCount) 名成员"
                let sub = makeLabel(subT, font: Fonts.sans(11.5, .medium), color: theme.fgSubdued)
                sub.frame = NSRect(x: 40, y: 24, width: inner - 40 - 30, height: 14)
                row.addSubview(sub)
                if on {
                    let ck = GlyphView(name: "checkmark", size: 16, color: theme.accent)
                    ck.frame = NSRect(x: inner - 26, y: 14, width: 16, height: 16)
                    row.addSubview(ck)
                }
                row.onState = { h, _ in if !on { row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor } }
                row.onClick = { [weak self] in
                    gPopoverHost?.dismissPopover()
                    self?.appState.setListSelection(self!.col.id, list.id)
                }
                content.addSubview(row)
                y += 44
            }
        }

        if multiAccount {
            let div = NSView(frame: NSRect(x: 8, y: y + 6, width: inner - 4, height: 1))
            div.wantsLayer = true
            div.layer?.backgroundColor = theme.borderDefault.cgColor
            content.addSubview(div)
            y += 13
            sectionLabel(isX ? "Account" : "账号")
            for a in appState.accounts {
                let on = a.id == account.id
                let row = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 44))
                row.wantsLayer = true
                row.layer?.cornerRadius = 9
                if on { row.layer?.backgroundColor = theme.gray100.cgColor }
                let av = AvatarView(person: a, size: 28)
                av.frame = NSRect(x: 10, y: 8, width: 28, height: 28)
                row.addSubview(av)
                let badge = PlatformBadge(platform: a.platform, size: 13)
                badge.frame = NSRect(x: 10 + 18, y: 8 + 18, width: 13, height: 13)
                row.addSubview(badge)
                if let nb = NotifBadge(count: appState.unread[a.id!] ?? 0, ring: theme.bgElevated, mini: true) {
                    nb.frame.origin = CGPoint(x: 2, y: 1)
                    row.addSubview(nb)
                }
                let nm = makeLabel(a.name, font: Fonts.sans(13.5, .bold), color: theme.fgHeading)
                nm.frame = NSRect(x: 48, y: 7, width: inner - 48 - 26, height: 17)
                row.addSubview(nm)
                let subT = a.platform == .x ? "@\(a.handle) · X" : "微博"
                let sub = makeLabel(subT, font: Fonts.sans(11.5, .medium), color: theme.fgSubdued)
                sub.frame = NSRect(x: 48, y: 24, width: inner - 48 - 26, height: 14)
                row.addSubview(sub)
                if on {
                    let ck = GlyphView(name: "checkmark", size: 16, color: theme.accent)
                    ck.frame = NSRect(x: inner - 26, y: 14, width: 16, height: 16)
                    row.addSubview(ck)
                }
                row.onState = { h, _ in if !on { row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor } }
                row.onClick = { [weak self] in
                    gPopoverHost?.dismissPopover()
                    self?.appState.setColAccount(self!.col.id, a.id!)
                }
                content.addSubview(row)
                y += 44
            }
        }
        y += 6
        content.frame = NSRect(x: 0, y: 0, width: w, height: y)
        let dx = floor((titleButton.bounds.width - w) / 2)
        gPopoverHost?.presentPopover(content, width: w, height: y, anchor: titleButton, edge: .below, dx: dx, dy: 0)
    }

    /// Open a JSON viewer window over this whole column's current posts.
    private func openColumnJson() {
        let isX = account.platform == .x
        let meta = colMeta(col.type)
        var title = isX ? meta.labelX : meta.labelW
        if col.type == "lists", let name = appState.listSelectionName(for: col) { title = name }
        var sub = "@\(account.handle) · \(col.type)"
        if col.type == "home" { sub += "/\(col.feed)" }
        let json = DebugJSON.array(appState.postsFor(col).map { DebugJSON.from(post: $0) })
        appState.openJsonViewer(JsonViewerContext(title: "\(title) · \(account.name)", subtitle: sub, json: json))
    }

    /// Debug hook: open the reload menu without a right-click (PERCH_STATE=reloadmenu).
    func debugShowReloadMenu() { showReloadMenu() }

    /// Debug hook: open the title (column-type / list-picker) menu (PERCH_STATE=listmenu).
    func debugShowMenu() { showMenu() }

    /// Chrome-style reload menu (right-click on the refresh button): normal reload
    /// keeps your place; clear-and-reload wipes the column and reloads from the top.
    private func showReloadMenu() {
        let theme = self.theme
        let isX = account.platform == .x
        let w: CGFloat = 272
        let rowW = w - 12
        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 13
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1

        var y: CGFloat = 6
        func add(_ row: HoverControl) {
            row.frame.origin = CGPoint(x: 6, y: y)
            content.addSubview(row)
            y += row.frame.height
        }
        add(makeReloadRow(title: isX ? "Normal reload" : "普通刷新",
                          desc: isX ? "Pull in new posts, keep your place" : "拉取新内容，保留当前阅读位置",
                          kbd: "⌘R", width: rowW) { [weak self] in
            gPopoverHost?.dismissPopover(); self?.spin(); self?.onRefresh()
        })
        add(makeReloadRow(title: isX ? "Clear and reload" : "清空并重载",
                          desc: isX ? "Discard everything and reload from the top" : "丢弃全部内容，从顶部重新加载",
                          kbd: "⇧⌘R", width: rowW) { [weak self] in
            gPopoverHost?.dismissPopover(); self?.spin(); self?.onClearReload()
        })
        y += 6
        content.frame = NSRect(x: 0, y: 0, width: w, height: y)
        let dx = refreshButton.bounds.width - w
        gPopoverHost?.presentPopover(content, width: w, height: y, anchor: refreshButton, edge: .below, dx: dx, dy: 0)
    }

    /// A reload-menu row: bold title over a wrapping description, with a right-aligned
    /// ⌘ shortcut hint. No leading icon (matches the design's ReloadMenuItem).
    private func makeReloadRow(title: String, desc: String, kbd: String, width: CGFloat,
                               onClick: @escaping () -> Void) -> HoverControl {
        let theme = self.theme
        let padX: CGFloat = 11
        let padY: CGFloat = 8

        let kbdLabel = makeLabel(kbd, font: Fonts.sans(13.5, .medium), color: theme.fgSubdued, align: .right)
        let kbdW = kbdLabel.perchSingleLineWidth
        let textW = max(0, width - padX * 2 - 12 - kbdW)

        let titleLabel = makeLabel(title, font: Fonts.sans(13.5, .bold), color: theme.fgHeading)
        let titleH = titleLabel.perchSingleLineHeight

        // Measure the wrapping description with its own cell so the height matches
        // exactly how it renders (cellSize accounts for the field's internal inset).
        let descLabel = makeLabel(desc, font: Fonts.sans(11.5, .medium), color: theme.fgSubdued)
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.maximumNumberOfLines = 0
        let descH = ceil(descLabel.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: textW, height: .greatestFiniteMagnitude)).height ?? 0)

        let rowH = padY + titleH + 1 + descH + padY
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
        row.wantsLayer = true
        row.layer?.cornerRadius = 9

        titleLabel.placeSingleLine(x: padX, y: padY, width: textW, height: titleH)
        row.addSubview(titleLabel)

        descLabel.frame = NSRect(x: padX, y: padY + titleH + 1, width: textW, height: descH)
        row.addSubview(descLabel)

        let kbdH = kbdLabel.perchSingleLineHeight
        kbdLabel.frame = NSRect(x: width - padX - kbdW, y: (rowH - kbdH) / 2, width: kbdW, height: kbdH)
        row.addSubview(kbdLabel)

        row.onState = { h, _ in row.layer?.backgroundColor = (h ? theme.gray100 : NSColor.clear).cgColor }
        row.onClick = onClick
        return row
    }
}
