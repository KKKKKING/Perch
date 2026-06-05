import AppKit

/// A diagonal gradient tile.
final class GradientTile: NSView {
    init(_ g: Gradient) {
        super.init(frame: .zero)
        wantsLayer = true
        let grad = CAGradientLayer()
        grad.colors = [g.c0.cgColor, g.c1.cgColor]
        grad.startPoint = CGPoint(x: 0, y: 1)
        grad.endPoint = CGPoint(x: 1, y: 0)
        layer = grad
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        layer?.frame = bounds
    }
}

/// A media tile: gradient placeholder with a real image faded in on top (aspect-fill).
final class ImageTile: NSView {
    private let gradLayer = CAGradientLayer()
    private let imageLayer = CALayer()
    /// The decoded image once loaded (used by the viewer's download/copy).
    private(set) var loadedImage: NSImage?
    /// Fired once the real image is decoded (used for dynamic aspect sizing).
    var onLoad: ((NSImage) -> Void)?

    init(_ item: MediaItem, size: ImageLoader.Size = .small) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        gradLayer.colors = [item.grad.c0.cgColor, item.grad.c1.cgColor]
        gradLayer.startPoint = CGPoint(x: 0, y: 1)
        gradLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradLayer)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.opacity = 0
        layer?.addSublayer(imageLayer)

        if let local = item.localImage {
            var rect = CGRect(origin: .zero, size: local.size)
            if let cg = local.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                imageLayer.contents = cg
                imageLayer.opacity = 1
                loadedImage = local
            }
        } else if let url = item.url {
            ImageLoader.shared.image(for: url, size: size) { [weak self] img in
                guard let self, let img else { return }
                var rect = CGRect(origin: .zero, size: img.size)
                guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
                self.imageLayer.contents = cg
                self.loadedImage = img
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.22
                self.imageLayer.opacity = 1
                self.imageLayer.add(fade, forKey: "fade")
                self.onLoad?(img)
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradLayer.frame = bounds
        imageLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Clip view that centers its document view on any axis where the (magnified)
/// content is smaller than the viewport — the standard zoomable-image pattern.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let df = doc.frame
        if df.width < rect.width { rect.origin.x = (df.width - rect.width) / 2 }
        if df.height < rect.height { rect.origin.y = (df.height - rect.height) / 2 }
        return rect
    }
}

/// Document view for the zoomable viewer: gradient placeholder + image, sized to
/// the image's natural points so the scroll view's `magnification` drives scale.
private final class ZoomDocView: FlippedView {
    let gradLayer = CAGradientLayer()
    let imageView = NSImageView()
    /// Forwarded to the scroll view (NSImageView would otherwise eat the click).
    var onDoubleClick: ((NSEvent) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradLayer.startPoint = CGPoint(x: 0, y: 1)
        gradLayer.endPoint = CGPoint(x: 1, y: 0)
        layer?.addSublayer(gradLayer)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.isEditable = false
        imageView.wantsLayer = true
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gradLayer.frame = bounds
        CATransaction.commit()
        imageView.frame = bounds
    }
    // Keep clicks at the document level so double-click zoom is reliable; scroll
    // wheel / magnify still bubble to the scroll view.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?(event) } else { super.mouseDown(with: event) }
    }
}

/// Full-image viewer surface: black background, pinch / double-click zoom, and
/// vertical scrolling for long (tall) images. Used by `MediaViewerView` in place
/// of `ImageTile` for the lightbox image case; `ImageTile` stays for thumbnails.
final class ZoomableImageScrollView: NSScrollView {
    /// The decoded image once loaded (used by the viewer's download/copy).
    private(set) var loadedImage: NSImage?
    /// Fired once the real image is decoded.
    var onLoad: ((NSImage) -> Void)?

    private let item: MediaItem
    private let docView = ZoomDocView(frame: .zero)
    private var baselineMag: CGFloat = 1
    private var userHasZoomed = false
    private var hasImage = false
    private var didInitialFit = false
    private var lastFitSize: CGSize = .zero

    init(_ item: MediaItem) {
        self.item = item
        super.init(frame: .zero)
        wantsLayer = true

        let clip = CenteringClipView()
        clip.drawsBackground = true
        clip.backgroundColor = .black
        contentView = clip
        documentView = docView
        docView.gradLayer.colors = [item.grad.c0.cgColor, item.grad.c1.cgColor]
        docView.onDoubleClick = { [weak self] e in self?.toggleZoom(at: e) }

        allowsMagnification = true
        minMagnification = 0.1
        maxMagnification = 4
        hasVerticalScroller = true
        hasHorizontalScroller = true
        scrollerStyle = .overlay
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = .black
        borderType = .noBorder
        verticalScrollElasticity = .allowed
        horizontalScrollElasticity = .allowed

        if let url = item.url {
            docView.imageView.alphaValue = 0
            ImageLoader.shared.image(for: url, size: .orig) { [weak self] img in
                guard let self, let img else { return }
                self.setImage(img, real: true)
            }
        } else {
            // No real URL (debug gradients): render the gradient as zoomable content.
            setImage(MediaViewerView.renderGradient(item), real: false)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setImage(_ img: NSImage, real: Bool) {
        docView.imageView.image = img
        if real { loadedImage = img }
        hasImage = true
        didInitialFit = false
        needsLayout = true
        if real {
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.22
                docView.imageView.animator().alphaValue = 1
            }
        } else {
            docView.imageView.alphaValue = 1
        }
        onLoad?(img)
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        guard hasImage else {
            docView.frame = CGRect(origin: .zero, size: bounds.size)  // gradient placeholder
            return
        }
        if !didInitialFit {
            didInitialFit = true
            lastFitSize = bounds.size
            recomputeFit()
        } else if bounds.size != lastFitSize {
            lastFitSize = bounds.size
            if !userHasZoomed { recomputeFit() }
        }
    }

    private func recomputeFit() {
        guard let img = docView.imageView.image else { return }
        let sz = img.size
        guard sz.width > 0, sz.height > 0, bounds.width > 0, bounds.height > 0 else { return }
        docView.frame = CGRect(origin: .zero, size: sz)
        let viewW = bounds.width, viewH = bounds.height
        let isTall = sz.height > sz.width * 2.5
        let fitMag = isTall ? viewW / sz.width : min(viewW / sz.width, viewH / sz.height)
        baselineMag = fitMag
        minMagnification = max(0.01, min(fitMag, viewH / sz.height))
        maxMagnification = max(fitMag * 4, 4.0)
        magnification = fitMag
        // Position: tall images start at the top; everything else is centered.
        // contentView.bounds is in (magnification-scaled) document units.
        let clip = contentView.bounds.size
        let origin = NSPoint(x: (sz.width - clip.width) / 2,
                             y: isTall ? 0 : (sz.height - clip.height) / 2)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }

    /// Re-fit to the current viewport unless the user has manually zoomed.
    func relayoutForResize() {
        guard hasImage, !userHasZoomed else { return }
        needsLayout = true
    }

    override func magnify(with event: NSEvent) {
        userHasZoomed = true
        super.magnify(with: event)
    }

    private func toggleZoom(at event: NSEvent) {
        guard hasImage else { return }
        let pt = docView.convert(event.locationInWindow, from: nil)
        if magnification > baselineMag * 1.02 {
            userHasZoomed = false
            recomputeFit()
        } else {
            userHasZoomed = true
            let target = min(max(baselineMag * 2.5, 1.0), maxMagnification)
            setMagnification(target, centeredAt: pt)
        }
    }
}

/// 1–4 image grid. Computes its own height for a given content width.
/// A single image follows Flare's `singleAspectRatio` (real ratio clamped to
/// `max(9/21, ratio)`), resolved asynchronously once the image decodes and
/// cached so re-builds don't re-flow.
final class MediaImagesView: FlippedView {
    private let onTap: ((Int) -> Void)?
    /// Fired when the single image resolves its real aspect ratio and the
    /// height changes — the host re-flows the feed.
    var onHeightChanged: (() -> Void)?

    /// Discovered single-image display aspect (width/height), keyed by URL.
    static var singleAspectCache: [String: CGFloat] = [:]
    /// Natural display width (pts) for images narrower than their container, keyed by URL.
    /// nil = not yet loaded; value ≥ container width means use full container width.
    static var singleNaturalWidthCache: [String: CGFloat] = [:]

    static func clampAspect(_ a: CGFloat) -> CGFloat {
        max(9.0 / 21.0, min(21.0 / 9.0, a))
    }

    static func singleAspect(for item: MediaItem) -> CGFloat {
        if let a = item.aspect { return clampAspect(a) }
        if let url = item.url, let a = singleAspectCache[url] { return a }
        return 16.0 / 10.0
    }

    /// Effective display width: the image's natural width if smaller than the container.
    static func singleDisplayWidth(for item: MediaItem, containerWidth: CGFloat) -> CGFloat {
        if let url = item.url, let nw = singleNaturalWidthCache[url], nw < containerWidth { return nw }
        return containerWidth
    }

    /// Layout height for a width without instantiating tiles (no image loads).
    /// Mirrors the frame height set in `init`.
    static func contentHeight(items: [MediaItem], width: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        if items.count == 1 {
            let dw = singleDisplayWidth(for: items[0], containerWidth: width)
            return ceil(dw / singleAspect(for: items[0]))
        }
        return ceil(width * 9 / 16)
    }

    init(items: [MediaItem], width: CGFloat, onTap: ((Int) -> Void)? = nil) {
        self.onTap = onTap
        super.init(frame: .zero)
        wantsLayer = true
        let theme = ThemeManager.shared.theme
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1

        let n = items.count
        let gap: CGFloat = 2
        var h: CGFloat
        if n == 1 {
            let item = items[0]
            let dw = Self.singleDisplayWidth(for: item, containerWidth: width)
            h = dw / Self.singleAspect(for: item)
            let tile = ImageTile(item)
            tile.frame = NSRect(x: 0, y: 0, width: dw, height: h)
            addSubview(tile)
            let hover = HoverControl(frame: tile.frame)
            hover.onState = { hv, _ in tile.alphaValue = hv ? 0.9 : 1 }
            hover.onClick = { [weak self] in self?.onTap?(0) }
            addSubview(hover)
            let needsLoad = item.aspect == nil && Self.singleAspectCache[item.url ?? ""] == nil
                         || Self.singleNaturalWidthCache[item.url ?? ""] == nil
            if let url = item.url, needsLoad {
                tile.onLoad = { [weak self, weak tile, weak hover] img in
                    guard let self else { return }
                    let imgW = img.size.width, imgH = img.size.height
                    guard imgW > 0, imgH > 0 else { return }
                    let a = Self.clampAspect(imgW / imgH)
                    Self.singleAspectCache[url] = a
                    let newDW = imgW < width ? imgW : width
                    Self.singleNaturalWidthCache[url] = newDW
                    let newH = ceil(newDW / a)
                    guard abs(newDW - self.frame.width) > 0.5 || abs(newH - self.frame.height) > 0.5 else { return }
                    tile?.frame = NSRect(x: 0, y: 0, width: newDW, height: newH)
                    hover?.frame = NSRect(x: 0, y: 0, width: newDW, height: newH)
                    self.frame = NSRect(x: 0, y: 0, width: newDW, height: newH)
                    self.onHeightChanged?()
                }
            }
        } else if n == 2 {
            h = width * 9 / 16
            let cw = (width - gap) / 2
            addTile(items[0], 0, NSRect(x: 0, y: 0, width: cw, height: h))
            addTile(items[1], 1, NSRect(x: cw + gap, y: 0, width: cw, height: h))
        } else if n == 3 {
            h = width * 9 / 16
            let cw = (width - gap) / 2
            addTile(items[0], 0, NSRect(x: 0, y: 0, width: cw, height: h))
            let rh = (h - gap) / 2
            addTile(items[1], 1, NSRect(x: cw + gap, y: 0, width: cw, height: rh))
            addTile(items[2], 2, NSRect(x: cw + gap, y: rh + gap, width: cw, height: rh))
        } else {
            h = width * 9 / 16
            let cw = (width - gap) / 2
            let rh = (h - gap) / 2
            let four = Array(items.prefix(4))
            addTile(four[0], 0, NSRect(x: 0, y: 0, width: cw, height: rh))
            addTile(four[1], 1, NSRect(x: cw + gap, y: 0, width: cw, height: rh))
            addTile(four[2], 2, NSRect(x: 0, y: rh + gap, width: cw, height: rh))
            addTile(four[3], 3, NSRect(x: cw + gap, y: rh + gap, width: cw, height: rh))
        }
        frame = NSRect(x: 0, y: 0, width: width, height: ceil(h))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func addTile(_ item: MediaItem, _ index: Int, _ rect: NSRect) {
        let t = ImageTile(item)
        t.frame = rect
        addSubview(t)
        let hover = HoverControl(frame: rect)
        hover.onState = { h, _ in t.alphaValue = h ? 0.9 : 1 }
        hover.onClick = { [weak self] in self?.onTap?(index) }
        addSubview(hover)
    }
}

/// Link preview card.
final class LinkCardView: FlippedView {
    private let theme = ThemeManager.shared.theme

    /// Layout height for a width without instantiating the tile. Mirrors `init`.
    static func contentHeight(media: Media, width: CGFloat) -> CGFloat {
        let theme = ThemeManager.shared.theme
        let imgH = width * 8 / 16
        let padX: CGFloat = 14
        let textW = width - padX * 2
        var y = imgH + 10 + 15 + 3
        let titleAttr = NSAttributedString(string: media.title ?? "", attributes: [
            .font: Fonts.sans(15, .bold), .foregroundColor: theme.fgHeading
        ])
        y += measureHeight(titleAttr, width: textW) + 3
        let descPara = NSMutableParagraphStyle()
        descPara.lineBreakMode = .byTruncatingTail
        let descAttr = NSAttributedString(string: media.desc ?? "", attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: descPara
        ])
        let lineH = ceil(Fonts.sans(13.5).boundingRectForFont.height * 1.4)
        y += min(measureHeight(descAttr, width: textW), lineH * 2 + 2) + 12
        return ceil(y)
    }

    init(media: Media, width: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1

        let imgH = width * 8 / 16
        if let item = media.item {
            let tile = ImageTile(item)
            tile.frame = NSRect(x: 0, y: 0, width: width, height: imgH)
            addSubview(tile)
        }
        if media.domain == "Article" {
            let badge = NSTextField(labelWithString: "X Article")
            badge.font = Fonts.sans(11, .bold)
            badge.textColor = .white
            badge.isBezeled = false; badge.drawsBackground = false
            badge.sizeToFit()
            let bw = badge.frame.width + 16
            let bh: CGFloat = 22
            let bg = FlippedView(frame: NSRect(x: 8, y: imgH - bh - 8, width: bw, height: bh))
            bg.wantsLayer = true
            bg.layer?.cornerRadius = 6
            bg.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.72).cgColor
            badge.frame = NSRect(x: 8, y: (bh - badge.frame.height) / 2, width: badge.frame.width, height: badge.frame.height)
            bg.addSubview(badge)
            addSubview(bg)
        }

        let padX: CGFloat = 14
        let textW = width - padX * 2
        var y = imgH + 10

        let domain = makeLabel(media.domain ?? "", font: Fonts.sans(12), color: theme.fgSubdued)
        domain.frame = NSRect(x: padX, y: y, width: textW, height: 15)
        addSubview(domain)
        y += 15 + 3

        let titleAttr = NSAttributedString(string: media.title ?? "", attributes: [
            .font: Fonts.sans(15, .bold), .foregroundColor: theme.fgHeading
        ])
        let titleH = measureHeight(titleAttr, width: textW)
        let title = NSTextField(labelWithAttributedString: titleAttr)
        title.isBezeled = false; title.drawsBackground = false
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 0
        title.frame = NSRect(x: padX, y: y, width: textW, height: titleH)
        addSubview(title)
        y += titleH + 3

        let descPara = NSMutableParagraphStyle()
        descPara.lineBreakMode = .byTruncatingTail
        let descAttr = NSAttributedString(string: media.desc ?? "", attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: theme.fgSubdued, .paragraphStyle: descPara
        ])
        // 2-line clamp
        let lineH = ceil(Fonts.sans(13.5).boundingRectForFont.height * 1.4)
        let descH = min(measureHeight(descAttr, width: textW), lineH * 2 + 2)
        let desc = NSTextField(labelWithAttributedString: descAttr)
        desc.isBezeled = false; desc.drawsBackground = false
        desc.lineBreakMode = .byTruncatingTail
        desc.maximumNumberOfLines = 2
        desc.frame = NSRect(x: padX, y: y, width: textW, height: descH)
        addSubview(desc)
        y += descH + 12

        frame = NSRect(x: 0, y: 0, width: width, height: ceil(y))

        let hover = HoverControl(frame: bounds)
        hover.autoresizingMask = [.width, .height]
        hover.onState = { [weak self] h, _ in
            self?.layer?.backgroundColor = (h ? self?.theme.bgLayer1 : NSColor.clear)?.cgColor
        }
        if let link = media.url, let dest = URL(string: link) {
            hover.onClick = { NSWorkspace.shared.open(dest) }
        }
        addSubview(hover)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Compact attribution row shown under a promoted video.
final class MediaSourceView: HoverControl {
    static let rowHeight: CGFloat = 20

    init(source: Person, isX: Bool, width: CGFloat, onOpenProfile: ((Person) -> Void)? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.rowHeight))
        let theme = ThemeManager.shared.theme
        var x: CGFloat = 0

        let prefix = makeLabel(isX ? "From" : "视频来自", font: Fonts.sans(13), color: theme.fgSubdued)
        let prefixW = min(prefix.perchSingleLineWidth, width)
        prefix.placeSingleLine(x: x, y: 1, width: prefixW, height: 18)
        addSubview(prefix)
        x += prefixW + 7

        if x + 18 <= width {
            let avatar = AvatarView(person: source, size: 18)
            avatar.frame = NSRect(x: x, y: 1, width: 18, height: 18)
            addSubview(avatar)
            x += 18 + 7
        }

        let handle: NSTextField?
        let handleW: CGFloat
        if isX {
            let h = makeLabel("@\(source.handle)", font: Fonts.sans(13), color: theme.fgSubdued)
            handleW = min(h.perchSingleLineWidth, max(0, width * 0.36))
            handle = h
        } else {
            handleW = 0
            handle = nil
        }

        let verifiedW: CGFloat = source.verified ? 17 : 0
        let handleGap: CGFloat = handleW > 0 ? 6 : 0
        let nameMaxW = max(0, width - x - verifiedW - handleGap - handleW)
        let name = makeLabel(source.name, font: Fonts.sans(13.5, .bold), color: theme.fgHeading)
        let nameW = min(name.perchSingleLineWidth, nameMaxW)
        name.placeSingleLine(x: x, y: 0, width: nameW, height: 20)
        addSubview(name)
        x += nameW

        if source.verified, x + 17 <= width {
            let verified = VerifiedBadge(size: 13)
            verified.frame = NSRect(x: x + 4, y: 3.5, width: 13, height: 13)
            addSubview(verified)
            x += 17
        }

        if let handle, x + handleGap + handleW <= width {
            x += handleGap
            handle.placeSingleLine(x: x, y: 1, width: handleW, height: 18)
            addSubview(handle)
        }

        onClick = { onOpenProfile?(source) }
        onState = { hovering, _ in
            name.textColor = hovering ? theme.accent : theme.fgHeading
        }
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Embedded quote post.
final class QuotePostView: HoverControl {
    /// Layout height for a width without instantiating tiles. Mirrors `init`.
    static func contentHeight(quote: Quote, width: CGFloat) -> CGFloat {
        let theme = ThemeManager.shared.theme
        let padX: CGFloat = 12, padY: CGFloat = 10
        let innerW = width - padX * 2
        var y = padY + 18 + 4   // header row
        let textPara = NSMutableParagraphStyle()
        textPara.lineHeightMultiple = 1.45
        let textAttr = NSAttributedString(string: quote.text, attributes: [
            .font: Fonts.sans(13.5), .foregroundColor: theme.fgBody, .paragraphStyle: textPara
        ])
        let lineH = ceil(Fonts.sans(13.5).boundingRectForFont.height * 1.45)
        y += min(measureHeight(textAttr, width: innerW), lineH * 4 + 4)
        if let media = quote.media {
            switch media.type {
            case .images where !media.items.isEmpty:
                y += 8 + MediaImagesView.contentHeight(items: media.items, width: innerW)
            case .video:
                y += 8 + innerW * 9 / 16
            case .link:
                let cardImgH = innerW * 9 / 16
                let domainH: CGFloat = 15
                let titleAttrC = NSAttributedString(string: media.title ?? "", attributes: [
                    .font: Fonts.sans(13.5, .bold), .foregroundColor: theme.fgHeading
                ])
                let titleH = min(measureHeight(titleAttrC, width: innerW - 20), ceil(Fonts.sans(13.5, .bold).boundingRectForFont.height) + 4)
                y += 8 + cardImgH + 8 + domainH + 2 + titleH + 10
            default: break
            }
        }
        y += padY
        return ceil(y)
    }

    init(quote: Quote, width: CGFloat, onClick: (() -> Void)? = nil,
         onOpenProfile: ((Person) -> Void)? = nil,
         onMention: ((String) -> Void)? = nil,
         onOpenMedia: ((MediaViewerContext) -> Void)? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        let theme = ThemeManager.shared.theme
        layer?.cornerRadius = 12
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1
        layer?.masksToBounds = true

        let padX: CGFloat = 12, padY: CGFloat = 10
        let innerW = width - padX * 2
        var y = padY
        let isX = quote.author.platform == .x

        // header row
        let avatar = AvatarView(person: quote.author, size: 18)
        avatar.frame = NSRect(x: padX, y: y, width: 18, height: 18)
        addSubview(avatar)
        var x = padX + 18 + 6
        let name = makeLabel(quote.author.name, font: Fonts.sans(13.5, .bold), color: theme.fgHeading)
        name.lineBreakMode = .byTruncatingTail
        let nameW = min(name.perchSingleLineWidth, innerW - 24)
        name.frame = NSRect(x: x, y: y + (18 - name.intrinsicContentSize.height) / 2, width: nameW, height: name.intrinsicContentSize.height)
        addSubview(name)
        x += nameW + 4
        if quote.author.verified {
            let v = VerifiedBadge(size: 13)
            v.frame = NSRect(x: x, y: y + 2, width: 13, height: 13)
            addSubview(v)
            x += 13 + 4
        }
        let time = makeLabel("· \(quote.time)", font: Fonts.sans(13.5), color: theme.fgSubdued)
        let timeW = time.perchSingleLineWidth
        if isX {
            let handle = makeLabel("@\(quote.author.handle)", font: Fonts.sans(13.5), color: theme.fgSubdued)
            handle.lineBreakMode = .byTruncatingTail
            let avail = max(0, innerW - (x - padX) - timeW - 6)
            let hw = min(handle.perchSingleLineWidth, avail)
            handle.frame = NSRect(x: x, y: y + (18 - handle.intrinsicContentSize.height) / 2, width: hw, height: handle.intrinsicContentSize.height)
            addSubview(handle)
            x += hw + 4
        }
        time.frame = NSRect(x: x, y: y + (18 - time.intrinsicContentSize.height) / 2, width: timeW, height: time.intrinsicContentSize.height)
        addSubview(time)
        // transparent header hit area — intercepts clicks to open author profile
        if let onOpenProfile {
            let hit = HoverControl(frame: NSRect(x: 0, y: y, width: width, height: 18))
            hit.onClick = { onOpenProfile(quote.author) }
            addSubview(hit)
        }
        y += 18 + 4

        // text (clamp ~4 lines) — RichTextView for tappable mentions + links
        let rich = RichTextView(text: quote.text, font: Fonts.sans(13.5), color: theme.fgBody,
                                accent: theme.accent, lineHeightMultiple: 1.45, onMention: onMention)
        rich.lineLimit = 4
        rich.onTap = onClick
        let lineH = ceil(Fonts.sans(13.5).boundingRectForFont.height * 1.45)
        let textH = min(rich.height(forWidth: innerW), lineH * 4 + 4)
        rich.frame = NSRect(x: padX, y: y, width: innerW, height: textH)
        addSubview(rich)
        y += textH

        if let media = quote.media {
            switch media.type {
            case .images where !media.items.isEmpty:
                let items = media.items
                y += 8
                let imgH = MediaImagesView.contentHeight(items: items, width: innerW)
                let miv = MediaImagesView(items: items, width: innerW, onTap: onOpenMedia.map { cb in
                    { idx in cb(MediaViewerContext(items: items, initialIndex: idx,
                                                   author: quote.author, type: .images, dur: nil)) }
                })
                miv.frame = NSRect(x: padX, y: y, width: innerW, height: imgH)
                addSubview(miv)
                y += imgH

            case .video:
                let vitem = media.item ?? media.items.first ?? MediaItem(Gradient("#1c1c22", "#0e0e12"))
                y += 8
                let imgH = innerW * 9 / 16
                let playbackKey = VideoPlaybackStore.quoteKey(author: quote.author, text: quote.text, item: vitem)
                let vp = VideoPlayerView(item: vitem, durText: media.dur, isX: isX, variant: .inline,
                    playbackKey: playbackKey,
                    onOpenWindow: onOpenMedia.map { cb in
                        {
                            cb(MediaViewerContext(items: [vitem], initialIndex: 0,
                                                   author: quote.author, type: .video, dur: media.dur,
                                                   playbackKey: playbackKey))
                        }
                    })
                vp.frame = NSRect(x: padX, y: y, width: innerW, height: imgH)
                vp.wantsLayer = true
                vp.layer?.cornerRadius = 8
                vp.layer?.masksToBounds = true
                addSubview(vp)
                y += imgH

            case .link:
                y += 8
                let cardImgH = innerW * 9 / 16
                let cont = FlippedView()
                cont.wantsLayer = true
                cont.layer?.cornerRadius = 8
                cont.layer?.masksToBounds = true
                cont.layer?.borderColor = theme.borderDefault.cgColor
                cont.layer?.borderWidth = 1
                var cardY: CGFloat = 0
                if let item = media.item {
                    let tile = ImageTile(item)
                    tile.frame = NSRect(x: 0, y: 0, width: innerW, height: cardImgH)
                    cont.addSubview(tile)
                }
                cardY += cardImgH + 8
                let cardPadX: CGFloat = 10
                let cardTextW = innerW - cardPadX * 2
                let domainLbl = makeLabel(media.domain ?? "", font: Fonts.sans(12), color: theme.fgSubdued)
                domainLbl.frame = NSRect(x: cardPadX, y: cardY, width: cardTextW, height: 15)
                cont.addSubview(domainLbl)
                cardY += 15 + 2
                let titleAttrC = NSAttributedString(string: media.title ?? "", attributes: [
                    .font: Fonts.sans(13.5, .bold), .foregroundColor: theme.fgHeading
                ])
                let titleH = min(measureHeight(titleAttrC, width: cardTextW), ceil(Fonts.sans(13.5, .bold).boundingRectForFont.height) + 4)
                let titleLbl = NSTextField(labelWithAttributedString: titleAttrC)
                titleLbl.isBezeled = false; titleLbl.drawsBackground = false
                titleLbl.lineBreakMode = .byTruncatingTail
                titleLbl.maximumNumberOfLines = 1
                titleLbl.frame = NSRect(x: cardPadX, y: cardY, width: cardTextW, height: titleH)
                cont.addSubview(titleLbl)
                cardY += titleH + 10
                cont.frame = NSRect(x: padX, y: y, width: innerW, height: cardY)
                if let link = media.url, let dest = URL(string: link) {
                    let hover = HoverControl(frame: NSRect(x: 0, y: 0, width: innerW, height: cardY))
                    hover.autoresizingMask = [.width, .height]
                    hover.onState = { [weak cont] h, _ in
                        cont?.layer?.backgroundColor = (h ? theme.bgLayer1 : NSColor.clear).cgColor
                    }
                    hover.onClick = { NSWorkspace.shared.open(dest) }
                    cont.addSubview(hover)
                }
                addSubview(cont)
                y += cardY

            default: break
            }
        }
        y += padY
        frame = NSRect(x: 0, y: 0, width: width, height: ceil(y))

        self.onClick = onClick
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Compose-only thumbnail grid for picked (not-yet-uploaded) media, with per-tile remove + ALT chrome.
final class ComposeMediaGrid: FlippedView {
    init(picks: [PickedMedia], width: CGFloat,
         onRemove: @escaping (Int) -> Void, onAlt: @escaping (Int) -> Void) {
        super.init(frame: .zero)
        let theme = ThemeManager.shared.theme
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        layer?.borderColor = theme.borderDefault.cgColor
        layer?.borderWidth = 1

        let n = min(picks.count, 4)
        let gap: CGFloat = 2
        let grad = Gradient("#3b3b46", "#26262e")
        func item(_ i: Int) -> MediaItem { MediaItem(url: nil, grad: grad, localImage: picks[i].thumbnail) }

        var frames: [NSRect] = []
        var h: CGFloat
        if n == 1 {
            h = min(width * 10 / 16, 360)
            frames = [NSRect(x: 0, y: 0, width: width, height: h)]
        } else if n == 2 {
            h = width * 9 / 16
            let cw = (width - gap) / 2
            frames = [NSRect(x: 0, y: 0, width: cw, height: h), NSRect(x: cw + gap, y: 0, width: cw, height: h)]
        } else if n == 3 {
            h = width * 9 / 16
            let cw = (width - gap) / 2
            let rh = (h - gap) / 2
            frames = [NSRect(x: 0, y: 0, width: cw, height: h),
                      NSRect(x: cw + gap, y: 0, width: cw, height: rh),
                      NSRect(x: cw + gap, y: rh + gap, width: cw, height: rh)]
        } else {
            h = width * 9 / 16
            let cw = (width - gap) / 2
            let rh = (h - gap) / 2
            frames = [NSRect(x: 0, y: 0, width: cw, height: rh),
                      NSRect(x: cw + gap, y: 0, width: cw, height: rh),
                      NSRect(x: 0, y: rh + gap, width: cw, height: rh),
                      NSRect(x: cw + gap, y: rh + gap, width: cw, height: rh)]
        }

        for i in 0..<n {
            let f = frames[i]
            let tile = ImageTile(item(i))
            tile.frame = f
            addSubview(tile)

            if picks[i].kind == .video || picks[i].kind == .gif {
                let badge = FlippedView(frame: NSRect(x: f.midX - 21, y: f.midY - 21, width: 42, height: 42))
                badge.wantsLayer = true
                badge.layer?.cornerRadius = 21
                badge.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.62).cgColor
                if picks[i].kind == .video {
                    let play = GlyphView(name: "play", size: 22, color: .white)
                    play.frame = NSRect(x: 11, y: 10, width: 22, height: 22)
                    badge.addSubview(play)
                } else {
                    let lbl = makeLabel("GIF", font: Fonts.sans(13, .bold), color: .white, align: .center)
                    lbl.frame = NSRect(x: 0, y: 13, width: 42, height: 16)
                    badge.addSubview(lbl)
                }
                addSubview(badge)
            }

            // remove button (top-right)
            let rm = HoverControl(frame: NSRect(x: f.maxX - 7 - 28, y: f.minY + 7, width: 28, height: 28))
            rm.wantsLayer = true
            rm.layer?.cornerRadius = 14
            rm.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.72).cgColor
            let xg = GlyphView(name: "close", size: 15, color: .white)
            xg.frame = NSRect(x: 6.5, y: 6.5, width: 15, height: 15)
            rm.addSubview(xg)
            rm.onClick = { onRemove(i) }
            addSubview(rm)

            // ALT pill (bottom-left)
            let alt = HoverControl(frame: NSRect(x: f.minX + 7, y: f.maxY - 7 - 22, width: 40, height: 22))
            alt.wantsLayer = true
            alt.layer?.cornerRadius = 6
            let hasAlt = !(picks[i].alt ?? "").isEmpty
            alt.layer?.backgroundColor = (hasAlt ? theme.accentBg : NSColor(white: 0.06, alpha: 0.72)).cgColor
            let altL = makeLabel("ALT", font: Fonts.sans(11, .bold), color: .white, align: .center)
            altL.frame = NSRect(x: 0, y: 4, width: 40, height: 14)
            alt.addSubview(altL)
            alt.onClick = { onAlt(i) }
            addSubview(alt)
        }
        frame = NSRect(x: 0, y: 0, width: width, height: ceil(h))
    }
    required init?(coder: NSCoder) { fatalError() }
}
