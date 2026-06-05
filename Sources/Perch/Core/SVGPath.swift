import AppKit

/// Parses an SVG path "d" string into an NSBezierPath in SVG (y-down) coordinates.
/// Supports M/m L/l H/h V/v C/c S/s Q/q T/t Z/z and an A/a arc (converted to cubic beziers).
enum SVGPath {

    static func parse(_ d: String) -> NSBezierPath {
        let path = NSBezierPath()
        var tokens = Tokenizer(d)

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint? = nil
        var lastQuadControl: CGPoint? = nil
        var hasStarted = false

        func num() -> CGFloat? { tokens.nextNumber() }
        func pt(rel: Bool) -> CGPoint? {
            guard let x = num(), let y = num() else { return nil }
            return rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while let cmd = tokens.nextCommand() {
            let rel = cmd.isLowercase
            switch Character(cmd.lowercased()) {
            case "m":
                guard let p = pt(rel: rel && hasStarted) else { break }
                current = p
                subpathStart = p
                path.move(to: p)
                hasStarted = true
                lastCubicControl = nil; lastQuadControl = nil
                // subsequent pairs are implicit lineto
                while tokens.peekIsNumber() {
                    guard let q = pt(rel: rel) else { break }
                    path.line(to: q)
                    current = q
                }
                lastCubicControl = nil; lastQuadControl = nil
            case "l":
                while tokens.peekIsNumber() {
                    guard let q = pt(rel: rel) else { break }
                    path.line(to: q)
                    current = q
                }
                lastCubicControl = nil; lastQuadControl = nil
            case "h":
                while tokens.peekIsNumber() {
                    guard let x = num() else { break }
                    let nx = rel ? current.x + x : x
                    current.x = nx
                    path.line(to: current)
                }
                lastCubicControl = nil; lastQuadControl = nil
            case "v":
                while tokens.peekIsNumber() {
                    guard let y = num() else { break }
                    let ny = rel ? current.y + y : y
                    current.y = ny
                    path.line(to: current)
                }
                lastCubicControl = nil; lastQuadControl = nil
            case "c":
                while tokens.peekIsNumber() {
                    guard let c1 = pt(rel: rel), let c2 = pt(rel: rel), let end = pt(rel: rel) else { break }
                    path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                    lastCubicControl = c2
                    current = end
                }
                lastQuadControl = nil
            case "s":
                while tokens.peekIsNumber() {
                    guard let c2 = pt(rel: rel), let end = pt(rel: rel) else { break }
                    let c1: CGPoint
                    if let lc = lastCubicControl {
                        c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                    } else {
                        c1 = current
                    }
                    path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                    lastCubicControl = c2
                    current = end
                }
                lastQuadControl = nil
            case "q":
                while tokens.peekIsNumber() {
                    guard let q = pt(rel: rel), let end = pt(rel: rel) else { break }
                    addQuad(path, from: current, control: q, to: end)
                    lastQuadControl = q
                    current = end
                }
                lastCubicControl = nil
            case "t":
                while tokens.peekIsNumber() {
                    guard let end = pt(rel: rel) else { break }
                    let q: CGPoint
                    if let lq = lastQuadControl {
                        q = CGPoint(x: 2 * current.x - lq.x, y: 2 * current.y - lq.y)
                    } else {
                        q = current
                    }
                    addQuad(path, from: current, control: q, to: end)
                    lastQuadControl = q
                    current = end
                }
                lastCubicControl = nil
            case "a":
                while tokens.peekIsNumber() {
                    guard let rx = num(), let ry = num(), let xrot = num(),
                          let laf = num(), let sf = num(),
                          let ex = num(), let ey = num() else { break }
                    let end = rel ? CGPoint(x: current.x + ex, y: current.y + ey) : CGPoint(x: ex, y: ey)
                    addArc(path, from: current, rx: rx, ry: ry, xAxisRotationDeg: xrot,
                           largeArc: laf != 0, sweep: sf != 0, to: end)
                    current = end
                }
                lastCubicControl = nil; lastQuadControl = nil
            case "z":
                path.close()
                current = subpathStart
                lastCubicControl = nil; lastQuadControl = nil
            default:
                break
            }
        }
        return path
    }

    private static func addQuad(_ path: NSBezierPath, from p0: CGPoint, control q: CGPoint, to p2: CGPoint) {
        let c1 = CGPoint(x: p0.x + 2.0 / 3.0 * (q.x - p0.x), y: p0.y + 2.0 / 3.0 * (q.y - p0.y))
        let c2 = CGPoint(x: p2.x + 2.0 / 3.0 * (q.x - p2.x), y: p2.y + 2.0 / 3.0 * (q.y - p2.y))
        path.curve(to: p2, controlPoint1: c1, controlPoint2: c2)
    }

    /// Endpoint-arc → center parameterization → cubic bezier segments.
    private static func addArc(_ path: NSBezierPath, from p0: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               xAxisRotationDeg: CGFloat, largeArc: Bool, sweep: Bool, to p1: CGPoint) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 { path.line(to: p1); return }
        let phi = xAxisRotationDeg * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        var rxSq = rx * rx, rySq = ry * ry
        let lambda = (x1p * x1p) / rxSq + (y1p * y1p) / rySq
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
            rxSq = rx * rx; rySq = ry * ry
        }
        var denom = rxSq * y1p * y1p + rySq * x1p * x1p
        if denom == 0 { denom = 1e-6 }
        var factor = (rxSq * rySq - rxSq * y1p * y1p - rySq * x1p * x1p) / denom
        if factor < 0 { factor = 0 }
        var coef = sqrt(factor)
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let segments = Int(ceil(abs(dTheta) / (.pi / 2)))
        let delta = dTheta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(delta / 4)
        var angleStart = theta1
        for _ in 0..<segments {
            let cosA = cos(angleStart), sinA = sin(angleStart)
            let cosB = cos(angleStart + delta), sinB = sin(angleStart + delta)
            let e1 = CGPoint(x: cosPhi * rx * cosA - sinPhi * ry * sinA + cx,
                             y: sinPhi * rx * cosA + cosPhi * ry * sinA + cy)
            let e2 = CGPoint(x: cosPhi * rx * cosB - sinPhi * ry * sinB + cx,
                             y: sinPhi * rx * cosB + cosPhi * ry * sinB + cy)
            let d1 = CGPoint(x: -cosPhi * rx * sinA - sinPhi * ry * cosA,
                             y: -sinPhi * rx * sinA + cosPhi * ry * cosA)
            let d2 = CGPoint(x: -cosPhi * rx * sinB - sinPhi * ry * cosB,
                             y: -sinPhi * rx * sinB + cosPhi * ry * cosB)
            let c1 = CGPoint(x: e1.x + t * d1.x, y: e1.y + t * d1.y)
            let c2 = CGPoint(x: e2.x - t * d2.x, y: e2.y - t * d2.y)
            path.curve(to: e2, controlPoint1: c1, controlPoint2: c2)
            angleStart += delta
        }
    }

    /// Lightweight number/command tokenizer for path data.
    private struct Tokenizer {
        private let chars: [Character]
        private var i = 0
        init(_ s: String) { chars = Array(s) }

        private func isCommandChar(_ c: Character) -> Bool {
            return "MmLlHhVvCcSsQqTtAaZz".contains(c)
        }

        mutating func nextCommand() -> Character? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if isCommandChar(c) { i += 1; return c }
            return nil
        }

        mutating func skipSeparators() {
            while i < chars.count {
                let c = chars[i]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1 } else { break }
            }
        }

        func peekIsNumber() -> Bool {
            var j = i
            while j < chars.count {
                let c = chars[j]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { j += 1 } else { break }
            }
            guard j < chars.count else { return false }
            let c = chars[j]
            return c == "-" || c == "+" || c == "." || (c >= "0" && c <= "9")
        }

        mutating func nextNumber() -> CGFloat? {
            skipSeparators()
            guard i < chars.count else { return nil }
            var str = ""
            var seenDot = false
            var seenE = false
            // optional sign
            if chars[i] == "-" || chars[i] == "+" { str.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c >= "0" && c <= "9" {
                    str.append(c); i += 1
                } else if c == "." {
                    if seenDot { break }       // a second dot starts a new number
                    seenDot = true; str.append(c); i += 1
                } else if c == "e" || c == "E" {
                    if seenE { break }
                    seenE = true; str.append(c); i += 1
                    if i < chars.count && (chars[i] == "-" || chars[i] == "+") { str.append(chars[i]); i += 1 }
                } else {
                    break
                }
            }
            return Double(str).map { CGFloat($0) }
        }
    }
}
