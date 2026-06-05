import AppKit
import CryptoKit
import Foundation

enum TimelineStatus: String, Codable {
    case loading
    case ready
    case error
    case empty
}

enum TimelineGapStatus: String, Codable {
    case idle
    case loading
    case error
}

enum HomeFeed: String, Codable, CaseIterable {
    case forYou = "for-you"
    case following

    var storageComponent: String {
        switch self {
        case .forYou: return "for-you"
        case .following: return "following"
        }
    }

    var labelX: String {
        switch self {
        case .forYou: return "For you"
        case .following: return "Following"
        }
    }

    var labelW: String {
        switch self {
        case .forYou: return "推荐"
        case .following: return "关注"
        }
    }

    var icon: String {
        switch self {
        case .forYou: return "sparkle"
        case .following: return "user"
        }
    }

    static func normalize(_ raw: String?) -> HomeFeed {
        guard let raw else { return .forYou }
        if raw == "foryou" { return .forYou }
        return HomeFeed(rawValue: raw) ?? .forYou
    }
}

struct TimelineIdentity: Hashable, Codable {
    enum Kind: String, Codable {
        case home
        case likes
        case bookmarks
        case search
        case lists
        case profile
    }

    let accountId: String
    let kind: Kind
    let variant: String

    var key: String { "\(accountId)|\(storageName)" }

    var storageName: String {
        switch kind {
        case .home:
            return "home-\(variant)"
        case .likes:
            return "likes"
        case .bookmarks:
            return "bookmarks"
        case .search:
            return "search-\(Self.stableHash(variant))"
        case .lists:
            return "list-\(Self.sanitize(variant))"
        case .profile:
            return "profile-\(Self.sanitize(variant))"
        }
    }

    static func forColumn(_ col: ColumnSpec, account: Account, searchQuery: String?,
                          listId: String? = nil) -> TimelineIdentity? {
        guard let accountId = account.id else { return nil }
        switch col.type {
        case "home":
            return TimelineIdentity(accountId: accountId, kind: .home,
                                    variant: HomeFeed.normalize(col.feed).storageComponent)
        case "likes":
            return TimelineIdentity(accountId: accountId, kind: .likes, variant: "")
        case "bookmarks":
            return TimelineIdentity(accountId: accountId, kind: .bookmarks, variant: "")
        case "search":
            let q = searchQuery ?? ""
            guard !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TimelineIdentity(accountId: accountId, kind: .search, variant: q)
        case "lists":
            guard let listId, !listId.isEmpty else { return nil }
            return TimelineIdentity(accountId: accountId, kind: .lists, variant: listId)
        default:
            return nil
        }
    }

    static func profile(accountId: String, person: Person) -> TimelineIdentity {
        TimelineIdentity(accountId: accountId, kind: .profile, variant: person.id ?? person.handle)
    }

    private static func sanitize(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_@."))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "unknown" : s
    }

    static func stableHash(_ raw: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for b in raw.utf8 {
            hash ^= UInt64(b)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct TimelineAnchor: Codable, Equatable {
    var postId: String?
    var offset: CGFloat
    var fallbackY: CGFloat
}

struct TimelineGap: Codable, Equatable {
    var id: String
    var cursor: String
    var status: TimelineGapStatus
    var message: String?

    init(id: String = "gap-\(UUID().uuidString)", cursor: String,
         status: TimelineGapStatus = .idle, message: String? = nil) {
        self.id = id
        self.cursor = cursor
        self.status = status
        self.message = message
    }
}

enum TimelineRow {
    case post(Post)
    case gap(TimelineGap)

    var postValue: Post? {
        if case .post(let p) = self { return p }
        return nil
    }

    var postId: String? {
        if case .post(let p) = self { return p.id }
        return nil
    }

    var gapId: String? {
        if case .gap(let g) = self { return g.id }
        return nil
    }
}

struct TimelineSnapshot {
    var identity: TimelineIdentity
    var rows: [TimelineRow]
    var status: TimelineStatus
    var refreshing: Bool
    var unreadIds: [String]
    var bottomCursor: String?
    var anchor: TimelineAnchor?
    var errorMessage: String?
    var loadedFromDisk: Bool

    init(identity: TimelineIdentity,
         rows: [TimelineRow] = [],
         status: TimelineStatus = .loading,
         refreshing: Bool = false,
         unreadIds: [String] = [],
         bottomCursor: String? = nil,
         anchor: TimelineAnchor? = nil,
         errorMessage: String? = nil,
         loadedFromDisk: Bool = false) {
        self.identity = identity
        self.rows = rows
        self.status = status
        self.refreshing = refreshing
        self.unreadIds = unreadIds
        self.bottomCursor = bottomCursor
        self.anchor = anchor
        self.errorMessage = errorMessage
        self.loadedFromDisk = loadedFromDisk
    }

    var posts: [Post] {
        rows.compactMap {
            if case .post(let p) = $0 { return p }
            return nil
        }
    }

    var unreadCount: Int { unreadIds.count }

    mutating func normalizeStatus() {
        if rows.isEmpty {
            status = status == .error ? .error : .empty
        } else {
            status = .ready
        }
    }
}

struct TimelineMergeResult {
    var rows: [TimelineRow]
    var unreadIds: [String]
    var bottomCursor: String?
    var insertedGap: Bool
}

enum TimelineMergePolicy {
    case ordered
    case unorderedById
}

enum TimelineMerge {
    static func mergeLatest(existing: [TimelineRow], incoming: [Post], bottomCursor: String?,
                            policy: TimelineMergePolicy = .ordered) -> TimelineMergeResult {
        if policy == .unorderedById {
            return mergeLatestUnordered(existing: existing, incoming: incoming, bottomCursor: bottomCursor)
        }

        let existingIds = Set(existing.compactMap(\.postId))
        let incomingIds = Set(incoming.map(\.id))
        let newIds = incoming.map(\.id).filter { !existingIds.contains($0) }

        guard !incoming.isEmpty else {
            return TimelineMergeResult(rows: existing, unreadIds: [], bottomCursor: bottomCursor, insertedGap: false)
        }

        if existingIds.isEmpty {
            return TimelineMergeResult(rows: incoming.map { .post($0) },
                                       unreadIds: [],
                                       bottomCursor: bottomCursor,
                                       insertedGap: false)
        }

        let hasOverlap = incoming.contains { existingIds.contains($0.id) }
        if hasOverlap {
            let incomingRows: [TimelineRow] = incoming.map { .post($0) }
            let rest = existing.filter { row in
                guard let id = row.postId else { return true }
                return !incomingIds.contains(id)
            }
            return TimelineMergeResult(rows: incomingRows + rest,
                                       unreadIds: newIds,
                                       bottomCursor: bottomCursor,
                                       insertedGap: false)
        }

        var rows = incoming.map { TimelineRow.post($0) }
        if let bottomCursor, !bottomCursor.isEmpty {
            rows.append(.gap(TimelineGap(cursor: bottomCursor)))
        }
        rows.append(contentsOf: existing)
        return TimelineMergeResult(rows: rows,
                                   unreadIds: newIds,
                                   bottomCursor: bottomCursor,
                                   insertedGap: bottomCursor?.isEmpty == false)
    }

    static func fillGap(existing: [TimelineRow], gapId: String, incoming: [Post],
                        nextCursor: String?, policy: TimelineMergePolicy = .ordered) -> TimelineMergeResult {
        if policy == .unorderedById {
            return fillGapUnordered(existing: existing, gapId: gapId, incoming: incoming, nextCursor: nextCursor)
        }

        guard let gapIndex = existing.firstIndex(where: { $0.gapId == gapId }) else {
            return TimelineMergeResult(rows: existing, unreadIds: [], bottomCursor: nextCursor, insertedGap: false)
        }

        let before = Array(existing[..<gapIndex])
        let after = Array(existing[(gapIndex + 1)...])
        let afterIds = Set(after.compactMap(\.postId))
        let incomingIds = Set(incoming.map(\.id))
        let hasOverlap = incoming.contains { afterIds.contains($0.id) }

        var replacement = incoming.map { TimelineRow.post($0) }
        var insertedGap = false
        if !hasOverlap, let nextCursor, !nextCursor.isEmpty {
            replacement.append(.gap(TimelineGap(cursor: nextCursor)))
            insertedGap = true
        }

        let dedupedAfter = after.filter { row in
            guard let id = row.postId else { return true }
            return !incomingIds.contains(id)
        }
        return TimelineMergeResult(rows: before + replacement + dedupedAfter,
                                   unreadIds: [],
                                   bottomCursor: nextCursor,
                                   insertedGap: insertedGap)
    }

    private static func mergeLatestUnordered(existing: [TimelineRow], incoming: [Post],
                                             bottomCursor: String?) -> TimelineMergeResult {
        guard !incoming.isEmpty else {
            return TimelineMergeResult(rows: dedupeRows(existing), unreadIds: [],
                                       bottomCursor: bottomCursor, insertedGap: false)
        }

        var rows = dedupeRows(existing)
        let existingIds = Set(rows.compactMap(\.postId))
        var seenIds = existingIds
        var newPosts: [Post] = []
        var touchedExisting = false

        for post in incoming {
            if existingIds.contains(post.id) {
                touchedExisting = true
                rows = updateKnownPost(in: rows, with: post)
            } else if seenIds.insert(post.id).inserted {
                newPosts.append(post)
            }
        }

        guard !existingIds.isEmpty else {
            return TimelineMergeResult(rows: normalizeThreadConnections(newPosts.map { .post($0) }),
                                       unreadIds: [],
                                       bottomCursor: bottomCursor,
                                       insertedGap: false)
        }

        let unreadIds = newPosts.map(\.id)
        var merged = newPosts.map { TimelineRow.post($0) }
        var insertedGap = false
        if !touchedExisting, let bottomCursor, !bottomCursor.isEmpty {
            merged.append(.gap(TimelineGap(cursor: bottomCursor)))
            insertedGap = true
        }
        merged.append(contentsOf: rows)

        return TimelineMergeResult(rows: normalizeThreadConnections(merged),
                                   unreadIds: unreadIds,
                                   bottomCursor: bottomCursor,
                                   insertedGap: insertedGap)
    }

    private static func fillGapUnordered(existing: [TimelineRow], gapId: String, incoming: [Post],
                                         nextCursor: String?) -> TimelineMergeResult {
        guard existing.contains(where: { $0.gapId == gapId }) else {
            return TimelineMergeResult(rows: dedupeRows(existing), unreadIds: [],
                                       bottomCursor: nextCursor, insertedGap: false)
        }

        var rows = dedupeRows(existing)
        guard let normalizedGapIndex = rows.firstIndex(where: { $0.gapId == gapId }) else {
            return TimelineMergeResult(rows: rows, unreadIds: [], bottomCursor: nextCursor, insertedGap: false)
        }

        var knownIds = Set(rows.compactMap(\.postId))
        var replacement: [TimelineRow] = []
        for post in incoming {
            if knownIds.contains(post.id) {
                rows = updateKnownPost(in: rows, with: post)
            } else if knownIds.insert(post.id).inserted {
                replacement.append(.post(post))
            }
        }

        rows.remove(at: normalizedGapIndex)
        let insertionIndex = min(normalizedGapIndex, rows.count)
        rows.insert(contentsOf: replacement, at: insertionIndex)

        var insertedGap = false
        if let nextCursor, !nextCursor.isEmpty {
            rows.insert(.gap(TimelineGap(cursor: nextCursor)), at: insertionIndex + replacement.count)
            insertedGap = true
        }

        return TimelineMergeResult(rows: normalizeThreadConnections(rows),
                                   unreadIds: [],
                                   bottomCursor: nextCursor,
                                   insertedGap: insertedGap)
    }

    private static func dedupeRows(_ rows: [TimelineRow]) -> [TimelineRow] {
        var seen = Set<String>()
        var out: [TimelineRow] = []
        for row in rows {
            guard let id = row.postId else {
                out.append(row)
                continue
            }
            guard seen.insert(id).inserted else { continue }
            out.append(row)
        }
        return normalizeThreadConnections(out)
    }

    private static func updateKnownPost(in rows: [TimelineRow], with incoming: Post) -> [TimelineRow] {
        rows.map { row in
            guard case .post(let existing) = row, existing.id == incoming.id else { return row }
            return .post(mergeKnownDuplicate(existing: existing, incoming: incoming))
        }
    }

    private static func mergeKnownDuplicate(existing: Post, incoming: Post) -> Post {
        guard hasNewConversationContext(existing: existing, incoming: incoming) else { return existing }
        let merged = existing.copy()
        if let incomingReplies = incoming.stats.replies {
            merged.stats.replies = max(existing.stats.replies ?? 0, incomingReplies)
        }
        merged.stats.quotes = max(existing.stats.quotes ?? 0, incoming.stats.quotes ?? 0)
        return merged
    }

    private static func hasNewConversationContext(existing: Post, incoming: Post) -> Bool {
        let existingReplies = existing.stats.replies ?? 0
        let incomingReplies = incoming.stats.replies ?? 0
        let existingQuotes = existing.stats.quotes ?? 0
        let incomingQuotes = incoming.stats.quotes ?? 0
        return incomingReplies > existingReplies || incomingQuotes > existingQuotes
    }

    private static func normalizeThreadConnections(_ rows: [TimelineRow]) -> [TimelineRow] {
        rows.enumerated().map { index, row in
            guard case .post(let post) = row else { return row }
            let prev = index > 0 ? rows[index - 1].postValue : nil
            let next = index + 1 < rows.count ? rows[index + 1].postValue : nil
            let copy = post.copy()
            copy.connectTop = post.connectTop && prev.map { canConnect($0, copy) } == true
            copy.connectBottom = post.connectBottom && next.map { canConnect(copy, $0) } == true
            return .post(copy)
        }
    }

    private static func canConnect(_ upper: Post, _ lower: Post) -> Bool {
        if lower.replyToId == upper.id { return true }
        guard let uc = upper.conversationId, let lc = lower.conversationId else { return false }
        return uc == lc
    }

    static func markGap(_ rows: [TimelineRow], id: String, status: TimelineGapStatus,
                        message: String? = nil) -> [TimelineRow] {
        rows.map { row in
            guard case .gap(var gap) = row, gap.id == id else { return row }
            gap.status = status
            gap.message = message
            return .gap(gap)
        }
    }
}

struct StoredTimelinePayload {
    var rows: [TimelineRow]
    var bottomCursor: String?
    var unreadIds: [String]
    var anchor: TimelineAnchor?
}

struct RawGraphQLPostIndex: Codable, Equatable {
    var postId: String
    var pagePath: String
    var operation: String
    var timeline: String
    var fetchedAt: Date
}

actor PersistentTimelineStore {
    static let shared = PersistentTimelineStore()

    private let root: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL? = nil) {
        let base = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
            .appendingPathComponent("AppData", isDirectory: true)
        self.root = base
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func load(_ identity: TimelineIdentity) async -> StoredTimelinePayload? {
        let rowsURL = rowsURL(for: identity)
        let stateURL = stateURL(for: identity)
        var rows: [TimelineRow] = []

        if let text = try? String(contentsOf: rowsURL, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard let data = String(line).data(using: .utf8),
                      let stored = try? decoder.decode(StoredTimelineLine.self, from: data),
                      let row = stored.timelineRow else { continue }
                rows.append(row)
            }
        }

        let state: StoredTimelineState?
        if let data = try? Data(contentsOf: stateURL) {
            state = try? decoder.decode(StoredTimelineState.self, from: data)
        } else {
            state = nil
        }

        guard !rows.isEmpty || state != nil else { return nil }
        return StoredTimelinePayload(rows: rows,
                                     bottomCursor: state?.bottomCursor,
                                     unreadIds: state?.unreadIds ?? [],
                                     anchor: state?.anchor)
    }

    func save(_ snapshot: TimelineSnapshot) async {
        do {
            try ensureDirectory(for: snapshot.identity)
            let lines = snapshot.rows.compactMap { StoredTimelineLine(row: $0) }
            let data = lines.compactMap { line -> Data? in
                guard let encoded = try? encoder.encode(line) else { return nil }
                return encoded + Data([0x0A])
            }.reduce(Data(), +)
            try data.write(to: rowsURL(for: snapshot.identity), options: .atomic)
            try writeState(snapshot)
        } catch {
            // Persistence is cache-only; runtime state should not fail because disk did.
        }
    }

    func saveState(_ snapshot: TimelineSnapshot) async {
        do { try writeState(snapshot) } catch {}
    }

    func saveRawGraphQL(_ capture: RawGraphQLCapture) async {
        do {
            let timeline = sanitizeFileComponent(capture.identity.storageName)
            let operation = sanitizeFileComponent(capture.operation)
            let filename = "\(timestampString(capture.fetchedAt))-\(operation)-\(sha8(capture.rawData)).json"
            let pageDir = rawRoot(for: capture.accountId)
                .appendingPathComponent("pages", isDirectory: true)
                .appendingPathComponent(timeline, isDirectory: true)
            try FileManager.default.createDirectory(at: pageDir, withIntermediateDirectories: true)
            let pageURL = pageDir.appendingPathComponent(filename)
            try capture.rawData.write(to: pageURL, options: .atomic)

            let relativePagePath = "pages/\(timeline)/\(filename)"
            let byPostDir = rawRoot(for: capture.accountId).appendingPathComponent("by-post", isDirectory: true)
            try FileManager.default.createDirectory(at: byPostDir, withIntermediateDirectories: true)

            let uniqueIds = Array(Set(capture.tweetIds)).sorted()
            for postId in uniqueIds {
                let index = RawGraphQLPostIndex(postId: postId,
                                                pagePath: relativePagePath,
                                                operation: capture.operation,
                                                timeline: capture.identity.storageName,
                                                fetchedAt: capture.fetchedAt)
                let data = try encoder.encode(index)
                try data.write(to: byPostDir.appendingPathComponent("\(sanitizeFileComponent(postId)).json"),
                               options: .atomic)
            }
        } catch {
            // Raw GraphQL archival is cache-only; live timeline state should not fail because disk did.
        }
    }

    func rawGraphQLIndex(accountId: String, postId: String) async -> RawGraphQLPostIndex? {
        let url = rawRoot(for: accountId)
            .appendingPathComponent("by-post", isDirectory: true)
            .appendingPathComponent("\(sanitizeFileComponent(postId)).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(RawGraphQLPostIndex.self, from: data)
    }

    func clearAccount(_ accountId: String) async {
        let url = root.appendingPathComponent(accountId, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
    }

    private func writeState(_ snapshot: TimelineSnapshot) throws {
        try ensureDirectory(for: snapshot.identity)
        let state = StoredTimelineState(bottomCursor: snapshot.bottomCursor,
                                        unreadIds: snapshot.unreadIds,
                                        anchor: snapshot.anchor,
                                        updatedAt: Date())
        let data = try encoder.encode(state)
        try data.write(to: stateURL(for: snapshot.identity), options: .atomic)
    }

    private func ensureDirectory(for identity: TimelineIdentity) throws {
        try FileManager.default.createDirectory(at: timelinesDir(for: identity),
                                                withIntermediateDirectories: true)
    }

    private func timelinesDir(for identity: TimelineIdentity) -> URL {
        root.appendingPathComponent(identity.accountId, isDirectory: true)
            .appendingPathComponent("timelines", isDirectory: true)
    }

    private func rowsURL(for identity: TimelineIdentity) -> URL {
        timelinesDir(for: identity).appendingPathComponent("\(identity.storageName).jsonl")
    }

    private func stateURL(for identity: TimelineIdentity) -> URL {
        timelinesDir(for: identity).appendingPathComponent("\(identity.storageName).state.json")
    }

    private func rawRoot(for accountId: String) -> URL {
        root.appendingPathComponent(accountId, isDirectory: true)
            .appendingPathComponent("raw-graphql", isDirectory: true)
    }

    private func sanitizeFileComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_@."))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "unknown" : s
    }

    private func timestampString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        fmt.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        return fmt.string(from: date)
    }

    private func sha8(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

private struct StoredTimelineState: Codable {
    var bottomCursor: String?
    var unreadIds: [String]
    var anchor: TimelineAnchor?
    var updatedAt: Date
}

private struct StoredTimelineLine: Codable {
    var type: String
    var post: StoredPost?
    var gap: TimelineGap?

    init?(row: TimelineRow) {
        switch row {
        case .post(let post):
            type = "post"
            self.post = StoredPost(post)
            gap = nil
        case .gap(let gap):
            type = "gap"
            post = nil
            self.gap = gap
        }
    }

    var timelineRow: TimelineRow? {
        switch type {
        case "post":
            return post.map { .post($0.post) }
        case "gap":
            return gap.map { .gap($0) }
        default:
            return nil
        }
    }
}

private struct StoredPerson: Codable {
    var id: String?
    var name: String
    var handle: String
    var colorToken: String
    var verified: Bool
    var platform: String
    var avatarURL: String?
    var followers: String?
    var following: String?
    var unreadSeed: Int

    init(_ person: Person) {
        id = person.id
        name = person.name
        handle = person.handle
        colorToken = person.colorToken
        verified = person.verified
        platform = person.platform.rawValue
        avatarURL = person.avatarURL
        followers = person.followers
        following = person.following
        unreadSeed = person.unreadSeed
    }

    var person: Person {
        Person(id: id, name: name, handle: handle, colorToken: colorToken,
               verified: verified, platform: Platform(rawValue: platform) ?? .x,
               avatarURL: avatarURL, followers: followers, following: following,
               unreadSeed: unreadSeed)
    }
}

private struct StoredPost: Codable {
    var id: String
    var author: StoredPerson
    var time: String
    var createdAt: Date?
    var pinned: Bool
    var repostedBy: String?
    var text: String
    var media: StoredMedia?
    var stats: StoredStats
    var liked: Bool
    var reposted: Bool
    var bookmarked: Bool
    var quote: StoredQuote?
    var quoteSrcId: String?
    var replyToId: String?
    var conversationId: String?
    var connectTop: Bool
    var connectBottom: Bool

    init(_ post: Post) {
        id = post.id
        author = StoredPerson(post.author)
        time = post.time
        createdAt = post.createdAt
        pinned = post.pinned
        repostedBy = post.repostedBy
        text = post.text
        media = post.media.map(StoredMedia.init)
        stats = StoredStats(post.stats)
        liked = post.liked
        reposted = post.reposted
        bookmarked = post.bookmarked
        quote = post.quote.map(StoredQuote.init)
        quoteSrcId = post.quoteSrcId
        replyToId = post.replyToId
        conversationId = post.conversationId
        connectTop = post.connectTop
        connectBottom = post.connectBottom
    }

    var post: Post {
        let p = Post(id: id, author: author.person,
                     time: createdAt.map { TimelineDate.relativeTime(from: $0) } ?? time,
                     pinned: pinned, repostedBy: repostedBy, text: text,
                     media: media?.media(seed: id), stats: stats.stats,
                     liked: liked, reposted: reposted, bookmarked: bookmarked,
                     quote: quote?.quote, quoteSrcId: quoteSrcId,
                     replyToId: replyToId, conversationId: conversationId,
                     createdAt: createdAt)
        p.connectTop = connectTop
        p.connectBottom = connectBottom
        return p
    }
}

private struct StoredStats: Codable {
    var replies: Int?
    var reposts: Int
    var likes: Int
    var views: String?
    var quotes: Int?

    init(_ stats: Stats) {
        replies = stats.replies
        reposts = stats.reposts
        likes = stats.likes
        views = stats.views
        quotes = stats.quotes
    }

    var stats: Stats { Stats(replies: replies, reposts: reposts, likes: likes, views: views, quotes: quotes) }
}

private struct StoredQuote: Codable {
    var author: StoredPerson
    var time: String
    var createdAt: Date?
    var text: String
    var media: StoredMedia?

    init(_ quote: Quote) {
        author = StoredPerson(quote.author)
        time = quote.time
        createdAt = quote.createdAt
        text = quote.text
        media = quote.media.map(StoredMedia.init)
    }

    var quote: Quote {
        Quote(author: author.person,
              time: createdAt.map { TimelineDate.relativeTime(from: $0) } ?? time,
              text: text,
              media: media?.media(seed: text),
              createdAt: createdAt)
    }
}

private struct StoredMedia: Codable {
    var type: String
    var items: [StoredMediaItem]
    var dur: String?
    var title: String?
    var desc: String?
    var domain: String?
    var url: String?
    var item: StoredMediaItem?
    var source: StoredPerson?

    init(_ media: Media) {
        switch media.type {
        case .images: type = "images"
        case .video: type = "video"
        case .link: type = "link"
        }
        items = media.items.map(StoredMediaItem.init)
        dur = media.dur
        title = media.title
        desc = media.desc
        domain = media.domain
        url = media.url
        item = media.item.map(StoredMediaItem.init)
        source = media.source.map(StoredPerson.init)
    }

    func media(seed: String) -> Media {
        let mediaType: MediaType
        switch type {
        case "video": mediaType = .video
        case "link": mediaType = .link
        default: mediaType = .images
        }
        return Media(type: mediaType,
                     items: items.map { $0.mediaItem(seed: seed) },
                     dur: dur,
                     title: title,
                     desc: desc,
                     domain: domain,
                     url: url,
                     item: item?.mediaItem(seed: seed),
                     source: source?.person)
    }
}

private struct StoredMediaItem: Codable {
    var url: String?
    var videoURL: String?
    var alt: String?
    var aspect: CGFloat?

    init(_ item: MediaItem) {
        url = item.url
        videoURL = item.videoURL
        alt = item.alt
        aspect = item.aspect
    }

    func mediaItem(seed: String) -> MediaItem {
        MediaItem(url: url, grad: Gradients.forSeed(url ?? videoURL ?? seed),
                  videoURL: videoURL, alt: alt, aspect: aspect)
    }
}

enum TimelineDate {
    static func date(fromTwitter raw: String?) -> Date? {
        guard let raw else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return fmt.date(from: raw)
    }

    static func relativeTime(from date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "now" }
        if delta < 3600 { return "\(Int(delta / 60))m" }
        if delta < 86400 { return "\(Int(delta / 3600))h" }
        if delta < 604800 { return "\(Int(delta / 86400))d" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }
}
