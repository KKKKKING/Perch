import AppKit

private final class PopUpTarget: NSObject {
    let cb: (Int) -> Void
    init(_ cb: @escaping (Int) -> Void) { self.cb = cb }
    @objc func fire(_ sender: NSPopUpButton) { cb(sender.indexOfSelectedItem) }
}

/// Bottom column-manager tray with drag-to-reorder, type/account swap, add/remove.
final class ColumnManagerView: FlippedView {
    private let appState: AppState
    private let onDone: () -> Void
    private let theme = ThemeManager.shared.theme
    private var targets: [PopUpTarget] = []

    private let cardsContainer = FlippedView()
    private var cardViews: [NSView] = []        // editable + fixed card views, index aligned to columns
    private var addCard: NSView!

    // drag state
    private var dragIndex: Int? = nil
    private var dragView: NSView? = nil
    private var overIndex: Int? = nil
    private var dragOffset: CGFloat = 0

    static let trayHeight: CGFloat = 256

    init(appState: AppState, onDone: @escaping () -> Void) {
        self.appState = appState
        self.onDone = onDone
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = theme.bgElevated.cgColor
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private var isX: Bool { appState.active.platform == .x }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        targets.removeAll()
        let isX = self.isX

        // top border
        let topBorder = NSView(frame: NSRect(x: 0, y: 0, width: 2000, height: 1))
        topBorder.wantsLayer = true
        topBorder.layer?.backgroundColor = theme.borderDefault.cgColor
        topBorder.autoresizingMask = [.width]
        addSubview(topBorder)

        // header
        let icon = GlyphView(name: "columns", size: 20, color: theme.fgHeading)
        icon.frame = NSRect(x: 18, y: 14, width: 20, height: 20)
        addSubview(icon)
        let title = makeLabel(isX ? "Arrange columns" : "排列分栏", font: Fonts.sans(15.5, .heavy), color: theme.fgHeading)
        title.frame = NSRect(x: 48, y: 12, width: 400, height: 20)
        addSubview(title)
        let sub = makeLabel(isX ? "Drag to reorder · swap type & account · add or remove" : "拖动排序 · 切换类型与账号 · 添加或移除",
                            font: Fonts.sans(12), color: theme.fgSubdued)
        sub.frame = NSRect(x: 48, y: 31, width: 500, height: 16)
        addSubview(sub)
        let done = HoverControl(frame: .zero)
        done.wantsLayer = true
        done.layer?.cornerRadius = 9
        done.layer?.backgroundColor = theme.accentBg.cgColor
        let doneLbl = makeLabel(isX ? "Done" : "完成", font: Fonts.sans(13.5, .bold), color: .white, align: .center)
        let dw = doneLbl.intrinsicContentSize.width + 32
        done.frame = NSRect(x: 0, y: 13, width: dw, height: 32)
        doneLbl.frame = NSRect(x: 0, y: (32 - doneLbl.intrinsicContentSize.height) / 2, width: dw, height: doneLbl.intrinsicContentSize.height)
        done.addSubview(doneLbl)
        done.onClick = { [weak self] in self?.onDone() }
        addSubview(done)
        done.frame.origin.x = 0 // set in layout
        doneButton = done

        cardsContainer.frame = NSRect(x: 0, y: 60, width: 2000, height: 180)
        addSubview(cardsContainer)
        buildCards()
    }

    private var doneButton: HoverControl!

    private func buildCards() {
        cardsContainer.subviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        let isX = self.isX
        let cardH: CGFloat = 168

        for (i, col) in appState.columns.enumerated() {
            let card = makeCard(col: col, index: i, isFixed: i == 0, height: cardH)
            cardsContainer.addSubview(card)
            cardViews.append(card)
        }

        // add card
        let add = HoverControl(frame: NSRect(x: 0, y: 6, width: 132, height: cardH))
        add.wantsLayer = true
        add.layer?.cornerRadius = 12
        add.layer?.borderColor = theme.gray400.cgColor
        add.layer?.borderWidth = 1.5
        // dashed border
        let dashed = CAShapeLayer()
        dashed.strokeColor = theme.gray400.cgColor
        dashed.fillColor = NSColor.clear.cgColor
        dashed.lineDashPattern = [5, 4]
        dashed.lineWidth = 1.5
        dashed.path = CGPath(roundedRect: NSRect(x: 0.75, y: 0.75, width: 132 - 1.5, height: cardH - 1.5), cornerWidth: 12, cornerHeight: 12, transform: nil)
        add.layer?.borderWidth = 0
        add.layer?.addSublayer(dashed)
        let circle = FlippedView(frame: NSRect(x: (132 - 34) / 2, y: cardH / 2 - 24, width: 34, height: 34))
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 17
        circle.layer?.borderColor = theme.fgSubdued.cgColor
        circle.layer?.borderWidth = 1.5
        let plus = GlyphView(name: "add", size: 18, color: theme.fgSubdued)
        plus.frame = NSRect(x: 8, y: 8, width: 18, height: 18)
        circle.addSubview(plus)
        add.addSubview(circle)
        let addLbl = makeLabel(isX ? "Add column" : "添加分栏", font: Fonts.sans(13, .bold), color: theme.fgSubdued, align: .center)
        addLbl.frame = NSRect(x: 0, y: cardH / 2 + 16, width: 132, height: 17)
        add.addSubview(addLbl)
        add.onClick = { [weak self] in self?.appState.addColumn("home") }
        cardsContainer.addSubview(add)
        addCard = add

        relayoutCards()
    }

    private func makeCard(col: ColumnSpec, index: Int, isFixed: Bool, height cardH: CGFloat) -> NSView {
        let isX = self.isX
        let acct = (col.accountId.flatMap { appState.account($0) }) ?? appState.active
        let cIsX = acct.platform == .x
        let meta = colMeta(col.type)

        let card = FlippedView(frame: NSRect(x: 0, y: 6, width: UI.cardW, height: cardH))
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.backgroundColor = theme.bgBase.cgColor
        card.layer?.borderColor = theme.borderDefault.cgColor
        card.layer?.borderWidth = 1
        card.layer?.masksToBounds = true

        // header
        let header = FlippedView(frame: NSRect(x: 0, y: 0, width: UI.cardW, height: 37))
        header.wantsLayer = true
        header.layer?.backgroundColor = theme.bgLayer1.cgColor
        var hx: CGFloat = isFixed ? 10 : 6
        if !isFixed {
            let grip = GripHandle(onDragBegan: { [weak self] in self?.beginDrag(index: index, card: card) },
                                  onDragChanged: { [weak self] p in self?.dragChanged(globalPoint: p) },
                                  onDragEnded: { [weak self] in self?.endDrag() })
            grip.frame = NSRect(x: hx, y: 9, width: 18, height: 18)
            header.addSubview(grip)
            hx += 18 + 7
        }
        let micon = GlyphView(name: meta.icon, size: 17, color: theme.fgHeading)
        micon.frame = NSRect(x: hx, y: 10, width: 17, height: 17)
        header.addSubview(micon)
        hx += 17 + 7
        let label = makeLabel(cIsX ? meta.labelX : meta.labelW, font: Fonts.sans(13.5, .heavy), color: theme.fgHeading)
        label.frame = NSRect(x: hx, y: 10, width: UI.cardW - hx - 50, height: 17)
        header.addSubview(label)
        if isFixed {
            let badge = FlippedView(frame: NSRect(x: UI.cardW - 10 - 46, y: 8, width: 46, height: 20))
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 6
            badge.layer?.backgroundColor = theme.gray100.cgColor
            let bl = makeLabel(isX ? "Fixed" : "固定", font: Fonts.sans(9.5, .heavy), color: theme.fgSubdued, align: .center)
            bl.frame = NSRect(x: 0, y: 3, width: 46, height: 14)
            badge.addSubview(bl)
            header.addSubview(badge)
        } else {
            let idxLbl = makeLabel("\(index + 1)", font: Fonts.sans(10, .heavy), color: theme.fgDisabled)
            idxLbl.frame = NSRect(x: UI.cardW - 56, y: 12, width: 16, height: 14)
            header.addSubview(idxLbl)
            let close = HoverControl(frame: NSRect(x: UI.cardW - 30, y: 6, width: 24, height: 24))
            close.wantsLayer = true
            close.layer?.cornerRadius = 7
            let cg = GlyphView(name: "close", size: 14, color: theme.fgSubdued)
            cg.frame = NSRect(x: 5, y: 5, width: 14, height: 14)
            close.addSubview(cg)
            close.onState = { h, _ in
                close.layer?.backgroundColor = (h ? self.theme.negative.withAlphaComponent(0.14) : NSColor.clear).cgColor
                cg.color = h ? self.theme.negative : self.theme.fgSubdued
            }
            close.onClick = { [weak self] in self?.appState.closeColumn(col.id) }
            header.addSubview(close)
        }
        card.addSubview(header)

        // controls
        var cy: CGFloat = 37 + 10
        let typeLbl = makeLabel(isX ? "TYPE" : "类型", font: Fonts.sans(10.5, .heavy), color: theme.fgSubdued)
        typeLbl.frame = NSRect(x: 10, y: cy, width: UI.cardW - 20, height: 13)
        card.addSubview(typeLbl)
        cy += 17
        let typePop = NSPopUpButton(frame: NSRect(x: 10, y: cy, width: UI.cardW - 20, height: 28))
        for t in ADDABLE { typePop.addItem(withTitle: cIsX ? colMeta(t).labelX : colMeta(t).labelW) }
        if let ti = ADDABLE.firstIndex(of: col.type) { typePop.selectItem(at: ti) }
        let tTarget = PopUpTarget { [weak self] idx in
            guard let self else { return }
            let type = ADDABLE[idx]
            if isFixed { self.appState.setPrimaryType(type) } else { self.appState.setColType(col.id, type) }
        }
        typePop.target = tTarget; typePop.action = #selector(PopUpTarget.fire(_:))
        targets.append(tTarget)
        card.addSubview(typePop)
        cy += 28 + 10

        let acctLbl = makeLabel(isX ? "ACCOUNT" : "账号", font: Fonts.sans(10.5, .heavy), color: theme.fgSubdued)
        acctLbl.frame = NSRect(x: 10, y: cy, width: UI.cardW - 20, height: 13)
        card.addSubview(acctLbl)
        cy += 17
        let av = AvatarView(person: acct, size: 24)
        av.frame = NSRect(x: 10, y: cy, width: 24, height: 24)
        card.addSubview(av)
        let badge2 = PlatformBadge(platform: acct.platform, size: 12)
        badge2.frame = NSRect(x: 10 + 15, y: cy + 15, width: 12, height: 12)
        card.addSubview(badge2)
        let acctPop = NSPopUpButton(frame: NSRect(x: 41, y: cy, width: UI.cardW - 51, height: 28))
        for a in appState.accounts { acctPop.addItem(withTitle: a.name + (a.platform == .x ? " · X" : " · 微博")) }
        let curAcctId = col.accountId ?? appState.active.id
        if let ai = appState.accounts.firstIndex(where: { $0.id == curAcctId }) { acctPop.selectItem(at: ai) }
        let aTarget = PopUpTarget { [weak self] idx in
            guard let self else { return }
            self.appState.setColAccount(col.id, self.appState.accounts[idx].id!)
        }
        acctPop.target = aTarget; acctPop.action = #selector(PopUpTarget.fire(_:))
        targets.append(aTarget)
        card.addSubview(acctPop)

        return card
    }

    private func relayoutCards() {
        let startX: CGFloat = 18
        let gap: CGFloat = 12
        let slotW: CGFloat = 64
        var x = startX
        var slotX: CGFloat? = nil
        // Single pass drives both card layout and placeholder so they can't disagree.
        // The placeholder is checked at every column index (incl. dragIndex) so dropping
        // back in place shows the slot at the dragged card's home position.
        for (ci, card) in cardViews.enumerated() {
            if dragIndex != nil, overIndex == ci {
                slotX = x
                x += slotW + gap
            }
            if ci == dragIndex { continue }   // dragged card floats; not in flow
            card.frame.origin.x = x
            x += UI.cardW + gap
        }
        if dragIndex != nil, overIndex == cardViews.count {
            slotX = x
            x += slotW + gap
        }
        addCard.frame.origin.x = x
        cardsContainer.frame.size.width = x + 132 + 18

        // position / show drop slot from the single recorded slotX
        dropSlot?.removeFromSuperview()
        dropSlot = nil
        if dragIndex != nil, let slotX {
            let slot = makeDropSlot()
            slot.frame = NSRect(x: slotX, y: 6, width: slotW, height: 168)
            cardsContainer.addSubview(slot)
            dropSlot = slot
        }
    }

    private var dropSlot: NSView?

    private func makeDropSlot() -> NSView {
        let v = FlippedView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.backgroundColor = theme.accent.withAlphaComponent(0.09).cgColor
        let dashed = CAShapeLayer()
        dashed.strokeColor = theme.accent.cgColor
        dashed.fillColor = NSColor.clear.cgColor
        dashed.lineDashPattern = [5, 4]
        dashed.lineWidth = 2
        dashed.path = CGPath(roundedRect: NSRect(x: 1, y: 1, width: 62, height: 166), cornerWidth: 12, cornerHeight: 12, transform: nil)
        v.layer?.addSublayer(dashed)
        return v
    }

    // ── drag handling ──
    private func beginDrag(index: Int, card: NSView) {
        guard index > 0 else { return }
        dragIndex = index
        dragView = card
        overIndex = index
        card.layer?.shadowOpacity = 0.3
        card.layer?.shadowRadius = 16
        card.layer?.shadowOffset = CGSize(width: 0, height: -6)
        card.layer?.zPosition = 100
        relayoutCards()
    }

    private func dragChanged(globalPoint: NSPoint) {
        guard let dragIndex, let dragView else { return }
        let local = cardsContainer.convert(globalPoint, from: nil)
        dragView.frame.origin.x = local.x - UI.cardW / 2
        dragView.frame.origin.y = 6
        // compute insertion index by walking the compacted (placeholder-free) layout,
        // using the prototype's left/right-half rule. overIndex is an insertion index in
        // [1, count] over original column indices, matching reorderColumns.
        let startX: CGFloat = 18
        let gap: CGFloat = 12
        var found: Int? = nil
        var x = startX
        for ci in 0..<cardViews.count {
            if ci == dragIndex { continue }   // dragged card not in flow
            if local.x < x + UI.cardW / 2 { found = ci; break }   // left half → before ci
            found = ci + 1                                        // right half → after ci
            x += UI.cardW + gap
        }
        overIndex = min(max(found ?? cardViews.count, 1), cardViews.count)
        relayoutCards()
        dragView.frame.origin.x = local.x - UI.cardW / 2
    }

    private func endDrag() {
        guard let dragIndex else { return }
        let target = overIndex ?? dragIndex
        dragView?.layer?.shadowOpacity = 0
        dragView?.layer?.zPosition = 0
        self.dragIndex = nil
        self.dragView = nil
        self.overIndex = nil
        dropSlot?.removeFromSuperview()
        dropSlot = nil
        appState.reorderColumns(dragIndex, target)
    }

    override func layout() {
        super.layout()
        doneButton.frame.origin = CGPoint(x: bounds.width - 18 - doneButton.frame.width, y: 13)
    }

    func refresh() { buildCards() }
}

/// Grip handle that initiates a card drag on mouse drag.
final class GripHandle: NSView {
    private let onDragBegan: () -> Void
    private let onDragChanged: (NSPoint) -> Void
    private let onDragEnded: () -> Void
    private var dragging = false

    init(onDragBegan: @escaping () -> Void, onDragChanged: @escaping (NSPoint) -> Void, onDragEnded: @escaping () -> Void) {
        self.onDragBegan = onDragBegan
        self.onDragChanged = onDragChanged
        self.onDragEnded = onDragEnded
        super.init(frame: .zero)
        let g = GlyphView(name: "grip", size: 18, color: ThemeManager.shared.theme.fgDisabled)
        addSubview(g)
        g.frame = NSRect(x: 0, y: 0, width: 18, height: 18)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) { /* wait for drag */ }
    override func mouseDragged(with event: NSEvent) {
        if !dragging { dragging = true; onDragBegan() }
        onDragChanged(event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        if dragging { dragging = false; onDragEnded() }
    }
}
