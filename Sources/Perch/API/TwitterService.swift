import AppKit
import AVFoundation

actor BadgeCountRequestCoalescer {
    private final class TaskBox {
        let task: Task<Int, Error>

        init(_ task: Task<Int, Error>) {
            self.task = task
        }
    }

    private var tasks: [String: TaskBox] = [:]

    func run(key: String, operation: @escaping () async throws -> Int) async throws -> Int {
        let box: TaskBox
        let ownsTask: Bool

        if let existing = tasks[key] {
            box = existing
            ownsTask = false
        } else {
            box = TaskBox(Task { try await operation() })
            tasks[key] = box
            ownsTask = true
        }

        defer {
            if ownsTask, tasks[key] === box {
                tasks[key] = nil
            }
        }

        return try await box.task.value
    }

    func cancel(key: String) {
        let box = tasks.removeValue(forKey: key)
        box?.task.cancel()
    }

    func cancelAll() {
        let pending = Array(tasks.values)
        tasks.removeAll()
        pending.forEach { $0.task.cancel() }
    }
}

/// High-level coordinator for the live X session: owns the API client, derives
/// the Perch `Account`, and bridges async fetches back to the main thread.
final class TwitterService {
    static let shared = TwitterService()

    private(set) var client: TwitterAPIClient?
    private(set) var credentials: TwitterCredentials?
    private var clients: [String: TwitterAPIClient] = [:]
    private var credentialMap: [String: TwitterCredentials] = [:]
    private var accountOrder: [String] = []
    private let badgeCountRequests = BadgeCountRequestCoalescer()
    var onAvatarBackfill: ((_ accountId: String, _ url: String?) -> Void)?

    var isLoggedIn: Bool { client != nil }

    /// Stable account id for the live X session (one per Twitter user id).
    static func accountId(for userId: String) -> String { "axlive_\(userId)" }

    var account: Account? {
        guard let c = credentials else { return nil }
        return TwitterService.makeAccount(from: c)
    }

    var accounts: [Account] {
        accountOrder.compactMap { credentialMap[$0] }.map { TwitterService.makeAccount(from: $0) }
    }

    private static func makeAccount(from c: TwitterCredentials) -> Account {
        Account(id: accountId(for: c.userId),
                name: c.displayName.isEmpty ? c.username : c.displayName,
                handle: c.username,
                colorToken: "indigo-700",
                verified: false,
                platform: .x,
                avatarURL: c.avatarURL,
                followers: nil, following: nil, unreadSeed: 0)
    }

    /// Restore saved sessions from the Keychain, if any. Does not hit the network.
    @discardableResult
    func restoreSessions() -> [Account] {
        let restored = TwitterCredentialStore.loadAll()
        clients.removeAll()
        credentialMap.removeAll()
        accountOrder.removeAll()

        for creds in restored {
            addSession(creds, client: TwitterAPIClient(authToken: creds.authToken, ct0: creds.ct0))
        }
        if let first = accountOrder.first { activate(accountId: first) }
        backfillAvatarURLs()
        return accounts
    }

    private func backfillAvatarURLs() {
        for aid in accountOrder {
            guard var creds = credentialMap[aid], creds.avatarURL == nil,
                  let api = clients[aid] else { continue }
            let screenName = creds.username
            Task { [weak self] in
                var url = (try? await api.getCurrentUser())?.avatarURL
                if url == nil { url = await self?.fetchAvatarURL(api: api, screenName: screenName) }
                guard let url else { return }
                creds.avatarURL = url
                self?.credentialMap[aid] = creds
                TwitterCredentialStore.save(creds)
                await MainActor.run { self?.onAvatarBackfill?(aid, url) }
            }
        }
    }

    /// Restore a saved session from the Keychain, if any. Does not hit the network.
    @discardableResult
    func restoreSession() -> Account? {
        restoreSessions().first
    }

    private func fetchAvatarURL(api: TwitterAPIClient, screenName: String) async -> String? {
        guard let node = try? await api.userByScreenName(screenName) else { return nil }
        return node.avatarURL
    }

    /// Validate fresh cookies, persist them, and return the resolved account.
    func login(authToken: String, ct0: String) async throws -> Account {
        let api = TwitterAPIClient(authToken: authToken, ct0: ct0)
        let user = try await api.getCurrentUser()
        var avatar = user.avatarURL
        if avatar == nil { avatar = await fetchAvatarURL(api: api, screenName: user.username) }
        let creds = TwitterCredentials(authToken: authToken, ct0: ct0,
                                       userId: user.id, username: user.username,
                                       displayName: user.name, avatarURL: avatar)
        TwitterCredentialStore.save(creds)
        addSession(creds, client: api)
        activate(accountId: TwitterService.accountId(for: creds.userId))
        return TwitterService.makeAccount(from: creds)
    }

    @discardableResult
    func activate(accountId: String) -> Bool {
        guard let creds = credentialMap[accountId], let api = clients[accountId] else { return false }
        credentials = creds
        client = api
        return true
    }

    func hasSession(accountId: String?) -> Bool {
        guard let accountId else { return false }
        return credentialMap[accountId] != nil && clients[accountId] != nil
    }

    func credentials(forAccountId accountId: String) -> TwitterCredentials? {
        credentialMap[accountId]
    }

    func account(forAccountId accountId: String) -> Account? {
        credentialMap[accountId].map { TwitterService.makeAccount(from: $0) }
    }

    private func addSession(_ creds: TwitterCredentials, client api: TwitterAPIClient) {
        let aid = TwitterService.accountId(for: creds.userId)
        credentialMap[aid] = creds
        clients[aid] = api
        if !accountOrder.contains(aid) { accountOrder.append(aid) }
    }

    private func requireClient() throws -> TwitterAPIClient {
        guard let client else { throw TwitterAPIError.authExpired }
        return client
    }

    private func requireClient(accountId: String) throws -> TwitterAPIClient {
        guard let client = clients[accountId] else { throw TwitterAPIError.authExpired }
        return client
    }

    // MARK: - Reads

    func fetchHomeTimeline(count: Int = 30, feed: HomeFeed = .following) async throws -> [Post] {
        let (groups, _) = try await requireClient().fetchHomeTimelineGroups(count: count, feed: feed)
        return TwitterDataMapper.posts(fromGroups: groups)
    }

    func fetchHomeTimeline(accountId: String, count: Int = 30,
                           cursor: String?, feed: HomeFeed = .following) async throws -> (posts: [Post], cursor: String?) {
        let page = try await fetchHomeTimelinePage(accountId: accountId, identity: nil,
                                                   count: count, cursor: cursor, feed: feed)
        return (page.posts, page.cursor)
    }

    func fetchHomeTimelinePage(accountId: String, identity: TimelineIdentity?,
                               count: Int = 30, cursor: String?,
                               feed: HomeFeed = .following,
                               seenTweetIds: [String] = [], fetchNewer: Bool = false) async throws -> TimelineFetchPage {
        let raw = try await requireClient(accountId: accountId)
            .fetchHomeTimelineGroupsRaw(count: count, cursor: cursor, feed: feed,
                                        seenTweetIds: seenTweetIds, fetchNewer: fetchNewer)
        let posts = TwitterDataMapper.posts(fromGroups: raw.groups)
        let newAuthors = raw.alertUsers.map { TwitterDataMapper.person(from: $0) }
        return timelinePage(posts: posts, cursor: raw.cursor,
                            accountId: accountId, identity: identity,
                            operation: raw.operation, rawData: raw.rawData,
                            tweetIds: TwitterDataMapper.tweetIds(fromGroups: raw.groups),
                            newAuthors: newAuthors, topCursor: raw.topCursor)
    }

    func fetchHomeTimeline(count: Int = 30, cursor: String?,
                           feed: HomeFeed = .following) async throws -> (posts: [Post], cursor: String?) {
        let (groups, next) = try await requireClient().fetchHomeTimelineGroups(count: count, cursor: cursor, feed: feed)
        return (TwitterDataMapper.posts(fromGroups: groups), next)
    }

    func tweetDetail(id: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().tweetDetail(id: id, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func userTweets(userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().userTweets(userId: userId, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func userTweets(accountId: String, userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let page = try await userTweetsPage(accountId: accountId, identity: nil,
                                            userId: userId, cursor: cursor)
        return (page.posts, page.cursor)
    }

    func userTweetsPage(accountId: String, identity: TimelineIdentity?,
                        userId: String, cursor: String? = nil) async throws -> TimelineFetchPage {
        let raw = try await requireClient(accountId: accountId).userTweetsRaw(userId: userId, cursor: cursor)
        let posts = TwitterDataMapper.posts(from: raw.nodes)
        return timelinePage(posts: posts, cursor: raw.cursor,
                            accountId: accountId, identity: identity,
                            operation: raw.operation, rawData: raw.rawData,
                            tweetIds: TwitterDataMapper.tweetIds(from: raw.nodes))
    }

    func likes(userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().likes(userId: userId, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func likes(accountId: String, userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let page = try await likesPage(accountId: accountId, identity: nil,
                                       userId: userId, cursor: cursor)
        return (page.posts, page.cursor)
    }

    func likesPage(accountId: String, identity: TimelineIdentity?,
                   userId: String, cursor: String? = nil) async throws -> TimelineFetchPage {
        let raw = try await requireClient(accountId: accountId).likesRaw(userId: userId, cursor: cursor)
        let posts = TwitterDataMapper.posts(from: raw.nodes)
        return timelinePage(posts: posts, cursor: raw.cursor,
                            accountId: accountId, identity: identity,
                            operation: raw.operation, rawData: raw.rawData,
                            tweetIds: TwitterDataMapper.tweetIds(from: raw.nodes))
    }

    func bookmarks(cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().bookmarks(cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func bookmarks(accountId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let page = try await bookmarksPage(accountId: accountId, identity: nil, cursor: cursor)
        return (page.posts, page.cursor)
    }

    func bookmarksPage(accountId: String, identity: TimelineIdentity?,
                       cursor: String? = nil) async throws -> TimelineFetchPage {
        let raw = try await requireClient(accountId: accountId).bookmarksRaw(cursor: cursor)
        let posts = TwitterDataMapper.posts(from: raw.nodes)
        return timelinePage(posts: posts, cursor: raw.cursor,
                            accountId: accountId, identity: identity,
                            operation: raw.operation, rawData: raw.rawData,
                            tweetIds: TwitterDataMapper.tweetIds(from: raw.nodes))
    }

    func bookmarkFolders() async throws -> [BookmarkFolder] {
        let (folders, _) = try await requireClient().bookmarkFolders()
        return folders.map { BookmarkFolder(id: $0.id, name: $0.name, colorToken: "") }
    }

    func bookmarkFolderTimeline(folderId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().bookmarkFolderTimeline(folderId: folderId, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func search(query: String, product: String = "Top", cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().searchTimeline(query: query, product: product, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func search(accountId: String, query: String, product: String = "Top", cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let page = try await searchPage(accountId: accountId, identity: nil,
                                        query: query, product: product, cursor: cursor)
        return (page.posts, page.cursor)
    }

    func searchPage(accountId: String, identity: TimelineIdentity?,
                    query: String, product: String = "Top", cursor: String? = nil) async throws -> TimelineFetchPage {
        let raw = try await requireClient(accountId: accountId)
            .searchTimelineRaw(query: query, product: product, cursor: cursor)
        let posts = TwitterDataMapper.posts(from: raw.nodes)
        return timelinePage(posts: posts, cursor: raw.cursor,
                            accountId: accountId, identity: identity,
                            operation: raw.operation, rawData: raw.rawData,
                            tweetIds: TwitterDataMapper.tweetIds(from: raw.nodes))
    }

    private func timelinePage(posts: [Post], cursor: String?,
                              accountId: String, identity: TimelineIdentity?,
                              operation: String, rawData: Data,
                              tweetIds: [String], newAuthors: [Person] = [],
                              topCursor: String? = nil) -> TimelineFetchPage {
        let capture = identity.map {
            RawGraphQLCapture(accountId: accountId,
                              identity: $0,
                              operation: operation,
                              fetchedAt: Date(),
                              rawData: rawData,
                              tweetIds: tweetIds)
        }
        return TimelineFetchPage(posts: posts, cursor: cursor, rawCapture: capture,
                                 newAuthors: newAuthors, topCursor: topCursor)
    }

    func user(screenName: String) async throws -> Person {
        TwitterDataMapper.person(from: try await requireClient().userByScreenName(screenName))
    }

    /// Resolve a profile: the person (with rest id) plus bio / counts / joined metadata.
    func profile(screenName: String) async throws -> (person: Person, profile: Profile) {
        let node = try await requireClient().userByScreenName(screenName)
        return (TwitterDataMapper.person(from: node), TwitterDataMapper.profile(from: node))
    }

    func fetchNotifications(tab: String = "all", cursor: String? = nil) async throws -> (items: [NotifItem], cursor: String?) {
        let (top, next) = try await requireClient().fetchNotifications(tab: tab, cursor: cursor)
        return (TwitterDataMapper.notifications(from: top), next)
    }

    func fetchNotifications(accountId: String, tab: String = "all", cursor: String? = nil) async throws -> (items: [NotifItem], cursor: String?) {
        let (top, next) = try await requireClient(accountId: accountId).fetchNotifications(tab: tab, cursor: cursor)
        return (TwitterDataMapper.notifications(from: top), next)
    }

    func badgeNotificationCount() async throws -> Int {
        guard let credentials else { throw TwitterAPIError.authExpired }
        return try await badgeNotificationCount(accountId: Self.accountId(for: credentials.userId))
    }

    func badgeNotificationCount(accountId: String) async throws -> Int {
        try await badgeCountRequests.run(key: accountId) { [self] in
            Self.notificationBadgeCount(from: try await requireClient(accountId: accountId).badgeCount())
        }
    }

    // MARK: - Writes

    func like(_ id: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.favorite(id: id) } else { try await c.unfavorite(id: id) }
    }

    func repost(_ id: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.retweet(id: id) } else { try await c.unretweet(id: id) }
    }

    func bookmark(_ id: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.bookmark(id: id) } else { try await c.unbookmark(id: id) }
    }

    @discardableResult
    func createBookmarkFolder(name: String) async throws -> String? {
        try await requireClient().createBookmarkFolder(name: name)
    }

    func editBookmarkFolder(id: String, name: String) async throws {
        try await requireClient().editBookmarkFolder(id: id, name: name)
    }

    func deleteBookmarkFolder(id: String) async throws {
        try await requireClient().deleteBookmarkFolder(id: id)
    }

    func bookmarkTweetToFolder(tweetId: String, folderId: String) async throws {
        try await requireClient().bookmarkTweetToFolder(tweetId: tweetId, folderId: folderId)
    }

    func removeTweetFromBookmarkFolder(tweetId: String, folderId: String) async throws {
        try await requireClient().removeTweetFromBookmarkFolder(tweetId: tweetId, folderId: folderId)
    }

    @discardableResult
    func postTweet(text: String, media: [PickedMedia] = [],
                   replyTo: String? = nil, quote: String? = nil) async throws -> Post? {
        let client = try requireClient()
        var mediaIds: [String] = []
        for m in media {
            let id = try await client.uploadMedia(data: m.data, mimeType: m.mimeType,
                                                  kind: m.kind, durationMs: await Self.durationMs(m))
            try? await client.setMediaMetadata(mediaId: id, alt: m.alt, aiGenerated: false)
            mediaIds.append(id)
        }
        let node = try await client.createTweet(text: text, replyToId: replyTo,
                                                quoteId: quote, mediaIds: mediaIds)
        return node.flatMap { TwitterDataMapper.post(from: $0) }
    }

    /// Video duration in whole milliseconds (from the picked file), needed by media INIT.
    private static func durationMs(_ m: PickedMedia) async -> Int? {
        guard m.kind == .video, let url = m.fileURL else { return nil }
        guard let dur = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(dur)
        return seconds.isFinite && seconds > 0 ? Int(seconds * 1000) : nil
    }

    func deleteTweet(id: String) async throws {
        try await requireClient().deleteTweet(id: id)
    }

    func follow(_ userId: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.followUser(userId: userId) } else { try await c.unfollowUser(userId: userId) }
    }

    func mute(_ userId: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.muteUser(userId: userId) } else { try await c.unmuteUser(userId: userId) }
    }

    func block(_ userId: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.blockUser(userId: userId) } else { try await c.unblockUser(userId: userId) }
    }

    func muteConversation(conversationId: String, on: Bool) async throws {
        let c = try requireClient()
        if on { try await c.muteConversation(conversationId: conversationId) } else { try await c.unmuteConversation(conversationId: conversationId) }
    }

    func logout(accountId: String) {
        Task { [badgeCountRequests] in await badgeCountRequests.cancel(key: accountId) }
        TwitterCredentialStore.clear(accountId: accountId)
        credentialMap[accountId] = nil
        clients[accountId] = nil
        accountOrder.removeAll { $0 == accountId }
        if account?.id == accountId {
            if let first = accountOrder.first {
                activate(accountId: first)
            } else {
                credentials = nil
                client = nil
            }
        }
    }

    func logout() {
        if let aid = account?.id {
            logout(accountId: aid)
        } else {
            TwitterCredentialStore.clear()
            Task { [badgeCountRequests] in await badgeCountRequests.cancelAll() }
            credentialMap.removeAll()
            clients.removeAll()
            accountOrder.removeAll()
            credentials = nil
            client = nil
        }
    }

    private static func notificationBadgeCount(from raw: Any) -> Int {
        firstNotificationBadgeCount(in: raw) ?? 0
    }

    private static let preferredNotificationBadgeKeys = [
        "ntab_unread_count",
        "ntab_count",
        "notification_unread_count",
        "notifications_unread_count",
        "unread_notification_count",
        "unread_notifications_count",
        "notification_count",
        "notifications_count"
    ]

    private static let nestedNotificationBadgeKeys = [
        "count",
        "unread_count",
        "badge_count",
        "badge"
    ]

    private static func firstNotificationBadgeCount(in value: Any, notificationContext: Bool = false) -> Int? {
        if let dict = value as? [String: Any] {
            for key in preferredNotificationBadgeKeys {
                if let n = intValue(dict[key]) { return max(0, n) }
            }
            if notificationContext {
                for key in nestedNotificationBadgeKeys {
                    if let n = intValue(dict[key]) { return max(0, n) }
                }
            }
            for (key, child) in dict {
                let lower = key.lowercased()
                if lower.contains("dm") || lower.contains("home") || lower.contains("timeline") {
                    continue
                }
                let nextContext = notificationContext || lower.contains("ntab") || lower.contains("notification")
                if nextContext, let n = intValue(child) { return max(0, n) }
                if let n = firstNotificationBadgeCount(in: child, notificationContext: nextContext) {
                    return n
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let n = firstNotificationBadgeCount(in: child, notificationContext: notificationContext) {
                    return n
                }
            }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let n as Int:
            return n
        case let n as NSNumber:
            return n.intValue
        case let s as String:
            return Int(s)
        default:
            return nil
        }
    }
}

// MARK: - Rettiwt-ported high-level surface
//
// Exposes the full Rettiwt-API operation set through `TwitterService`, mapping to
// Perch view models (`Post` / `Person`) where they exist, and to the lightweight
// `Twitter*` DTOs for entities Perch did not previously model.
extension TwitterService {

    // ── Tweets ──

    func tweetDetailsSingle(id: String) async throws -> Post? {
        (try await requireClient().tweetDetailsSingle(id: id)).flatMap { TwitterDataMapper.post(from: $0) }
    }

    func bulkTweets(ids: [String]) async throws -> [Post] {
        TwitterDataMapper.posts(from: try await requireClient().bulkTweetDetails(ids: ids))
    }

    func tweetHistory(id: String) async throws -> [Post] {
        TwitterDataMapper.posts(from: try await requireClient().tweetHistory(id: id))
    }

    func likers(tweetId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().likers(tweetId: tweetId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func retweeters(tweetId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().retweeters(tweetId: tweetId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    @discardableResult
    func scheduleTweet(text: String, mediaIds: [String] = [], executeAt: Date) async throws -> String? {
        try await requireClient().scheduleTweet(text: text, mediaIds: mediaIds, executeAt: executeAt)
    }

    func unscheduleTweet(id: String) async throws {
        try await requireClient().unscheduleTweet(id: id)
    }

    @discardableResult
    func postNote(text: String, media: [PickedMedia] = []) async throws -> Post? {
        let client = try requireClient()
        var mediaIds: [String] = []
        for m in media {
            let id = try await client.uploadMedia(data: m.data, mimeType: m.mimeType,
                                                  kind: m.kind, durationMs: nil)
            try? await client.setMediaMetadata(mediaId: id, alt: m.alt, aiGenerated: false)
            mediaIds.append(id)
        }
        let node = try await client.createNoteTweet(text: text, mediaIds: mediaIds)
        return node.flatMap { TwitterDataMapper.post(from: $0) }
    }

    // ── Users ──

    func profileSpotlights(screenName: String) async throws -> Any {
        try await requireClient().profileSpotlights(screenName: screenName)
    }

    func about(username: String) async throws -> TwitterUserAbout? {
        TwitterDataMapper.userAbout(from: try await requireClient().aboutByUsername(username))
    }

    func affiliates(userId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().affiliates(userId: userId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func analytics(from: Date, to: Date, granularity: String = "Day",
                   metrics: [String], showVerifiedFollowers: Bool = false) async throws -> TwitterAnalytics {
        let json = try await requireClient().analytics(from: from, to: to, granularity: granularity,
                                                       metrics: metrics, showVerifiedFollowers: showVerifiedFollowers)
        return TwitterDataMapper.analytics(fromJSON: json)
    }

    func usersByIds(_ ids: [String]) async throws -> [Person] {
        TwitterDataMapper.people(from: try await requireClient().bulkUserDetails(ids: ids))
    }

    func followers(userId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().followers(userId: userId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func followersYouKnow(userId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().followersYouKnow(userId: userId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func following(userId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().following(userId: userId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func highlights(userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().highlights(userId: userId, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func userMedia(userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().userMedia(userId: userId, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func userReplies(userId: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().userTweetsAndReplies(userId: userId, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func subscriptions(userId: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().subscriptions(userId: userId, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func lists(cursor: String? = nil) async throws -> (lists: [TwitterList], cursor: String?) {
        let (raw, next) = try await requireClient().userLists(cursor: cursor)
        return (raw.compactMap { TwitterDataMapper.list(from: $0) }, next)
    }

    func searchUsers(query: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().searchUsers(query: query, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func notificationsTimeline(cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().notificationsTimeline(cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func scheduledTweetsList() async throws -> [TwitterScheduledTweet] {
        TwitterDataMapper.scheduledTweets(from: try await requireClient().scheduledTweets())
    }

    func removeFollower(userId: String) async throws {
        try await requireClient().removeFollower(userId: userId)
    }

    func updateProfile(name: String? = nil, url: String? = nil,
                       location: String? = nil, description: String? = nil) async throws {
        try await requireClient().updateProfile(name: name, url: url, location: location, description: description)
    }

    func updateProfileImage(base64: String) async throws {
        try await requireClient().updateProfileImage(base64: base64)
    }

    func updateProfileBanner(base64: String) async throws {
        try await requireClient().updateProfileBanner(base64: base64)
    }

    func changeUsername(_ newUsername: String) async throws {
        try await requireClient().changeUsername(newUsername)
    }

    func changePassword(current: String, new: String) async throws {
        try await requireClient().changePassword(current: current, new: new)
    }

    // ── Lists ──

    func listDetails(id: String) async throws -> TwitterList? {
        TwitterDataMapper.list(from: try await requireClient().listDetails(id: id))
    }

    func listOwnerships(userId: String, targetUserId: String? = nil,
                        cursor: String? = nil) async throws -> (lists: [TwitterList], cursor: String?) {
        let (raw, next) = try await requireClient().listOwnerships(userId: userId, targetUserId: targetUserId, cursor: cursor)
        return (raw.compactMap { TwitterDataMapper.list(from: $0) }, next)
    }

    func listMembers(id: String, cursor: String? = nil) async throws -> (people: [Person], cursor: String?) {
        let (nodes, next) = try await requireClient().listMembers(id: id, cursor: cursor)
        return (TwitterDataMapper.people(from: nodes), next)
    }

    func listTweets(id: String, cursor: String? = nil) async throws -> (posts: [Post], cursor: String?) {
        let (nodes, next) = try await requireClient().listTweets(id: id, cursor: cursor)
        return (TwitterDataMapper.posts(from: nodes), next)
    }

    func listTweetsPage(accountId: String, identity: TimelineIdentity?,
                        id: String, cursor: String? = nil) async throws -> TimelineFetchPage {
        let raw = try await requireClient(accountId: accountId).listTweetsRaw(id: id, cursor: cursor)
        let posts = TwitterDataMapper.posts(from: raw.nodes)
        return timelinePage(posts: posts, cursor: raw.cursor,
                            accountId: accountId, identity: identity,
                            operation: raw.operation, rawData: raw.rawData,
                            tweetIds: TwitterDataMapper.tweetIds(from: raw.nodes))
    }

    func listAddMember(listId: String, userId: String) async throws {
        try await requireClient().listAddMember(listId: listId, userId: userId)
    }

    func listRemoveMember(listId: String, userId: String) async throws {
        try await requireClient().listRemoveMember(listId: listId, userId: userId)
    }

    func createList(name: String, description: String = "", isPrivate: Bool = false) async throws -> TwitterList? {
        TwitterDataMapper.list(from: try await requireClient().createList(name: name, description: description, isPrivate: isPrivate))
    }

    func updateList(id: String, name: String, description: String = "",
                    isPrivate: Bool = false) async throws -> TwitterList? {
        TwitterDataMapper.list(from: try await requireClient().updateList(id: id, name: name,
                                                                          description: description,
                                                                          isPrivate: isPrivate))
    }

    func deleteList(id: String) async throws {
        try await requireClient().deleteList(id: id)
    }

    func editListBanner(id: String, mediaId: String) async throws -> TwitterList? {
        TwitterDataMapper.list(from: try await requireClient().editListBanner(id: id, mediaId: mediaId))
    }

    // ── Spaces ──

    func space(id: String) async throws -> TwitterSpace? {
        TwitterDataMapper.space(from: try await requireClient().spaceDetails(id: id))
    }

    // ── Direct messages ──

    func dmInbox() async throws -> DMInbox {
        TwitterDataMapper.dmInbox(fromJSON: try await requireClient().dmInboxInitial())
    }

    func dmInboxTimeline(maxId: String? = nil) async throws -> DMInbox {
        TwitterDataMapper.dmInbox(fromJSON: try await requireClient().dmInboxTimeline(maxId: maxId))
    }

    func dmConversation(conversationId: String, maxId: String? = nil) async throws -> DMConversation? {
        let json = try await requireClient().dmConversation(conversationId: conversationId, maxId: maxId)
        return TwitterDataMapper.dmConversation(fromJSON: json)
    }

    func dmDeleteConversation(conversationId: String) async throws {
        try await requireClient().dmDeleteConversation(conversationId: conversationId)
    }

    func dmInboxTimelineUntrusted(maxId: String? = nil) async throws -> Any {
        try await requireClient().dmInboxTimelineUntrusted(maxId: maxId)
    }

    func dmPermissions(recipientIds: [String]) async throws -> Any {
        try await requireClient().dmPermissions(recipientIds: recipientIds)
    }

    func dmUserUpdates() async throws -> Any {
        try await requireClient().dmUserUpdates()
    }

    func dmAcceptConversation(conversationId: String) async throws {
        try await requireClient().dmAcceptConversation(conversationId: conversationId)
    }

    func dmDisableNotifications(conversationId: String, duration: Int = 0) async throws {
        try await requireClient().dmDisableNotifications(conversationId: conversationId, duration: duration)
    }

    func dmEnableNotifications(conversationId: String) async throws {
        try await requireClient().dmEnableNotifications(conversationId: conversationId)
    }

    func dmMarkRead(conversationId: String, lastReadEventId: String) async throws {
        try await requireClient().dmMarkRead(conversationId: conversationId, lastReadEventId: lastReadEventId)
    }

    func dmUpdateAvatar(conversationId: String, avatarId: String) async throws {
        try await requireClient().dmUpdateAvatar(conversationId: conversationId, avatarId: avatarId)
    }

    func dmUpdateMentionNotificationsSetting(conversationId: String, disabled: Bool = true) async throws {
        try await requireClient().dmUpdateMentionNotificationsSetting(conversationId: conversationId, disabled: disabled)
    }

    func dmUpdateName(conversationId: String, name: String) async throws {
        try await requireClient().dmUpdateName(conversationId: conversationId, name: name)
    }

    func dmUpdateLastSeenEventId(_ eventId: String, trustedEventId: String? = nil) async throws {
        try await requireClient().dmUpdateLastSeenEventId(eventId, trustedEventId: trustedEventId)
    }

    func dmAddWelcomeMessageToConversation(conversationId: String,
                                           requestId: String = UUID().uuidString) async throws -> Any {
        try await requireClient().dmAddWelcomeMessageToConversation(conversationId: conversationId,
                                                                    requestId: requestId)
    }

    func dmSendMessage(conversationId: String, text: String,
                       requestId: String = UUID().uuidString,
                       mediaId: String? = nil, replyToDMId: String? = nil) async throws -> Any {
        try await requireClient().dmSendMessage(conversationId: conversationId, text: text,
                                                requestId: requestId, mediaId: mediaId,
                                                replyToDMId: replyToDMId)
    }

    func dmConversationSearchGroups(variables: [String: Any]) async throws -> Any {
        try await requireClient().dmConversationSearchGroups(variables: variables)
    }

    func dmConversationSearchPeople(variables: [String: Any]) async throws -> Any {
        try await requireClient().dmConversationSearchPeople(variables: variables)
    }

    func dmMessageSearch(variables: [String: Any], features: [String: Bool]? = nil) async throws -> Any {
        try await requireClient().dmMessageSearch(variables: variables, features: features)
    }

    func dmPinnedInbox(label: String = "Pinned") async throws -> Any {
        try await requireClient().dmPinnedInbox(label: label)
    }

    func dmAllSearchSlice(variables: [String: Any], features: [String: Bool]? = nil) async throws -> Any {
        try await requireClient().dmAllSearchSlice(variables: variables, features: features)
    }

    func dmAddParticipants(conversationId: String, participantIds: [String]) async throws -> Any {
        try await requireClient().dmAddParticipants(conversationId: conversationId, participantIds: participantIds)
    }

    func dmBlockUser(userId: String) async throws -> Any {
        try await requireClient().dmBlockUser(userId: userId)
    }

    func dmUnblockUser(userId: String) async throws -> Any {
        try await requireClient().dmUnblockUser(userId: userId)
    }

    func dmDeleteMessage(messageId: String, requestId: String = UUID().uuidString) async throws -> Any {
        try await requireClient().dmDeleteMessage(messageId: messageId, requestId: requestId)
    }

    func dmPinConversation(conversationId: String, label: String = "Pinned") async throws -> Any {
        try await requireClient().dmPinConversation(conversationId: conversationId, label: label)
    }

    func dmUnpinConversation(conversationId: String, label: String = "Pinned") async throws -> Any {
        try await requireClient().dmUnpinConversation(conversationId: conversationId, label: label)
    }

    func dmAddReaction(conversationId: String, messageId: String,
                       emojiReactions: [String], reactionTypes: [String]) async throws -> Any {
        try await requireClient().dmAddReaction(conversationId: conversationId, messageId: messageId,
                                                emojiReactions: emojiReactions,
                                                reactionTypes: reactionTypes)
    }

    func dmRemoveReaction(conversationId: String, messageId: String,
                          emojiReactions: [String], reactionTypes: [String]) async throws -> Any {
        try await requireClient().dmRemoveReaction(conversationId: conversationId, messageId: messageId,
                                                   emojiReactions: emojiReactions,
                                                   reactionTypes: reactionTypes)
    }

    // ── Misc legacy REST endpoints from Flare xqt ──

    func guestActivate() async throws -> Any {
        try await requireClient().guestActivate()
    }

    func other() async throws -> Any {
        try await requireClient().other()
    }

    func friendsFollowingList(userId: String, cursor: Int = -1, count: Int = 3) async throws -> Any {
        try await requireClient().friendsFollowingList(userId: userId, cursor: cursor, count: count)
    }

    func searchTypeahead(query: String, resultType: String = "events,users,topics") async throws -> Any {
        try await requireClient().searchTypeahead(query: query, resultType: resultType)
    }

    func userRecommendations(userId: String, limit: Int = 3,
                             displayLocation: String = "profile_accounts_sidebar") async throws -> Any {
        try await requireClient().userRecommendations(userId: userId, limit: limit,
                                                      displayLocation: displayLocation)
    }

    func listMemberships(userId: String, cursor: Int = -1,
                         count: Int = 1000, filterToOwnedLists: Bool = true) async throws -> Any {
        try await requireClient().listMemberships(userId: userId, cursor: cursor,
                                                  count: count, filterToOwnedLists: filterToOwnedLists)
    }

    func liveVideoStreamStatus(mediaKey: String) async throws -> Any {
        try await requireClient().liveVideoStreamStatus(mediaKey: mediaKey)
    }

    func fleets(onlySpaces: Bool = true) async throws -> Any {
        try await requireClient().fleets(onlySpaces: onlySpaces)
    }

    func searchAdaptive(query: String, count: Int = 20,
                        querySource: String = "trend_click") async throws -> Any {
        try await requireClient().searchAdaptive(query: query, count: count, querySource: querySource)
    }

    func notificationMentions(count: Int = 20, cursor: String? = nil) async throws -> Any {
        try await requireClient().notificationMentions(count: count, cursor: cursor)
    }

    func guide(tabCategory: String = "objective_trends", count: Int = 20) async throws -> Any {
        try await requireClient().guide(tabCategory: tabCategory, count: count)
    }

    func notificationDeviceFollow(count: Int = 20, cursor: String? = nil) async throws -> Any {
        try await requireClient().notificationDeviceFollow(count: count, cursor: cursor)
    }

    func badgeCount() async throws -> Any {
        try await requireClient().badgeCount()
    }

    func markNotificationsAllSeen(cursor: String) async throws {
        try await requireClient().markNotificationsAllSeen(cursor: cursor)
    }
}
