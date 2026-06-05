import AppKit

/// What a JSON viewer window shows — one tweet, or one whole column's data.
struct JsonViewerContext {
    let title: String
    let subtitle: String
    let json: DebugJSON
}

/// A standalone window rendering one `DebugJSON` payload as a collapsible, syntax-colored
/// tree with a Copy button (port of the design's `JsonModal`). Multiple can coexist so
/// tweets can be compared side by side.
final class JsonViewerView: FlippedView {
    private let ctx: JsonViewerContext
    private let theme = ThemeManager.shared.theme
    private let isX: Bool
    private weak var panelController: PanelWindowController?

    private let card = FlippedView()
    private let header = FlippedView()
    private let headerBorder = NSView()
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private let tree: JSONTreeView
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField
    private var traffic: NSView!
    private var copyBtn: CopyJsonButton!

    private let HEADER_H: CGFloat = 52
    private let bodyPadX: CGFloat = 18
    private let bodyPadTop: CGFloat = 14
    private let bodyPadBottom: CGFloat = 18

    init(ctx: JsonViewerContext, isX: Bool) {
        self.ctx = ctx
        self.isX = isX
        let theme = ThemeManager.shared.theme
        self.tree = JSONTreeView(json: ctx.json, theme: theme)
        self.titleLabel = makeLabel(ctx.title, font: Fonts.sans(14.5, .heavy), color: theme.fgHeading)
        self.subtitleLabel = makeLabel(ctx.subtitle, font: Fonts.mono(11.5), color: theme.fgSubdued)
        super.init(frame: NSRect(x: 0, y: 0, width: 560, height: 600))
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

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

        header.wantsLayer = true
        header.layer?.backgroundColor = theme.bgElevated.cgColor
        card.addSubview(header)

        traffic = makeTrafficLights(onClose: { [weak self] in self?.close() })
        header.addSubview(traffic)

        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        header.addSubview(titleLabel)
        if !ctx.subtitle.isEmpty { header.addSubview(subtitleLabel) }

        let json = ctx.json
        copyBtn = CopyJsonButton(isX: isX, copyProvider: { json.prettyString() })
        header.addSubview(copyBtn)

        headerBorder.wantsLayer = true
        headerBorder.layer?.backgroundColor = theme.borderDefault.cgColor
        header.addSubview(headerBorder)

        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = theme.bgLayer1
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = doc
        doc.addSubview(tree)
        card.addSubview(scroll)
    }

    override func layout() {
        super.layout()
        card.frame = bounds
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: HEADER_H)
        headerBorder.frame = NSRect(x: 0, y: HEADER_H - 1, width: bounds.width, height: 1)

        traffic.frame.origin = NSPoint(x: 16, y: (HEADER_H - traffic.frame.height) / 2)
        let cw = copyBtn.frame.width
        copyBtn.frame = NSRect(x: bounds.width - 16 - cw, y: (HEADER_H - 30) / 2, width: cw, height: 30)

        let tx = 16 + traffic.frame.width + 12
        let titleRight = copyBtn.frame.minX - 12
        let tw = max(10, titleRight - tx)
        if ctx.subtitle.isEmpty {
            titleLabel.frame = NSRect(x: tx, y: (HEADER_H - 18) / 2, width: tw, height: 18)
        } else {
            titleLabel.frame = NSRect(x: tx, y: 9, width: tw, height: 18)
            subtitleLabel.frame = NSRect(x: tx, y: 29, width: tw, height: 15)
        }

        scroll.frame = NSRect(x: 0, y: HEADER_H, width: bounds.width, height: max(0, bounds.height - HEADER_H))
        relayoutTree()
    }

    private func relayoutTree() {
        let avail = scroll.contentView.bounds.width
        guard avail > 0 else { return }
        tree.frame.origin = NSPoint(x: bodyPadX, y: bodyPadTop)
        tree.rebuild(availableWidth: max(120, avail - bodyPadX * 2))
        let docW = max(avail, tree.frame.maxX + bodyPadX)
        doc.frame = NSRect(x: 0, y: 0, width: docW, height: tree.frame.height + bodyPadTop + bodyPadBottom)
    }

    private func close() {
        // Close normally so the controller's `windowWillClose` → `onClose` runs
        // and RootViewController drops this panel from its list.
        panelController?.window?.close()
    }
}

extension JsonViewerView: PanelContentView {
    var panelPreferredSize: CGSize { CGSize(width: 560, height: 600) }
    var panelTitle: String { ctx.title }
    func attach(to panel: PanelWindowController) { panelController = panel }
    var panelResizable: Bool { true }
    var panelMinSize: CGSize { CGSize(width: 400, height: 320) }
}
