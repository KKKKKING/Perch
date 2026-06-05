import AppKit

/// "Configure navigation" modal — port of design/project/app/navconfig.jsx.
/// Two lists (Sidebar / Overflow menu) whose rows are dragged within and between
/// each other; every drop persists via `setNavConfig` so the rail behind the scrim
/// updates live. Adds the Perch constraint that the sidebar keeps ≥1 item.
final class NavConfigDialogView: FlippedView {
    private let appState: AppState
    private let onClose: () -> Void
    private let theme = ThemeManager.shared.theme
    private var isX: Bool { appState.active.platform == .x }

    private let card = FlippedView()
    private let barList = FlippedView()
    private let menuList = FlippedView()
    private let barIndicator = NSView()
    private let menuIndicator = NSView()
    private var barRows: [(id: String, view: NavRowView)] = []
    private var menuRows: [(id: String, view: NavRowView)] = []

    // drag state
    private var dragId: String?
    private var dragFrom: String?               // "bar" / "menu"
    private var over: (list: String, index: Int)?
    private var dragGhost: NSView?

    private let cardW: CGFloat = 460
    private let pad: CGFloat = 16
    private var innerW: CGFloat { cardW - pad * 2 }
    private let rowH: CGFloat = 46
    private let stride: CGFloat = 47            // row + 1px divider

    init(appState: AppState, onClose: @escaping () -> Void) {
        self.appState = appState
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
        for (list, ind) in [(barList, barIndicator), (menuList, menuIndicator)] {
            list.wantsLayer = true
            list.layer?.backgroundColor = theme.bgBase.cgColor
            list.layer?.cornerRadius = 12
            list.layer?.borderColor = theme.borderDefault.cgColor
            list.layer?.borderWidth = 1
            list.layer?.masksToBounds = true
            ind.wantsLayer = true
            ind.layer?.backgroundColor = theme.accent.cgColor
            ind.layer?.cornerRadius = 1
            ind.isHidden = true
        }
        buildCard()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if !card.frame.contains(pt) { onClose() }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose() } else { super.keyDown(with: event) }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let s = card.frame.size
        card.frame = NSRect(x: floor((bounds.width - s.width) / 2),
                            y: floor((bounds.height - s.height) / 2), width: s.width, height: s.height)
    }

    // ── build ──
    private func buildCard() {
        card.subviews.forEach { $0.removeFromSuperview() }
        barRows.removeAll(); menuRows.removeAll()

        let headerH: CGFloat = 62
        buildHeader(headerH: headerH)
        var y = headerH + 1 + pad

        y = buildSection(y: y,
                         title: isX ? "SIDEBAR" : "侧边栏",
                         list: "bar",
                         helper: isX ? "Shown as icons directly in the rail, top to bottom." : "以图标形式从上到下显示在侧栏中。")
        y += 18
        y = buildSection(y: y,
                         title: isX ? "OVERFLOW MENU  ·  ⋯" : "更多菜单  ·  ⋯",
                         list: "menu",
                         helper: isX ? "Tucked inside the ⋯ button at the bottom of the icons." : "收纳在图标底部的 ⋯ 按钮中。")
        y += pad

        card.frame.size = NSSize(width: cardW, height: y)
        needsLayout = true
    }

    private func buildHeader(headerH: CGFloat) {
        let band: CGFloat = 32
        let top = (headerH - band) / 2
        let gear = GlyphView(name: "gear", size: 20, color: theme.fgHeading)
        gear.frame = NSRect(x: pad, y: top + (band - 20) / 2, width: 20, height: 20)
        card.addSubview(gear)

        let title = makeLabel(isX ? "Configure navigation" : "自定义导航",
                              font: Fonts.sans(16, .heavy), color: theme.fgHeading)
        title.lineBreakMode = .byTruncatingTail

        let doneText = isX ? "Done" : "完成"
        let doneFont = Fonts.sans(13.5, .bold)
        let doneW = ceil((doneText as NSString).size(withAttributes: [.font: doneFont]).width) + 32
        let done = HoverControl(frame: NSRect(x: cardW - pad - doneW, y: top, width: doneW, height: band))
        done.wantsLayer = true
        done.layer?.cornerRadius = 9
        done.layer?.backgroundColor = theme.accentBg.cgColor
        let dl = makeLabel(doneText, font: doneFont, color: .white, align: .center)
        dl.frame = NSRect(x: 0, y: (band - dl.perchSingleLineHeight) / 2, width: doneW, height: dl.perchSingleLineHeight)
        done.addSubview(dl)
        done.onState = { [weak self] h, _ in
            guard let self else { return }
            done.layer?.backgroundColor = (h ? self.theme.accentBgHover : self.theme.accentBg).cgColor
        }
        done.onClick = { [weak self] in self?.onClose() }
        card.addSubview(done)

        let titleX = pad + 20 + 11
        title.placeSingleLine(x: titleX, y: top, width: done.frame.minX - 10 - titleX, height: band)
        card.addSubview(title)

        let line = NSView(frame: NSRect(x: 0, y: headerH, width: cardW, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        card.addSubview(line)
    }

    private func buildSection(y: CGFloat, title: String, list: String, helper: String) -> CGFloat {
        var y = y
        let lab = sectionLabel(title)
        lab.frame = NSRect(x: pad + 2, y: y, width: innerW - 4, height: 15)
        card.addSubview(lab)
        y += 15 + 8

        let container = list == "bar" ? barList : menuList
        container.frame.origin = NSPoint(x: pad, y: y)
        container.frame.size.width = innerW
        buildList(list)
        card.addSubview(container)
        y += container.frame.height

        y += 8
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = 1.45
        let attr = NSAttributedString(string: helper, attributes: [
            .font: Fonts.sans(12.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: para])
        let helpH = measureHeight(attr, width: innerW - 4)
        let help = NSTextField(labelWithAttributedString: attr)
        help.isBezeled = false; help.drawsBackground = false; help.isEditable = false; help.isSelectable = false
        help.frame = NSRect(x: pad + 2, y: y, width: innerW - 4, height: helpH)
        card.addSubview(help)
        y += helpH
        return y
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let attr = NSAttributedString(string: text, attributes: [
            .font: Fonts.sans(11.5, .bold), .foregroundColor: theme.fgSubdued, .kern: 0.69])
        let l = NSTextField(labelWithAttributedString: attr)
        l.isBezeled = false; l.drawsBackground = false; l.isEditable = false; l.isSelectable = false
        return l
    }

    private func buildList(_ list: String) {
        let container = list == "bar" ? barList : menuList
        let indicator = list == "bar" ? barIndicator : menuIndicator
        container.subviews.forEach { $0.removeFromSuperview() }
        let ids = appState.navConfig[list]

        if ids.isEmpty {
            container.frame.size.height = 50
            let empty = makeLabel(isX ? "Drag items here" : "拖动到此处",
                                  font: Fonts.sans(13, .semibold), color: theme.fgDisabled, align: .center)
            empty.frame = NSRect(x: 0, y: (50 - empty.perchSingleLineHeight) / 2, width: innerW, height: empty.perchSingleLineHeight)
            container.addSubview(empty)
        } else {
            container.frame.size.height = CGFloat(ids.count) * stride - 1
            var rows: [(id: String, view: NavRowView)] = []
            for (i, id) in ids.enumerated() {
                if i > 0 {
                    let div = NSView(frame: NSRect(x: 12, y: CGFloat(i) * stride - 1, width: innerW - 24, height: 1))
                    div.wantsLayer = true
                    div.layer?.backgroundColor = theme.borderDefault.cgColor
                    container.addSubview(div)
                }
                let row = NavRowView(id: id, list: list, isX: isX, theme: theme, width: innerW,
                                     onBegin: { [weak self] pt in self?.beginDrag(id: id, from: list, at: pt) },
                                     onChanged: { [weak self] pt in self?.dragChanged(at: pt) },
                                     onEnded: { [weak self] in self?.endDrag() })
                row.frame = NSRect(x: 0, y: CGFloat(i) * stride, width: innerW, height: rowH)
                container.addSubview(row)
                rows.append((id, row))
            }
            if list == "bar" { barRows = rows } else { menuRows = rows }
        }
        container.addSubview(indicator)   // keep on top
    }

    // ── drag ──
    private func beginDrag(id: String, from: String, at windowPoint: NSPoint) {
        dragId = id
        dragFrom = from
        let g = makeGhost(id: id)
        card.addSubview(g)
        dragGhost = g
        dragChanged(at: windowPoint)
    }

    private func dragChanged(at windowPoint: NSPoint) {
        guard dragId != nil else { return }
        let p = card.convert(windowPoint, from: nil)
        dragGhost?.frame.origin = NSPoint(x: pad, y: p.y - rowH / 2)

        let split = (barList.frame.maxY + menuList.frame.minY) / 2
        let list = p.y < split ? "bar" : "menu"
        let container = list == "bar" ? barList : menuList
        let localY = p.y - container.frame.minY
        let count = appState.navConfig[list].count
        var idx = count
        for k in 0..<count where localY < CGFloat(k) * stride + rowH / 2 { idx = k; break }
        over = (list, idx)
        updateDragVisuals()
    }

    private func updateDragVisuals() {
        for (id, row) in barRows { row.alphaValue = (dragId == id) ? 0.45 : 1 }
        for (id, row) in menuRows { row.alphaValue = (dragId == id) ? 0.45 : 1 }
        positionIndicator(list: "bar")
        positionIndicator(list: "menu")
    }

    private func positionIndicator(list: String) {
        let indicator = list == "bar" ? barIndicator : menuIndicator
        guard dragId != nil, let over, over.list == list else { indicator.isHidden = true; return }
        // ≥1-bar constraint: suppress the menu drop hint while dragging the only sidebar item.
        if dragFrom == "bar", list == "menu", appState.navConfig.bar.count == 1 { indicator.isHidden = true; return }
        let container = list == "bar" ? barList : menuList
        let count = appState.navConfig[list].count
        let h = container.frame.height
        let yy: CGFloat
        if over.index <= 0 { yy = 0 }
        else if over.index >= count { yy = h - 2 }
        else { yy = CGFloat(over.index) * stride - 2 }
        indicator.frame = NSRect(x: 10, y: yy, width: innerW - 20, height: 2)
        indicator.isHidden = false
    }

    private func endDrag() {
        let id = dragId, from = dragFrom, target = over
        if let id, let from, let target {
            var next = appState.navConfig
            if let srcIdx = next[from].firstIndex(of: id) {
                let blocked = (from == "bar" && target.list == "menu" && next.bar.count == 1)
                if !blocked {
                    next[from].remove(at: srcIdx)
                    var idx = target.index
                    if from == target.list, srcIdx < idx { idx -= 1 }
                    idx = max(0, min(idx, next[target.list].count))
                    next[target.list].insert(id, at: idx)
                    appState.setNavConfig(next)
                }
            }
        }
        dragId = nil; dragFrom = nil; over = nil
        // Defer the rebuild: it removes the very NavRowView whose mouseUp we're in.
        DispatchQueue.main.async { [weak self] in
            self?.dragGhost?.removeFromSuperview()
            self?.dragGhost = nil
            self?.buildCard()
        }
    }

    private func makeGhost(id: String) -> NSView {
        let g = FlippedView(frame: NSRect(x: pad, y: 0, width: innerW, height: rowH))
        g.wantsLayer = true
        g.layer?.backgroundColor = theme.bgElevated.cgColor
        g.layer?.cornerRadius = 10
        g.layer?.borderColor = theme.borderDefault.cgColor
        g.layer?.borderWidth = 1
        g.layer?.shadowColor = theme.gray1000.cgColor
        g.layer?.shadowOpacity = 0.22
        g.layer?.shadowRadius = 14
        g.layer?.shadowOffset = CGSize(width: 0, height: -4)
        if let meta = NAV_ITEMS[id] {
            let glyph = GlyphView(name: meta.glyph, size: 21, color: theme.accent)
            glyph.frame = NSRect(x: 12, y: (rowH - 21) / 2, width: 21, height: 21)
            g.addSubview(glyph)
            let lbl = makeLabel(isX ? meta.labelX : meta.labelW, font: Fonts.sans(14.5, .semibold), color: theme.fgHeading)
            lbl.placeSingleLine(x: 45, y: 0, width: innerW - 45 - 30, height: rowH)
            g.addSubview(lbl)
        }
        return g
    }
}

/// One draggable row inside either nav list. The whole row initiates the drag
/// (no separate grip handle), matching the prototype's `cursor: grab`.
private final class NavRowView: FlippedView {
    private let onBegin: (NSPoint) -> Void
    private let onChanged: (NSPoint) -> Void
    private let onEnded: () -> Void
    private var dragging = false
    private var hovering = false
    private let theme: Theme
    private let grip: GlyphView
    private var trackingAreaRef: NSTrackingArea?

    init(id: String, list: String, isX: Bool, theme: Theme, width: CGFloat,
         onBegin: @escaping (NSPoint) -> Void, onChanged: @escaping (NSPoint) -> Void, onEnded: @escaping () -> Void) {
        self.onBegin = onBegin
        self.onChanged = onChanged
        self.onEnded = onEnded
        self.theme = theme
        self.grip = GlyphView(name: "grip", size: 20, color: theme.fgDisabled)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = theme.bgBase.cgColor
        let meta = NAV_ITEMS[id]
        let glyph = GlyphView(name: meta?.glyph ?? "home", size: 21, color: theme.accent)
        glyph.frame = NSRect(x: 12, y: (46 - 21) / 2, width: 21, height: 21)
        addSubview(glyph)
        let lbl = makeLabel(isX ? (meta?.labelX ?? id) : (meta?.labelW ?? id),
                            font: Fonts.sans(14.5, .semibold), color: theme.fgHeading)
        lbl.lineBreakMode = .byTruncatingTail
        lbl.placeSingleLine(x: 45, y: 0, width: width - 45 - 12 - 20 - 10, height: 46)
        addSubview(lbl)
        grip.frame = NSRect(x: width - 10 - 20, y: (46 - 20) / 2, width: 20, height: 20)
        addSubview(grip)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }
    override func mouseEntered(with event: NSEvent) {
        hovering = true
        layer?.backgroundColor = theme.gray75.cgColor
        grip.color = theme.fgSubdued
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        if !dragging {
            layer?.backgroundColor = theme.bgBase.cgColor
            grip.color = theme.fgDisabled
        }
    }
    override func mouseDown(with event: NSEvent) { /* wait for drag */ }
    override func mouseDragged(with event: NSEvent) {
        if !dragging { dragging = true; onBegin(event.locationInWindow) }
        else { onChanged(event.locationInWindow) }
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { dragging = false; onEnded() }
    }
}
