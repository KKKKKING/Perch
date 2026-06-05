import AppKit

/// An ordered JSON value model for the debug tools. Unlike `Codable`/`JSONSerialization`,
/// object entries keep insertion order — tweet data is shown with a meaningful key order.
indirect enum DebugJSON {
    case object([(String, DebugJSON)])
    case array([DebugJSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

// MARK: - Building from app models

extension DebugJSON {
    static func from(post: Post) -> DebugJSON {
        var o: [(String, DebugJSON)] = []
        o.append(("id", .string(post.id)))
        o.append(("author", personJSON(post.author)))
        o.append(("time", .string(post.time)))
        o.append(("text", .string(post.text)))
        if post.pinned { o.append(("pinned", .bool(true))) }
        if let rb = post.repostedBy { o.append(("repostedBy", .string(rb))) }
        o.append(("stats", statsJSON(post.stats)))
        o.append(("liked", .bool(post.liked)))
        o.append(("reposted", .bool(post.reposted)))
        o.append(("bookmarked", .bool(post.bookmarked)))
        if let q = post.quote { o.append(("quote", quoteJSON(q))) }
        if let qs = post.quoteSrcId { o.append(("quoteSrcId", .string(qs))) }
        if let r = post.replyToId { o.append(("replyToId", .string(r))) }
        if let c = post.conversationId { o.append(("conversationId", .string(c))) }
        if let m = post.media { o.append(("media", mediaJSON(m))) }
        return .object(o)
    }

    static func personJSON(_ p: Person) -> DebugJSON {
        var o: [(String, DebugJSON)] = []
        if let id = p.id { o.append(("id", .string(id))) }
        o.append(("name", .string(p.name)))
        o.append(("handle", .string(p.handle)))
        o.append(("verified", .bool(p.verified)))
        o.append(("platform", .string(p.platform.rawValue)))
        o.append(("colorToken", .string(p.colorToken)))
        if let a = p.avatarURL { o.append(("avatarURL", .string(a))) }
        if let f = p.followers { o.append(("followers", .string(f))) }
        if let f = p.following { o.append(("following", .string(f))) }
        return .object(o)
    }

    static func statsJSON(_ s: Stats) -> DebugJSON {
        var o: [(String, DebugJSON)] = []
        if let r = s.replies { o.append(("replies", .number(Double(r)))) }
        o.append(("reposts", .number(Double(s.reposts))))
        o.append(("likes", .number(Double(s.likes))))
        if let v = s.views { o.append(("views", .string(v))) }
        if let q = s.quotes { o.append(("quotes", .number(Double(q)))) }
        return .object(o)
    }

    static func quoteJSON(_ q: Quote) -> DebugJSON {
        var o: [(String, DebugJSON)] = []
        o.append(("author", personJSON(q.author)))
        o.append(("time", .string(q.time)))
        o.append(("text", .string(q.text)))
        if let m = q.media { o.append(("media", mediaJSON(m))) }
        return .object(o)
    }

    static func mediaJSON(_ m: Media) -> DebugJSON {
        var o: [(String, DebugJSON)] = []
        switch m.type {
        case .images: o.append(("type", .string("images")))
        case .video: o.append(("type", .string("video")))
        case .link: o.append(("type", .string("link")))
        }
        if !m.items.isEmpty { o.append(("items", .array(m.items.map(itemJSON)))) }
        if let d = m.dur { o.append(("dur", .string(d))) }
        if let t = m.title { o.append(("title", .string(t))) }
        if let d = m.desc { o.append(("desc", .string(d))) }
        if let d = m.domain { o.append(("domain", .string(d))) }
        if let u = m.url { o.append(("url", .string(u))) }
        if let i = m.item { o.append(("item", itemJSON(i))) }
        if let s = m.source { o.append(("source", personJSON(s))) }
        return .object(o)
    }

    static func itemJSON(_ i: MediaItem) -> DebugJSON {
        var o: [(String, DebugJSON)] = []
        if let u = i.url { o.append(("url", .string(u))) }
        if let v = i.videoURL { o.append(("videoURL", .string(v))) }
        if let a = i.alt { o.append(("alt", .string(a))) }
        if let a = i.aspect { o.append(("aspect", .number(Double(a)))) }
        if o.isEmpty { return .null }
        return .object(o)
    }
}

// MARK: - Parsing network bodies (order not significant)

extension DebugJSON {
    static func parse(_ data: Data) -> DebugJSON? {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return convert(obj)
    }

    private static func convert(_ any: Any) -> DebugJSON {
        switch any {
        case let dict as [String: Any]:
            let keys = dict.keys.sorted { $0.lowercased() < $1.lowercased() }
            return .object(keys.map { ($0, convert(dict[$0]!)) })
        case let arr as [Any]:
            return .array(arr.map(convert))
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return .bool(num.boolValue) }
            return .number(num.doubleValue)
        case let str as String:
            return .string(str)
        case is NSNull:
            return .null
        default:
            return .null
        }
    }
}

// MARK: - Pretty printing (for the Copy button)

extension DebugJSON {
    func prettyString() -> String {
        var out = ""
        write(into: &out, indent: 0)
        return out
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        let pad1 = String(repeating: "  ", count: indent + 1)
        switch self {
        case .object(let entries):
            if entries.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, kv) in entries.enumerated() {
                out += pad1 + "\"" + DebugJSON.escape(kv.0) + "\": "
                kv.1.write(into: &out, indent: indent + 1)
                out += i < entries.count - 1 ? ",\n" : "\n"
            }
            out += pad + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad1
                item.write(into: &out, indent: indent + 1)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += pad + "]"
        case .string(let s):
            out += "\"" + DebugJSON.escape(s) + "\""
        case .number(let n):
            out += DebugJSON.numberString(n)
        case .bool(let b):
            out += b ? "true" : "false"
        case .null:
            out += "null"
        }
    }

    static func numberString(_ n: Double) -> String {
        if n.isFinite && n == n.rounded() && abs(n) < 1e15 {
            return String(Int64(n))
        }
        return String(n)
    }

    static func escape(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            default: r.unicodeScalars.append(ch)
            }
        }
        return r
    }
}

/// Theme-aware syntax colors for the JSON tree (Spectrum 1100 steps; absent from `Theme.scale`).
struct DebugPalette {
    let key: NSColor
    let string: NSColor
    let number: NSColor
    let bool: NSColor
    let null: NSColor
    let punct: NSColor

    init(_ theme: Theme) {
        let d = theme.isDark
        key = NSColor(hex: d ? "#7ca9fc" : "#1d3ecf")     // blue-1100
        string = NSColor(hex: d ? "#18c16e" : "#025d3c")  // green-1100
        number = NSColor(hex: d ? "#ff80ab" : "#a3053e")  // magenta-1100
        bool = NSColor(hex: d ? "#c595f0" : "#730dcc")    // purple-1100
        null = theme.fgDisabled
        punct = theme.fgSubdued
    }
}
