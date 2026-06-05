import Foundation
import CryptoKit

enum TwitterAPIError: Error, LocalizedError {
    case http(Int, String)
    case authExpired
    case rateLimited
    case decode(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .authExpired: return "Session expired"
        case .rateLimited: return "Rate limited, try again later"
        case .decode(let m): return "Decode error: \(m)"
        case .noData: return "No data returned"
        }
    }
}

struct CurrentUser {
    let id: String
    let username: String
    let name: String
    var avatarURL: String? = nil
}

struct TwitterTimelineNodePage {
    let nodes: [TweetResultNode]
    let cursor: String?
    let operation: String
    let rawData: Data
}

struct TwitterTimelineGroupPage {
    let groups: [[TweetResultNode]]
    let cursor: String?
    let operation: String
    let rawData: Data
    var alertUsers: [UserResultNode] = []   // TimelineShowAlert "new posts" authors (home only)
    var topCursor: String? = nil            // cursor for fetch-newer (pull-to-refresh) requests
}

/// Cookie-authed client for X's undocumented GraphQL/REST endpoints, modeled on Flare's
/// `xqt` client. Reads go through `graphqlGET` (variables/features as query params), writes
/// through `graphqlPOST` (JSON body). Every GraphQL call is signed with an
/// `x-client-transaction-id` header via `TwitterTransactionID`. Operation query IDs rotate
/// with X's client bundles, so `TwitterQueryIDs` refreshes them at runtime.
final class TwitterAPIClient {
    private let authToken: String
    private let ct0: String
    private let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36"
    private let graphqlBase = "https://x.com/i/api/graphql"

    init(authToken: String, ct0: String) {
        self.authToken = authToken
        self.ct0 = ct0
    }

    private func baseHeaders() -> [String: String] {
        [
            "authorization": "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA",
            "content-type": "application/json",
            "x-csrf-token": ct0,
            "x-twitter-auth-type": "OAuth2Session",
            "x-twitter-active-user": "yes",
            "x-twitter-client-language": "en",
            "cookie": "auth_token=\(authToken); ct0=\(ct0)",
            "user-agent": userAgent,
            "origin": "https://x.com",
            "referer": "https://x.com/",
            "sec-ch-ua": "\"Chromium\";v=\"116\", \"Not)A;Brand\";v=\"24\", \"Google Chrome\";v=\"116\"",
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": "\"Windows\"",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
        ]
    }

    // MARK: - Feature flags

    // Per-operation `features` / `fieldToggles` now live in `TwitterRequestConfigs`
    // (transcribed verbatim from Rettiwt-API). This serializes the toggles for a GET op.
    private func fieldTogglesJSON(for op: String) -> String? {
        TwitterRequestConfigs.fieldToggles(op).map { jsonString($0) }
    }

    // MARK: - Reads

    func fetchHomeTimeline(count: Int = 30, cursor: String? = nil,
                           feed: HomeFeed = .following) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await fetchHomeTimelineRaw(count: count, cursor: cursor, feed: feed)
        return (page.nodes, page.cursor)
    }

    /// Home timeline with conversation threads kept grouped (for thread lines).
    func fetchHomeTimelineGroups(count: Int = 30, cursor: String? = nil,
                                 feed: HomeFeed = .following) async throws -> (groups: [[TweetResultNode]], cursor: String?) {
        let page = try await fetchHomeTimelineGroupsRaw(count: count, cursor: cursor, feed: feed)
        return (page.groups, page.cursor)
    }

    func fetchHomeTimelineRaw(count: Int = 30, cursor: String? = nil,
                              feed: HomeFeed = .following) async throws -> TwitterTimelineNodePage {
        let data = try await homeTimelineData(count: count, cursor: cursor, feed: feed)
        return try timelinePage(from: data, operation: Self.homeOperation(for: feed))
    }

    func fetchHomeTimelineGroupsRaw(count: Int = 30, cursor: String? = nil,
                                    feed: HomeFeed = .following,
                                    seenTweetIds: [String] = [], fetchNewer: Bool = false) async throws -> TwitterTimelineGroupPage {
        let data = try await homeTimelineData(count: count, cursor: cursor, feed: feed,
                                              seenTweetIds: seenTweetIds, fetchNewer: fetchNewer)
        return try timelineGroupPage(from: data, operation: Self.homeOperation(for: feed))
    }

    /// Rettiwt models the home feeds as POST ops: `.following` → `HomeLatestTimeline`
    /// (followed), `.forYou` → `HomeTimeline` (recommended).
    private func homeTimelineData(count: Int, cursor: String?, feed: HomeFeed,
                                  seenTweetIds: [String] = [], fetchNewer: Bool = false) async throws -> Data {
        let op = Self.homeOperation(for: feed)
        var variables: [String: Any] = [
            "count": count,
            "includePromotedContent": false,
            "seenTweetIds": seenTweetIds,
        ]
        // X surfaces the `TimelineShowAlert` ("N new posts") instruction on a
        // fetch-newer (top-cursor) pull, which the web client sends *without* a
        // requestContext; the cold/launch load sends `requestContext: "launch"`.
        if !fetchNewer { variables["requestContext"] = "launch" }
        switch feed {
        case .following: variables["enableRanking"] = false
        case .forYou:    variables["withCommunity"] = false
        }
        if let cursor { variables["cursor"] = cursor }
        return try await graphqlPOST(op: op, variables: variables, features: TwitterRequestConfigs.features(op))
    }

    private static func homeOperation(for feed: HomeFeed) -> String {
        switch feed {
        case .forYou: return "HomeTimeline"
        case .following: return "HomeLatestTimeline"
        }
    }

    func tweetDetail(id: String, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        var variables: [String: Any] = [
            "focalTweetId": id,
            "referrer": "tweet",
            "with_rux_injections": false,
            "rankingMode": "Relevance",
            "includePromotedContent": true,
            "withCommunity": true,
            "withQuickPromoteEligibilityTweetFields": true,
            "withBirdwatchNotes": true,
            "withVoice": true,
        ]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "TweetDetail", variables: variables)
        return try timeline(from: data)
    }

    func userTweets(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await userTweetsRaw(userId: userId, count: count, cursor: cursor)
        return (page.nodes, page.cursor)
    }

    func userTweetsRaw(userId: String, count: Int = 40, cursor: String? = nil) async throws -> TwitterTimelineNodePage {
        var variables: [String: Any] = [
            "userId": userId, "count": count, "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": false, "withVoice": false, "withV2Timeline": false,
        ]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "UserTweets", variables: variables)
        return try timelinePage(from: data, operation: "UserTweets")
    }

    func likes(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await likesRaw(userId: userId, count: count, cursor: cursor)
        return (page.nodes, page.cursor)
    }

    func likesRaw(userId: String, count: Int = 40, cursor: String? = nil) async throws -> TwitterTimelineNodePage {
        var variables: [String: Any] = [
            "userId": userId, "count": count, "includePromotedContent": false,
            "withClientEventToken": false, "withBirdwatchNotes": false, "withVoice": false, "withV2Timeline": false,
        ]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "Likes", variables: variables)
        return try timelinePage(from: data, operation: "Likes")
    }

    func bookmarks(count: Int = 20, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await bookmarksRaw(count: count, cursor: cursor)
        return (page.nodes, page.cursor)
    }

    func bookmarksRaw(count: Int = 20, cursor: String? = nil) async throws -> TwitterTimelineNodePage {
        var variables: [String: Any] = ["count": count, "includePromotedContent": false]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "Bookmarks", variables: variables)
        return try timelinePage(from: data, operation: "Bookmarks")
    }

    /// All bookmark folders for the current user (BookmarkFoldersSlice → viewer.user_results).
    func bookmarkFolders(cursor: String? = nil) async throws -> (folders: [(id: String, name: String)], cursor: String?) {
        var variables: [String: Any] = [:]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "BookmarkFoldersSlice", variables: variables)
        let slice = try decodeResponse(data).data?.viewer?.user_results?.result?.bookmark_collections_slice
        let folders: [(id: String, name: String)] = (slice?.items ?? []).compactMap { item in
            guard let id = item.id else { return nil }
            return (id, item.name ?? "")
        }
        return (folders, slice?.slice_info?.next_cursor)
    }

    /// Tweets inside one bookmark folder (BookmarkFolderTimeline).
    func bookmarkFolderTimeline(folderId: String, count: Int = 50, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await bookmarkFolderTimelineRaw(folderId: folderId, count: count, cursor: cursor)
        return (page.nodes, page.cursor)
    }

    func bookmarkFolderTimelineRaw(folderId: String, count: Int = 50, cursor: String? = nil) async throws -> TwitterTimelineNodePage {
        var variables: [String: Any] = ["bookmark_collection_id": folderId, "count": count, "includePromotedContent": true]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "BookmarkFolderTimeline", variables: variables)
        return try timelinePage(from: data, operation: "BookmarkFolderTimeline")
    }

    func searchTimeline(query: String, product: String = "Top", count: Int = 20, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await searchTimelineRaw(query: query, product: product, count: count, cursor: cursor)
        return (page.nodes, page.cursor)
    }

    func searchTimelineRaw(query: String, product: String = "Top", count: Int = 20, cursor: String? = nil) async throws -> TwitterTimelineNodePage {
        var variables: [String: Any] = [
            "rawQuery": query, "count": count, "querySource": "typed_query", "product": product,
            "withGrokTranslatedBio": false,
        ]
        if let cursor { variables["cursor"] = cursor }
        let data = try await gqlGET(op: "SearchTimeline", variables: variables)
        return try timelinePage(from: data, operation: "SearchTimeline")
    }

    /// Notification center via the legacy v2 REST endpoint (X has no GraphQL op for it).
    /// `tab` selects the server feed — `all` / `verified` / `mentions` each have their
    /// own endpoint; all three share this payload shape. Returns the raw
    /// `globalObjects + timeline` payload plus the bottom paging cursor.
    func fetchNotifications(tab: String = "all", count: Int = 40, cursor: String? = nil) async throws -> (top: NotifTopLevel, cursor: String?) {
        var params: [String: String] = [
            "include_profile_interstitial_type": "1",
            "include_blocking": "1",
            "include_blocked_by": "1",
            "include_followed_by": "1",
            "include_want_retweets": "1",
            "include_mute_edge": "1",
            "include_can_dm": "1",
            "include_can_media_tag": "1",
            "include_ext_is_blue_verified": "1",
            "include_ext_verified_type": "1",
            "include_ext_profile_image_shape": "1",
            "skip_status": "1",
            "cards_platform": "Web-12",
            "include_cards": "1",
            "include_ext_alt_text": "true",
            "include_ext_limited_action_results": "true",
            "include_quote_count": "true",
            "include_reply_count": "1",
            "tweet_mode": "extended",
            "include_ext_views": "true",
            "include_entities": "true",
            "include_user_entities": "true",
            "include_ext_media_color": "true",
            "include_ext_media_availability": "true",
            "include_ext_sensitive_media_warning": "true",
            "include_ext_trusted_friends_metadata": "true",
            "send_error_codes": "true",
            "simple_quoted_tweet": "true",
            "count": "\(count)",
            "requestContext": "launch",
            "ext": "mediaStats,highlightedLabel,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl,article",
        ]
        if let cursor { params["cursor"] = cursor }
        let endpoint: String
        switch tab {
        case "verified": endpoint = "verified"
        case "mention", "mentions": endpoint = "mentions"
        default: endpoint = "all"
        }
        let query = params.map { "\($0.key)=\(enc($0.value))" }.joined(separator: "&")
        guard let url = URL(string: "https://x.com/i/api/2/notifications/\(endpoint).json?\(query)") else {
            throw TwitterAPIError.noData
        }
        let data = try await send(await makeRequest("GET", url))
        let top: NotifTopLevel
        do {
            top = try JSONDecoder().decode(NotifTopLevel.self, from: data)
        } catch {
            throw TwitterAPIError.decode(error.localizedDescription)
        }
        return (top, Self.notifBottomCursor(top))
    }

    /// Walk the timeline instructions for the `Bottom` paging cursor.
    private static func notifBottomCursor(_ top: NotifTopLevel) -> String? {
        for instr in top.timeline?.instructions ?? [] {
            for entry in instr.addEntries?.entries ?? [] {
                if let c = entry.content?.operation?.cursor, c.cursorType == "Bottom", let v = c.value {
                    return v
                }
            }
        }
        return nil
    }

    func userByScreenName(_ name: String) async throws -> UserResultNode? {
        let data = try await gqlGET(op: "UserByScreenName",
                                    variables: ["screen_name": name, "withGrokTranslatedBio": false])
        return try decodeResponse(data).data?.user?.result
    }

    func userByRestId(_ id: String) async throws -> UserResultNode? {
        let data = try await gqlGET(op: "UserByRestId",
                                    variables: ["userId": id, "withSafetyModeUserFields": true])
        return try decodeResponse(data).data?.user?.result
    }

    // MARK: - Writes

    func createTweet(text: String, replyToId: String? = nil, quoteId: String? = nil,
                     mediaIds: [String] = []) async throws -> TweetResultNode? {
        let entities = mediaIds.map { ["media_id": $0, "tagged_users": []] as [String: Any] }
        var variables: [String: Any] = [
            "tweet_text": text,
            "dark_request": false,
            "media": ["media_entities": entities, "possibly_sensitive": false],
            "semantic_annotation_ids": [],
        ]
        if let replyToId {
            variables["reply"] = ["in_reply_to_tweet_id": replyToId, "exclude_reply_user_ids": []]
        }
        if let quoteId {
            variables["attachment_url"] = "https://x.com/i/status/\(quoteId)"
        }
        let data = try await graphqlPOST(op: "CreateTweet", variables: variables,
                                         features: TwitterRequestConfigs.features("CreateTweet"))
        return try decodeResponse(data).data?.create_tweet?.tweet_results?.result
    }

    /// Long-form (X Premium) tweet via `CreateNoteTweet`.
    func createNoteTweet(text: String, mediaIds: [String] = []) async throws -> TweetResultNode? {
        let entities = mediaIds.map { ["media_id": $0, "tagged_users": []] as [String: Any] }
        let variables: [String: Any] = [
            "tweet_text": text,
            "media": ["media_entities": entities, "possibly_sensitive": false],
            "semantic_annotation_ids": [],
            "disallowed_reply_options": NSNull(),
        ]
        let data = try await graphqlPOST(op: "CreateNoteTweet", variables: variables,
                                         features: TwitterRequestConfigs.features("CreateNoteTweet"))
        return try decodeResponse(data).data?.create_tweet?.tweet_results?.result
            ?? decodeResponse(data).data?.notetweet_create?.tweet_results?.result
    }

    // MARK: - Media upload (chunked) — contract reverse-engineered from a real session HAR.
    // Host `upload.x.com` omits x-client-transaction-id / x-twitter-active-user / client-language.
    // Image: INIT → APPEND → FINALIZE(original_md5).  Video/GIF: INIT(video_duration_ms) →
    // APPENDMULTI(8 MiB chunks, per-chunk media_md5) → FINALIZE(allow_async) → poll STATUS.

    private let mediaUploadURL = "https://upload.x.com/i/media/upload.json"
    private let mediaChunkSize = 8 * 1024 * 1024

    /// Upload one media item and return its `media_id_string`.
    func uploadMedia(data: Data, mimeType: String, kind: PickedMediaKind, durationMs: Int?) async throws -> String {
        let category: String
        switch kind {
        case .image: category = "tweet_image"
        case .gif:   category = "tweet_gif"
        case .video: category = "amplify_video"
        }
        let mediaId = try await mediaInit(totalBytes: data.count, mediaType: mimeType,
                                          category: category, durationMs: durationMs)
        if kind == .image {
            try await mediaAppend(mediaId: mediaId, chunk: data, segment: 0, multi: false, chunkMD5: nil)
            _ = try await mediaFinalize(mediaId: mediaId, originalMD5: Self.md5Hex(data), allowAsync: false)
        } else {
            var segment = 0, offset = 0
            while offset < data.count {
                let end = min(offset + mediaChunkSize, data.count)
                let chunk = data.subdata(in: offset..<end)
                try await mediaAppend(mediaId: mediaId, chunk: chunk, segment: segment,
                                      multi: true, chunkMD5: Self.md5Hex(chunk))
                offset = end; segment += 1
            }
            let needsPolling = try await mediaFinalize(mediaId: mediaId, originalMD5: nil, allowAsync: true)
            if needsPolling { try await pollStatus(mediaId: mediaId) }
        }
        return mediaId
    }

    /// Set per-media metadata (download status, ALT, AI flag). X calls this for every uploaded item.
    func setMediaMetadata(mediaId: String, alt: String?, aiGenerated: Bool) async throws {
        var body: [String: Any] = ["media_id": mediaId,
                                    "allow_download_status": ["allow_download": "true"]]
        if let alt, !alt.isEmpty { body["alt_text"] = ["text": alt] }
        if aiGenerated { body["self_reported_ai_generated"] = ["self_reported_ai_generated": "true"] }
        guard let url = URL(string: "https://x.com/i/api/1.1/media/metadata/create.json") else { return }
        let req = await makeRequest("POST", url, body: try JSONSerialization.data(withJSONObject: body))
        _ = try await send(req)
    }

    private func mediaInit(totalBytes: Int, mediaType: String, category: String, durationMs: Int?) async throws -> String {
        var items = [URLQueryItem(name: "command", value: "INIT"),
                     URLQueryItem(name: "total_bytes", value: String(totalBytes)),
                     URLQueryItem(name: "media_type", value: mediaType),
                     URLQueryItem(name: "media_category", value: category)]
        if let durationMs { items.append(URLQueryItem(name: "video_duration_ms", value: String(durationMs))) }
        let data = try await send(uploadRequest("POST", items))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["media_id_string"] as? String else { throw TwitterAPIError.noData }
        return id
    }

    private func mediaAppend(mediaId: String, chunk: Data, segment: Int, multi: Bool, chunkMD5: String?) async throws {
        var items = [URLQueryItem(name: "command", value: multi ? "APPENDMULTI" : "APPEND"),
                     URLQueryItem(name: "media_id", value: mediaId)]
        if multi {
            items.append(URLQueryItem(name: "segment_indexes", value: String(segment)))
            items.append(URLQueryItem(name: "max_segment_size", value: String(mediaChunkSize)))
            if let chunkMD5 { items.append(URLQueryItem(name: "media_md5", value: chunkMD5)) }
        } else {
            items.append(URLQueryItem(name: "segment_index", value: String(segment)))
        }
        let (body, contentType) = Self.multipartMediaBody(chunk)
        _ = try await send(uploadRequest("POST", items, body: body, contentType: contentType))
    }

    /// Returns true when STATUS polling is required (video/GIF still processing).
    private func mediaFinalize(mediaId: String, originalMD5: String?, allowAsync: Bool) async throws -> Bool {
        var items = [URLQueryItem(name: "command", value: "FINALIZE"),
                     URLQueryItem(name: "media_id", value: mediaId)]
        if let originalMD5 { items.append(URLQueryItem(name: "original_md5", value: originalMD5)) }
        if allowAsync { items.append(URLQueryItem(name: "allow_async", value: "true")) }
        let data = try await send(uploadRequest("POST", items))
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let pi = json["processing_info"] as? [String: Any] {
            return (pi["state"] as? String) != "succeeded"
        }
        return false
    }

    private func pollStatus(mediaId: String) async throws {
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            let items = [URLQueryItem(name: "command", value: "STATUS"),
                         URLQueryItem(name: "media_id", value: mediaId)]
            let data = try await send(uploadRequest("GET", items))
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pi = json["processing_info"] as? [String: Any],
                  let state = pi["state"] as? String else { return }
            switch state {
            case "succeeded": return
            case "failed":
                let msg = (pi["error"] as? [String: Any])?["message"] as? String ?? "media processing failed"
                throw TwitterAPIError.http(0, msg)
            default:
                let secs = max(1, (pi["check_after_secs"] as? Int) ?? 1)
                try await Task.sleep(nanoseconds: UInt64(secs) * 1_000_000_000)
            }
        }
        throw TwitterAPIError.http(0, "media processing timed out")
    }

    /// Request builder for the upload host: reuses cookie/csrf/bearer auth but drops the
    /// transaction-id and the x-twitter-active-user/client-language headers.
    private func uploadRequest(_ method: String, _ items: [URLQueryItem], body: Data? = nil, contentType: String? = nil) -> URLRequest {
        var comp = URLComponents(string: mediaUploadURL)!
        comp.queryItems = items
        var req = URLRequest(url: comp.url!)
        req.httpMethod = method
        var h = baseHeaders()
        h.removeValue(forKey: "x-twitter-active-user")
        h.removeValue(forKey: "x-twitter-client-language")
        if let contentType { h["content-type"] = contentType } else { h.removeValue(forKey: "content-type") }
        for (k, v) in h { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        return req
    }

    private static func multipartMediaBody(_ data: Data) -> (Data, String) {
        let boundary = "----PerchBoundary\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"media\"; filename=\"blob\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return (body, "multipart/form-data; boundary=\(boundary)")
    }

    private static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func deleteTweet(id: String) async throws { try await writeOp("DeleteTweet", ["tweet_id": id, "dark_request": false]) }
    func favorite(id: String) async throws { try await writeOp("FavoriteTweet", ["tweet_id": id, "dark_request": false]) }
    func unfavorite(id: String) async throws { try await writeOp("UnfavoriteTweet", ["tweet_id": id, "dark_request": false]) }
    func retweet(id: String) async throws { try await writeOp("CreateRetweet", ["tweet_id": id, "dark_request": false]) }
    func unretweet(id: String) async throws { try await writeOp("DeleteRetweet", ["source_tweet_id": id, "dark_request": false]) }
    func bookmark(id: String) async throws { try await writeOp("CreateBookmark", ["tweet_id": id]) }
    func unbookmark(id: String) async throws { try await writeOp("DeleteBookmark", ["tweet_id": id]) }

    // ── Bookmark folder mutations ──

    /// Create a folder; returns the new folder id (best-effort scrape of the response).
    func createBookmarkFolder(name: String) async throws -> String? {
        let data = try await graphqlPOST(op: "createBookmarkFolder", variables: ["name": name])
        _ = try decodeResponse(data)   // throws on GraphQL errors
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let d = json["data"] as? [String: Any] else { return nil }
        for (_, v) in d {
            guard let obj = v as? [String: Any] else { continue }
            if let id = obj["id"] as? String { return id }
            if let id = obj["rest_id"] as? String { return id }
            if let inner = obj["bookmark_collection"] as? [String: Any],
               let id = (inner["id"] as? String) ?? (inner["rest_id"] as? String) { return id }
        }
        return nil
    }

    func editBookmarkFolder(id: String, name: String) async throws {
        try await writeOp("EditBookmarkFolder", ["bookmark_collection_id": id, "name": name])
    }
    func deleteBookmarkFolder(id: String) async throws {
        try await writeOp("DeleteBookmarkFolder", ["bookmark_collection_id": id])
    }
    func bookmarkTweetToFolder(tweetId: String, folderId: String) async throws {
        try await writeOp("bookmarkTweetToFolder", ["tweet_id": tweetId, "bookmark_collection_id": folderId])
    }
    func removeTweetFromBookmarkFolder(tweetId: String, folderId: String) async throws {
        try await writeOp("RemoveTweetFromBookmarkFolder", ["tweet_id": tweetId, "bookmark_collection_id": folderId])
    }

    private func writeOp(_ op: String, _ variables: [String: Any]) async throws {
        let data = try await graphqlPOST(op: op, variables: variables)
        _ = try decodeResponse(data)
    }

    // MARK: - User relationships (REST v1.1)

    func followUser(userId: String) async throws { try await restPOSTForm("1.1/friendships/create.json", ["user_id": userId]) }
    func unfollowUser(userId: String) async throws { try await restPOSTForm("1.1/friendships/destroy.json", ["user_id": userId]) }
    func muteUser(userId: String) async throws { try await restPOSTForm("1.1/mutes/users/create.json", ["user_id": userId]) }
    func unmuteUser(userId: String) async throws { try await restPOSTForm("1.1/mutes/users/destroy.json", ["user_id": userId]) }
    func blockUser(userId: String) async throws { try await restPOSTForm("1.1/blocks/create.json", ["user_id": userId]) }
    func unblockUser(userId: String) async throws { try await restPOSTForm("1.1/blocks/destroy.json", ["user_id": userId]) }
    // VERIFY: mute-conversation endpoint is unconfirmed; mirrors the mutes/users REST shape.
    func muteConversation(conversationId: String) async throws { try await restPOSTForm("1.1/mutes/conversations/create.json", ["conversation_id": conversationId]) }
    func unmuteConversation(conversationId: String) async throws { try await restPOSTForm("1.1/mutes/conversations/destroy.json", ["conversation_id": conversationId]) }

    /// Form-encoded POST to a legacy REST endpoint (relationships live on v1.1).
    private func restPOSTForm(_ path: String, _ fields: [String: String]) async throws {
        let body = fields.map { "\(enc($0.key))=\(enc($0.value))" }.joined(separator: "&")
        guard let url = URL(string: "https://x.com/i/api/\(path)") else { throw TwitterAPIError.noData }
        var req = await makeRequest("POST", url, body: body.data(using: .utf8))
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        _ = try await send(req)
    }

    private func restGETRaw(_ path: String, _ params: [String: String] = [:]) async throws -> Any {
        let data = try await restData("GET", path: path, params: params)
        return try rawJSON(data, context: path)
    }

    private func restPOSTFormRaw(_ path: String, _ fields: [String: String] = [:]) async throws -> Any {
        let body = fields.map { "\(enc($0.key))=\(enc($0.value))" }.joined(separator: "&")
        let data = try await restData("POST", path: path, body: body.data(using: .utf8),
                                      contentType: "application/x-www-form-urlencoded")
        return try rawJSON(data, context: path)
    }

    private func restPOSTJSONRaw(_ path: String, body: [String: Any] = [:],
                                 query: [String: String] = [:]) async throws -> Any {
        let data = try await restData("POST", path: path, params: query,
                                      body: try JSONSerialization.data(withJSONObject: body),
                                      contentType: "application/json")
        return try rawJSON(data, context: path)
    }

    private func restData(_ method: String, path: String, params: [String: String] = [:],
                          body: Data? = nil, contentType: String? = nil) async throws -> Data {
        guard var comp = URLComponents(string: "https://x.com/i/api/\(path)") else {
            throw TwitterAPIError.noData
        }
        if !params.isEmpty {
            comp.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comp.url else { throw TwitterAPIError.noData }
        var req = await makeRequest(method, url, body: body)
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "content-type") }
        return try await send(req)
    }

    // MARK: - GraphQL request builders

    /// GET a GraphQL op, auto-resolving its `features` / `fieldToggles` from
    /// `TwitterRequestConfigs`. Pass only the per-call `variables`. Ops with no
    /// configured features omit the `features` query param entirely (matching Rettiwt).
    private func gqlGET(op: String, variables: [String: Any]) async throws -> Data {
        let features = TwitterRequestConfigs.features(op)
        return try await graphqlGET(op: op, variables: variables,
                                    featuresJSON: features.isEmpty ? nil : jsonString(features),
                                    fieldTogglesJSON: fieldTogglesJSON(for: op))
    }

    private func graphqlGET(op: String, variables: [String: Any], featuresJSON: String?, fieldTogglesJSON: String? = nil) async throws -> Data {
        let queryId = await resolvedQueryId(op)
        var query = "variables=\(enc(jsonString(variables)))"
        if let featuresJSON { query += "&features=\(enc(featuresJSON))" }
        if let fieldTogglesJSON { query += "&fieldToggles=\(enc(fieldTogglesJSON))" }
        guard let url = URL(string: "\(graphqlBase)/\(queryId)/\(op)?\(query)") else { throw TwitterAPIError.noData }
        return try await send(await makeRequest("GET", url))
    }

    private func graphqlPOST(op: String, variables: [String: Any], features: [String: Bool]? = nil) async throws -> Data {
        let queryId = await resolvedQueryId(op)
        var body: [String: Any] = ["queryId": queryId, "variables": variables]
        if let features { body["features"] = features }
        guard let url = URL(string: "\(graphqlBase)/\(queryId)/\(op)") else { throw TwitterAPIError.noData }
        let req = await makeRequest("POST", url, body: try JSONSerialization.data(withJSONObject: body))
        return try await send(req)
    }

    private func graphqlPOSTQuery(op: String, params: [String: Any]) async throws -> Data {
        let queryId = await resolvedQueryId(op)
        var items = [URLQueryItem(name: "queryId", value: queryId)]
        for (key, value) in params {
            if let values = value as? [String] {
                items.append(contentsOf: values.map { URLQueryItem(name: key, value: $0) })
            } else {
                items.append(URLQueryItem(name: key, value: String(describing: value)))
            }
        }
        guard var comp = URLComponents(string: "\(graphqlBase)/\(queryId)/\(op)") else {
            throw TwitterAPIError.noData
        }
        comp.queryItems = items
        guard let url = comp.url else { throw TwitterAPIError.noData }
        return try await send(await makeRequest("POST", url))
    }

    private func graphqlRawGET(op: String, variables: [String: Any],
                               features: [String: Bool]? = nil) async throws -> Any {
        let featuresJSON = features.map { jsonString($0) }
        let data = try await graphqlGET(op: op, variables: variables, featuresJSON: featuresJSON)
        _ = try decodeResponse(data)
        return try rawJSON(data, context: op)
    }

    private func graphqlRawPOST(op: String, variables: [String: Any],
                                features: [String: Bool]? = nil) async throws -> Any {
        let data = try await graphqlPOST(op: op, variables: variables, features: features)
        _ = try decodeResponse(data)
        return try rawJSON(data, context: op)
    }

    private func graphqlRawPOSTQuery(op: String, params: [String: Any]) async throws -> Any {
        let data = try await graphqlPOSTQuery(op: op, params: params)
        _ = try decodeResponse(data)
        return try rawJSON(data, context: op)
    }

    private func resolvedQueryId(_ op: String) async -> String {
        await TwitterQueryIDs.shared.discover(headers: ["user-agent": userAgent])
        return await TwitterQueryIDs.shared.id(for: op)
    }

    private func makeRequest(_ method: String, _ url: URL, body: Data? = nil) async -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        var h = baseHeaders()
        if let txn = await TwitterTransactionID.shared.id(method: method, path: url.path) {
            h["x-client-transaction-id"] = txn
        }
        for (k, v) in h { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body
        return req
    }

    // MARK: - Decoding helpers

    private func decodeResponse(_ data: Data) throws -> GQLResponse {
        let decoded: GQLResponse
        do {
            decoded = try JSONDecoder().decode(GQLResponse.self, from: data)
        } catch {
            throw TwitterAPIError.decode(error.localizedDescription)
        }
        if let errs = decoded.errors, !errs.isEmpty {
            throw TwitterAPIError.http(400, errs.compactMap { $0.message }.joined(separator: ", "))
        }
        return decoded
    }

    private func rawJSON(_ data: Data, context: String) throws -> Any {
        guard !data.isEmpty else { return [:] as [String: Any] }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw TwitterAPIError.decode("Bad JSON from \(context): \(error.localizedDescription)")
        }
    }

    private func timeline(from data: Data) throws -> (nodes: [TweetResultNode], cursor: String?) {
        let instructions = try decodeResponse(data).data?.timelineInstructions
        return (Self.extractTweets(instructions), Self.extractCursor(instructions, type: "Bottom"))
    }

    private func timelinePage(from data: Data, operation: String) throws -> TwitterTimelineNodePage {
        let (nodes, cursor) = try timeline(from: data)
        return TwitterTimelineNodePage(nodes: nodes, cursor: cursor, operation: operation, rawData: data)
    }

    /// Like `timeline(from:)`, but keeps conversation modules grouped: each
    /// returned inner array is one thread (≥2 tweets) or a standalone tweet.
    private func timelineGroups(from data: Data) throws -> (groups: [[TweetResultNode]], cursor: String?, alertUsers: [UserResultNode], topCursor: String?) {
        let instructions = try decodeResponse(data).data?.timelineInstructions
        return (Self.extractGroups(instructions), Self.extractCursor(instructions, type: "Bottom"),
                Self.extractAlertUsers(instructions), Self.extractCursor(instructions, type: "Top"))
    }

    private func timelineGroupPage(from data: Data, operation: String) throws -> TwitterTimelineGroupPage {
        let (groups, cursor, alertUsers, topCursor) = try timelineGroups(from: data)
        return TwitterTimelineGroupPage(groups: groups, cursor: cursor, operation: operation,
                                        rawData: data, alertUsers: alertUsers, topCursor: topCursor)
    }

    private static func extractTweets(_ instructions: [GQLInstruction]?) -> [TweetResultNode] {
        extractGroups(instructions).flatMap { $0 }
    }

    /// Walk the timeline, emitting one group per entry. A single tweet entry is a
    /// group of one; a `TimelineModule` (conversation) keeps its tweets together.
    private static func extractGroups(_ instructions: [GQLInstruction]?) -> [[TweetResultNode]] {
        var out: [[TweetResultNode]] = []
        for instr in instructions ?? [] {
            for entry in instr.entries ?? [] {
                guard let id = entry.entryId, !id.hasPrefix("promoted-"), !id.hasPrefix("cursor-") else { continue }
                if let r = entry.content?.itemContent?.tweet_results?.result {
                    out.append([r.unwrapped])
                }
                var module: [TweetResultNode] = []
                for mod in entry.content?.items ?? [] {
                    if let r = mod.item?.itemContent?.tweet_results?.result {
                        module.append(r.unwrapped)
                    }
                }
                if !module.isEmpty { out.append(module) }
            }
        }
        return out
    }

    /// `TimelineShowAlert` (the "N new posts" banner) carries the avatars to show
    /// under `usersResults` — sourced for the home column's new-posts pill.
    fileprivate static func extractAlertUsers(_ instructions: [GQLInstruction]?) -> [UserResultNode] {
        for instr in instructions ?? [] where instr.alertType == "NewTweets" || instr.usersResults != nil {
            if let us = instr.usersResults, !us.isEmpty { return us.compactMap { $0.result } }
        }
        return []
    }

    private static func extractCursor(_ instructions: [GQLInstruction]?, type: String) -> String? {
        for instr in instructions ?? [] {
            for entry in instr.entries ?? [] {
                if entry.content?.cursorType == type, let v = entry.content?.value { return v }
                if let id = entry.entryId, id.hasPrefix("cursor-\(type.lowercased())"),
                   let v = entry.content?.value { return v }
            }
        }
        return nil
    }

    // MARK: - Current user

    func getCurrentUser() async throws -> CurrentUser {
        let candidateUrls = [
            "https://x.com/i/api/account/settings.json",
            "https://api.twitter.com/1.1/account/settings.json",
            "https://x.com/i/api/account/verify_credentials.json?skip_status=true&include_entities=false",
            "https://api.twitter.com/1.1/account/verify_credentials.json?skip_status=true&include_entities=false",
        ]
        var lastError = "Unknown error fetching current user"
        var best: CurrentUser?
        for urlStr in candidateUrls {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            for (k, v) in baseHeaders() { req.setValue(v, forHTTPHeaderField: k) }
            do {
                let data = try await send(req)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    lastError = "Bad JSON from \(urlStr)"
                    continue
                }
                let user = json["user"] as? [String: Any]
                let username = (json["screen_name"] as? String) ?? (user?["screen_name"] as? String)
                let name = (json["name"] as? String) ?? (user?["name"] as? String) ?? username
                let userId = (json["user_id"] as? String)
                    ?? (json["user_id_str"] as? String)
                    ?? (user?["id_str"] as? String)
                    ?? (user?["id"] as? String)
                let avatar = (user?["profile_image_url_https"] as? String)
                    ?? (json["profile_image_url_https"] as? String)
                if let username, let userId {
                    let cur = CurrentUser(id: userId, username: username, name: name ?? username, avatarURL: avatar)
                    if avatar != nil { return cur }
                    if best == nil { best = cur }
                }
                lastError = "Could not determine user from \(urlStr)"
            } catch let TwitterAPIError.http(code, msg) {
                lastError = "HTTP \(code): \(msg)"
                if code == 401 || code == 403 { throw TwitterAPIError.authExpired }
            } catch {
                lastError = error.localizedDescription
            }
        }
        if let best { return best }

        // Fallback: scrape authenticated settings page HTML.
        for page in ["https://x.com/settings/account", "https://twitter.com/settings/account"] {
            guard let url = URL(string: page) else { continue }
            var req = URLRequest(url: url)
            req.setValue("auth_token=\(authToken); ct0=\(ct0)", forHTTPHeaderField: "cookie")
            req.setValue(userAgent, forHTTPHeaderField: "user-agent")
            let started = Date()
            guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
                NetworkLog.shared.log(method: "GET", url: url, status: nil, bytes: 0,
                                      startedAt: started, detail: "transport error")
                continue
            }
            let code = (resp as? HTTPURLResponse)?.statusCode
            NetworkLog.shared.log(method: "GET", url: url, status: code, bytes: data.count, startedAt: started)
            guard code == 200, let html = String(data: data, encoding: .utf8) else { continue }
            let username = Self.firstMatch(html, #""screen_name":"([^"]+)""#)
            let userId = Self.firstMatch(html, #""user_id"\s*:\s*"(\d+)""#)
            let name = Self.firstMatch(html, #""name":"([^"\\]*(?:\\.[^"\\]*)*)""#)?.replacingOccurrences(of: "\\\"", with: "\"")
            if let username, let userId {
                return CurrentUser(id: userId, username: username, name: name ?? username)
            }
        }
        throw TwitterAPIError.decode(lastError)
    }

    // MARK: - Plumbing

    private func send(_ req: URLRequest) async throws -> Data {
        let started = Date()
        let method = req.httpMethod ?? "GET"
        let url = req.url
        // Snapshot the request for the redaction-safe debug log (cookies/tokens stripped in `record`).
        let reqHeaders = req.allHTTPHeaderFields
        let reqBody = req.httpBody
        func capture(status: Int?, resBody: Data?, error: String?) {
            DebugLog.shared.record(method: method, url: url, requestHeaders: reqHeaders,
                                   requestBody: reqBody, status: status, responseBody: resBody,
                                   durationMs: Int(Date().timeIntervalSince(started) * 1000),
                                   error: error)
        }
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            NetworkLog.shared.log(method: method, url: url, status: nil, bytes: 0,
                                  startedAt: started, detail: error.localizedDescription)
            capture(status: nil, resBody: nil, error: error.localizedDescription)
            throw TwitterAPIError.decode(error.localizedDescription)
        }
        guard let http = resp as? HTTPURLResponse else {
            NetworkLog.shared.log(method: method, url: url, status: nil, bytes: data.count,
                                  startedAt: started, detail: "non-http response")
            capture(status: nil, resBody: data, error: "non-http response")
            return data
        }
        let code = http.statusCode
        switch code {
        case 200..<300:
            NetworkLog.shared.log(method: method, url: url, status: code, bytes: data.count, startedAt: started)
            capture(status: code, resBody: data, error: nil)
            return data
        case 401, 403:
            NetworkLog.shared.log(method: method, url: url, status: code, bytes: data.count,
                                  startedAt: started, detail: "auth expired")
            capture(status: code, resBody: data, error: "auth expired")
            throw TwitterAPIError.authExpired
        case 429:
            NetworkLog.shared.log(method: method, url: url, status: code, bytes: data.count,
                                  startedAt: started, detail: "rate limited")
            capture(status: code, resBody: data, error: "rate limited")
            throw TwitterAPIError.rateLimited
        default:
            let prefix = String((String(data: data, encoding: .utf8) ?? "").prefix(200))
            NetworkLog.shared.log(method: method, url: url, status: code, bytes: data.count,
                                  startedAt: started, detail: prefix)
            capture(status: code, resBody: data, error: prefix)
            throw TwitterAPIError.http(code, prefix)
        }
    }

    private func jsonString(_ obj: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Percent-encode a query value the way `encodeURIComponent` does (RFC 3986 unreserved).
    private static let queryAllowed: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "-_.!~*'()")
        return s
    }()

    private func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? s
    }

    private static func firstMatch(_ text: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: - User / list timeline extraction (shared by the Rettiwt-ported ops)

    /// Decode a user-timeline response into `(users, bottomCursor)`.
    fileprivate func userTimeline(from data: Data) throws -> (nodes: [UserResultNode], cursor: String?) {
        let instructions = try decodeResponse(data).data?.timelineInstructions
        return (Self.extractUsers(instructions), Self.extractCursor(instructions, type: "Bottom"))
    }

    fileprivate static func extractUsers(_ instructions: [GQLInstruction]?) -> [UserResultNode] {
        var out: [UserResultNode] = []
        for instr in instructions ?? [] {
            for entry in instr.entries ?? [] {
                guard let id = entry.entryId, !id.hasPrefix("cursor-") else { continue }
                if let u = entry.content?.itemContent?.user_results?.result { out.append(u) }
                for mod in entry.content?.items ?? [] {
                    if let u = mod.item?.itemContent?.user_results?.result { out.append(u) }
                }
            }
        }
        return out
    }

    fileprivate static func extractLists(_ instructions: [GQLInstruction]?) -> [GQLList] {
        var out: [GQLList] = []
        for instr in instructions ?? [] {
            for entry in instr.entries ?? [] {
                if let l = entry.content?.itemContent?.list { out.append(l) }
                for mod in entry.content?.items ?? [] {
                    if let l = mod.item?.itemContent?.list { out.append(l) }
                }
            }
        }
        return out
    }

    // MARK: - REST GET (DM / settings payloads)

    fileprivate func restGETJSON(_ path: String, _ params: [String: String]) async throws -> [String: Any] {
        let query = params.map { "\(enc($0.key))=\(enc($0.value))" }.joined(separator: "&")
        guard let url = URL(string: "https://x.com/i/api/\(path)?\(query)") else { throw TwitterAPIError.noData }
        let data = try await send(await makeRequest("GET", url))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TwitterAPIError.decode("Bad JSON from \(path)")
        }
        return json
    }
}

// MARK: - Rettiwt-ported operations
//
// Every operation below mirrors a method in Rettiwt-API's `src/requests/*.ts`
// (queryId in `TwitterQueryIDs`, features/fieldToggles in `TwitterRequestConfigs`).

extension TwitterAPIClient {

    // ── Tweets ──

    /// Single tweet via `TweetResultByRestId`.
    func tweetDetailsSingle(id: String) async throws -> TweetResultNode? {
        let data = try await gqlGET(op: "TweetResultByRestId", variables: tweetLookupVariables(["tweetId": id]))
        return try decodeResponse(data).data?.tweetResult?.result
    }

    /// Bulk tweet details via `TweetResultsByRestIds`.
    func bulkTweetDetails(ids: [String]) async throws -> [TweetResultNode] {
        let data = try await gqlGET(op: "TweetResultsByRestIds", variables: tweetLookupVariables(["tweetIds": ids]))
        let decoded: GQLBulkTweetResponse
        do { decoded = try JSONDecoder().decode(GQLBulkTweetResponse.self, from: data) }
        catch { throw TwitterAPIError.decode(error.localizedDescription) }
        if let errs = decoded.errors, !errs.isEmpty {
            throw TwitterAPIError.http(400, errs.compactMap { $0.message }.joined(separator: ", "))
        }
        return (decoded.data?.tweetResult ?? []).compactMap { $0.result?.unwrapped }
    }

    private func tweetLookupVariables(_ extra: [String: Any]) -> [String: Any] {
        var v: [String: Any] = [
            "referrer": "home", "with_rux_injections": false, "includePromotedContent": false,
            "withCommunity": false, "withQuickPromoteEligibilityTweetFields": false,
            "withBirdwatchNotes": false, "withVoice": false, "withV2Timeline": false,
        ]
        for (k, val) in extra { v[k] = val }
        return v
    }

    /// Edit history of a tweet via `TweetEditHistory`.
    func tweetHistory(id: String) async throws -> [TweetResultNode] {
        let data = try await gqlGET(op: "TweetEditHistory",
                                    variables: ["tweetId": id, "withQuickPromoteEligibilityTweetFields": true])
        return try timeline(from: data).nodes
    }

    /// Users who liked a tweet (`Favoriters`).
    func likers(tweetId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["tweetId": tweetId, "count": count, "enableRanking": false, "includePromotedContent": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "Favoriters", variables: v))
    }

    /// Users who retweeted a tweet (`Retweeters`).
    func retweeters(tweetId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["tweetId": tweetId, "count": count, "includePromotedContent": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "Retweeters", variables: v))
    }

    /// Schedule a tweet (`CreateScheduledTweet`). Returns the new scheduled-tweet id.
    @discardableResult
    func scheduleTweet(text: String, mediaIds: [String] = [], executeAt: Date) async throws -> String? {
        let variables: [String: Any] = [
            "post_tweet_request": [
                "auto_populate_reply_metadata": false,
                "status": text,
                "exclude_reply_user_ids": [],
                "media_ids": mediaIds,
            ],
            "execute_at": Int(executeAt.timeIntervalSince1970),
        ]
        let data = try await graphqlPOST(op: "CreateScheduledTweet", variables: variables)
        _ = try decodeResponse(data)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return Self.deepFindString(json, key: "rest_id")
        }
        return nil
    }

    /// Cancel a scheduled tweet (`DeleteScheduledTweet`).
    func unscheduleTweet(id: String) async throws {
        let data = try await graphqlPOST(op: "DeleteScheduledTweet", variables: ["scheduled_tweet_id": id])
        _ = try decodeResponse(data)
    }

    // ── Users ──

    /// Profile spotlights (`ProfileSpotlightsQuery`), returned raw because Perch does
    /// not model spotlight modules.
    func profileSpotlights(screenName: String) async throws -> Any {
        try await graphqlRawGET(op: "ProfileSpotlightsQuery",
                                variables: ["screen_name": screenName])
    }

    /// About profile (`AboutAccountQuery`).
    func aboutByUsername(_ username: String) async throws -> GQLAboutResult? {
        let data = try await gqlGET(op: "AboutAccountQuery", variables: ["screenName": username])
        return try decodeResponse(data).data?.user_result_by_screen_name?.result
    }

    /// Affiliated users (`UserBusinessProfileTeamTimeline`).
    func affiliates(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "teamName": "NotAssigned",
                                "includePromotedContent": false, "withClientEventToken": false, "withVoice": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "UserBusinessProfileTeamTimeline", variables: v))
    }

    /// Premium analytics overview (`AccountOverviewQuery`). Premium accounts only.
    func analytics(from: Date, to: Date, granularity: String = "Day",
                   metrics: [String], showVerifiedFollowers: Bool = false) async throws -> [String: Any] {
        let iso = ISO8601DateFormatter()
        let variables: [String: Any] = [
            "from_time": iso.string(from: from),
            "to_time": iso.string(from: to),
            "granularity": granularity,
            "requested_metrics": metrics,
            "show_verified_followers": showVerifiedFollowers,
        ]
        let data = try await gqlGET(op: "AccountOverviewQuery", variables: variables)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TwitterAPIError.decode("Bad analytics JSON")
        }
        return json
    }

    /// Bulk user details by ids (`UsersByRestIds`).
    func bulkUserDetails(ids: [String]) async throws -> [UserResultNode] {
        let data = try await gqlGET(op: "UsersByRestIds", variables: ["userIds": ids])
        let decoded: GQLBulkUsersResponse
        do { decoded = try JSONDecoder().decode(GQLBulkUsersResponse.self, from: data) }
        catch { throw TwitterAPIError.decode(error.localizedDescription) }
        if let errs = decoded.errors, !errs.isEmpty {
            throw TwitterAPIError.http(400, errs.compactMap { $0.message }.joined(separator: ", "))
        }
        return (decoded.data?.users ?? []).compactMap { $0.result }
    }

    /// Followers of a user (`Followers`).
    func followers(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false, "withGrokTranslatedBio": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "Followers", variables: v))
    }

    /// Followers the viewer knows (`FollowersYouKnow`).
    func followersYouKnow(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "FollowersYouKnow", variables: v))
    }

    /// Users a user follows (`Following`).
    func following(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "Following", variables: v))
    }

    /// Highlighted tweets of a user (`UserHighlightsTweets`).
    func highlights(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false, "withVoice": false]
        if let cursor { v["cursor"] = cursor }
        return try timeline(from: try await gqlGET(op: "UserHighlightsTweets", variables: v))
    }

    /// Media timeline of a user (`UserMedia`).
    func userMedia(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false,
                                "withClientEventToken": false, "withBirdwatchNotes": false,
                                "withVoice": false, "withV2Timeline": false]
        if let cursor { v["cursor"] = cursor }
        return try timeline(from: try await gqlGET(op: "UserMedia", variables: v))
    }

    /// Replies timeline of a user (`UserTweetsAndReplies`).
    func userTweetsAndReplies(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false,
                                "withCommunity": false, "withVoice": false, "withV2Timeline": false]
        if let cursor { v["cursor"] = cursor }
        return try timeline(from: try await gqlGET(op: "UserTweetsAndReplies", variables: v))
    }

    /// Creator subscriptions of a user (`UserCreatorSubscriptions`).
    func subscriptions(userId: String, count: Int = 40, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count, "includePromotedContent": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "UserCreatorSubscriptions", variables: v))
    }

    /// The logged-in user's lists (`ListsManagementPageTimeline`).
    func userLists(cursor: String? = nil) async throws -> (lists: [GQLList], cursor: String?) {
        var v: [String: Any] = ["count": 100]
        if let cursor { v["cursor"] = cursor }
        let data = try await gqlGET(op: "ListsManagementPageTimeline", variables: v)
        let instructions = try decodeResponse(data).data?.timelineInstructions
        return (Self.extractLists(instructions), Self.extractCursor(instructions, type: "Bottom"))
    }

    /// Search for users (`SearchTimeline`, product=People).
    func searchUsers(query: String, count: Int = 20, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["rawQuery": query, "count": count, "querySource": "typed_query",
                                "product": "People", "withGrokTranslatedBio": false]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "SearchTimeline", variables: v))
    }

    /// Notifications timeline via GraphQL (`NotificationsTimeline`). Returns the tweet
    /// entries plus the paging cursor. Perch's notification-center UI still uses the
    /// legacy REST `fetchNotifications`; this is the Rettiwt-equivalent GraphQL op.
    func notificationsTimeline(count: Int = 40, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        var v: [String: Any] = ["timeline_type": "All", "count": count]
        if let cursor { v["cursor"] = cursor }
        return try timeline(from: try await gqlGET(op: "NotificationsTimeline", variables: v))
    }

    /// Scheduled tweets of the logged-in user (`FetchScheduledTweets`).
    func scheduledTweets() async throws -> [GQLScheduledTweet] {
        let data = try await gqlGET(op: "FetchScheduledTweets", variables: ["ascending": true])
        return try decodeResponse(data).data?.viewer?.scheduled_tweet_list ?? []
    }

    /// Remove a follower (`RemoveFollower`).
    func removeFollower(userId: String) async throws {
        let data = try await graphqlPOST(op: "RemoveFollower", variables: ["target_user_id": userId])
        _ = try decodeResponse(data)
    }

    // ── User profile mutations (REST 1.1) ──

    func updateProfile(name: String? = nil, url: String? = nil,
                       location: String? = nil, description: String? = nil) async throws {
        var fields: [String: String] = [:]
        if let name { fields["name"] = name }
        if let url { fields["url"] = url }
        if let location { fields["location"] = location }
        if let description { fields["description"] = description }
        try await restPOSTForm("1.1/account/update_profile.json", fields)
    }

    func updateProfileImage(base64: String) async throws {
        try await restPOSTForm("1.1/account/update_profile_image.json", ["image": base64])
    }

    func updateProfileBanner(base64: String) async throws {
        try await restPOSTForm("1.1/account/update_profile_banner.json", ["banner": base64])
    }

    func changeUsername(_ newUsername: String) async throws {
        try await restPOSTForm("1.1/account/settings.json", ["screen_name": newUsername])
    }

    func changePassword(current: String, new: String) async throws {
        try await restPOSTForm("i/account/change_password.json",
                               ["current_password": current, "password": new, "password_confirmation": new])
    }

    // ── Lists ──

    /// List details (`ListByRestId`).
    func listDetails(id: String) async throws -> GQLList? {
        let data = try await gqlGET(op: "ListByRestId", variables: ["listId": id])
        return try decodeResponse(data).data?.list
    }

    /// Lists owned by a user (`ListOwnerships`).
    func listOwnerships(userId: String, targetUserId: String? = nil,
                        count: Int = 20, cursor: String? = nil) async throws -> (lists: [GQLList], cursor: String?) {
        var v: [String: Any] = ["userId": userId, "count": count]
        if let targetUserId { v["isListMemberTargetUserId"] = targetUserId }
        if let cursor { v["cursor"] = cursor }
        let data = try await gqlGET(op: "ListOwnerships", variables: v)
        let instructions = try decodeResponse(data).data?.timelineInstructions
        return (Self.extractLists(instructions), Self.extractCursor(instructions, type: "Bottom"))
    }

    /// Members of a list (`ListMembers`).
    func listMembers(id: String, count: Int = 100, cursor: String? = nil) async throws -> (nodes: [UserResultNode], cursor: String?) {
        var v: [String: Any] = ["listId": id, "count": count]
        if let cursor { v["cursor"] = cursor }
        return try userTimeline(from: try await gqlGET(op: "ListMembers", variables: v))
    }

    /// Tweets in a list (`ListLatestTweetsTimeline`).
    func listTweets(id: String, count: Int = 100, cursor: String? = nil) async throws -> (nodes: [TweetResultNode], cursor: String?) {
        let page = try await listTweetsRaw(id: id, count: count, cursor: cursor)
        return (page.nodes, page.cursor)
    }

    func listTweetsRaw(id: String, count: Int = 100, cursor: String? = nil) async throws -> TwitterTimelineNodePage {
        var v: [String: Any] = ["listId": id, "count": count]
        if let cursor { v["cursor"] = cursor }
        let data = try await gqlGET(op: "ListLatestTweetsTimeline", variables: v)
        return try timelinePage(from: data, operation: "ListLatestTweetsTimeline")
    }

    /// Add a member to a list (`ListAddMember`).
    func listAddMember(listId: String, userId: String) async throws {
        let data = try await graphqlPOST(op: "ListAddMember", variables: ["listId": listId, "userId": userId],
                                         features: TwitterRequestConfigs.features("ListAddMember"))
        _ = try decodeResponse(data)
    }

    /// Remove a member from a list (`ListRemoveMember`).
    func listRemoveMember(listId: String, userId: String) async throws {
        let data = try await graphqlPOST(op: "ListRemoveMember", variables: ["listId": listId, "userId": userId],
                                         features: TwitterRequestConfigs.features("ListRemoveMember"))
        _ = try decodeResponse(data)
    }

    /// Create a list (`CreateList`).
    func createList(name: String, description: String = "", isPrivate: Bool = false) async throws -> GQLList? {
        let data = try await graphqlPOST(op: "CreateList",
                                         variables: ["name": name, "description": description, "isPrivate": isPrivate],
                                         features: TwitterRequestConfigs.features("CreateList"))
        return try decodeResponse(data).data?.list
    }

    /// Update a list (`UpdateList`).
    func updateList(id: String, name: String, description: String = "",
                    isPrivate: Bool = false) async throws -> GQLList? {
        let data = try await graphqlPOST(op: "UpdateList",
                                         variables: ["listId": id, "name": name,
                                                     "description": description, "isPrivate": isPrivate],
                                         features: TwitterRequestConfigs.features("UpdateList"))
        return try decodeResponse(data).data?.list
    }

    /// Delete a list (`DeleteList`).
    func deleteList(id: String) async throws {
        let data = try await graphqlPOST(op: "DeleteList", variables: ["listId": id])
        _ = try decodeResponse(data)
    }

    /// Set a list banner (`EditListBanner`).
    func editListBanner(id: String, mediaId: String) async throws -> GQLList? {
        let data = try await graphqlPOST(op: "EditListBanner",
                                         variables: ["listId": id, "mediaId": mediaId],
                                         features: TwitterRequestConfigs.features("EditListBanner"))
        return try decodeResponse(data).data?.list
    }

    // ── Spaces ──

    /// Space details (`AudioSpaceById`).
    func spaceDetails(id: String, withReplays: Bool = true, withListeners: Bool = false) async throws -> GQLAudioSpace? {
        let data = try await gqlGET(op: "AudioSpaceById",
                                    variables: ["id": id, "isMetatagsQuery": false,
                                                "withReplays": withReplays, "withListeners": withListeners])
        return try decodeResponse(data).data?.audioSpace
    }

    // ── Direct messages (REST 1.1) ──

    func dmInboxInitial() async throws -> [String: Any] {
        try await restGETJSON("1.1/dm/inbox_initial_state.json", Self.dmParams(["dm_users": "true"]))
    }

    func dmInboxTimeline(maxId: String? = nil) async throws -> [String: Any] {
        var p = Self.dmParams(["dm_users": "false"])
        if let maxId { p["max_id"] = maxId }
        return try await restGETJSON("1.1/dm/inbox_timeline/trusted.json", p)
    }

    func dmConversation(conversationId: String, maxId: String? = nil) async throws -> [String: Any] {
        var p = Self.dmParams([
            "dm_users": "false",
            "context": maxId == nil ? "FETCH_DM_CONVERSATION" : "FETCH_DM_CONVERSATION_HISTORY",
            "include_conversation_info": "true",
        ])
        if let maxId { p["max_id"] = maxId }
        return try await restGETJSON("1.1/dm/conversation/\(conversationId).json", p)
    }

    func dmDeleteConversation(conversationId: String) async throws {
        try await restPOSTForm("1.1/dm/conversation/\(conversationId)/delete.json",
                               Self.dmDeleteParams())
    }

    func dmInboxTimelineUntrusted(maxId: String? = nil) async throws -> Any {
        var p = Self.dmParams(["filter_low_quality": "false", "include_quality": "high"])
        if let maxId { p["max_id"] = maxId }
        return try await restGETRaw("1.1/dm/inbox_timeline/untrusted.json", p)
    }

    func dmPermissions(recipientIds: [String]) async throws -> Any {
        try await restGETRaw("1.1/dm/permissions.json",
                             ["recipient_ids": recipientIds.joined(separator: ","), "dm_users": "true"])
    }

    func dmUserUpdates() async throws -> Any {
        try await restGETRaw("1.1/dm/user_updates.json",
                             Self.dmParams(["dm_secret_conversations_enabled": "false",
                                            "krs_registration_enabled": "true"]))
    }

    func dmAcceptConversation(conversationId: String) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/accept.json",
                                      ["conversationId": conversationId])
    }

    func dmDisableNotifications(conversationId: String, duration: Int = 0) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/disable_notifications.json",
                                      ["duration": "\(duration)"])
    }

    func dmEnableNotifications(conversationId: String) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/enable_notifications.json",
                                      ["conversationId": conversationId])
    }

    func dmMarkRead(conversationId: String, lastReadEventId: String) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/mark_read.json",
                                      ["conversationId": conversationId,
                                       "last_read_event_id": lastReadEventId])
    }

    func dmUpdateAvatar(conversationId: String, avatarId: String) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/update_avatar.json",
                                      ["avatar_id": avatarId])
    }

    func dmUpdateMentionNotificationsSetting(conversationId: String, disabled: Bool = true) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/update_mention_notifications_setting.json",
                                      ["mention_notifications_disabled": Self.bool(disabled)])
    }

    func dmUpdateName(conversationId: String, name: String) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/conversation/\(conversationId)/update_name.json",
                                      ["name": name])
    }

    func dmUpdateLastSeenEventId(_ eventId: String, trustedEventId: String? = nil) async throws {
        _ = try await restPOSTFormRaw("1.1/dm/update_last_seen_event_id.json",
                                      ["last_seen_event_id": eventId,
                                       "trusted_last_seen_event_id": trustedEventId ?? eventId])
    }

    func dmAddWelcomeMessageToConversation(conversationId: String,
                                           requestId: String = UUID().uuidString) async throws -> Any {
        try await restPOSTJSONRaw("1.1/dm/welcome_messages/add_to_conversation.json",
                                  body: ["conversation_id": conversationId],
                                  query: ["cards_platform": "Web-12", "request_id": requestId])
    }

    func dmSendMessage(conversationId: String, text: String,
                       requestId: String = UUID().uuidString,
                       mediaId: String? = nil, replyToDMId: String? = nil) async throws -> Any {
        var body: [String: Any] = [
            "cards_platform": "Web-12",
            "dm_users": false,
            "include_cards": 1,
            "include_quote_count": true,
            "conversation_id": conversationId,
            "request_id": requestId,
            "text": text,
            "strato_ext": Self.dmStratoExt,
        ]
        if let mediaId { body["media_id"] = mediaId }
        if let replyToDMId { body["reply_to_dm_id"] = replyToDMId }
        return try await restPOSTJSONRaw("1.1/dm/new2.json", body: body,
                                         query: Self.dmNewMessageParams())
    }

    // ── Direct messages (GraphQL) ──

    func dmConversationSearchGroups(variables: [String: Any]) async throws -> Any {
        try await graphqlRawGET(op: "DMConversationSearchTabGroupsQuery", variables: variables)
    }

    func dmConversationSearchPeople(variables: [String: Any]) async throws -> Any {
        try await graphqlRawGET(op: "DMConversationSearchTabPeopleQuery", variables: variables)
    }

    func dmMessageSearch(variables: [String: Any], features: [String: Bool]? = nil) async throws -> Any {
        try await graphqlRawGET(op: "DMMessageSearchTabQuery", variables: variables, features: features)
    }

    func dmPinnedInbox(label: String = "Pinned") async throws -> Any {
        try await graphqlRawGET(op: "DMPinnedInboxQuery", variables: ["label": label])
    }

    func dmAllSearchSlice(variables: [String: Any], features: [String: Bool]? = nil) async throws -> Any {
        try await graphqlRawGET(op: "DmAllSearchSlice", variables: variables, features: features)
    }

    func dmAddParticipants(conversationId: String, participantIds: [String]) async throws -> Any {
        try await graphqlRawPOSTQuery(op: "AddParticipantsMutation",
                                      params: ["conversationId": conversationId,
                                               "addedParticipants": participantIds])
    }

    func dmBlockUser(userId: String) async throws -> Any {
        try await graphqlRawPOSTQuery(op: "dmBlockUser", params: ["target_user_id": userId])
    }

    func dmUnblockUser(userId: String) async throws -> Any {
        try await graphqlRawPOSTQuery(op: "dmUnblockUser", params: ["target_user_id": userId])
    }

    func dmDeleteMessage(messageId: String, requestId: String = UUID().uuidString) async throws -> Any {
        try await graphqlRawPOSTQuery(op: "DMMessageDeleteMutation",
                                      params: ["messageId": messageId, "requestId": requestId])
    }

    func dmPinConversation(conversationId: String, label: String = "Pinned") async throws -> Any {
        try await graphqlRawPOSTQuery(op: "DMPinnedInboxAppend_Mutation",
                                      params: ["conversation_id": conversationId, "label": label])
    }

    func dmUnpinConversation(conversationId: String, label: String = "Pinned") async throws -> Any {
        try await graphqlRawPOSTQuery(op: "DMPinnedInboxDelete_Mutation",
                                      params: ["conversation_id": conversationId, "label_type": label])
    }

    func dmAddReaction(conversationId: String, messageId: String,
                       emojiReactions: [String], reactionTypes: [String]) async throws -> Any {
        try await graphqlRawPOSTQuery(op: "useDMReactionMutationAddMutation",
                                      params: ["conversationId": conversationId,
                                               "messageId": messageId,
                                               "emojiReactions": emojiReactions,
                                               "reactionTypes": reactionTypes])
    }

    func dmRemoveReaction(conversationId: String, messageId: String,
                          emojiReactions: [String], reactionTypes: [String]) async throws -> Any {
        try await graphqlRawPOSTQuery(op: "useDMReactionMutationRemoveMutation",
                                      params: ["conversationId": conversationId,
                                               "messageId": messageId,
                                               "emojiReactions": emojiReactions,
                                               "reactionTypes": reactionTypes])
    }

    // ── Misc legacy REST endpoints from Flare xqt ──

    func guestActivate() async throws -> Any {
        try await restPOSTFormRaw("1.1/guest/activate.json")
    }

    func other() async throws -> Any {
        try await restGETRaw("other")
    }

    func friendsFollowingList(userId: String, cursor: Int = -1, count: Int = 3) async throws -> Any {
        try await restGETRaw("1.1/friends/following/list.json",
                             Self.commonLegacyParams(["cursor": "\(cursor)",
                                                      "user_id": userId,
                                                      "count": "\(count)",
                                                      "with_total_count": "true"]))
    }

    func searchTypeahead(query: String, resultType: String = "events,users,topics") async throws -> Any {
        try await restGETRaw("1.1/search/typeahead.json",
                             ["include_ext_is_blue_verified": "1",
                              "include_ext_verified_type": "1",
                              "include_ext_profile_image_shape": "1",
                              "q": query,
                              "src": "search_box",
                              "result_type": resultType])
    }

    func userRecommendations(userId: String, limit: Int = 3,
                             displayLocation: String = "profile_accounts_sidebar") async throws -> Any {
        try await restGETRaw("1.1/users/recommendations.json",
                             Self.commonLegacyParams(["pc": "true",
                                                      "display_location": displayLocation,
                                                      "limit": "\(limit)",
                                                      "user_id": userId,
                                                      "ext": Self.legacyUserExt]))
    }

    func listMemberships(userId: String, cursor: Int = -1,
                         count: Int = 1000, filterToOwnedLists: Bool = true) async throws -> Any {
        try await restGETRaw("1.1/lists/memberships.json",
                             Self.commonLegacyParams(["cards_platform": "Web-12",
                                                      "include_cards": "1",
                                                      "include_ext_limited_action_results": "true",
                                                      "include_quote_count": "true",
                                                      "include_reply_count": "1",
                                                      "tweet_mode": "extended",
                                                      "include_ext_views": "true",
                                                      "include_ext_alt_text": "true",
                                                      "cursor": "\(cursor)",
                                                      "user_id": userId,
                                                      "count": "\(count)",
                                                      "filter_to_owned_lists": Self.bool(filterToOwnedLists)]))
    }

    func liveVideoStreamStatus(mediaKey: String) async throws -> Any {
        try await restGETRaw("1.1/live_video_stream/status/\(mediaKey)",
                             ["client": "web",
                              "use_syndication_guest_id": "false",
                              "cookie_set_host": "x.com"])
    }

    func fleets(onlySpaces: Bool = true) async throws -> Any {
        try await restGETRaw("fleets/v1/fleetline", ["only_spaces": Self.bool(onlySpaces)])
    }

    func searchAdaptive(query: String, count: Int = 20,
                        querySource: String = "trend_click") async throws -> Any {
        try await restGETRaw("2/search/adaptive.json",
                             Self.notificationParams(["q": query,
                                                      "query_source": querySource,
                                                      "count": "\(count)",
                                                      "requestContext": "launch",
                                                      "pc": "1",
                                                      "spelling_corrections": "1",
                                                      "include_ext_edit_control": "true",
                                                      "ext": Self.adaptiveSearchExt],
                                                     includeLimitedActions: "false"))
    }

    func notificationMentions(count: Int = 20, cursor: String? = nil) async throws -> Any {
        var p = Self.notificationParams(["count": "\(count)",
                                         "requestContext": "launch",
                                         "ext": Self.notificationMentionsExt])
        if let cursor { p["cursor"] = cursor }
        return try await restGETRaw("2/notifications/mentions.json", p)
    }

    func guide(tabCategory: String = "objective_trends", count: Int = 20) async throws -> Any {
        try await restGETRaw("2/guide.json",
                             Self.notificationParams(["tab_category": tabCategory,
                                                      "count": "\(count)",
                                                      "ext": Self.notificationMentionsExt]))
    }

    func notificationDeviceFollow(count: Int = 20, cursor: String? = nil) async throws -> Any {
        var p = Self.notificationParams(["count": "\(count)",
                                         "ext": Self.notificationDeviceFollowExt])
        if let cursor { p["cursor"] = cursor }
        return try await restGETRaw("2/notifications/device_follow.json", p)
    }

    func badgeCount() async throws -> Any {
        try await restGETRaw("2/badge_count/badge_count.json", ["supports_ntab_urt": "1"])
    }

    func markNotificationsAllSeen(cursor: String) async throws {
        _ = try await restPOSTFormRaw("2/notifications/all/last_seen_cursor.json",
                                      ["cursor": cursor])
    }

    /// Common query params for the DM REST endpoints (subset of Rettiwt's BaseDMParams).
    private static func dmParams(_ extra: [String: String]) -> [String: String] {
        var p: [String: String] = [
            "nsfw_filtering_enabled": "false",
            "filter_low_quality": "true",
            "include_quality": "all",
            "include_profile_interstitial_type": "1",
            "include_blocking": "1",
            "include_blocked_by": "1",
            "include_followed_by": "1",
            "include_want_retweets": "1",
            "include_mute_edge": "1",
            "include_can_dm": "1",
            "include_can_media_tag": "1",
            "include_ext_is_blue_verified": "1",
            "include_ext_verified_type": "1",
            "include_ext_profile_image_shape": "1",
            "skip_status": "1",
            "cards_platform": "Web-12",
            "include_cards": "1",
            "include_ext_alt_text": "true",
            "include_quote_count": "true",
            "include_reply_count": "1",
            "tweet_mode": "extended",
            "include_ext_views": "true",
            "include_groups": "true",
            "include_inbox_timelines": "true",
            "include_ext_media_color": "true",
            "supports_reactions": "true",
        ]
        for (k, v) in extra { p[k] = v }
        return p
    }

    private static func dmDeleteParams() -> [String: String] {
        dmParams(["dm_secret_conversations_enabled": "false",
                  "dm_users": "false",
                  "include_conversation_info": "true",
                  "krs_registration_enabled": "true",
                  "include_ext_limited_action_results": "true",
                  "include_ext_media_color": "true",
                  "supports_edit": "true"])
    }

    private static func dmNewMessageParams() -> [String: String] {
        [
            "ext": "mediaColor,altText,mediaStats,highlightedLabel,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl,article",
            "include_ext_alt_text": "true",
            "include_ext_limited_action_results": "true",
            "include_reply_count": "1",
            "tweet_mode": "extended",
            "include_ext_views": "true",
            "include_groups": "true",
            "include_inbox_timelines": "true",
            "include_ext_media_color": "true",
            "supports_reactions": "true",
            "supports_edit": "true",
        ]
    }

    private static func commonLegacyParams(_ extra: [String: String]) -> [String: String] {
        var p: [String: String] = [
            "include_profile_interstitial_type": "1",
            "include_blocking": "1",
            "include_blocked_by": "1",
            "include_followed_by": "1",
            "include_want_retweets": "1",
            "include_mute_edge": "1",
            "include_can_dm": "1",
            "include_can_media_tag": "1",
            "include_ext_has_nft_avatar": "1",
            "include_ext_is_blue_verified": "1",
            "include_ext_verified_type": "1",
            "include_ext_profile_image_shape": "1",
            "skip_status": "1",
        ]
        for (k, v) in extra { p[k] = v }
        return p
    }

    private static func notificationParams(_ extra: [String: String],
                                           includeLimitedActions: String = "true") -> [String: String] {
        commonLegacyParams([
            "cards_platform": "Web-12",
            "include_cards": "1",
            "include_ext_alt_text": "true",
            "include_ext_limited_action_results": includeLimitedActions,
            "include_quote_count": "true",
            "include_reply_count": "1",
            "tweet_mode": "extended",
            "include_ext_views": "true",
            "include_entities": "true",
            "include_user_entities": "true",
            "include_ext_media_color": "true",
            "include_ext_media_availability": "true",
            "include_ext_sensitive_media_warning": "true",
            "include_ext_trusted_friends_metadata": "true",
            "send_error_codes": "true",
            "simple_quoted_tweet": "true",
        ].merging(extra) { _, new in new })
    }

    private static let legacyUserExt = "mediaStats,highlightedLabel,hasNftAvatar,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl"
    private static let adaptiveSearchExt = "mediaStats,highlightedLabel,hasNftAvatar,voiceInfo,birdwatchPivot,enrichments,superFollowMetadata,unmentionInfo,editControl,vibe"
    private static let notificationMentionsExt = "mediaStats,highlightedLabel,hasNftAvatar,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl"
    private static let notificationDeviceFollowExt = "mediaStats,highlightedLabel,parodyCommentaryFanLabel,voiceInfo,birdwatchPivot,superFollowMetadata,unmentionInfo,editControl,article"
    private static let dmStratoExt = "mediaRestrictions,altText,mediaStats,mediaColor,info360,highlightedLabel,unmentionInfo,editControl,previousCounts,limitedActionResults,superFollowMetadata"

    private static func bool(_ value: Bool) -> String {
        value ? "true" : "false"
    }

    /// Depth-first search for the first string value under `key`.
    fileprivate static func deepFindString(_ node: Any, key: String) -> String? {
        if let dict = node as? [String: Any] {
            if let s = dict[key] as? String { return s }
            for (_, v) in dict { if let f = deepFindString(v, key: key) { return f } }
        } else if let arr = node as? [Any] {
            for v in arr { if let f = deepFindString(v, key: key) { return f } }
        }
        return nil
    }
}
