import AppKit

/// The Bookmarks column body: a folder filter strip, in-column search, a
/// create/edit/delete folder dialog, and a Select-to-move mode — a faithful
/// AppKit port of design/project/app/bookmarks.jsx. Folders + membership are
/// live against X; folder colors are a Perch-local cosmetic.
final class BookmarksPanel: ColumnPanel {
    private let appState: AppState
    private let col: ColumnSpec
    private let callbacks: PostCallbacks
    private let theme = ThemeManager.shared.theme
    private let isX: Bool
    private let width: CGFloat

    // ── Transient local UI state (reset on canvas rebuild) ──
    private var searchOpen = false
    private var query = ""
    private var selectMode = false
    private var selected: Set<String> = []
    private var moveOpen = false

    // ── Subviews ──
    private let strip = FlippedView()
    private var searchField: NSTextField?
    private var selectBar: NSView?
    private var dialog: FolderDialogView?
    private var stripHeight: CGFloat = 48
    private var lastStripWidth: CGFloat = 0

    init(appState: AppState, col: ColumnSpec, width: CGFloat, header: NSView, callbacks: PostCallbacks) {
        self.appState = appState
        self.col = col
        self.width = width
        self.callbacks = callbacks
        self.isX = appState.colAccount(col).platform == .x
        super.init(header: header, body: makeColumnScroll())
        strip.bgColor = theme.bgBase
        addSubview(strip)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.appState.refreshBookmarkFolders()
            self.appState.ensureTimelineLoaded(for: self.col)
        }
        render()
        applyDebugState()
    }

    /// Snapshot helper: drive select mode / dialog from PERCH_STATE.
    private func applyDebugState() {
        switch ProcessInfo.processInfo.environment["PERCH_STATE"] {
        case "bmselect":
            selectMode = true
            selected = Set(appState.bookmarkPosts(for: col, scope: scope).prefix(2).map { $0.id })
            render()
        case "bmdialog":
            presentDialog(mode: .new, folder: nil)
        default: break
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var scope: String {
        get { appState.bmScope[col.id] ?? "__all__" }
        set { appState.bmScope[col.id] = newValue }
    }

    private var folders: [BookmarkFolder] { appState.liveBookmarkFolders }
    private var curFolder: BookmarkFolder? { folders.first { $0.id == scope } }

    // ── Layout ──
    override func layout() {
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 54)
        // The strip lays its chips/buttons out at the panel's real width; rebuild it
        // whenever that width changes (panels start at zero width before first layout).
        if bounds.width > 0, abs(bounds.width - lastStripWidth) > 0.5 {
            lastStripWidth = bounds.width
            buildStrip()
        }
        strip.frame = NSRect(x: 0, y: 54, width: bounds.width, height: stripHeight)
        let bodyY = 54 + stripHeight
        body.frame = NSRect(x: 0, y: bodyY, width: bounds.width, height: max(0, bounds.height - bodyY))
        if let selectBar {
            let s = selectBar.frame.size
            selectBar.frame = NSRect(x: floor((bounds.width - s.width) / 2),
                                     y: bounds.height - s.height - 14, width: s.width, height: s.height)
        }
        dialog?.frame = bounds
    }

    // ── Master render ──
    private func render() {
        buildStrip()
        buildList()
        buildSelectBar()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    // ── Filter / toolbar strip ──
    private func buildStrip() {
        strip.subviews.forEach { $0.removeFromSuperview() }
        searchField = nil
        if searchOpen {
            stripHeight = 54
            buildSearchStrip()
        } else {
            stripHeight = 48
            buildChipStrip()
        }
        // bottom border
        let line = NSView(frame: NSRect(x: 0, y: stripHeight - 1, width: max(bounds.width, width), height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        strip.addSubview(line)
    }

    private func buildChipStrip() {
        let padL: CGFloat = 10
        let btnSize: CGFloat = 30
        let btnGap: CGFloat = 2
        // right-pinned icon buttons
        var rightButtons: [NSView] = []
        rightButtons.append(BmIconButton(icon: "search", tooltip: isX ? "Search" : "搜索") { [weak self] in
            self?.searchOpen = true; self?.render(); self?.focusSearch()
        })
        if curFolder != nil {
            rightButtons.append(BmIconButton(icon: "pencil", tooltip: isX ? "Edit folder" : "编辑文件夹") { [weak self] in
                guard let self, let f = self.curFolder else { return }
                self.presentDialog(mode: .edit, folder: f)
            })
        }
        let postCount = appState.bookmarkPosts(for: col, scope: "__all__").count
        if postCount > 0 {
            rightButtons.append(BmIconButton(icon: "checkmark-circle", tooltip: isX ? "Select" : "选择",
                                             active: selectMode) { [weak self] in
                guard let self else { return }
                if self.selectMode { self.exitSelect() } else { self.selectMode = true; self.render() }
            })
        }
        let rightW = CGFloat(rightButtons.count) * btnSize + CGFloat(max(0, rightButtons.count - 1)) * btnGap
        let rightX = (bounds.width > 0 ? bounds.width : width) - 8 - rightW
        var rx = rightX
        for b in rightButtons {
            b.frame = NSRect(x: rx, y: (stripHeight - btnSize) / 2, width: btnSize, height: btnSize)
            strip.addSubview(b)
            rx += btnSize + btnGap
        }

        // left chip scroller
        let chipsScroll = NSScrollView(frame: NSRect(x: padL, y: 8, width: max(10, rightX - padL - 6), height: 32))
        chipsScroll.drawsBackground = false
        chipsScroll.hasVerticalScroller = false
        chipsScroll.hasHorizontalScroller = false
        chipsScroll.autohidesScrollers = true
        chipsScroll.horizontalScrollElasticity = .allowed
        chipsScroll.verticalScrollElasticity = .none
        let chipsDoc = FlippedView()
        var cx: CGFloat = 0
        let chipGap: CGFloat = 6

        let allChip = BmChipView(label: isX ? "All" : "全部", count: postCount, colorToken: nil,
                                 selected: scope == "__all__", showCount: true) { [weak self] in self?.pickScope("__all__") }
        allChip.frame.origin = CGPoint(x: cx, y: 0)
        chipsDoc.addSubview(allChip)
        cx += allChip.frame.width + chipGap

        for f in folders {
            let chip = BmChipView(label: f.name, count: nil, colorToken: f.colorToken,
                                  selected: scope == f.id, showCount: false) { [weak self] in self?.pickScope(f.id) }
            chip.frame.origin = CGPoint(x: cx, y: 0)
            chipsDoc.addSubview(chip)
            cx += chip.frame.width + chipGap
        }

        let newPill = BmNewPill(label: isX ? "New" : "新建") { [weak self] in self?.presentDialog(mode: .new, folder: nil) }
        newPill.frame.origin = CGPoint(x: cx, y: 0)
        chipsDoc.addSubview(newPill)
        cx += newPill.frame.width

        chipsDoc.frame = NSRect(x: 0, y: 0, width: cx, height: 32)
        chipsScroll.documentView = chipsDoc
        strip.addSubview(chipsScroll)
    }

    private func buildSearchStrip() {
        let pad: CGFloat = 10
        let cancelW: CGFloat = 56
        let fieldH: CGFloat = 36
        let avail = (bounds.width > 0 ? bounds.width : width)
        let pill = roundedLayerView(radius: fieldH / 2, fill: theme.bgLayer1,
                                    border: theme.borderDefault, borderWidth: 1)
        pill.frame = NSRect(x: pad, y: 9, width: avail - pad * 2 - cancelW - 8, height: fieldH)
        let glyph = GlyphView(name: "search", size: 17, color: theme.fgSubdued)
        glyph.frame = NSRect(x: 12, y: (fieldH - 17) / 2, width: 17, height: 17)
        pill.addSubview(glyph)
        let field = NSTextField(string: query)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Fonts.sans(14)
        field.textColor = theme.fgBody
        field.delegate = self
        let ph = curFolder != nil ? (isX ? "Search \(curFolder!.name)" : "搜索\(curFolder!.name)") : (isX ? "Search bookmarks" : "搜索收藏")
        field.placeholderString = ph
        field.frame = NSRect(x: 37, y: (fieldH - 22) / 2, width: pill.frame.width - 37 - 12, height: 22)
        pill.addSubview(field)
        searchField = field
        strip.addSubview(pill)

        let cancel = BmTextButton(label: isX ? "Cancel" : "取消", color: theme.accent) { [weak self] in self?.closeSearch() }
        cancel.frame = NSRect(x: avail - pad - cancelW, y: 9, width: cancelW, height: 34)
        strip.addSubview(cancel)
    }

    private func focusSearch() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let f = self.searchField else { return }
            self.window?.makeFirstResponder(f)
        }
    }

    // ── Results list ──
    private func buildList() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let searching = searchOpen && !q.isEmpty
        let base = appState.bookmarkPosts(for: col, scope: scope)
        let list = searching ? base.filter { p in
            p.text.lowercased().contains(q)
                || p.author.name.lowercased().contains(q)
                || p.author.handle.lowercased().contains(q)
        } : base

        // Loading / error placeholder for the All scope.
        if scope == "__all__" && base.isEmpty {
            switch appState.bookmarkAllStatus(for: col) {
            case .loading:
                body.documentView = TimelineSkeletonView(width: width, isX: isX)
                return
            case .error:
                body.documentView = TimelineErrorView(width: width, isX: isX, retrying: false) { [weak self] in
                    guard let self else { return }
                    self.appState.refreshTimeline(for: self.col, userInitiated: true)
                }
                return
            default: break
            }
        }

        if list.isEmpty {
            let empty: BmEmptyView
            if searching {
                empty = BmEmptyView(icon: "search", title: isX ? "No matches" : "没有匹配的收藏",
                                    body: isX ? "Try a different word." : "换个关键词试试。", width: width)
            } else if scope == "__all__" {
                empty = BmEmptyView(icon: "bookmark", title: isX ? "No bookmarks yet" : "还没有收藏",
                                    body: isX ? "Save posts to read them later." : "收藏内容方便稍后阅读。", width: width)
            } else {
                empty = BmEmptyView(icon: "folder", title: isX ? "This folder is empty" : "这个文件夹是空的",
                                    body: isX ? "Tap Select, then Move to add bookmarks here." : "点击“选择”再“移动”，把收藏放进这个文件夹。", width: width)
            }
            body.documentView = empty
            return
        }

        let doc = FeedDocument(width: width, bottomPad: selectMode ? 88 : 24)
        for p in list {
            if selectMode {
                let row = SelectablePostView(post: p, selected: selected.contains(p.id), width: width,
                                             callbacks: callbacks) { [weak self] in self?.toggleSelect(p.id) }
                doc.append(row)
            } else {
                doc.append(PostCellView(post: p, width: width, callbacks: callbacks))
            }
        }
        doc.restack()
        body.documentView = doc
    }

    // ── Select action bar ──
    private func buildSelectBar() {
        selectBar?.removeFromSuperview()
        selectBar = nil
        guard selectMode else { return }
        let selCount = selected.count
        let bar = FlippedView()
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 22
        bar.layer?.backgroundColor = theme.bgElevated.cgColor
        bar.layer?.borderColor = theme.borderDefault.cgColor
        bar.layer?.borderWidth = 1
        bar.layer?.shadowColor = NSColor.black.cgColor
        bar.layer?.shadowOpacity = theme.isDark ? 0.5 : 0.16
        bar.layer?.shadowRadius = 12
        bar.layer?.shadowOffset = CGSize(width: 0, height: -3)
        bar.layer?.masksToBounds = false

        let h: CGFloat = 44
        var x: CGFloat = 16
        let label = makeLabel(selCount > 0 ? (isX ? "\(selCount) selected" : "已选 \(selCount) 项")
                                           : (isX ? "Select posts" : "选择内容"),
                              font: Fonts.sans(13.5, .bold),
                              color: selCount > 0 ? theme.fgHeading : theme.fgSubdued)
        let labelW = label.perchSingleLineWidth
        label.placeSingleLine(x: x, y: 0, width: labelW, height: h)
        bar.addSubview(label)
        x += labelW + 12

        let div1 = divider(); div1.frame = NSRect(x: x, y: 11, width: 1, height: 22); bar.addSubview(div1); x += 1 + 6

        let move = BmPillButton(label: isX ? "Move" : "移动", icon: "folder", primary: true,
                                disabled: selCount == 0) { [weak self] in
            guard let self, selCount > 0 else { return }
            self.moveOpen = true; self.buildSelectBar(); self.needsLayout = true
        }
        move.frame.origin = CGPoint(x: x, y: (h - 34) / 2)
        bar.addSubview(move)
        x += move.frame.width + 6

        let trash = BmIconButton(icon: "trash", tooltip: isX ? "Remove from bookmarks" : "移除收藏", danger: true) { [weak self] in
            guard let self, selCount > 0 else { return }
            self.removeSelected()
        }
        trash.frame = NSRect(x: x, y: (h - 30) / 2, width: 30, height: 30)
        bar.addSubview(trash); x += 30 + 4

        let div2 = divider(); div2.frame = NSRect(x: x, y: 11, width: 1, height: 22); bar.addSubview(div2); x += 1 + 4

        let close = BmIconButton(icon: "close", tooltip: isX ? "Done" : "完成") { [weak self] in self?.exitSelect() }
        close.frame = NSRect(x: x, y: (h - 30) / 2, width: 30, height: 30)
        bar.addSubview(close); x += 30 + 7

        bar.frame = NSRect(x: 0, y: 0, width: x, height: h)
        addSubview(bar)
        selectBar = bar

        if moveOpen {
            let pop = MovePopoverView(folders: folders, isX: isX,
                                      onPick: { [weak self] fid in self?.moveSelected(to: fid) },
                                      onNew: { [weak self] in
                                          guard let self else { return }
                                          self.moveOpen = false
                                          self.presentDialog(mode: .new, folder: nil, assignIds: Array(self.selected))
                                      },
                                      onClose: { [weak self] in self?.moveOpen = false; self?.buildSelectBar(); self?.needsLayout = true })
            // position above the bar, centered
            let pw = pop.frame.width
            pop.frame.origin = CGPoint(x: floor((bar.frame.width - pw) / 2), y: -pop.frame.height - 8)
            bar.addSubview(pop)
        }
    }

    private func divider() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = theme.borderDefault.cgColor
        return v
    }

    // ── Actions ──
    private func pickScope(_ v: String) {
        scope = v
        selected.removeAll()
        if v != "__all__" { appState.loadBookmarkFolder(v) }
        render()
    }

    private func toggleSelect(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        render()
    }

    private func exitSelect() {
        selectMode = false
        selected.removeAll()
        moveOpen = false
        render()
    }

    private func moveSelected(to folderId: String?) {
        let ids = Array(selected)
        moveOpen = false
        exitSelect()
        for id in ids { appState.moveBookmark(id, to: folderId) }
    }

    private func removeSelected() {
        let ids = Array(selected)
        exitSelect()
        for id in ids { appState.onAction(id, "bookmarked") }
        appState.showToastNow(isX ? "Removed" : "已移除")
    }

    private func closeSearch() {
        searchOpen = false
        query = ""
        if let f = searchField { window?.makeFirstResponder(nil); _ = f }
        render()
    }

    // ── Folder dialog ──
    private func presentDialog(mode: FolderDialogView.Mode, folder: BookmarkFolder?, assignIds: [String] = []) {
        dialog?.removeFromSuperview()
        let d = FolderDialogView(mode: mode, folder: folder, isX: isX, maxWidth: width - 40,
                                 onSave: { [weak self] name, color in
                                     guard let self else { return }
                                     if mode == .new {
                                         self.appState.addBookmarkFolder(name: name, colorToken: color,
                                                                         selectIn: assignIds.isEmpty ? self.col.id : nil,
                                                                         assign: assignIds)
                                         if !assignIds.isEmpty { self.exitSelect() }
                                     } else if let f = folder {
                                         self.appState.updateBookmarkFolder(id: f.id, name: name, colorToken: color)
                                     }
                                     self.dismissDialog()
                                 },
                                 onDelete: { [weak self] in
                                     guard let self, let f = folder else { return }
                                     self.appState.deleteBookmarkFolder(id: f.id)
                                     self.dismissDialog()
                                 },
                                 onClose: { [weak self] in self?.dismissDialog() })
        d.frame = bounds
        addSubview(d)
        dialog = d
    }

    private func dismissDialog() {
        dialog?.removeFromSuperview()
        dialog = nil
    }
}

extension BookmarksPanel: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === searchField else { return }
        query = f.stringValue
        buildList()           // re-filter without rebuilding the strip (keeps focus)
    }
}

// ── A folder filter chip ──
private final class BmChipView: HoverControl {
    private let theme = ThemeManager.shared.theme
    init(label: String, count: Int?, colorToken: String?, selected: Bool, showCount: Bool, onClick: @escaping () -> Void) {
        super.init(frame: .zero)
        self.onClick = onClick
        wantsLayer = true
        layer?.cornerRadius = 16
        let dotW: CGFloat = colorToken != nil ? 13 + 7 : 0
        let labelText = makeLabel(label, font: Fonts.sans(13.5, .bold),
                                  color: selected ? .white : theme.fgBody)
        let labelW = labelText.perchSingleLineWidth
        var countLabel: NSTextField?
        var countW: CGFloat = 0
        if showCount, let count {
            let cl = makeLabel(String(count), font: Fonts.sans(11.5, .heavy),
                               color: selected ? NSColor.white.withAlphaComponent(0.82) : theme.fgSubdued)
            countLabel = cl
            countW = cl.perchSingleLineWidth + 5
        }
        let leftPad: CGFloat = colorToken != nil ? 9 : 13
        let rightPad: CGFloat = 13
        let w = leftPad + dotW + labelW + countW + rightPad
        frame = NSRect(x: 0, y: 0, width: w, height: 32)

        layer?.backgroundColor = (selected ? theme.accentBg : theme.gray100).cgColor

        var x = leftPad
        if let colorToken {
            let dot = NSView(frame: NSRect(x: x, y: (32 - 13) / 2, width: 13, height: 13))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 4
            dot.layer?.backgroundColor = theme.scaleColor(colorToken).cgColor
            addSubview(dot)
            x += 13 + 7
        }
        labelText.placeSingleLine(x: x, y: 0, width: labelW, height: 32)
        addSubview(labelText)
        x += labelW
        if let cl = countLabel {
            cl.placeSingleLine(x: x + 5, y: 0, width: countW, height: 32)
            addSubview(cl)
        }
        onState = { [weak self] h, _ in
            guard let self, !selected else { return }
            self.layer?.backgroundColor = (h ? self.theme.gray200 : self.theme.gray100).cgColor
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Dashed "New folder" pill ──
private final class BmNewPill: HoverControl {
    private let theme = ThemeManager.shared.theme
    init(label: String, onClick: @escaping () -> Void) {
        super.init(frame: .zero)
        self.onClick = onClick
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1.5
        layer?.borderColor = theme.gray400.cgColor
        let glyph = GlyphView(name: "add", size: 15, color: theme.fgSubdued)
        let lbl = makeLabel(label, font: Fonts.sans(13.5, .bold), color: theme.fgSubdued)
        let lblW = lbl.perchSingleLineWidth
        let w = 10 + 15 + 5 + lblW + 13
        frame = NSRect(x: 0, y: 0, width: w, height: 32)
        glyph.frame = NSRect(x: 10, y: (32 - 15) / 2, width: 15, height: 15)
        addSubview(glyph)
        lbl.placeSingleLine(x: 30, y: 0, width: lblW, height: 32)
        addSubview(lbl)
        onState = { [weak self] h, _ in
            guard let self else { return }
            self.layer?.borderColor = (h ? self.theme.gray500 : self.theme.gray400).cgColor
            glyph.color = h ? self.theme.fgBody : self.theme.fgSubdued
            lbl.textColor = h ? self.theme.fgBody : self.theme.fgSubdued
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Ghost icon button (30×30) ──
private final class BmIconButton: HoverControl {
    private let theme = ThemeManager.shared.theme
    init(icon: String, tooltip: String, active: Bool = false, danger: Bool = false, onClick: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
        self.onClick = onClick
        self.toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 8
        let size: CGFloat = 17
        let baseColor = danger ? theme.negative : (active ? theme.fgHeading : theme.fgSubdued)
        let glyph = GlyphView(name: icon, size: size, color: baseColor)
        glyph.frame = NSRect(x: (30 - size) / 2, y: (30 - size) / 2, width: size, height: size)
        addSubview(glyph)
        func bg(_ on: Bool) -> CGColor {
            if !on { return NSColor.clear.cgColor }
            return (danger ? theme.negativeBg.withAlphaComponent(0.14) : theme.gray100).cgColor
        }
        layer?.backgroundColor = bg(active)
        onState = { [weak self] h, _ in
            guard let self else { return }
            self.layer?.backgroundColor = bg(active || h)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Text-only button (Cancel) ──
private final class BmTextButton: HoverControl {
    private let theme = ThemeManager.shared.theme
    init(label: String, color: NSColor, onClick: @escaping () -> Void) {
        super.init(frame: .zero)
        self.onClick = onClick
        wantsLayer = true
        layer?.cornerRadius = 8
        let lbl = makeLabel(label, font: Fonts.sans(13.5, .bold), color: color, align: .center)
        addSubview(lbl)
        frame = NSRect(x: 0, y: 0, width: 56, height: 34)
        lbl.placeSingleLine(x: 0, y: 0, width: 56, height: 34)
        lbl.autoresizingMask = [.width]
        onState = { [weak self] h, _ in
            self?.layer?.backgroundColor = (h ? self?.theme.gray100.cgColor : NSColor.clear.cgColor)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Pill text button (primary / hairline / danger) ──
private final class BmPillButton: HoverControl {
    private let theme = ThemeManager.shared.theme
    init(label: String, icon: String? = nil, primary: Bool = false, danger: Bool = false,
         disabled: Bool = false, onClick: @escaping () -> Void) {
        super.init(frame: .zero)
        self.onClick = disabled ? nil : onClick
        self.enabledControl = !disabled
        wantsLayer = true
        layer?.cornerRadius = 17
        let fg: NSColor = primary ? .white : (danger ? theme.negative : theme.fgHeading)
        var x: CGFloat = icon != nil ? 13 : 16
        var glyph: GlyphView?
        if let icon {
            let g = GlyphView(name: icon, size: 16, color: fg)
            addSubview(g); glyph = g
        }
        let lbl = makeLabel(label, font: Fonts.sans(13.5, .bold), color: fg)
        let lblW = lbl.perchSingleLineWidth
        let iconBlock: CGFloat = icon != nil ? 16 + 7 : 0
        let w = x + iconBlock + lblW + 16
        frame = NSRect(x: 0, y: 0, width: w, height: 34)
        if let g = glyph { g.frame = NSRect(x: x, y: (34 - 16) / 2, width: 16, height: 16); x += 16 + 7 }
        lbl.placeSingleLine(x: x, y: 0, width: lblW, height: 34)
        addSubview(lbl)
        alphaValue = disabled ? 0.55 : 1

        func fill(_ hover: Bool) -> CGColor {
            if disabled { return theme.borderDisabled.cgColor }
            if primary { return (hover ? theme.accentBgHover : theme.accentBg).cgColor }
            return (hover ? theme.gray100 : NSColor.clear).cgColor
        }
        if !primary {
            layer?.borderWidth = 1
            layer?.borderColor = theme.borderStrong.cgColor
        }
        layer?.backgroundColor = fill(false)
        onState = { [weak self] h, _ in self?.layer?.backgroundColor = fill(h) }
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Rounded folder tile with the bookmark glyph ──
private final class FolderTileView: NSView {
    init(colorToken: String, size: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = round(size * 0.28)
        layer?.backgroundColor = ThemeManager.shared.theme.scaleColor(colorToken).cgColor
        let gs = round(size * 0.5)
        let glyph = GlyphView(name: "bookmark", size: gs, color: .white)
        glyph.frame = NSRect(x: (size - gs) / 2, y: (size - gs) / 2, width: gs, height: gs)
        addSubview(glyph)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}

// ── A post wrapped for Select mode (tap toggles selection) ──
private final class SelectablePostView: FlippedView {
    init(post: Post, selected: Bool, width: CGFloat, callbacks: PostCallbacks, onToggle: @escaping () -> Void) {
        let theme = ThemeManager.shared.theme
        let cell = PostCellView(post: post, width: width, callbacks: callbacks)
        let h = cell.frame.height
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        addSubview(cell)
        let overlay = HoverControl(frame: bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = (selected ? theme.accentBg.withAlphaComponent(0.12) : NSColor.clear).cgColor
        overlay.onClick = onToggle
        if selected {
            let bar = NSView(frame: NSRect(x: 0, y: 0, width: 3, height: h))
            bar.autoresizingMask = [.height]
            bar.wantsLayer = true
            bar.layer?.backgroundColor = theme.accentBg.cgColor
            overlay.addSubview(bar)
        }
        let dot = NSView(frame: NSRect(x: width - 14 - 22, y: 14, width: 22, height: 22))
        dot.autoresizingMask = [.minXMargin]
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 11
        if selected {
            dot.layer?.backgroundColor = theme.accentBg.cgColor
            let ck = GlyphView(name: "checkmark", size: 15, color: .white)
            ck.frame = NSRect(x: (22 - 15) / 2, y: (22 - 15) / 2, width: 15, height: 15)
            dot.addSubview(ck)
        } else {
            dot.layer?.backgroundColor = theme.bgBase.withAlphaComponent(0.7).cgColor
            dot.layer?.borderWidth = 2
            dot.layer?.borderColor = theme.borderStrong.cgColor
        }
        overlay.addSubview(dot)
        addSubview(overlay)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Centered empty state ──
private final class BmEmptyView: FlippedView {
    init(icon: String, title: String, body: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 240))
        let theme = ThemeManager.shared.theme
        let circle = NSView(frame: NSRect(x: (width - 54) / 2, y: 64, width: 54, height: 54))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 27
        circle.layer?.backgroundColor = theme.gray100.cgColor
        let glyph = GlyphView(name: icon, size: 27, color: theme.fgSubdued)
        glyph.frame = NSRect(x: (54 - 27) / 2, y: (54 - 27) / 2, width: 27, height: 27)
        circle.addSubview(glyph)
        addSubview(circle)

        let t = makeLabel(title, font: Fonts.sans(16, .heavy), color: theme.fgHeading, align: .center)
        t.frame = NSRect(x: 16, y: 132, width: width - 32, height: 22)
        t.autoresizingMask = [.width]
        addSubview(t)

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineHeightMultiple = 1.4
        let b = NSTextField(labelWithAttributedString: NSAttributedString(string: body, attributes: [
            .font: Fonts.sans(14), .foregroundColor: theme.fgSubdued, .paragraphStyle: para
        ]))
        b.isBezeled = false; b.drawsBackground = false; b.isEditable = false
        b.frame = NSRect(x: (width - 280) / 2, y: 158, width: 280, height: 44)
        b.autoresizingMask = [.minXMargin, .maxXMargin]
        addSubview(b)
    }
    required init?(coder: NSCoder) { fatalError() }
}

// ── Move-to-folder popover (Select mode) ──
private final class MovePopoverView: FlippedView {
    private let theme = ThemeManager.shared.theme
    init(folders: [BookmarkFolder], isX: Bool, onPick: @escaping (String?) -> Void,
         onNew: @escaping () -> Void, onClose: @escaping () -> Void) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.backgroundColor = theme.bgElevated.cgColor
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = theme.isDark ? 0.5 : 0.16
        layer?.shadowRadius = 12
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.masksToBounds = false

        let w: CGFloat = 244
        var y: CGFloat = 6
        let title = makeLabel(isX ? "Move to" : "移动到", font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        title.frame = NSRect(x: 16, y: y + 4, width: w - 24, height: 14)
        addSubview(title)
        y += 26

        for f in folders {
            let row = makeRow(width: w, y: y, tile: FolderTileView(colorToken: f.colorToken, size: 26),
                              text: f.name, color: theme.fgBody, bold: false) { onPick(f.id) }
            addSubview(row); y += 38
        }

        let div = NSView(frame: NSRect(x: 8, y: y + 5, width: w - 16, height: 1))
        div.wantsLayer = true; div.layer?.backgroundColor = theme.borderDefault.cgColor
        addSubview(div); y += 11

        let removeTile = tileIcon("close", fg: theme.fgSubdued, bg: theme.gray100)
        let removeRow = makeRow(width: w, y: y, tile: removeTile, text: isX ? "Remove from folder" : "移出文件夹",
                                color: theme.fgSubdued, bold: false) { onPick(nil) }
        addSubview(removeRow); y += 38

        let newTile = tileIcon("add", fg: theme.accent, bg: theme.accentBg.withAlphaComponent(0.14))
        let newRow = makeRow(width: w, y: y, tile: newTile, text: isX ? "New folder…" : "新建文件夹…",
                             color: theme.accent, bold: true, onClick: onNew)
        addSubview(newRow); y += 38 + 6

        frame = NSRect(x: 0, y: 0, width: w, height: y)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func tileIcon(_ icon: String, fg: NSColor, bg: NSColor) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        v.wantsLayer = true
        v.layer?.cornerRadius = 7
        v.layer?.backgroundColor = bg.cgColor
        let g = GlyphView(name: icon, size: 15, color: fg)
        g.frame = NSRect(x: (26 - 15) / 2, y: (26 - 15) / 2, width: 15, height: 15)
        v.addSubview(g)
        return v
    }

    private func makeRow(width: CGFloat, y: CGFloat, tile: NSView, text: String, color: NSColor,
                         bold: Bool, onClick: @escaping () -> Void) -> HoverControl {
        let row = HoverControl(frame: NSRect(x: 6, y: y, width: width - 12, height: 34))
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        row.onClick = onClick
        tile.frame.origin = CGPoint(x: 10, y: (34 - tile.frame.height) / 2)
        row.addSubview(tile)
        let lbl = makeLabel(text, font: Fonts.sans(14, bold ? .bold : .semibold), color: color)
        lbl.lineBreakMode = .byTruncatingTail
        lbl.placeSingleLine(x: 10 + tile.frame.width + 11, y: 0, width: width - 12 - 10 - tile.frame.width - 11 - 10, height: 34)
        row.addSubview(lbl)
        row.onState = { [weak self] h, _ in
            row.layer?.backgroundColor = (h ? self?.theme.gray100.cgColor : NSColor.clear.cgColor)
        }
        return row
    }
}

// ── Create / edit folder dialog (modal overlay covering the column) ──
final class FolderDialogView: FlippedView {
    enum Mode { case new, edit }
    private let theme = ThemeManager.shared.theme
    private let mode: Mode
    private let isX: Bool
    private var name: String
    private var color: String
    private var confirming = false
    private let onSave: (String, String) -> Void
    private let onDelete: () -> Void
    private let onClose: () -> Void

    private let card = FlippedView()
    private var nameField: NSTextField?
    private let folderName: String
    private let cardWidth: CGFloat

    init(mode: Mode, folder: BookmarkFolder?, isX: Bool, maxWidth: CGFloat = 320,
         onSave: @escaping (String, String) -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.mode = mode
        self.isX = isX
        self.cardWidth = max(240, min(320, maxWidth))
        self.name = folder?.name ?? ""
        self.color = folder?.colorToken ?? AppState.bmPalette[0]
        self.folderName = folder?.name ?? ""
        self.onSave = onSave
        self.onDelete = onDelete
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = theme.gray1000.withAlphaComponent(0.34).cgColor
        card.wantsLayer = true
        card.layer?.backgroundColor = theme.bgElevated.cgColor
        card.layer?.cornerRadius = 16
        card.layer?.borderColor = theme.borderDefault.cgColor
        card.layer?.borderWidth = 1
        addSubview(card)
        buildCard()
    }
    required init?(coder: NSCoder) { fatalError() }

    // tap on the dim backdrop closes
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(pt) { onClose() }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        // Card has a fixed size; just keep it centered. Never resize it (resizing
        // would trigger autoresizing havoc during the panel's zero-width first pass).
        let s = card.frame.size
        card.frame = NSRect(x: floor((bounds.width - s.width) / 2),
                            y: floor((bounds.height - s.height) / 2), width: s.width, height: s.height)
    }

    private func buildCard() {
        card.subviews.forEach { $0.removeFromSuperview() }
        nameField = nil
        if confirming { buildConfirm(w: cardWidth) } else { buildForm(w: cardWidth) }
        needsLayout = true
    }

    private func buildForm(w: CGFloat) {
        let pad: CGFloat = 18
        var y: CGFloat = pad
        let tile = FolderTileView(colorToken: color, size: 40)
        tile.frame.origin = CGPoint(x: pad, y: y)
        card.addSubview(tile)
        let title = makeLabel(mode == .edit ? (isX ? "Edit folder" : "编辑文件夹") : (isX ? "New folder" : "新建文件夹"),
                              font: Fonts.sans(16.5, .heavy), color: theme.fgHeading)
        title.placeSingleLine(x: pad + 40 + 11, y: y, width: w - pad - 40 - 11 - pad, height: 22)
        card.addSubview(title)
        let sub = makeLabel(name.isEmpty ? (isX ? "Pick a name and color" : "选择名称和颜色") : name,
                            font: Fonts.sans(12.5), color: theme.fgSubdued)
        sub.placeSingleLine(x: pad + 40 + 11, y: y + 22, width: w - pad - 40 - 11 - pad, height: 16)
        card.addSubview(sub)
        y += 40 + 16

        let nameLabel = makeLabel(isX ? "NAME" : "名称", font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        nameLabel.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 14)
        card.addSubview(nameLabel)
        y += 20

        let field = NSTextField(string: name)
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = theme.bgBase
        field.wantsLayer = true
        field.layer?.cornerRadius = 9
        field.layer?.borderWidth = 1
        field.layer?.borderColor = theme.borderDefault.cgColor
        field.focusRingType = .none
        field.font = Fonts.sans(14.5)
        field.textColor = theme.fgBody
        field.placeholderString = isX ? "Folder name" : "文件夹名称"
        field.delegate = self
        field.target = self
        field.action = #selector(commitFromField)
        field.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 38)
        card.addSubview(field)
        nameField = field
        y += 38 + 16

        let colorLabel = makeLabel(isX ? "COLOR" : "颜色", font: Fonts.sans(11, .heavy), color: theme.fgSubdued)
        colorLabel.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 14)
        card.addSubview(colorLabel)
        y += 23

        let swatch: CGFloat = 28
        let gap: CGFloat = 10
        let perRow = Int((w - pad * 2 + gap) / (swatch + gap))
        var sx = pad, col = 0
        for token in AppState.bmPalette {
            let on = token == color
            let b = HoverControl(frame: NSRect(x: sx, y: y, width: swatch, height: swatch))
            b.wantsLayer = true
            b.layer?.cornerRadius = swatch / 2
            b.layer?.backgroundColor = theme.scaleColor(token).cgColor
            b.toolTip = token
            if on {
                b.layer?.borderWidth = 2
                b.layer?.borderColor = theme.fgHeading.cgColor
                let ck = GlyphView(name: "checkmark", size: 16, color: .white)
                ck.frame = NSRect(x: (swatch - 16) / 2, y: (swatch - 16) / 2, width: 16, height: 16)
                b.addSubview(ck)
            }
            b.onClick = { [weak self] in self?.color = token; self?.buildCard() }
            card.addSubview(b)
            col += 1
            if col >= perRow { col = 0; sx = pad; y += swatch + gap } else { sx += swatch + gap }
        }
        if col != 0 { y += swatch }
        y += 20

        // footer
        var fx = pad
        let footerY = y
        if mode == .edit {
            let del = BmIconButton(icon: "trash", tooltip: isX ? "Delete folder" : "删除文件夹", danger: true) { [weak self] in
                self?.confirming = true; self?.buildCard()
            }
            del.frame = NSRect(x: pad, y: footerY, width: 36, height: 34)
            del.layer?.borderWidth = 1
            del.layer?.borderColor = theme.borderStrong.cgColor
            del.layer?.cornerRadius = 9
            card.addSubview(del)
        }
        fx = w - pad
        let create = BmPillButton(label: mode == .edit ? (isX ? "Save" : "保存") : (isX ? "Create" : "创建"),
                                  primary: true, disabled: name.trimmingCharacters(in: .whitespaces).isEmpty) { [weak self] in
            self?.commit()
        }
        create.frame.origin = CGPoint(x: fx - create.frame.width, y: footerY)
        card.addSubview(create)
        fx -= create.frame.width + 10
        let cancel = BmPillButton(label: isX ? "Cancel" : "取消") { [weak self] in self?.onClose() }
        cancel.frame.origin = CGPoint(x: fx - cancel.frame.width, y: footerY)
        card.addSubview(cancel)
        y += 34 + pad

        card.frame.size = NSSize(width: w, height: y)
        DispatchQueue.main.async { [weak self] in
            guard let self, let f = self.nameField else { return }
            self.window?.makeFirstResponder(f)
        }
    }

    private func buildConfirm(w: CGFloat) {
        let pad: CGFloat = 18
        var y: CGFloat = pad
        let circle = NSView(frame: NSRect(x: (w - 48) / 2, y: y, width: 48, height: 48))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 24
        circle.layer?.backgroundColor = theme.negativeBg.cgColor
        let g = GlyphView(name: "trash", size: 24, color: .white)
        g.frame = NSRect(x: 12, y: 12, width: 24, height: 24)
        circle.addSubview(g)
        card.addSubview(circle)
        y += 48 + 12

        let title = makeLabel(isX ? "Delete “\(folderName)”?" : "删除“\(folderName)”？",
                              font: Fonts.sans(16.5, .heavy), color: theme.fgHeading, align: .center)
        title.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 22)
        card.addSubview(title)
        y += 27

        let para = NSMutableParagraphStyle()
        para.alignment = .center; para.lineHeightMultiple = 1.4
        let bodyText = isX ? "The folder is removed. Your bookmarks stay saved in All bookmarks."
                           : "文件夹将被删除，其中的收藏仍会保留在“全部收藏”里。"
        let b = NSTextField(labelWithAttributedString: NSAttributedString(string: bodyText, attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: para]))
        b.isBezeled = false; b.drawsBackground = false; b.isEditable = false
        b.frame = NSRect(x: pad, y: y, width: w - pad * 2, height: 40)
        card.addSubview(b)
        y += 40 + 18

        let half = (w - pad * 2 - 10) / 2
        let cancel = BmPillButton(label: isX ? "Cancel" : "取消") { [weak self] in
            guard let self else { return }
            if self.mode == .new { self.onClose() } else { self.confirming = false; self.buildCard() }
        }
        cancel.frame = NSRect(x: pad, y: y, width: half, height: 34)
        card.addSubview(cancel)
        let del = HoverControl(frame: NSRect(x: pad + half + 10, y: y, width: half, height: 34))
        del.wantsLayer = true
        del.layer?.cornerRadius = 17
        del.layer?.backgroundColor = theme.negative.cgColor
        let dl = makeLabel(isX ? "Delete" : "删除", font: Fonts.sans(13.5, .bold), color: .white, align: .center)
        dl.placeSingleLine(x: 0, y: 0, width: half, height: 34)
        del.addSubview(dl)
        del.onClick = { [weak self] in self?.onDelete() }
        card.addSubview(del)
        y += 34 + pad

        card.frame.size = NSSize(width: w, height: y)
    }

    @objc private func commitFromField() { commit() }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed, color)
    }
}

extension FolderDialogView: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let f = obj.object as? NSTextField, f === nameField else { return }
        name = f.stringValue
    }
}
