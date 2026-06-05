import AppKit

/// A collapsible, syntax-colored JSON tree (port of the prototype's JsonView/JsonNode).
/// Manual flipped layout; rows are click-to-toggle for object/array nodes. Self-sizing —
/// reports its content height through `onHeightChange` after every (re)build.
final class JSONTreeView: FlippedView, Themeable {
    private let root: DebugJSON
    private var theme: Theme
    private var palette: DebugPalette
    var onHeightChange: ((CGFloat) -> Void)?

    /// Per-node explicit expand/collapse choices, keyed by index path. Absent → default
    /// (`depth < 2` auto-opens).
    private var state: [String: Bool] = [:]
    private var availableWidth: CGFloat = 520

    private let fontSize: CGFloat = 12.5
    private let indent: CGFloat = 15
    private let padLeft: CGFloat = 13
    private let padV: CGFloat = 6
    private var lineH: CGFloat { ceil(fontSize * 1.65) }

    init(json: DebugJSON, theme: Theme) {
        self.root = json
        self.theme = theme
        self.palette = DebugPalette(theme)
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: Theme) {
        self.theme = theme
        self.palette = DebugPalette(theme)
        rebuild(availableWidth: availableWidth)
    }

    func rebuild(availableWidth: CGFloat) {
        self.availableWidth = availableWidth
        subviews.forEach { $0.removeFromSuperview() }

        var rows: [Row] = []
        appendRows(root, key: nil, path: "$", depth: 0, isLast: true, into: &rows)

        var maxRight: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let y = padV + CGFloat(i) * lineH
            let contentX = padLeft + CGFloat(row.depth) * indent
            if let path = row.togglePath {
                let control = ToggleRow(expanded: row.isExpanded)
                control.onClick = { [weak self] in
                    guard let self else { return }
                    self.state[path] = !(self.state[path] ?? (row.depth < 2))
                    self.rebuild(availableWidth: self.availableWidth)
                }
                let label = makeRowLabel(row.attributed)
                let labelW = ceil(row.attributed.size().width) + 4
                control.addSubview(label)
                label.frame = NSRect(x: contentX, y: 0, width: labelW, height: lineH)
                control.triangleX = contentX - padLeft
                control.triangleColor = palette.punct
                control.frame = NSRect(x: 0, y: y, width: max(availableWidth, contentX + labelW), height: lineH)
                addSubview(control)
                maxRight = max(maxRight, contentX + labelW)
            } else {
                let label = makeRowLabel(row.attributed)
                let labelW = ceil(row.attributed.size().width) + 4
                label.frame = NSRect(x: contentX, y: y, width: labelW, height: lineH)
                addSubview(label)
                maxRight = max(maxRight, contentX + labelW)
            }
        }

        let h = padV * 2 + CGFloat(rows.count) * lineH
        let w = max(availableWidth, maxRight + padLeft)
        frame = NSRect(x: frame.minX, y: frame.minY, width: w, height: h)
        onHeightChange?(h)
    }

    func copyText() -> String { root.prettyString() }

    // MARK: Row model

    private struct Row {
        let depth: Int
        let attributed: NSAttributedString
        let togglePath: String?
        let isExpanded: Bool
    }

    private func isExpanded(_ path: String, _ depth: Int) -> Bool {
        state[path] ?? (depth < 2)
    }

    private func appendRows(_ value: DebugJSON, key: String?, path: String, depth: Int,
                            isLast: Bool, into rows: inout [Row]) {
        switch value {
        case .object(let entries):
            appendContainer(entries.map { ($0.0, $0.1) }, open: "{", close: "}", keyed: true,
                            key: key, path: path, depth: depth, isLast: isLast, into: &rows)
        case .array(let items):
            appendContainer(items.map { (nil, $0) }, open: "[", close: "]", keyed: false,
                            key: key, path: path, depth: depth, isLast: isLast, into: &rows)
        case .string, .number, .bool, .null:
            let line = NSMutableAttributedString()
            appendKeyPrefix(line, key)
            appendScalar(line, value)
            appendComma(line, isLast)
            rows.append(Row(depth: depth, attributed: line, togglePath: nil, isExpanded: false))
        }
    }

    private func appendContainer(_ children: [(String?, DebugJSON)], open: String, close: String,
                                 keyed: Bool, key: String?, path: String, depth: Int,
                                 isLast: Bool, into rows: inout [Row]) {
        let header = NSMutableAttributedString()
        appendKeyPrefix(header, key)
        if children.isEmpty {
            append(header, open + close, palette.punct)
            appendComma(header, isLast)
            rows.append(Row(depth: depth, attributed: header, togglePath: nil, isExpanded: false))
            return
        }
        let expanded = isExpanded(path, depth)
        if expanded {
            append(header, open, palette.punct)
            rows.append(Row(depth: depth, attributed: header, togglePath: path, isExpanded: true))
            for (i, child) in children.enumerated() {
                let childPath = keyed ? path + "." + (child.0 ?? "") : path + "[\(i)]"
                appendRows(child.1, key: child.0, path: childPath, depth: depth + 1,
                           isLast: i == children.count - 1, into: &rows)
            }
            let closer = NSMutableAttributedString()
            append(closer, close, palette.punct)
            appendComma(closer, isLast)
            rows.append(Row(depth: depth, attributed: closer, togglePath: nil, isExpanded: true))
        } else {
            append(header, open + " ", palette.punct)
            append(header, "…", palette.null)
            append(header, " " + close, palette.punct)
            appendComma(header, isLast)
            rows.append(Row(depth: depth, attributed: header, togglePath: path, isExpanded: false))
        }
    }

    // MARK: Attributed-string token helpers

    private func append(_ s: NSMutableAttributedString, _ text: String, _ color: NSColor) {
        s.append(NSAttributedString(string: text, attributes: [
            .font: Fonts.mono(fontSize), .foregroundColor: color,
        ]))
    }

    private func appendKeyPrefix(_ s: NSMutableAttributedString, _ key: String?) {
        guard let key else { return }
        append(s, "\"" + DebugJSON.escape(key) + "\"", palette.key)
        append(s, ": ", palette.punct)
    }

    private func appendScalar(_ s: NSMutableAttributedString, _ value: DebugJSON) {
        switch value {
        case .string(let str): append(s, "\"" + DebugJSON.escape(str) + "\"", palette.string)
        case .number(let n): append(s, DebugJSON.numberString(n), palette.number)
        case .bool(let b): append(s, b ? "true" : "false", palette.bool)
        case .null: append(s, "null", palette.null)
        default: break
        }
    }

    private func appendComma(_ s: NSMutableAttributedString, _ isLast: Bool) {
        if !isLast { append(s, ",", palette.punct) }
    }

    private func makeRowLabel(_ attr: NSAttributedString) -> NSTextField {
        let l = NSTextField(labelWithAttributedString: attr)
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        l.lineBreakMode = .byClipping
        l.maximumNumberOfLines = 1
        return l
    }
}

// MARK: - Shared debug-chrome helpers

/// The three macOS traffic-light dots used by the debug windows' headers. The red
/// dot closes; amber/green are inert (faithful to the design's `TrafficClose`).
func makeTrafficLights(onClose: @escaping () -> Void) -> NSView {
    let row = FlippedView(frame: NSRect(x: 0, y: 0, width: 52, height: 12))
    let specs: [(String, Bool)] = [("#ff5f57", true), ("#febc2e", false), ("#28c840", false)]
    var x: CGFloat = 0
    for (hex, closeable) in specs {
        let dot = HoverControl(frame: NSRect(x: x, y: 0, width: 12, height: 12))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = NSColor(hex: hex).cgColor
        dot.layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
        dot.layer?.borderWidth = 0.5
        if closeable { dot.onClick = onClose }
        row.addSubview(dot)
        x += 20
    }
    return row
}

/// Copy-to-clipboard chip with a transient "Copied" confirmation (port of `CopyJsonBtn`).
/// Width is fixed to the wider of the two labels so the header never reflows on toggle.
final class CopyJsonButton: HoverControl {
    private let isX: Bool
    private let copyProvider: () -> String
    private let theme = ThemeManager.shared.theme
    private let glyph: GlyphView
    private let label: NSTextField
    private var resetWork: DispatchWorkItem?

    init(isX: Bool, copyProvider: @escaping () -> String) {
        self.isX = isX
        self.copyProvider = copyProvider
        self.glyph = GlyphView(name: "copy", size: 15, color: ThemeManager.shared.theme.fgBody)
        self.label = makeLabel(isX ? "Copy" : "复制", font: Fonts.sans(13, .semibold), color: ThemeManager.shared.theme.fgBody)
        let copyW = (isX ? "Copy" : "复制").size(withAttributes: [.font: Fonts.sans(13, .semibold)]).width
        let doneW = (isX ? "Copied" : "已复制").size(withAttributes: [.font: Fonts.sans(13, .semibold)]).width
        let labelW = ceil(max(copyW, doneW))
        let w = 13 + 15 + 6 + labelW + 13
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1
        layer?.backgroundColor = theme.bgBase.cgColor
        glyph.frame = NSRect(x: 13, y: (30 - 15) / 2, width: 15, height: 15)
        addSubview(glyph)
        label.frame = NSRect(x: 13 + 15 + 6, y: (30 - 17) / 2, width: labelW + 2, height: 17)
        addSubview(label)
        onState = { [weak self] h, _ in
            self?.layer?.backgroundColor = (h ? self?.theme.gray75 : self?.theme.bgBase)?.cgColor
        }
        onClick = { [weak self] in self?.performCopy() }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func performCopy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(copyProvider(), forType: .string)
        glyph.setName("checkmark")
        glyph.color = theme.positive
        label.stringValue = isX ? "Copied" : "已复制"
        label.textColor = theme.positive
        resetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.glyph.setName("copy")
            self.glyph.color = self.theme.fgBody
            self.label.stringValue = self.isX ? "Copy" : "复制"
            self.label.textColor = self.theme.fgBody
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

/// One expandable row: a click target that draws a ▾/▸ triangle in the left gutter.
private final class ToggleRow: HoverControl {
    var triangleX: CGFloat = 0
    var triangleColor: NSColor = .gray
    private let expanded: Bool

    init(expanded: Bool) {
        self.expanded = expanded
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let glyph = expanded ? "▾" : "▸"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.sans(9), .foregroundColor: triangleColor,
        ]
        let s = NSAttributedString(string: glyph, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: triangleX + (13 - size.width) / 2,
                           y: (bounds.height - size.height) / 2))
    }
}
