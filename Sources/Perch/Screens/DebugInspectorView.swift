import AppKit

/// One column's data snapshot for the Inspector's Data tab.
struct DebugColumnSnapshot {
    let id: String
    let icon: String
    let platform: Platform
    let label: String
    let sub: String
    let count: Int
    let json: DebugJSON
}

/// The floating network + data inspector window (port of the design's `DebugInspector`).
/// Network tab = redacted request log; Data tab = per-column raw data. Observes
/// `.debugLogDidChange` to live-update the request list while open.
final class DebugInspectorView: FlippedView {
    private let appState: AppState
    private let isX: Bool
    private let theme = ThemeManager.shared.theme
    private let palette = DebugPalette(ThemeManager.shared.theme)
    private weak var panelController: PanelWindowController?

    private let card = FlippedView()
    private let header = FlippedView()
    private let headerBorder = NSView()
    private var traffic: NSView!
    private let titleLabel: NSTextField
    private let pill = FlippedView()
    private let netTabBtn = HoverControl()
    private let netTabLabel: NSTextField
    private let netTabCount: NSTextField
    private let dataTabBtn = HoverControl()
    private let dataTabLabel: NSTextField
    private let dataTabCount: NSTextField
    private let doneBtn = HoverControl()
    private let doneLabel: NSTextField

    // Network pane
    private let netPane = FlippedView()
    private let netListHeader = FlippedView()
    private let netCountLabel: NSTextField
    private let netClearBtn = HoverControl()
    private let netClearLabel: NSTextField
    private let netClearGlyph = GlyphView(name: "trash", size: 13)
    private let netListScroll = NSScrollView()
    private let netListDoc = FlippedView()
    private let netDetailScroll = NSScrollView()
    private let netListDivider = NSView()
    private let netListHeaderBottom = NSView()
    private var netSel: String?

    // Data pane
    private let dataPane = FlippedView()
    private let colListHeader = FlippedView()
    private let colListScroll = NSScrollView()
    private let colListDoc = FlippedView()
    private let colFooter = FlippedView()
    private var colCopyBtn: CopyJsonButton?
    private let dataTreeScroll = NSScrollView()
    private let dataTreeDoc = FlippedView()
    private var dataTree: JSONTreeView?
    private let dataDivider = NSView()
    private let colFooterBorder = NSView()
    private let colListHeaderBottom = NSView()
    private var snapshots: [DebugColumnSnapshot] = []
    private var dataSel: String?

    private var active = "network"
    private var eventMonitor: Any?

    private let HEADER_H: CGFloat = 52
    private let NET_LIST_W: CGFloat = 318
    private let COL_LIST_W: CGFloat = 230
    private let SUBHEADER_H: CGFloat = 36
    private let NET_ROW_H: CGFloat = 47
    private let COL_ROW_H: CGFloat = 46

    init(appState: AppState, isX: Bool, initialTab: String = "network") {
        self.appState = appState
        self.isX = isX
        self.active = initialTab
        let theme = ThemeManager.shared.theme
        self.titleLabel = makeLabel(isX ? "Inspector" : "调试检查器", font: Fonts.sans(14.5, .heavy), color: theme.fgHeading)
        self.netTabLabel = makeLabel(isX ? "Network" : "网络", font: Fonts.sans(13, .bold), color: theme.fgSubdued)
        self.netTabCount = makeLabel("0", font: Fonts.sans(11, .bold), color: theme.fgDisabled)
        self.dataTabLabel = makeLabel(isX ? "Data" : "数据", font: Fonts.sans(13, .bold), color: theme.fgSubdued)
        self.dataTabCount = makeLabel("0", font: Fonts.sans(11, .bold), color: theme.fgDisabled)
        self.doneLabel = makeLabel(isX ? "Done" : "完成", font: Fonts.sans(13.5, .semibold), color: theme.fgSubdued)
        self.netCountLabel = makeLabel("", font: Fonts.sans(11.5, .bold), color: theme.fgSubdued)
        self.netClearLabel = makeLabel(isX ? "Clear" : "清空", font: Fonts.sans(12, .semibold), color: theme.fgBody)
        self.colListHeaderLabel = makeLabel(isX ? "Open columns" : "当前分栏", font: Fonts.sans(11.5, .bold), color: theme.fgSubdued)
        super.init(frame: NSRect(x: 0, y: 0, width: 860, height: 620))
        snapshots = appState.dataTabSnapshots()
        dataSel = snapshots.first?.id
        build()
        styleTabs()
        reloadNetwork()
        reloadData()
        NotificationCenter.default.addObserver(self, selector: #selector(logChanged), name: .debugLogDidChange, object: nil)
        installMonitor()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let m = eventMonitor { NSEvent.removeMonitor(m) }
    }

    private let colListHeaderLabel: NSTextField

    // MARK: - Build

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = theme.bgElevated.cgColor
        card.layer?.borderColor = theme.borderDefault.cgColor
        card.layer?.borderWidth = 1
        card.layer?.masksToBounds = true
        addSubview(card)

        // Header
        header.wantsLayer = true
        header.layer?.backgroundColor = theme.bgElevated.cgColor
        card.addSubview(header)
        traffic = makeTrafficLights(onClose: { [weak self] in self?.closeInspector() })
        header.addSubview(traffic)
        header.addSubview(titleLabel)

        pill.wantsLayer = true
        pill.layer?.cornerRadius = 17
        pill.layer?.backgroundColor = theme.gray100.cgColor
        header.addSubview(pill)
        for btn in [netTabBtn, dataTabBtn] {
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 15
            pill.addSubview(btn)
        }
        netTabBtn.addSubview(netTabLabel); netTabBtn.addSubview(netTabCount)
        dataTabBtn.addSubview(dataTabLabel); dataTabBtn.addSubview(dataTabCount)
        netTabBtn.onClick = { [weak self] in self?.showTab("network") }
        dataTabBtn.onClick = { [weak self] in self?.showTab("data") }

        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 8
        doneBtn.addSubview(doneLabel)
        doneBtn.onState = { [weak self] h, _ in
            self?.doneBtn.layer?.backgroundColor = (h ? self?.theme.gray100 : NSColor.clear)?.cgColor
        }
        doneBtn.onClick = { [weak self] in self?.closeInspector() }
        header.addSubview(doneBtn)

        headerBorder.wantsLayer = true
        headerBorder.layer?.backgroundColor = theme.borderDefault.cgColor
        header.addSubview(headerBorder)

        buildNetPane()
        buildDataPane()
        card.addSubview(netPane)
        card.addSubview(dataPane)
        netPane.isHidden = active != "network"
        dataPane.isHidden = active != "data"
    }

    private func buildNetPane() {
        netPane.wantsLayer = true
        // left list column
        netListHeader.wantsLayer = true
        netListHeader.layer?.backgroundColor = theme.bgLayer1.cgColor
        netPane.addSubview(netListHeader)
        netListHeader.addSubview(netCountLabel)

        netClearBtn.wantsLayer = true
        netClearBtn.layer?.cornerRadius = 7
        netClearBtn.layer?.borderColor = theme.borderDefault.cgColor
        netClearBtn.layer?.borderWidth = 1
        netClearBtn.layer?.backgroundColor = theme.bgBase.cgColor
        netClearGlyph.color = theme.fgBody
        netClearBtn.addSubview(netClearGlyph)
        netClearBtn.addSubview(netClearLabel)
        netClearBtn.onClick = { [weak self] in
            DebugLog.shared.clear()
            self?.netSel = nil
        }
        netListHeader.addSubview(netClearBtn)

        netListHeaderBottom.wantsLayer = true
        netListHeaderBottom.layer?.backgroundColor = theme.borderDefault.cgColor
        netListHeader.addSubview(netListHeaderBottom)

        netListScroll.borderType = .noBorder
        netListScroll.drawsBackground = false
        netListScroll.hasVerticalScroller = true
        netListScroll.hasHorizontalScroller = false
        netListScroll.autohidesScrollers = true
        netListScroll.scrollerStyle = .overlay
        netListScroll.documentView = netListDoc
        netPane.addSubview(netListScroll)

        // list / detail divider
        netListDivider.wantsLayer = true
        netListDivider.layer?.backgroundColor = theme.borderDefault.cgColor
        netPane.addSubview(netListDivider)

        netDetailScroll.borderType = .noBorder
        netDetailScroll.drawsBackground = false
        netDetailScroll.hasVerticalScroller = true
        netDetailScroll.hasHorizontalScroller = false
        netDetailScroll.autohidesScrollers = true
        netDetailScroll.scrollerStyle = .overlay
        netPane.addSubview(netDetailScroll)
    }

    private func buildDataPane() {
        dataPane.wantsLayer = true
        colListHeader.wantsLayer = true
        colListHeader.layer?.backgroundColor = theme.bgLayer1.cgColor
        colListHeader.addSubview(colListHeaderLabel)
        colListHeaderBottom.wantsLayer = true
        colListHeaderBottom.layer?.backgroundColor = theme.borderDefault.cgColor
        colListHeader.addSubview(colListHeaderBottom)
        dataPane.addSubview(colListHeader)

        colListScroll.borderType = .noBorder
        colListScroll.drawsBackground = false
        colListScroll.hasVerticalScroller = true
        colListScroll.hasHorizontalScroller = false
        colListScroll.autohidesScrollers = true
        colListScroll.scrollerStyle = .overlay
        colListScroll.documentView = colListDoc
        dataPane.addSubview(colListScroll)

        colFooter.wantsLayer = true
        colFooterBorder.wantsLayer = true
        colFooterBorder.layer?.backgroundColor = theme.borderDefault.cgColor
        colFooter.addSubview(colFooterBorder)
        dataPane.addSubview(colFooter)

        dataDivider.wantsLayer = true
        dataDivider.layer?.backgroundColor = theme.borderDefault.cgColor
        dataPane.addSubview(dataDivider)

        dataTreeScroll.borderType = .noBorder
        dataTreeScroll.drawsBackground = true
        dataTreeScroll.backgroundColor = theme.bgLayer1
        dataTreeScroll.hasVerticalScroller = true
        dataTreeScroll.hasHorizontalScroller = false
        dataTreeScroll.autohidesScrollers = true
        dataTreeScroll.scrollerStyle = .overlay
        dataTreeScroll.documentView = dataTreeDoc
        dataPane.addSubview(dataTreeScroll)
    }

    // MARK: - Tab switching

    private func showTab(_ id: String) {
        guard active != id else { return }
        active = id
        netPane.isHidden = id != "network"
        dataPane.isHidden = id != "data"
        styleTabs()
        needsLayout = true
    }

    private func styleTabs() {
        for (btn, label, count, on) in [
            (netTabBtn, netTabLabel, netTabCount, active == "network"),
            (dataTabBtn, dataTabLabel, dataTabCount, active == "data"),
        ] {
            btn.layer?.backgroundColor = (on ? theme.bgElevated : NSColor.clear).cgColor
            if on {
                btn.layer?.shadowColor = NSColor.black.cgColor
                btn.layer?.shadowOpacity = theme.isDark ? 0.4 : 0.12
                btn.layer?.shadowRadius = 3
                btn.layer?.shadowOffset = CGSize(width: 0, height: -1)
                btn.layer?.masksToBounds = false
            } else {
                btn.layer?.shadowOpacity = 0
            }
            label.textColor = on ? theme.fgHeading : theme.fgSubdued
            count.textColor = on ? theme.accent : theme.fgDisabled
        }
    }

    // MARK: - Network reload

    @objc private func logChanged() {
        netTabCount.stringValue = "\(DebugLog.shared.entries.count)"
        if active == "network" { reloadNetwork() }
        needsLayout = true
    }

    private func reloadNetwork() {
        let entries = Array(DebugLog.shared.entries.reversed())
        netTabCount.stringValue = "\(entries.count)"
        netCountLabel.stringValue = isX
            ? "\(entries.count) " + (entries.count == 1 ? "request" : "requests")
            : "\(entries.count) 个请求"
        netClearBtn.enabledControl = !entries.isEmpty
        netClearLabel.textColor = entries.isEmpty ? theme.fgDisabled : theme.fgBody
        netClearGlyph.color = entries.isEmpty ? theme.fgDisabled : theme.fgBody

        if netSel != nil, !entries.contains(where: { $0.id == netSel }) { netSel = nil }

        netListDoc.subviews.forEach { $0.removeFromSuperview() }
        let w = NET_LIST_W
        if entries.isEmpty {
            let empty = makeNetEmptyState(width: w)
            netListDoc.addSubview(empty)
            netListDoc.frame = NSRect(x: 0, y: 0, width: w, height: max(empty.frame.height, netListScroll.contentView.bounds.height))
        } else {
            var y: CGFloat = 0
            for entry in entries {
                let row = NetRowView(entry: entry, selected: entry.id == netSel, width: w) { [weak self] id in
                    self?.netSel = id
                    self?.reloadNetwork()
                }
                row.frame.origin = NSPoint(x: 0, y: y)
                netListDoc.addSubview(row)
                y += NET_ROW_H
            }
            netListDoc.frame = NSRect(x: 0, y: 0, width: w, height: y)
        }
        rebuildNetDetail()
    }

    private func rebuildNetDetail() {
        let entry = DebugLog.shared.entries.first(where: { $0.id == netSel })
        let w = max(360, bounds.width - NET_LIST_W)
        let paneH = max(200, bounds.height - HEADER_H)
        let doc = buildNetDetail(entry, width: w, paneHeight: paneH)
        netDetailScroll.documentView = doc
    }

    private func makeNetEmptyState(width: CGFloat) -> FlippedView {
        let v = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: 150))
        let title = makeLabel(isX ? "No requests yet" : "暂无请求", font: Fonts.sans(14, .bold), color: theme.fgHeading, align: .center)
        title.frame = NSRect(x: 22, y: 48, width: width - 44, height: 18)
        v.addSubview(title)
        let desc = makeLabel(isX ? "Refresh a column, like a post, or compose — calls show up here." : "刷新分栏、点赞或发帖，请求会显示在这里。",
                             font: Fonts.sans(12.5), color: theme.fgSubdued, align: .center)
        desc.lineBreakMode = .byWordWrapping
        desc.maximumNumberOfLines = 3
        desc.frame = NSRect(x: 22, y: 71, width: width - 44, height: 40)
        v.addSubview(desc)
        return v
    }

    // MARK: - NetDetail

    private func buildNetDetail(_ entry: DebugLogEntry?, width: CGFloat, paneHeight: CGFloat) -> FlippedView {
        let doc = FlippedView()
        guard let entry else {
            doc.frame = NSRect(x: 0, y: 0, width: width, height: paneHeight)
            let glyph = GlyphView(name: "code", size: 30, color: theme.fgDisabled)
            glyph.frame = NSRect(x: (width - 30) / 2, y: paneHeight / 2 - 32, width: 30, height: 30)
            doc.addSubview(glyph)
            let lbl = makeLabel(isX ? "Select a request to inspect it" : "选择一个请求查看详情",
                               font: Fonts.sans(13.5), color: theme.fgSubdued, align: .center)
            lbl.frame = NSRect(x: 20, y: paneHeight / 2 + 6, width: width - 40, height: 18)
            doc.addSubview(lbl)
            return doc
        }

        let padX: CGFloat = 16
        let innerW = width - padX * 2
        var y: CGFloat = 14

        // method + status + (right) ms · time
        let chip = MethodChip(method: entry.method)
        chip.frame.origin = NSPoint(x: padX, y: y)
        doc.addSubview(chip)
        let status = StatusChip(status: entry.status)
        status.frame.origin = NSPoint(x: padX + chip.frame.width + 8, y: y + (chip.frame.height - status.frame.height) / 2)
        doc.addSubview(status)
        let metaText = (entry.durationMs.map { "\($0)ms" } ?? "—") + " · " + entry.timeLabel
        let metaLbl = makeLabel(metaText, font: Fonts.mono(11.5), color: theme.fgDisabled, align: .right)
        metaLbl.frame = NSRect(x: padX + innerW - 200, y: y + 2, width: 200, height: 15)
        doc.addSubview(metaLbl)
        y += chip.frame.height + 10

        // URL line box
        let urlAttr = NSMutableAttributedString()
        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byCharWrapping
        para.lineHeightMultiple = 1.5
        func urlPart(_ s: String, _ c: NSColor, _ weight: NSFont.Weight = .regular) {
            urlAttr.append(NSAttributedString(string: s, attributes: [.font: Fonts.mono(12, weight), .foregroundColor: c, .paragraphStyle: para]))
        }
        urlPart(entry.host, theme.fgSubdued)
        urlPart(entry.path, theme.fgHeading, .bold)
        if !entry.query.isEmpty { urlPart("?" + entry.query, theme.accent) }
        let urlBoxInner = innerW - 22
        let urlH = measureHeight(urlAttr, width: urlBoxInner)
        let urlBox = boxView(frame: NSRect(x: padX, y: y, width: innerW, height: urlH + 18))
        doc.addSubview(urlBox)
        let urlLbl = NSTextField(labelWithAttributedString: urlAttr)
        urlLbl.isBezeled = false; urlLbl.drawsBackground = false; urlLbl.isEditable = false; urlLbl.isSelectable = false
        urlLbl.lineBreakMode = .byCharWrapping
        urlLbl.maximumNumberOfLines = 0
        urlLbl.frame = NSRect(x: 11, y: 9, width: urlBoxInner, height: urlH)
        urlBox.addSubview(urlLbl)
        y += urlH + 18 + 14

        // Request headers KV block
        let (kv, kvH) = buildKVBlock(title: isX ? "Request headers" : "请求头", pairs: entry.requestHeaders, width: innerW)
        kv.frame.origin = NSPoint(x: padX, y: y)
        doc.addSubview(kv)
        y += kvH + 14

        // Redaction note
        let lockGlyph = GlyphView(name: "lock", size: 14, color: theme.positive)
        lockGlyph.frame = NSRect(x: padX, y: y, width: 14, height: 14)
        doc.addSubview(lockGlyph)
        let noteAttr = NSAttributedString(string: isX ? "Cookies and tokens are stripped before logging." : "Cookie 与令牌已在记录前脱敏。",
                                          attributes: [.font: Fonts.sans(11.5), .foregroundColor: theme.fgSubdued])
        let noteW = innerW - 20
        let noteH = measureHeight(noteAttr, width: noteW)
        let note = NSTextField(labelWithAttributedString: noteAttr)
        note.isBezeled = false; note.drawsBackground = false; note.isEditable = false; note.isSelectable = false
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 0
        note.frame = NSRect(x: padX + 20, y: y, width: noteW, height: noteH)
        doc.addSubview(note)
        y += max(14, noteH) + 14

        // Request payload tree
        if let req = entry.requestBody {
            y = appendTreeSection(doc: doc, title: isX ? "Request payload" : "提交数据", json: req, x: padX, y: y, innerW: innerW)
        }
        // Response tree
        if let res = entry.responseBody {
            y = appendTreeSection(doc: doc, title: isX ? "Response" : "响应", json: res, x: padX, y: y, innerW: innerW)
        }

        doc.frame = NSRect(x: 0, y: 0, width: width, height: y + 4)
        return doc
    }

    private func appendTreeSection(doc: FlippedView, title: String, json: DebugJSON, x: CGFloat, y: CGFloat, innerW: CGFloat) -> CGFloat {
        var yy = y
        let titleLbl = makeLabel(title.uppercased(), font: Fonts.sans(10.5, .bold), color: theme.fgSubdued)
        titleLbl.frame = NSRect(x: x, y: yy, width: innerW, height: 14)
        doc.addSubview(titleLbl)
        yy += 14 + 6
        let tree = JSONTreeView(json: json, theme: theme)
        tree.frame.origin = NSPoint(x: x + 12, y: yy + 10)
        tree.rebuild(availableWidth: innerW - 24)
        let boxH = tree.frame.height + 20
        let box = boxView(frame: NSRect(x: x, y: yy, width: innerW, height: boxH))
        doc.addSubview(box)
        doc.addSubview(tree)   // above the box (same coords; box added first)
        yy += boxH + 14
        return yy
    }

    private func buildKVBlock(title: String, pairs: [(String, String)], width: CGFloat) -> (FlippedView, CGFloat) {
        let v = FlippedView()
        let titleLbl = makeLabel(title.uppercased(), font: Fonts.sans(10.5, .bold), color: theme.fgSubdued)
        titleLbl.frame = NSRect(x: 0, y: 0, width: width, height: 14)
        v.addSubview(titleLbl)
        var by: CGFloat = 14 + 6

        let box = boxView(frame: NSRect(x: 0, y: by, width: width, height: 0))
        v.addSubview(box)
        let keyW: CGFloat = 100
        let valW = width - 22 - keyW - 10
        var inner: CGFloat = 0
        for (i, pair) in pairs.enumerated() {
            if i > 0 {
                let line = NSView(frame: NSRect(x: 11, y: by + inner, width: width - 22, height: 1))
                line.wantsLayer = true
                line.layer?.backgroundColor = theme.borderDefault.cgColor
                box.addSubview(line)
            }
            let redacted = pair.1.range(of: "redacted|stripped", options: [.regularExpression, .caseInsensitive]) != nil
            let keyLbl = makeLabel(pair.0, font: Fonts.mono(12), color: palette.key)
            let valAttr = NSAttributedString(string: pair.1, attributes: [
                .font: redacted ? Fonts.mono(12).withItalic() : Fonts.mono(12),
                .foregroundColor: redacted ? theme.fgDisabled : theme.fgBody,
            ])
            let valH = measureHeight(valAttr, width: valW)
            let rowH = max(16, valH) + 6
            keyLbl.frame = NSRect(x: 11, y: by + inner + 3, width: keyW, height: 15)
            box.addSubview(keyLbl)
            let valLbl = NSTextField(labelWithAttributedString: valAttr)
            valLbl.isBezeled = false; valLbl.drawsBackground = false; valLbl.isEditable = false; valLbl.isSelectable = false
            valLbl.lineBreakMode = .byCharWrapping
            valLbl.maximumNumberOfLines = 0
            valLbl.frame = NSRect(x: 11 + keyW + 10, y: by + inner + 3, width: valW, height: max(15, valH))
            box.addSubview(valLbl)
            inner += rowH
        }
        box.frame.size.height = inner
        let total = by + inner
        v.frame = NSRect(x: 0, y: 0, width: width, height: total)
        return (v, total)
    }

    private func boxView(frame: NSRect) -> FlippedView {
        let b = FlippedView(frame: frame)
        b.wantsLayer = true
        b.layer?.cornerRadius = 9
        b.layer?.backgroundColor = theme.bgBase.cgColor
        b.layer?.borderColor = theme.borderDefault.cgColor
        b.layer?.borderWidth = 1
        return b
    }

    // MARK: - Data reload

    private func reloadData() {
        dataTabCount.stringValue = "\(snapshots.count)"
        colListDoc.subviews.forEach { $0.removeFromSuperview() }
        let w = COL_LIST_W - 12
        var y: CGFloat = 6
        for snap in snapshots {
            let row = makeColumnRow(snap, width: w, selected: snap.id == dataSel)
            row.frame = NSRect(x: 6, y: y, width: w, height: COL_ROW_H)
            colListDoc.addSubview(row)
            y += COL_ROW_H + 2
        }
        colListDoc.frame = NSRect(x: 0, y: 0, width: COL_LIST_W, height: y + 6)
        rebuildDataDetail()
    }

    private func makeColumnRow(_ snap: DebugColumnSnapshot, width: CGFloat, selected: Bool) -> HoverControl {
        let row = HoverControl(frame: NSRect(x: 0, y: 0, width: width, height: COL_ROW_H))
        row.wantsLayer = true
        row.layer?.cornerRadius = 9
        let icon = GlyphView(name: snap.icon, size: 17, color: theme.fgSubdued)
        icon.frame = NSRect(x: 9, y: (COL_ROW_H - 17) / 2, width: 17, height: 17)
        row.addSubview(icon)
        let labelX: CGFloat = 9 + 17 + 9
        let badgeW: CGFloat = 13
        let textW = width - labelX - badgeW - 9 - 6
        let label = makeLabel(snap.label, font: Fonts.sans(13, .bold), color: theme.fgHeading)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: labelX, y: 8, width: textW, height: 17)
        row.addSubview(label)
        let sub = makeLabel("\(snap.sub) · \(snap.count) " + (isX ? "items" : "条"), font: Fonts.sans(11), color: theme.fgSubdued)
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: labelX, y: 26, width: textW, height: 14)
        row.addSubview(sub)
        let badge = PlatformBadge(platform: snap.platform, size: badgeW)
        badge.frame = NSRect(x: width - 9 - badgeW, y: (COL_ROW_H - badgeW) / 2, width: badgeW, height: badgeW)
        row.addSubview(badge)
        let applyBg: (Bool) -> Void = { [weak self] hover in
            guard let self else { return }
            row.layer?.backgroundColor = (selected ? self.theme.gray100 : hover ? self.theme.gray75 : NSColor.clear).cgColor
        }
        applyBg(false)
        row.onState = { h, _ in applyBg(h) }
        row.onClick = { [weak self] in
            self?.dataSel = snap.id
            self?.reloadData()
        }
        return row
    }

    private func rebuildDataDetail() {
        let snap = snapshots.first(where: { $0.id == dataSel }) ?? snapshots.first
        // footer copy button
        colCopyBtn?.removeFromSuperview()
        if let snap {
            let json = snap.json
            let btn = CopyJsonButton(isX: isX, copyProvider: { json.prettyString() })
            colFooter.addSubview(btn)
            colCopyBtn = btn
        }
        // tree
        dataTree?.removeFromSuperview()
        if let snap {
            let tree = JSONTreeView(json: snap.json, theme: theme)
            dataTreeDoc.addSubview(tree)
            dataTree = tree
        } else {
            dataTree = nil
        }
        layoutDataDetail()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        card.frame = bounds
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: HEADER_H)
        headerBorder.frame = NSRect(x: 0, y: HEADER_H - 1, width: bounds.width, height: 1)
        layoutHeader()

        let bodyY = HEADER_H
        let bodyH = max(0, bounds.height - HEADER_H)
        netPane.frame = NSRect(x: 0, y: bodyY, width: bounds.width, height: bodyH)
        dataPane.frame = NSRect(x: 0, y: bodyY, width: bounds.width, height: bodyH)
        if active == "network" { layoutNetwork() } else { layoutData() }
    }

    private func layoutHeader() {
        traffic.frame.origin = NSPoint(x: 16, y: (HEADER_H - traffic.frame.height) / 2)
        let titleW = ceil(titleLabel.intrinsicContentSize.width)
        let titleX = 16 + traffic.frame.width + 14
        titleLabel.frame = NSRect(x: titleX, y: (HEADER_H - 18) / 2, width: titleW, height: 18)

        // pill tabs
        let netW = tabWidth(netTabLabel, netTabCount)
        let dataW = tabWidth(dataTabLabel, dataTabCount)
        let pillW = 2 + netW + 2 + dataW + 2
        pill.frame = NSRect(x: titleX + titleW + 10, y: (HEADER_H - 34) / 2, width: pillW, height: 34)
        netTabBtn.frame = NSRect(x: 2, y: 2, width: netW, height: 30)
        dataTabBtn.frame = NSRect(x: 2 + netW + 2, y: 2, width: dataW, height: 30)
        layoutTabContents(netTabBtn, netTabLabel, netTabCount)
        layoutTabContents(dataTabBtn, dataTabLabel, dataTabCount)

        let doneW = ceil(doneLabel.intrinsicContentSize.width) + 28
        doneBtn.frame = NSRect(x: bounds.width - 16 - doneW, y: (HEADER_H - 30) / 2, width: doneW, height: 30)
        doneLabel.frame = NSRect(x: 0, y: (30 - doneLabel.intrinsicContentSize.height) / 2, width: doneW, height: doneLabel.intrinsicContentSize.height)
    }

    private func tabWidth(_ label: NSTextField, _ count: NSTextField) -> CGFloat {
        14 + ceil(label.intrinsicContentSize.width) + 6 + ceil(count.intrinsicContentSize.width) + 14
    }

    private func layoutTabContents(_ btn: HoverControl, _ label: NSTextField, _ count: NSTextField) {
        let lw = ceil(label.intrinsicContentSize.width)
        let cw = ceil(count.intrinsicContentSize.width)
        label.frame = NSRect(x: 14, y: (30 - 16) / 2, width: lw, height: 16)
        count.frame = NSRect(x: 14 + lw + 6, y: (30 - 14) / 2, width: cw + 2, height: 14)
    }

    private func layoutNetwork() {
        // list header
        netListHeader.frame = NSRect(x: 0, y: 0, width: NET_LIST_W, height: SUBHEADER_H)
        netCountLabel.frame = NSRect(x: 12, y: (SUBHEADER_H - 14) / 2, width: 160, height: 14)
        let clearLW = ceil(netClearLabel.intrinsicContentSize.width)
        let clearW = 9 + 13 + 5 + clearLW + 9
        netClearBtn.frame = NSRect(x: NET_LIST_W - 12 - clearW, y: (SUBHEADER_H - 24) / 2, width: clearW, height: 24)
        netClearGlyph.frame = NSRect(x: 9, y: (24 - 13) / 2, width: 13, height: 13)
        netClearLabel.frame = NSRect(x: 9 + 13 + 5, y: (24 - 14) / 2, width: clearLW + 2, height: 14)
        netListHeaderBottom.frame = NSRect(x: 0, y: SUBHEADER_H - 1, width: NET_LIST_W, height: 1)

        netListScroll.frame = NSRect(x: 0, y: SUBHEADER_H, width: NET_LIST_W, height: netPane.frame.height - SUBHEADER_H)
        if netListDoc.frame.width != NET_LIST_W {
            netListDoc.frame.size.width = NET_LIST_W
        }
        netListDivider.frame = NSRect(x: NET_LIST_W, y: 0, width: 1, height: netPane.frame.height)
        netDetailScroll.frame = NSRect(x: NET_LIST_W + 1, y: 0, width: max(0, netPane.frame.width - NET_LIST_W - 1), height: netPane.frame.height)
        rebuildNetDetail()
    }

    private func layoutData() {
        colListHeader.frame = NSRect(x: 0, y: 0, width: COL_LIST_W, height: SUBHEADER_H)
        colListHeaderLabel.frame = NSRect(x: 12, y: (SUBHEADER_H - 14) / 2, width: COL_LIST_W - 24, height: 14)
        colListHeaderBottom.frame = NSRect(x: 0, y: SUBHEADER_H - 1, width: COL_LIST_W, height: 1)

        let footerH: CGFloat = 52
        colListScroll.frame = NSRect(x: 0, y: SUBHEADER_H, width: COL_LIST_W, height: max(0, dataPane.frame.height - SUBHEADER_H - footerH))
        colFooter.frame = NSRect(x: 0, y: dataPane.frame.height - footerH, width: COL_LIST_W, height: footerH)
        colFooterBorder.frame = NSRect(x: 0, y: 0, width: COL_LIST_W, height: 1)
        dataDivider.frame = NSRect(x: COL_LIST_W, y: 0, width: 1, height: dataPane.frame.height)
        dataTreeScroll.frame = NSRect(x: COL_LIST_W + 1, y: 0, width: max(0, dataPane.frame.width - COL_LIST_W - 1), height: dataPane.frame.height)
        layoutDataDetail()
    }

    private func layoutDataDetail() {
        if let btn = colCopyBtn {
            btn.frame.origin = NSPoint(x: 10, y: (52 - 30) / 2)
        }
        guard let tree = dataTree else {
            dataTreeDoc.frame = NSRect(x: 0, y: 0, width: dataTreeScroll.contentView.bounds.width, height: dataTreeScroll.contentView.bounds.height)
            return
        }
        let avail = dataTreeScroll.contentView.bounds.width
        guard avail > 0 else { return }
        tree.frame.origin = NSPoint(x: 16, y: 14)
        tree.rebuild(availableWidth: max(120, avail - 32))
        let docW = max(avail, tree.frame.maxX + 16)
        dataTreeDoc.frame = NSRect(x: 0, y: 0, width: docW, height: tree.frame.height + 14 + 18)
    }

    // MARK: - Debug hooks (snapshots)

    /// Select the top request row so its detail renders (PERCH_STATE=inspectordetail).
    func debugSelectFirstNetwork() {
        netSel = Array(DebugLog.shared.entries.reversed()).first?.id
        reloadNetwork()
        needsLayout = true
    }

    /// Switch to the Data tab (PERCH_STATE=inspectordata).
    func debugShowDataTab() { showTab("data") }

    // MARK: - Close / key handling

    private func closeInspector() { appState.closeInspector() }

    private func installMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { self.closeInspector(); return nil }
            return event
        }
    }
}

extension DebugInspectorView: PanelContentView {
    var panelPreferredSize: CGSize { CGSize(width: 860, height: 620) }
    var panelTitle: String { isX ? "Inspector" : "调试检查器" }
    func attach(to panel: PanelWindowController) { panelController = panel }
    var panelResizable: Bool { true }
    var panelMinSize: CGSize { CGSize(width: 680, height: 460) }
}

// MARK: - Chips & rows

private func methodColor(_ method: String, _ theme: Theme) -> NSColor {
    switch method.uppercased() {
    case "GET": return theme.scaleColor("blue-900")
    case "POST": return theme.scaleColor("green-800")
    case "PUT": return theme.scaleColor("orange-800")
    case "DELETE": return theme.scaleColor("red-800")
    case "PATCH": return theme.scaleColor("purple-800")
    default: return theme.gray600
    }
}

/// Colored uppercase HTTP-method pill.
final class MethodChip: FlippedView {
    init(method: String) {
        super.init(frame: .zero)
        let theme = ThemeManager.shared.theme
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = methodColor(method, theme).cgColor
        let lbl = makeLabel(method.uppercased(), font: Fonts.sans(10, .heavy), color: .white, align: .center)
        let w = max(50, ceil(lbl.intrinsicContentSize.width) + 12)
        frame = NSRect(x: 0, y: 0, width: w, height: 19)
        lbl.frame = NSRect(x: 0, y: (19 - lbl.intrinsicContentSize.height) / 2, width: w, height: lbl.intrinsicContentSize.height)
        addSubview(lbl)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Status dot + numeric code, colored by class (2xx green / 4xx orange / 5xx red).
final class StatusChip: FlippedView {
    init(status: Int?) {
        super.init(frame: .zero)
        let theme = ThemeManager.shared.theme
        let col: NSColor
        let text: String
        if let s = status {
            col = s >= 500 ? theme.scaleColor("red-900") : s >= 400 ? theme.scaleColor("orange-900") : theme.scaleColor("green-900")
            text = String(s)
        } else {
            col = theme.scaleColor("red-900"); text = "ERR"
        }
        let h: CGFloat = 16
        let lbl = makeLabel(text, font: Fonts.mono(12, .bold), color: col)
        let lw = ceil(lbl.intrinsicContentSize.width)
        frame = NSRect(x: 0, y: 0, width: 6 + 4 + lw, height: h)
        let dot = FlippedView(frame: NSRect(x: 0, y: (h - 6) / 2, width: 6, height: 6))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.layer?.backgroundColor = col.cgColor
        addSubview(dot)
        lbl.frame = NSRect(x: 10, y: (h - lbl.intrinsicContentSize.height) / 2, width: lw, height: lbl.intrinsicContentSize.height)
        addSubview(lbl)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// One request row in the Network list.
final class NetRowView: HoverControl {
    let entryId: String
    private let theme = ThemeManager.shared.theme
    private let selected: Bool

    init(entry: DebugLogEntry, selected: Bool, width: CGFloat, onSelect: @escaping (String) -> Void) {
        self.entryId = entry.id
        self.selected = selected
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 47))
        wantsLayer = true

        let chip = MethodChip(method: entry.method)
        chip.frame.origin = NSPoint(x: 12, y: (47 - chip.frame.height) / 2)
        addSubview(chip)

        // right cluster: status + ms
        let status = StatusChip(status: entry.status)
        let msText = entry.durationMs.map { "\($0)ms" } ?? "—"
        let msLbl = makeLabel(msText, font: Fonts.mono(10.5), color: theme.fgDisabled, align: .right)
        let msW = ceil(msLbl.intrinsicContentSize.width)
        let clusterW = max(status.frame.width, msW)
        let clusterX = width - 12 - clusterW
        status.frame.origin = NSPoint(x: clusterX + clusterW - status.frame.width, y: 8)
        addSubview(status)
        msLbl.frame = NSRect(x: clusterX, y: 26, width: clusterW, height: 13)
        addSubview(msLbl)

        // middle: path + query
        let midX = 12 + chip.frame.width + 9
        let midW = max(20, clusterX - 9 - midX)
        let path = makeLabel(entry.path.isEmpty ? "/" : entry.path, font: Fonts.mono(12.5, .semibold), color: entry.isError ? theme.negative : theme.fgHeading)
        path.lineBreakMode = .byTruncatingMiddle
        path.frame = NSRect(x: midX, y: 8, width: midW, height: 16)
        addSubview(path)
        let query = makeLabel(entry.query.isEmpty ? "—" : entry.query, font: Fonts.mono(11), color: theme.fgSubdued)
        query.lineBreakMode = .byTruncatingTail
        query.frame = NSRect(x: midX, y: 26, width: midW, height: 14)
        addSubview(query)

        let border = NSView(frame: NSRect(x: 0, y: 46, width: width, height: 1))
        border.wantsLayer = true
        border.layer?.backgroundColor = theme.borderDefault.cgColor
        addSubview(border)

        onClick = { onSelect(entry.id) }
        onState = { [weak self] h, _ in self?.applyBg(hover: h) }
        applyBg(hover: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func applyBg(hover: Bool) {
        if selected {
            layer?.backgroundColor = theme.accent.withAlphaComponent(0.12).cgColor
        } else {
            layer?.backgroundColor = (hover ? theme.gray75 : NSColor.clear).cgColor
        }
    }
}

private extension NSFont {
    func withItalic() -> NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .italicFontMask)
    }
}
