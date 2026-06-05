import AppKit

/// Generic clickable view that tracks hover + press and reports state changes.
class HoverControl: NSView {
    var onClick: (() -> Void)?
    /// Right-click / control+left-click handler (e.g. a context menu). When set,
    /// it fires instead of `onClick` for those gestures.
    var onRightClick: (() -> Void)?
    /// Called whenever hover/press state changes: (hovering, pressing).
    var onState: ((Bool, Bool) -> Void)?
    var enabledControl: Bool = true

    private(set) var hovering = false
    private(set) var pressing = false
    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override func mouseEntered(with event: NSEvent) {
        guard enabledControl else { return }
        hovering = true
        onState?(hovering, pressing)
    }
    override func mouseExited(with event: NSEvent) {
        hovering = false
        pressing = false
        onState?(hovering, pressing)
    }
    override func mouseDown(with event: NSEvent) {
        guard enabledControl else { return }
        if let onRightClick, event.modifierFlags.contains(.control) {
            onRightClick(); return
        }
        pressing = true
        onState?(hovering, pressing)
    }
    override func rightMouseDown(with event: NSEvent) {
        guard enabledControl, let onRightClick else { super.rightMouseDown(with: event); return }
        onRightClick()
    }
    override func mouseUp(with event: NSEvent) {
        guard enabledControl else { pressing = false; return }
        let wasPressing = pressing
        pressing = false
        let pt = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(pt)
        onState?(hovering, pressing)
        if wasPressing && inside { onClick?() }
    }
}

extension NSAttributedString.Key {
    static let mentionHandle = NSAttributedString.Key(rawValue: "perch.mention")
    static let linkURL = NSAttributedString.Key(rawValue: "perch.link")
}

/// Rich text with colored @mentions (clickable), #hashtags / links (colored).
final class RichTextView: NSView {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
    var onMention: ((String) -> Void)?
    /// Click on a URL token. Defaults to opening it in the system browser.
    var onLink: ((String) -> Void)?
    /// Plain click (no drag-selection, not on a mention/link) — used to open the post.
    var onTap: (() -> Void)?

    private var selectedRange = NSRange(location: 0, length: 0)
    private var anchorIndex = 0

    /// When set, the text is clamped to this many lines with a trailing ellipsis.
    var lineLimit: Int? {
        didSet {
            container.maximumNumberOfLines = lineLimit ?? 0
            container.lineBreakMode = lineLimit == nil ? .byWordWrapping : .byTruncatingTail
            needsDisplay = true
        }
    }

    init(text: String, font: NSFont, color: NSColor, accent: NSColor,
         lineHeightMultiple: CGFloat = 1.0, onMention: ((String) -> Void)? = nil) {
        super.init(frame: .zero)
        self.onMention = onMention
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        storage.setAttributedString(Self.build(text: text, font: font, color: color, accent: accent, lineHeightMultiple: lineHeightMultiple))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    static func build(text: String, font: NSFont, color: NSColor, accent: NSColor, lineHeightMultiple: CGFloat) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = lineHeightMultiple
        para.lineBreakMode = .byWordWrapping
        let result = NSMutableAttributedString()
        // split keeping whitespace runs (mirrors text.split(/(\s+)/))
        let tokens = tokenize(text)
        for tok in tokens {
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font, .foregroundColor: color, .paragraphStyle: para
            ]
            if tok.hasPrefix("@") && tok.count > 1 {
                let handle = stripMention(String(tok.dropFirst()))
                attrs[.foregroundColor] = accent
                attrs[.mentionHandle] = handle
            } else if tok.hasPrefix("http://") || tok.hasPrefix("https://") {
                attrs[.foregroundColor] = accent
                attrs[.linkURL] = stripTrailingPunct(tok)
            } else if tok.hasPrefix("#") || tok.hasPrefix("＃") || tok.hasSuffix("链接") {
                attrs[.foregroundColor] = accent
            }
            result.append(NSAttributedString(string: tok, attributes: attrs))
        }
        return result
    }

    private static func tokenize(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var inWS: Bool? = nil
        for ch in s {
            let isWS = ch == " " || ch == "\n" || ch == "\t" || ch == "\r"
            if inWS == nil { inWS = isWS; cur.append(ch); continue }
            if isWS == inWS! {
                cur.append(ch)
            } else {
                out.append(cur); cur = String(ch); inWS = isWS
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func stripMention(_ h: String) -> String {
        let trailing = Set("，,。.!！?？:：;；、)）")
        var s = h
        while let last = s.last, trailing.contains(last) { s.removeLast() }
        return s
    }

    private static func stripTrailingPunct(_ s: String) -> String {
        let trailing = Set("，,。.!！?？:：;；、)）]」』】>")
        var out = s
        while let last = out.last, trailing.contains(last) { out.removeLast() }
        return out
    }

    static func openExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    /// Number of wrapped lines the full (unclamped) text occupies at `width`.
    func lineCount(forWidth width: CGFloat) -> Int {
        let savedMax = container.maximumNumberOfLines
        let savedBreak = container.lineBreakMode
        container.maximumNumberOfLines = 0
        container.lineBreakMode = .byWordWrapping
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        var count = 0
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in count += 1 }
        container.maximumNumberOfLines = savedMax
        container.lineBreakMode = savedBreak
        return count
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        container.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        let range = layoutManager.glyphRange(for: container)
        layoutManager.drawBackground(forGlyphRange: range, at: .zero)
        if selectedRange.length > 0 {
            NSColor.selectedTextBackgroundColor.setFill()
            let sel = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: sel, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                rect.fill()
            }
        }
        layoutManager.drawGlyphs(forGlyphRange: range, at: .zero)
    }

    override var acceptsFirstResponder: Bool { true }

    /// Character index for the insertion point nearest `point` (rounds to glyph edges).
    private func charIndex(at point: NSPoint) -> Int {
        container.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        var frac: CGFloat = 0
        let glyphIdx = layoutManager.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &frac)
        var idx = layoutManager.characterIndexForGlyph(at: glyphIdx)
        if frac > 0.5 { idx += 1 }
        return min(idx, storage.length)
    }

    private func wordRange(in str: NSString, at idx: Int) -> NSRange {
        var result = NSRange(location: idx, length: 1)
        str.enumerateSubstrings(in: NSRange(location: 0, length: str.length), options: .byWords) { _, range, _, stop in
            if NSLocationInRange(idx, range) || range.location == idx {
                result = range; stop.pointee = true
            } else if range.location > idx {
                stop.pointee = true
            }
        }
        return result
    }

    private func attribute<T>(_ key: NSAttributedString.Key, at point: NSPoint) -> T? {
        container.size = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        var frac: CGFloat = 0
        let glyphIdx = layoutManager.glyphIndex(for: point, in: container, fractionOfDistanceThroughGlyph: &frac)
        // Reject points past the end of the glyph's run (clicks in trailing whitespace).
        guard frac < 1 else { return nil }
        let charIdx = layoutManager.characterIndexForGlyph(at: glyphIdx)
        guard charIdx < storage.length else { return nil }
        return storage.attribute(key, at: charIdx, effectiveRange: nil) as? T
    }

    private func mentionHandle(at point: NSPoint) -> String? { attribute(.mentionHandle, at: point) }
    private func linkURL(at point: NSPoint) -> String? { attribute(.linkURL, at: point) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = convert(event.locationInWindow, from: nil)
        if event.clickCount >= 2 {
            let str = storage.string as NSString
            guard str.length > 0 else { return }
            let idx = min(charIndex(at: pt), str.length - 1)
            selectedRange = event.clickCount == 2 ? wordRange(in: str, at: idx) : str.lineRange(for: NSRange(location: idx, length: 0))
            anchorIndex = selectedRange.location
            needsDisplay = true
            return
        }
        anchorIndex = charIndex(at: pt)
        if selectedRange.length > 0 { needsDisplay = true }
        selectedRange = NSRange(location: anchorIndex, length: 0)
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let idx = charIndex(at: pt)
        let lo = min(anchorIndex, idx), hi = max(anchorIndex, idx)
        selectedRange = NSRange(location: lo, length: hi - lo)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard selectedRange.length == 0 else { return }
        let pt = convert(event.locationInWindow, from: nil)
        if let handle = mentionHandle(at: pt) { onMention?(handle); return }
        if let url = linkURL(at: pt) { (onLink ?? Self.openExternal)(url); return }
        onTap?()
    }

    @objc func copy(_ sender: Any?) {
        guard selectedRange.length > 0 else { return }
        let text = (storage.string as NSString).substring(with: selectedRange)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    override func selectAll(_ sender: Any?) {
        selectedRange = NSRange(location: 0, length: storage.length)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let c = event.charactersIgnoringModifiers?.lowercased() {
            switch c {
            case "a": selectAll(nil); return
            case "c": copy(nil); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func resetCursorRects() {
        // pointing-hand cursor over mentions and links
        for key in [NSAttributedString.Key.mentionHandle, .linkURL] {
            storage.enumerateAttribute(key, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                guard value != nil else { return }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                    self.addCursorRect(rect, cursor: .pointingHand)
                }
            }
        }
    }
}

extension RichTextView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): return selectedRange.length > 0
        case #selector(selectAll(_:)): return storage.length > 0
        default: return true
        }
    }
}

/// Character ring (+ remaining number when near/over limit).
final class CharRingView: NSView {
    private var used = 0
    private var limit = 280
    private let numberLabel = NSTextField(labelWithString: "")
    private let ringSize: CGFloat = 26

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        numberLabel.isBezeled = false
        numberLabel.drawsBackground = false
        numberLabel.isEditable = false
        numberLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        addSubview(numberLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func update(used: Int, limit: Int) {
        self.used = used
        self.limit = limit
        needsDisplay = true
        invalidateIntrinsicContentSize()
        let remaining = limit - used
        let near = remaining <= 20
        let over = remaining < 0
        let theme = ThemeManager.shared.theme
        if near || over {
            numberLabel.stringValue = String(remaining)
            numberLabel.textColor = over ? theme.negative : theme.fgSubdued
            numberLabel.isHidden = false
        } else {
            numberLabel.isHidden = true
        }
        layoutPieces()
    }

    private func layoutPieces() {
        let remaining = limit - used
        let show = remaining <= 20
        if show {
            let w = numberLabel.intrinsicContentSize.width
            let h = numberLabel.intrinsicContentSize.height
            numberLabel.frame = NSRect(x: 0, y: (ringSize - h) / 2, width: w, height: h)
        }
    }

    override var intrinsicContentSize: NSSize {
        let remaining = limit - used
        let show = remaining <= 20
        let numW = show ? numberLabel.intrinsicContentSize.width + 8 : 0
        return NSSize(width: numW + ringSize, height: ringSize)
    }

    override func layout() {
        super.layout()
        layoutPieces()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = ThemeManager.shared.theme
        let remaining = limit - used
        let near = remaining <= 20
        let over = remaining < 0
        let ringX = bounds.width - ringSize
        let center = CGPoint(x: ringX + ringSize / 2, y: ringSize / 2)
        let r: CGFloat = 10
        let lw: CGFloat = 2.5

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: r, startAngle: 0, endAngle: 360)
        track.lineWidth = lw
        theme.gray300.setStroke()
        track.stroke()

        let ratio = min(Double(used) / Double(max(limit, 1)), 1.0)
        if ratio > 0 {
            let stroke = over ? theme.negative : (near ? theme.noticeBg : theme.accent)
            let prog = NSBezierPath()
            // start at top (90°), go clockwise
            let start: CGFloat = 90
            let end: CGFloat = 90 - CGFloat(ratio) * 360
            prog.appendArc(withCenter: center, radius: r, startAngle: start, endAngle: end, clockwise: true)
            prog.lineWidth = lw
            prog.lineCapStyle = .round
            stroke.setStroke()
            prog.stroke()
        }
    }
}

/// Toast pill: checkmark-circle + message.
final class ToastView: NSView {
    init(text: String) {
        super.init(frame: .zero)
        wantsLayer = true
        let theme = ThemeManager.shared.theme
        layer?.cornerRadius = 21
        layer?.backgroundColor = theme.gray900.cgColor
        layer?.masksToBounds = true

        let glyph = GlyphView(name: "checkmark-circle", size: 18, color: theme.green700)
        addSubview(glyph)
        let label = makeLabel(text, font: Fonts.sans(14, .semibold), color: theme.gray25)
        addSubview(label)

        let labelW = label.intrinsicContentSize.width
        let h: CGFloat = 42
        let padL: CGFloat = 18, gap: CGFloat = 9, padR: CGFloat = 18
        let w = padL + 18 + gap + labelW + padR
        frame = NSRect(x: 0, y: 0, width: w, height: h)
        glyph.frame = NSRect(x: padL, y: (h - 18) / 2, width: 18, height: 18)
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: padL + 18 + gap, y: (h - lh) / 2, width: labelW, height: lh)
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
}
