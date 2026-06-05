import AppKit

enum Platform: String {
    case x
    case weibo
}

/// A two-stop linear gradient used by media tiles, link cards, banners.
struct Gradient {
    let c0: NSColor
    let c1: NSColor
    init(_ a: String, _ b: String) {
        c0 = NSColor(hex: a)
        c1 = NSColor(hex: b)
    }
}

/// An author / mentionable person. Accounts are people with an `id` + extra fields.
final class Person {
    /// Viewer-perspective relationship to this user (from authed API responses).
    struct Relationship {
        var following: Bool?
        var followedBy: Bool?
        var muting: Bool?
        var blocking: Bool?
    }

    let id: String?
    let name: String
    let handle: String
    let colorToken: String
    let verified: Bool
    let platform: Platform
    var avatarURL: String?     // real profile image (live accounts); nil → initials
    // account-only extras
    let followers: String?
    let following: String?
    let unreadSeed: Int
    /// Set post-init by the data mapper (kept out of init to avoid call-site churn).
    var relationship: Relationship?

    init(id: String? = nil, name: String, handle: String, colorToken: String,
         verified: Bool, platform: Platform, avatarURL: String? = nil,
         followers: String? = nil, following: String? = nil, unreadSeed: Int = 0) {
        self.id = id
        self.name = name
        self.handle = handle
        self.colorToken = Theme.stripToken(colorToken)
        self.verified = verified
        self.platform = platform
        self.avatarURL = avatarURL
        self.followers = followers
        self.following = following
        self.unreadSeed = unreadSeed
    }

    func color(_ theme: Theme) -> NSColor { theme.scaleColor(colorToken) }
}

typealias Account = Person

enum MediaType {
    case images
    case video
    case link
}

/// A single media element: the real URL plus a gradient fallback that always renders.
struct MediaItem {
    let url: String?        // media_url_https (image / video thumbnail)
    let grad: Gradient      // gradient fallback (always present)
    let videoURL: String?   // best mp4 variant (video only)
    let alt: String?        // alt text
    let aspect: CGFloat?    // display aspect width/height (video, from API)
    let localImage: NSImage?  // compose/optimistic only — renders directly, bypassing ImageLoader
    init(url: String? = nil, grad: Gradient, videoURL: String? = nil, alt: String? = nil,
         aspect: CGFloat? = nil, localImage: NSImage? = nil) {
        self.url = url
        self.grad = grad
        self.videoURL = videoURL
        self.alt = alt
        self.aspect = aspect
        self.localImage = localImage
    }
    /// Convenience for mock data: gradient-only item.
    init(_ grad: Gradient) { self.init(url: nil, grad: grad, videoURL: nil, alt: nil, aspect: nil) }
}

/// A piece of media chosen in the composer (file pick or pasted), pending upload.
enum PickedMediaKind { case image, video, gif }

struct PickedMedia {
    let data: Data              // raw bytes (read from disk, or pasted)
    let kind: PickedMediaKind
    let mimeType: String        // image/jpeg, image/png, image/gif, video/mp4, video/quicktime
    var alt: String?
    let thumbnail: NSImage?     // preview for the compose grid + optimistic post
    let fileURL: URL?           // present for file picks (needed for video duration); nil when pasted
}

struct Media {
    let type: MediaType
    var items: [MediaItem] = []     // images
    var dur: String? = nil          // video
    var title: String? = nil        // link
    var desc: String? = nil         // link
    var domain: String? = nil       // link
    var url: String? = nil          // link destination
    var item: MediaItem? = nil      // video / link single-item
    var source: Person? = nil       // original creator for promoted/attributed media
}

/// Context passed to the media viewer window.
struct MediaViewerContext {
    let items: [MediaItem]
    let initialIndex: Int
    let author: Person
    let type: MediaType
    let dur: String?
    let playbackKey: String?

    init(items: [MediaItem], initialIndex: Int, author: Person, type: MediaType,
         dur: String?, playbackKey: String? = nil) {
        self.items = items
        self.initialIndex = initialIndex
        self.author = author
        self.type = type
        self.dur = dur
        self.playbackKey = playbackKey
    }
}

struct Quote {
    let author: Person
    let time: String
    let text: String
    let media: Media?
    let createdAt: Date?

    init(author: Person, time: String, text: String, media: Media?, createdAt: Date? = nil) {
        self.author = author
        self.time = time
        self.text = text
        self.media = media
        self.createdAt = createdAt
    }
}

struct Stats {
    var replies: Int?
    var reposts: Int
    var likes: Int
    var views: String?
    var quotes: Int?

    init(replies: Int? = nil, reposts: Int, likes: Int, views: String? = nil, quotes: Int? = nil) {
        self.replies = replies
        self.reposts = reposts
        self.likes = likes
        self.views = views
        self.quotes = quotes
    }
}

final class Post {
    let id: String
    let author: Person
    let time: String
    var pinned: Bool
    var repostedBy: String?
    var text: String
    var media: Media?
    var stats: Stats
    var liked: Bool
    var reposted: Bool
    var bookmarked: Bool
    var quote: Quote?
    var quoteSrcId: String?
    var createdAt: Date?
    // Conversation threading (detail page): who this post replies to, and its root.
    var replyToId: String?
    var conversationId: String?
    // Thread grouping: a vertical line links consecutive posts of one conversation.
    var urlMap: [String: String] = [:]  // expanded URL → full URL (for tooltip)
    var connectTop = false      // a thread line runs up from the avatar to the post above
    var connectBottom = false   // a thread line runs down from the avatar to the post below

    init(id: String, author: Person, time: String, pinned: Bool = false, repostedBy: String? = nil,
         text: String, media: Media? = nil, stats: Stats,
         liked: Bool = false, reposted: Bool = false, bookmarked: Bool = false,
         quote: Quote? = nil, quoteSrcId: String? = nil,
         replyToId: String? = nil, conversationId: String? = nil,
         createdAt: Date? = nil) {
        self.id = id
        self.author = author
        self.time = time
        self.pinned = pinned
        self.repostedBy = repostedBy
        self.text = text
        self.media = media
        self.stats = stats
        self.liked = liked
        self.reposted = reposted
        self.bookmarked = bookmarked
        self.quote = quote
        self.quoteSrcId = quoteSrcId
        self.createdAt = createdAt
        self.replyToId = replyToId
        self.conversationId = conversationId
    }

    /// Shallow copy used when producing a merged (overrides-applied) post.
    func copy() -> Post {
        let p = Post(id: id, author: author, time: time, pinned: pinned, repostedBy: repostedBy,
                     text: text, media: media, stats: stats, liked: liked, reposted: reposted,
                     bookmarked: bookmarked, quote: quote, quoteSrcId: quoteSrcId,
                     replyToId: replyToId, conversationId: conversationId,
                     createdAt: createdAt)
        p.connectTop = connectTop
        p.connectBottom = connectBottom
        return p
    }
}

/// A comment / reply in a detail thread.
final class Comment {
    let id: String
    let author: Person
    let time: String
    let text: String
    var stats: Stats
    var liked: Bool
    var replyToId: String?
    var children: [Comment]
    init(id: String, author: Person, time: String, text: String, stats: Stats, liked: Bool = false,
         replyToId: String? = nil, children: [Comment] = []) {
        self.id = id
        self.author = author
        self.time = time
        self.text = text
        self.stats = stats
        self.liked = liked
        self.replyToId = replyToId
        self.children = children
    }
}

struct Profile {
    let bio: String
    let location: String
    let joined: String
    let followers: String
    let following: String
    let banner: Gradient
}

/// A bookmark folder. `id`/`name` mirror X's `bookmark_collections_slice` items;
/// `colorToken` is a Perch-local cosmetic (X folders have no color) persisted on-device.
struct BookmarkFolder {
    let id: String
    var name: String
    var colorToken: String
}

/// A column descriptor.
final class ColumnSpec {
    let id: String
    var type: String          // home / mentions / search / bookmarks / likes / lists / profile
    var accountId: String?
    var feed: String
    init(id: String, type: String, accountId: String? = nil, feed: String = HomeFeed.forYou.rawValue) {
        self.id = id
        self.type = type
        self.accountId = accountId
        self.feed = feed
    }
}

/// A pushed navigation screen inside a column.
final class NavScreen {
    enum Kind { case post(String), profile(Person) }
    let key: String
    let kind: Kind
    init(key: String, kind: Kind) {
        self.key = key
        self.kind = kind
    }
}

/// Compose modes.
enum ComposeMode {
    case new
    case reply
    case quote
    case repost
}

struct ComposeContext {
    let mode: ComposeMode
    let post: Post?
}
