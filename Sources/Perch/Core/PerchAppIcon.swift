import AppKit

/// Perch's bird mark, rendered natively (resolution-independent) so it can be used
/// everywhere the design's SVG `PerchIcon` / `IconTray` appear without shipping any
/// raster assets — the app is a bare SwiftPM executable with no .icns bundle.
///
/// Two style variants, both ported from `design/project/app-icon/icons.jsx` +
/// `design/project/app/perchicon.jsx`:
///  - `.tray`  — Scheme E "Light tray": a gradient songbird + gray branch on a soft
///               neutral tile. Used as the dock / About-panel app icon.
///  - `.brand` — the shared `PerchIcon`: a white songbird + white branch on the
///               sky→ocean gradient squircle, with sheen. Used on the Welcome screen
///               and Settings ▸ About brand lockups.
enum PerchAppIcon {
    enum Style { case tray, brand }

    private static let sky = NSColor(hex: "#4FAEEE")     // gradient top — soft sky blue
    private static let ocean = NSColor(hex: "#1C81CF")   // gradient bottom — deep ocean blue
    private static let tile = NSColor(hex: "#f4f3f7")    // soft neutral tray
    private static let trayBranch = NSColor(hex: "#d3d2da")  // light gray perch (tray)
    private static let beak = NSColor(hex: "#ffce5c")    // golden beak
    private static let dockTrayScale: CGFloat = 0.80     // standard macOS icon-grid footprint (≈824/1024)

    /// The drop-shadow glow color the design applies under the brand mark.
    static let brandGlow = NSColor(hex: "#1C81CF")

    /// Shared 1024×1024 master for the dock icon (Scheme E); AppKit downscales it.
    static let shared: NSImage = make(style: .tray)

    /// The shared `PerchIcon` brand mark (white bird on blue gradient) for in-app lockups.
    static func brandImage(canvas: CGFloat = 256) -> NSImage { make(canvas: canvas, style: .brand) }

    static func make(canvas: CGFloat = 1024, style: Style = .tray) -> NSImage {
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            draw(canvas: canvas, style: style)
            return true
        }
        return image
    }

    /// Rasterizes the dock icon to a PNG (for verifying the mark without the dock); see PERCH_ICON_PNG.
    static func writePNG(to path: String, pixels: Int = 512) {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(canvas: CGFloat(pixels), style: .tray)
        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    /// macOS continuous-curvature squircle (superellipse, n=5) on a `size` canvas.
    private static func squircle(size: CGFloat = 1024, samples: Int = 240) -> NSBezierPath {
        let a = size / 2, n: CGFloat = 5
        let path = NSBezierPath()
        for i in 0...samples {
            let t = 2 * CGFloat.pi * CGFloat(i) / CGFloat(samples)
            let ct = cos(t), st = sin(t)
            let x = a + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
            let y = a + a * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.line(to: CGPoint(x: x, y: y)) }
        }
        path.close()
        return path
    }

    /// A round-capped vertical line (x, y0)→(y1) of `width` becomes a stadium/capsule.
    private static func capsule(x: CGFloat, y0: CGFloat, y1: CGFloat, width: CGFloat) -> NSBezierPath {
        let r = width / 2
        let rect = NSRect(x: x - r, y: y0 - r, width: width, height: (y1 - y0) + width)
        return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    }

    private static func draw(canvas: CGFloat, style: Style) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        // SVG is a 1024 y-down canvas; map it into the (y-up) image space.
        let k = canvas / 1024.0
        cg.translateBy(x: 0, y: canvas)
        cg.scaleBy(x: k, y: -k)
        if style == .tray {
            // The dock icon is assigned directly to applicationIconImage with no
            // .icns padding, so inset the tile to the standard macOS icon-grid
            // footprint. The bird is enlarged below by the inverse amount, so it
            // keeps its absolute size and ends up filling MORE of the smaller tile.
            cg.translateBy(x: 512, y: 512)
            cg.scaleBy(x: dockTrayScale, y: dockTrayScale)
            cg.translateBy(x: -512, y: -512)
        }

        let tray = squircle()
        // The brand mark perches the bird 10u higher than the tray variant (per design).
        let perchY: CGFloat = style == .tray ? 730 : 720
        let bgGradient = NSGradient(starting: sky, ending: ocean)!

        // 1 — tile / gradient background
        if style == .tray {
            tile.setFill()
            tray.fill()
        } else {
            cg.saveGState()
            tray.addClip()
            // perchicon.jsx bg gradient: x1=0.18 → x2=0.82, y1=0 → y2=1 across the 1024 box
            bgGradient.draw(from: CGPoint(x: 184, y: 0), to: CGPoint(x: 840, y: 1024), options: [])
            cg.restoreGState()
        }

        // 2 — clip to the tile, then lay the branch + bird inside it
        cg.saveGState()
        tray.addClip()

        let perch = NSBezierPath()
        perch.move(to: CGPoint(x: 150, y: perchY))
        perch.line(to: CGPoint(x: 874, y: perchY))
        perch.lineWidth = 26
        perch.lineCapStyle = .round
        (style == .tray ? trayBranch : NSColor.white.withAlphaComponent(0.5)).setStroke()
        perch.stroke()

        // bird transform: translate(470 perchY) scale(birdScale) translate(-95 -168).
        // Tray over-scales the bird so birdScale·dockTrayScale ≈ the design's 2.7 —
        // the bird holds its absolute size while the tile shrinks, so it fills more of it.
        let birdScale: CGFloat = style == .tray ? 3.75 : 2.7
        let birdT = AffineTransform(m11: birdScale, m12: 0, m21: 0, m22: birdScale,
                                    tX: 470 - birdScale * 95, tY: perchY - birdScale * 168)
        let body = SVGPath.parse("M128 46 C104 50 82 64 68 88 C60 100 56 108 54 116 C40 128 26 144 16 156 C30 158 46 157 62 153 C68 152 72 151 78 150 C100 162 122 162 140 150 C152 132 154 116 152 98 Z")
        let head = NSBezierPath(ovalIn: NSRect(x: 92, y: 30, width: 80, height: 80))
        let leg1 = capsule(x: 104, y0: 150, y1: 176, width: 7)
        let leg2 = capsule(x: 124, y0: 148, y1: 176, width: 7)
        let birdShapes = [body, head, leg1, leg2]
        for shape in birdShapes { shape.transform(using: birdT) }

        if style == .tray {
            // single sky→ocean gradient across the whole bird; clipping each shape to the
            // same bounding box keeps overlaps seamless (no per-shape banding).
            var bbox = body.bounds
            for shape in birdShapes { bbox = bbox.union(shape.bounds) }
            for shape in birdShapes {
                cg.saveGState()
                shape.addClip()
                bgGradient.draw(from: CGPoint(x: bbox.minX, y: bbox.minY),
                                to: CGPoint(x: bbox.maxX, y: bbox.maxY), options: [])
                cg.restoreGState()
            }
        } else {
            NSColor.white.setFill()
            for shape in birdShapes { shape.fill() }
        }

        let beakPath = SVGPath.parse("M168 66 L196 74 L168 86 Z")
        beakPath.transform(using: birdT)
        beak.setFill()
        beakPath.fill()

        let eye = NSBezierPath(ovalIn: NSRect(x: 138.5, y: 56.5, width: 15, height: 15))
        eye.transform(using: birdT)
        (style == .tray ? NSColor.white : ocean).setFill()
        eye.fill()

        // brand sheen: top white highlight → transparent → bottom shadow, clipped to the tile
        if style == .brand {
            let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22),
                                            NSColor.white.withAlphaComponent(0.0),
                                            NSColor.black.withAlphaComponent(0.12)],
                                   atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)!
            sheen.draw(from: CGPoint(x: 512, y: 0), to: CGPoint(x: 512, y: 1024), options: [])
        }

        cg.restoreGState() // drop the tile clip

        // 3 — pressed-glass inner hairline: squircle scaled 0.985 about center
        let hairline = squircle()
        hairline.transform(using: AffineTransform(m11: 0.985, m12: 0, m21: 0, m22: 0.985, tX: 7.68, tY: 7.68))
        hairline.lineWidth = 6
        (style == .tray ? NSColor.black.withAlphaComponent(0.08) : NSColor.white.withAlphaComponent(0.20)).setStroke()
        hairline.stroke()

        cg.restoreGState()
    }
}
