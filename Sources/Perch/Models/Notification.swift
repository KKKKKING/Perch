import AppKit

/// One of the six notification kinds. `like`/`repost`/`follow` aggregate into a
/// single avatar-stack row; `reply`/`mention`/`quote` render as engagement cards.
enum NotifKind: String {
    case like, repost, follow, reply, mention, quote

    var isAggregated: Bool { self == .like || self == .repost || self == .follow }

    func color(_ t: Theme) -> NSColor {
        switch self {
        case .like:   return t.magenta800
        case .repost: return t.green700
        case .quote:  return t.scaleColor("purple-700")
        case .follow, .reply, .mention: return t.accent
        }
    }

    /// Leading icon: a glyph name, or a literal character (mentions → "@").
    var iconGlyph: String? {
        switch self {
        case .like:   return "heart"
        case .repost, .quote: return "repost"
        case .follow: return "user"
        case .reply:  return "reply"
        case .mention: return nil
        }
    }
    var iconChar: String? { self == .mention ? "@" : nil }

    /// Verb for aggregated rows (like/repost/follow).
    func verb(_ isX: Bool) -> String {
        switch self {
        case .like:   return isX ? "liked your post" : "赞了你的微博"
        case .repost: return isX ? "reposted your post" : "转发了你的微博"
        case .follow: return isX ? "followed you" : "关注了你"
        default:      return ""
        }
    }

    /// Context line for engagement rows (reply/mention/quote).
    func ctx(_ isX: Bool) -> String {
        switch self {
        case .reply:   return isX ? "replied to you" : "回复了你"
        case .mention: return isX ? "mentioned you" : "提到了你"
        case .quote:   return isX ? "quoted your post" : "引用了你的微博"
        default:       return ""
        }
    }
}

/// A single notification. For aggregated kinds, `actors` is the avatar stack and
/// `count` the total. For engagement kinds, `post` carries the referenced post
/// (yours for reply, theirs for mention/quote) and `text` the reply body.
final class NotifItem {
    let id: String
    let kind: NotifKind
    let actors: [Person]
    let count: Int
    let time: String
    let unread: Bool
    let post: Post?
    let text: String?
    let bio: String?
    let single: Bool

    init(id: String, kind: NotifKind, actors: [Person] = [], count: Int = 0,
         time: String, unread: Bool = false, post: Post? = nil,
         text: String? = nil, bio: String? = nil, single: Bool = false) {
        self.id = id
        self.kind = kind
        self.actors = actors
        self.count = count == 0 ? actors.count : count
        self.time = time
        self.unread = unread
        self.post = post
        self.text = text
        self.bio = bio
        self.single = single
    }

    /// The actor whose avatar/name leads an engagement card.
    func engageActor() -> Person? {
        if kind == .reply { return actors.first }
        return post?.author ?? actors.first
    }
}

/// Filter sub-tab definitions (the segmented strip atop the notification center).
struct NotifFilter {
    let id: String
    let glyph: String?
    let char: String?
    let labelX: String
    let labelW: String
}

/// X mirrors the real product: three server-backed tabs. Each tab is its own
/// `2/notifications/{all,verified,mentions}.json` query — no client-side filtering.
let NOTIF_FILTERS: [NotifFilter] = [
    NotifFilter(id: "all",      glyph: "bell",             char: nil, labelX: "All",      labelW: "全部"),
    NotifFilter(id: "verified", glyph: "checkmark-circle", char: nil, labelX: "Verified", labelW: "认证"),
    NotifFilter(id: "mention",  glyph: nil,                char: "@", labelX: "Mentions", labelW: "@我的"),
]
