import AppKit
import AVFoundation
import UniformTypeIdentifiers

final class ComposeView: FlippedView {
    private let appState: AppState
    private var fromId: String
    private let context: ComposeContext?
    private let onClose: () -> Void
    private let onPost: (Account, String, [PickedMedia], ComposeContext?) -> Void

    private let card = FlippedView()
    private let textView = ComposeTextView()
    private let textScroll = NSScrollView()
    private let placeholder = NSTextField(labelWithString: "")
    private var charRing = CharRingView()
    private var postButton: ComposePostButton!
    private var accountChip: HoverControl!
    private var eventMonitor: Any?
    private weak var panelController: PanelWindowController?
    private var menuOverlay: NSView?
    private let theme = ThemeManager.shared.theme
    private var picks: [PickedMedia] = []
    /// Compose runs in its own titled window (not a borderless card).
    private var windowed: Bool { panelStyle == .window }

    init(appState: AppState, fromId: String, context: ComposeContext?,
         onClose: @escaping () -> Void, onPost: @escaping (Account, String, [PickedMedia], ComposeContext?) -> Void) {
        self.appState = appState
        self.fromId = fromId
        self.context = context
        self.onClose = onClose
        self.onPost = onPost
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // text view config (created once, preserved across rebuilds)
        textScroll.borderType = .noBorder
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = false
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = Fonts.sans(19)
        textView.textColor = theme.fgBody
        textView.isEditable = true
        textView.isSelectable = true
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.delegate = self
        textView.insertionPointColor = theme.accent
        textView.onPasteMedia = { [weak self] in self?.handlePasteMedia() ?? false }
        textScroll.documentView = textView

        placeholder.isBezeled = false; placeholder.drawsBackground = false; placeholder.isEditable = false
        placeholder.font = Fonts.sans(19)
        placeholder.textColor = theme.fgSubdued

        card.wantsLayer = true
        card.layer?.backgroundColor = theme.bgElevated.cgColor
        card.layer?.masksToBounds = true
        if !windowed {
            // borderless card chrome; a titled window supplies its own frame.
            card.layer?.cornerRadius = 16
            card.layer?.borderColor = theme.borderDefault.cgColor
            card.layer?.borderWidth = 1
        }
        addSubview(card)

        rebuildCard()
        installMonitor()
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self?.textView) }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { removeMonitor() }

    private var from: Account { appState.account(fromId) ?? appState.active }
    private var isX: Bool { from.platform == .x }
    private var limit: Int { isX ? 280 : 2000 }
    private var mode: ComposeMode? { context?.mode }

    private var usedCount: Int { textView.string.count }
    private var canPost: Bool {
        if mode == .repost { return usedCount <= limit }
        let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !picks.isEmpty) && usedCount <= limit
    }

    func changeFrom(_ id: String) {
        fromId = id
        appState.composeFrom = id
        rebuildCard()
    }

    private func rebuildCard() {
        // remove all card subviews except keep textScroll reference
        card.subviews.forEach { $0.removeFromSuperview() }
        let isX = self.isX
        let cardW: CGFloat = 560
        let padX: CGFloat = 16
        var y: CGFloat = 0

        // ── header ── (titled window supplies the close button + title; borderless card draws its own)
        let headerH: CGFloat = windowed ? 50 : 60
        if !windowed {
            let close = HoverControl(frame: NSRect(x: 14, y: 15, width: 30, height: 30))
            close.wantsLayer = true
            close.layer?.cornerRadius = 8
            let closeG = GlyphView(name: "close", size: 18, color: theme.fgSubdued)
            closeG.frame = NSRect(x: 6, y: 6, width: 18, height: 18)
            close.addSubview(closeG)
            close.onState = { h, _ in close.layer?.backgroundColor = (h ? self.theme.gray100 : NSColor.clear).cgColor }
            close.onClick = { [weak self] in self?.close() }
            card.addSubview(close)

            if let m = mode {
                let lbl = m == .reply ? (isX ? "Reply" : "评论") : m == .quote ? (isX ? "Quote" : "引用") : (isX ? "Repost" : "转发")
                let l = makeLabel(lbl, font: Fonts.sans(14, .bold), color: theme.fgHeading)
                l.frame = NSRect(x: 50, y: (headerH - 17) / 2, width: 120, height: 17)
                card.addSubview(l)
            }
        }

        // account chip
        let chip = HoverControl()
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 18
        chip.layer?.borderColor = theme.borderDefault.cgColor
        chip.layer?.borderWidth = 1
        chip.layer?.backgroundColor = theme.bgBase.cgColor
        let chipAv = AvatarView(person: from, size: 26)
        let chipName = makeLabel(isX ? "@\(from.handle)" : from.name, font: Fonts.sans(13.5, .bold), color: theme.fgHeading)
        let chipChev = GlyphView(name: "chevron-down", size: 16, color: theme.fgSubdued)
        let nameW = chipName.intrinsicContentSize.width
        let chipW = 6 + 26 + 8 + nameW + 6 + 16 + 8
        chip.frame = NSRect(x: cardW - 14 - chipW, y: 12, width: chipW, height: 36)
        chipAv.frame = NSRect(x: 6, y: 5, width: 26, height: 26)
        chip.addSubview(chipAv)
        chipName.frame = NSRect(x: 40, y: (36 - chipName.intrinsicContentSize.height) / 2, width: nameW, height: chipName.intrinsicContentSize.height)
        chip.addSubview(chipName)
        chipChev.frame = NSRect(x: 40 + nameW + 6, y: 10, width: 16, height: 16)
        chip.addSubview(chipChev)
        chip.onClick = { [weak self] in self?.showAccountMenu() }
        card.addSubview(chip)
        accountChip = chip
        y = headerH
        addBorder(at: y)

        // ── body ──
        y += 16
        let avatar = AvatarView(person: from, size: 44)
        avatar.frame = NSRect(x: padX, y: y, width: 44, height: 44)
        card.addSubview(avatar)
        let bodyX = padX + 44 + 12
        let bodyW = cardW - bodyX - padX
        var by = y

        if mode == .reply, let orig = context?.post {
            let r = NSMutableAttributedString(string: isX ? "Replying to " : "回复 ", attributes: [.font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued])
            r.append(NSAttributedString(string: "@\(orig.author.handle.isEmpty ? orig.author.name : orig.author.handle)", attributes: [.font: Fonts.sans(13.5), .foregroundColor: theme.accent]))
            let l = NSTextField(labelWithAttributedString: r)
            l.isBezeled = false; l.drawsBackground = false
            l.frame = NSRect(x: bodyX, y: by, width: bodyW, height: 18)
            card.addSubview(l)
            by += 18 + 8
        } else {
            let chipE = FlippedView()
            chipE.wantsLayer = true
            chipE.layer?.cornerRadius = 13
            chipE.layer?.borderColor = theme.borderDefault.cgColor
            chipE.layer?.borderWidth = 1
            let g = GlyphView(name: "globe", size: 14, color: theme.accent)
            let t = makeLabel(isX ? "Everyone can reply" : "公开 · 所有人可见", font: Fonts.sans(12.5, .semibold), color: theme.accent)
            let tw = t.intrinsicContentSize.width
            chipE.frame = NSRect(x: bodyX, y: by, width: 10 + 14 + 6 + tw + 10, height: 26)
            g.frame = NSRect(x: 10, y: 6, width: 14, height: 14)
            chipE.addSubview(g)
            t.frame = NSRect(x: 10 + 14 + 6, y: (26 - t.intrinsicContentSize.height) / 2, width: tw, height: t.intrinsicContentSize.height)
            chipE.addSubview(t)
            card.addSubview(chipE)
            by += 26 + 8
        }

        let taH: CGFloat = mode != nil ? 84 : 120
        textScroll.frame = NSRect(x: bodyX, y: by, width: bodyW, height: taH)
        textView.textContainer?.containerSize = NSSize(width: bodyW, height: CGFloat.greatestFiniteMagnitude)
        textView.textColor = theme.fgBody
        card.addSubview(textScroll)
        placeholder.stringValue = placeholderText()
        placeholder.frame = NSRect(x: bodyX + 2, y: by, width: bodyW - 4, height: 26)
        placeholder.isHidden = !textView.string.isEmpty
        card.addSubview(placeholder)
        by += taH

        if !picks.isEmpty {
            by += 6
            let grid = ComposeMediaGrid(picks: picks, width: bodyW,
                                        onRemove: { [weak self] i in self?.removePick(i) },
                                        onAlt: { [weak self] i in self?.editAlt(i) })
            grid.frame.origin = CGPoint(x: bodyX, y: by)
            card.addSubview(grid)
            by += grid.frame.height
        }

        if (mode == .quote || mode == .repost), let orig = context?.post {
            let snap = Quote(author: orig.author, time: orig.time, text: orig.text, media: orig.media)
            let qv = QuotePostView(quote: snap, width: bodyW)
            qv.frame.origin = CGPoint(x: bodyX, y: by)
            card.addSubview(qv)
            by += qv.frame.height
        }
        by += 6
        let bodyBottom = max(by, y + 44 + 6)

        // ── footer ──
        addBorder(at: bodyBottom)
        let footerY = bodyBottom
        var fx: CGFloat = 14
        // Image is wired (pick/paste). Poll/emoji/location/schedule remain disabled until later.
        let imageEnabled = canAddMore
        for icon in ["image", "poll", "emoji", "location", "calendar"] {
            let live = icon == "image"
            let tool = HoverControl(frame: NSRect(x: fx, y: footerY + 9, width: 34, height: 34))
            tool.wantsLayer = true
            tool.layer?.cornerRadius = 8
            let on = live && imageEnabled
            tool.enabledControl = on
            let g = GlyphView(name: icon, size: 20, color: on ? theme.accent : theme.fgDisabled)
            g.frame = NSRect(x: 7, y: 7, width: 20, height: 20)
            tool.addSubview(g)
            if on {
                tool.onState = { h, _ in tool.layer?.backgroundColor = (h ? self.theme.gray100 : NSColor.clear).cgColor }
                tool.onClick = { [weak self] in self?.pickMedia() }
            }
            card.addSubview(tool)
            fx += 34
        }

        // char ring + post button (right aligned)
        let postLabel = postButtonLabel()
        let pb = ComposePostButton(label: postLabel, theme: theme) { [weak self] in self?.submit() }
        let pbW = pb.frame.width
        pb.frame.origin = CGPoint(x: cardW - 14 - pbW, y: footerY + 12)
        pb.setEnabled(canPost)
        card.addSubview(pb)
        postButton = pb

        let ring = CharRingView(frame: .zero)
        ring.update(used: usedCount, limit: limit)
        let ringW = ring.intrinsicContentSize.width
        let dividerX = cardW - 14 - pbW - 12 - 1 - 10
        ring.frame = NSRect(x: dividerX - ringW, y: footerY + 9, width: ringW, height: 26)
        card.addSubview(ring)
        charRing = ring
        let divider = NSView(frame: NSRect(x: dividerX, y: footerY + 14, width: 1, height: 26))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = theme.borderDefault.cgColor
        card.addSubview(divider)

        let footerH: CGFloat = 12 + 36 + 12
        let totalH = footerY + footerH
        card.frame = NSRect(x: 0, y: 0, width: cardW, height: totalH)
        needsLayout = true
    }

    private func addBorder(at y: CGFloat) {
        let line = NSView(frame: NSRect(x: 0, y: y, width: 560, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = theme.borderDefault.cgColor
        card.addSubview(line)
    }

    private func placeholderText() -> String {
        switch mode {
        case .reply: return isX ? "Post your reply" : "回复…"
        case .quote: return isX ? "Add a comment" : "添加评论"
        case .repost: return isX ? "Add a comment" : "说点什么…（选填）"
        default: return isX ? "What’s happening?" : "有什么新鲜事想分享给大家？"
        }
    }
    private func postButtonLabel() -> String {
        switch mode {
        case .reply: return isX ? "Reply" : "回复"
        case .quote: return isX ? "Post" : "发布"
        case .repost: return isX ? "Repost" : "转发"
        default: return isX ? "Post" : "发布"
        }
    }

    override func layout() {
        super.layout()
        card.frame = NSRect(x: 0, y: 0, width: bounds.width, height: card.frame.height)
        menuOverlay?.frame = bounds
        panelController?.setContentHeight(card.frame.height)
    }

    private func submit() {
        guard canPost else { return }
        onPost(from, textView.string.trimmingCharacters(in: .whitespacesAndNewlines), picks, context)
    }

    private func close() { onClose() }

    private func installMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            if event.keyCode == 53 { // Esc
                if self.menuOverlay != nil { self.dismissAccountMenu(); return nil }
                self.close(); return nil
            }
            if event.keyCode == 36 && event.modifierFlags.contains(.command) { // ⌘↩
                if self.canPost { self.submit() }
                return nil
            }
            return event
        }
    }
    private func removeMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private func showAccountMenu() {
        let theme = self.theme
        let w: CGFloat = 248
        let inner = w - 12
        let content = FlippedView()
        content.wantsLayer = true
        content.layer?.backgroundColor = theme.bgElevated.cgColor
        content.layer?.cornerRadius = 12
        content.layer?.borderColor = theme.borderDefault.cgColor
        content.layer?.borderWidth = 1
        content.layer?.masksToBounds = true
        var y: CGFloat = 6
        for a in appState.accounts {
            let on = a.id == fromId
            let row = HoverControl(frame: NSRect(x: 6, y: y, width: inner, height: 44))
            row.wantsLayer = true
            row.layer?.cornerRadius = 8
            if on { row.layer?.backgroundColor = theme.gray100.cgColor }
            let av = AvatarView(person: a, size: 30)
            av.frame = NSRect(x: 8, y: 7, width: 30, height: 30)
            row.addSubview(av)
            let nm = makeLabel(a.name, font: Fonts.sans(13.5, .bold), color: theme.fgHeading)
            nm.frame = NSRect(x: 46, y: 7, width: inner - 46 - 24, height: 17)
            row.addSubview(nm)
            let sub = makeLabel(a.platform == .x ? "@\(a.handle) · X" : "微博", font: Fonts.sans(12), color: theme.fgSubdued)
            sub.frame = NSRect(x: 46, y: 24, width: inner - 46 - 24, height: 14)
            row.addSubview(sub)
            if on {
                let ck = GlyphView(name: "checkmark", size: 16, color: theme.accent)
                ck.frame = NSRect(x: inner - 24, y: 14, width: 16, height: 16)
                row.addSubview(ck)
            }
            row.onState = { h, _ in if !on { row.layer?.backgroundColor = (h ? theme.gray75 : NSColor.clear).cgColor } }
            row.onClick = { [weak self] in
                self?.dismissAccountMenu()
                self?.changeFrom(a.id!)
            }
            content.addSubview(row)
            y += 44
        }
        y += 6

        dismissAccountMenu()
        // click-catcher behind the menu
        let catcher = HoverControl(frame: bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.onClick = { [weak self] in self?.dismissAccountMenu() }
        addSubview(catcher)
        menuOverlay = catcher

        // position the menu under the account chip, right-aligned
        content.frame = NSRect(x: max(8, accountChip.frame.maxX - w),
                               y: accountChip.frame.maxY + 6, width: w, height: y)
        content.wantsLayer = true
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = theme.isDark ? 0.5 : 0.16
        content.layer?.shadowRadius = 12
        content.layer?.shadowOffset = CGSize(width: 0, height: -3)
        content.layer?.masksToBounds = false
        catcher.addSubview(content)
    }

    private func dismissAccountMenu() {
        menuOverlay?.removeFromSuperview()
        menuOverlay = nil
    }

    // MARK: - Media (Phase 2)

    private var hasNonImage: Bool { picks.contains { $0.kind != .image } }
    /// ≤4 images, OR exactly 1 video, OR exactly 1 gif.
    private var canAddMore: Bool { hasNonImage ? false : picks.count < 4 }

    private func pickMedia() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .image, .mpeg4Movie, .quickTimeMovie, .movie]
        panel.begin { [weak self] resp in
            guard resp == .OK, let self else { return }
            self.addPicks(from: panel.urls)
        }
    }

    private func addPicks(from urls: [URL]) {
        var added = false
        for url in urls {
            guard let pm = Self.pickedMedia(fileURL: url) else { continue }
            if appendPick(pm) { added = true }
        }
        if added { rebuildCard(); refreshAfterMediaChange() }
    }

    /// Insert a pick honoring exclusivity. Returns true if added.
    private func appendPick(_ pm: PickedMedia) -> Bool {
        if pm.kind == .image {
            guard !hasNonImage, picks.count < 4 else { return false }
        } else {
            guard picks.isEmpty else { return false }   // video / gif must stand alone
        }
        picks.append(pm)
        return true
    }

    private func removePick(_ i: Int) {
        guard picks.indices.contains(i) else { return }
        picks.remove(at: i)
        rebuildCard(); refreshAfterMediaChange()
    }

    private func editAlt(_ i: Int) {
        guard picks.indices.contains(i), let win = window else { return }
        let alert = NSAlert()
        alert.messageText = isX ? "Description (alt text)" : "图片描述"
        alert.informativeText = isX ? "Describe this image for people who are blind or have low vision."
                                    : "为视障人士描述这张图片。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = picks[i].alt ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: isX ? "Save" : "保存")
        alert.addButton(withTitle: isX ? "Cancel" : "取消")
        alert.beginSheetModal(for: win) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self, self.picks.indices.contains(i) else { return }
            self.picks[i].alt = field.stringValue.isEmpty ? nil : field.stringValue
            self.rebuildCard()
        }
    }

    /// Read images/files from the general pasteboard. Returns true if consumed.
    private func handlePasteMedia() -> Bool {
        guard canAddMore else { return false }
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let media = urls.compactMap { Self.pickedMedia(fileURL: $0) }
            guard !media.isEmpty else { return false }
            var added = false
            for m in media where appendPick(m) { added = true }
            if added { rebuildCard(); refreshAfterMediaChange() }
            return added
        }
        let raw = pb.data(forType: .png) ?? pb.data(forType: .tiff)
        if let raw, let img = NSImage(data: raw) {
            let png = Self.pngData(img) ?? raw
            let pm = PickedMedia(data: png, kind: .image, mimeType: "image/png",
                                 alt: nil, thumbnail: img, fileURL: nil)
            if appendPick(pm) { rebuildCard(); refreshAfterMediaChange(); return true }
        }
        return false
    }

    private func refreshAfterMediaChange() {
        postButton.setEnabled(canPost)
        window?.makeFirstResponder(textView)
    }

    private static func pickedMedia(fileURL url: URL) -> PickedMedia? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let kind: PickedMediaKind
        let mime: String
        switch url.pathExtension.lowercased() {
        case "gif":          kind = .gif;   mime = "image/gif"
        case "mp4", "m4v":   kind = .video; mime = "video/mp4"
        case "mov", "qt":    kind = .video; mime = "video/quicktime"
        case "png":          kind = .image; mime = "image/png"
        case "jpg", "jpeg":  kind = .image; mime = "image/jpeg"
        case "webp":         kind = .image; mime = "image/webp"
        case "heic":         kind = .image; mime = "image/heic"
        default:
            guard let t = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return nil }
            if t.conforms(to: .movie) { kind = .video; mime = "video/mp4" }
            else if t.conforms(to: .image) { kind = .image; mime = "image/png" }
            else { return nil }
        }
        let thumb = kind == .video ? videoThumbnail(url) : NSImage(data: data)
        return PickedMedia(data: data, kind: kind, mimeType: mime, alt: nil, thumbnail: thumb, fileURL: url)
    }

    private static func videoThumbnail(_ url: URL) -> NSImage? {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        let t = CMTime(seconds: 0.1, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: t, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private static func pngData(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Debug-only: seed sample picked images so snapshots can show the media grid + resize.
    func debugSeedSampleMedia() {
        let colors: [NSColor] = [.systemTeal, .systemPink, .systemIndigo]
        picks = colors.map { c in
            let img = NSImage(size: NSSize(width: 600, height: 400))
            img.lockFocus(); c.setFill(); NSRect(x: 0, y: 0, width: 600, height: 400).fill(); img.unlockFocus()
            return PickedMedia(data: Self.pngData(img) ?? Data(), kind: .image,
                               mimeType: "image/png", alt: nil, thumbnail: img, fileURL: nil)
        }
        rebuildCard()
    }
}

/// NSTextView that lets the composer intercept image paste before falling back to text paste.
final class ComposeTextView: NSTextView {
    var onPasteMedia: (() -> Bool)?
    override func paste(_ sender: Any?) {
        if onPasteMedia?() == true { return }
        super.paste(sender)
    }
}

extension ComposeView: PanelContentView {
    var panelPreferredSize: CGSize { card.frame.size }
    var panelStyle: PanelStyle { .window }
    var panelTitle: String {
        switch mode {
        case .reply: return isX ? "Reply" : "回复"
        case .quote: return isX ? "Quote Post" : "引用"
        case .repost: return isX ? "Repost" : "转发"
        default: return isX ? "New Post" : "发新微博"
        }
    }
    func attach(to panel: PanelWindowController) { panelController = panel }
}

extension ComposeView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        placeholder.isHidden = !textView.string.isEmpty
        charRing.update(used: usedCount, limit: limit)
        postButton.setEnabled(canPost)
    }
}

/// Pill "Post" button for compose.
final class ComposePostButton: HoverControl {
    private let label = NSTextField(labelWithString: "")
    private let themeRef: Theme
    private var enabledState = false

    init(label: String, theme: Theme, onClick: @escaping () -> Void) {
        self.themeRef = theme
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        self.label.stringValue = label
        self.label.font = Fonts.sans(15, .bold)
        self.label.isBezeled = false; self.label.drawsBackground = false; self.label.alignment = .center
        addSubview(self.label)
        let w = self.label.intrinsicContentSize.width + 40
        frame = NSRect(x: 0, y: 0, width: w, height: 36)
        self.label.frame = NSRect(x: 0, y: (36 - self.label.intrinsicContentSize.height) / 2, width: w, height: self.label.intrinsicContentSize.height)
        self.onClick = onClick
        self.onState = { [weak self] _, _ in self?.render() }
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    func setEnabled(_ e: Bool) { enabledState = e; enabledControl = e; render() }

    private func render() {
        if !enabledState {
            layer?.backgroundColor = themeRef.gray100.cgColor
            label.textColor = themeRef.fgDisabled
        } else {
            layer?.backgroundColor = (hovering ? themeRef.accentBgHover : themeRef.accentBg).cgColor
            label.textColor = .white
        }
    }
}
