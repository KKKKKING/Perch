import AppKit

/// Maps decoded GraphQL tweet nodes into Perch's view models.
enum TwitterDataMapper {

    private static let colorTokens = [
        "indigo-700", "seafoam-700", "magenta-700", "purple-700",
        "cyan-800", "green-700", "orange-700",
    ]

    private static let gradients = Gradients.pool

    private static func hash(_ s: String) -> Int {
        var sum = 0
        for u in s.utf16 { sum = (sum &* 31 &+ Int(u)) & 0x7fffffff }
        return sum
    }

    static func currentUser(from user: UserResultNode?) -> CurrentUser? {
        guard let user, let id = user.rest_id, let handle = user.screenName else { return nil }
        return CurrentUser(id: id, username: handle, name: user.displayName ?? handle)
    }

    static func person(from user: UserResultNode?) -> Person {
        let handle = user?.screenName ?? "unknown"
        let name = user?.displayName ?? handle
        let token = colorTokens[hash(handle) % colorTokens.count]
        let p = Person(id: user?.rest_id, name: name, handle: handle, colorToken: token,
                       verified: user?.verified ?? false, platform: .x,
                       avatarURL: user?.avatarURL)
        p.relationship = relationship(from: user?.legacy)
        return p
    }

    /// Viewer-perspective relationship flags, when X included any of them.
    private static func relationship(from legacy: UserLegacy?) -> Person.Relationship? {
        guard let legacy,
              legacy.following != nil || legacy.followed_by != nil
              || legacy.blocking != nil || legacy.muting != nil else { return nil }
        return Person.Relationship(following: legacy.following, followedBy: legacy.followed_by,
                                   muting: legacy.muting, blocking: legacy.blocking)
    }

    /// Build a profile (bio / location / joined / counts) from a GraphQL user node.
    static func profile(from user: UserResultNode?) -> Profile {
        let legacy = user?.legacy
        let followers = legacy?.followers_count.map { formatCount(String($0)) } ?? "—"
        let following = legacy?.friends_count.map { formatCount(String($0)) } ?? "—"
        return Profile(bio: legacy?.description ?? "",
                       location: legacy?.location ?? "",
                       joined: joinedString(legacy?.created_at),
                       followers: followers,
                       following: following,
                       banner: Gradients.forSeed(user?.screenName ?? "x"))
    }

    /// "Wed Oct 10 20:19:24 +0000 2018" → "Joined October 2018".
    private static func joinedString(_ raw: String?) -> String {
        guard let raw else { return "" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        guard let date = fmt.date(from: raw) else { return "" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "MMMM yyyy"
        return "Joined " + out.string(from: date)
    }

    /// "Wed Oct 10 20:19:24 +0000 2018" → relative ("2m", "1h", "Jan 5").
    static func relativeTime(_ raw: String?) -> String {
        guard let date = TimelineDate.date(fromTwitter: raw) else { return "" }
        return TimelineDate.relativeTime(from: date)
    }

    private static func media(from legacy: TweetLegacy?) -> Media? {
        let items = legacy?.extended_entities?.media ?? legacy?.entities?.media ?? []
        guard !items.isEmpty else { return nil }
        if let video = items.first(where: { $0.type == "video" || $0.type == "animated_gif" }) {
            let ms = video.video_info?.duration_millis ?? 0
            let dur = ms > 0 ? String(format: "%d:%02d", ms / 60000, (ms / 1000) % 60) : nil
            var aspect: CGFloat? = nil
            if let ar = video.video_info?.aspect_ratio, ar.count == 2, ar[1] > 0 {
                aspect = CGFloat(ar[0]) / CGFloat(ar[1])
            }
            let item = MediaItem(url: video.media_url_https,
                                 grad: grad(for: video.media_url_https ?? "v"),
                                 videoURL: bestVariant(video.video_info?.variants),
                                 alt: video.ext_alt_text,
                                 aspect: aspect)
            return Media(type: .video, dur: dur, item: item)
        }
        let photos = items.filter { $0.type == "photo" }
        if !photos.isEmpty {
            return Media(type: .images, items: photos.map { p in
                var aspect: CGFloat? = nil
                if let w = p.original_info?.width, let h = p.original_info?.height, h > 0 {
                    aspect = CGFloat(w) / CGFloat(h)
                }
                return MediaItem(url: p.media_url_https, grad: grad(for: p.media_url_https ?? "p"),
                                 videoURL: nil, alt: p.ext_alt_text, aspect: aspect)
            })
        }
        return nil
    }

    /// Map a tweet's link/article card (`card.legacy.binding_values`) to a `.link`
    /// Media. Skips non-article cards (polls, spaces). Returns nil when there's no
    /// usable title — those degrade to plain link text.
    private static func card(from node: TweetResultNode) -> Media? {
        guard let legacy = node.card?.legacy, let name = legacy.name,
              !name.hasPrefix("poll"), !name.contains("audiospace"),
              let values = legacy.binding_values else { return nil }
        var map: [String: GQLBindingValueData] = [:]
        for b in values { if let k = b.key, let v = b.value { map[k] = v } }
        let title = map["title"]?.string_value ?? ""
        guard !title.isEmpty else { return nil }
        let desc = map["description"]?.string_value ?? ""
        let domain = map["vanity_url"]?.string_value ?? map["domain"]?.string_value
            ?? hostName(legacy.url)
        let thumbKeys = ["thumbnail_image_large", "photo_image_full_size_large",
                         "summary_photo_image_large", "thumbnail_image",
                         "player_image_large", "player_image"]
        var thumbURL: String? = nil
        var thumbAspect: CGFloat? = nil
        for key in thumbKeys {
            guard let img = map[key]?.image_value else { continue }
            if thumbURL == nil { thumbURL = img.url }
            if thumbAspect == nil, let w = img.width, let h = img.height, h > 0 {
                thumbAspect = CGFloat(w) / CGFloat(h)
            }
            if thumbURL != nil, thumbAspect != nil { break }
        }
        let item = MediaItem(url: thumbURL, grad: grad(for: thumbURL ?? title),
                             videoURL: nil, alt: nil, aspect: thumbAspect)
        let url = map["card_url"]?.string_value ?? legacy.url
        return Media(type: .link, title: title, desc: desc, domain: domain, url: url, item: item)
    }

    /// Map an X Article (`tweet.article.article_results.result`) to a `.link` Media.
    private static func article(from node: TweetResultNode) -> Media? {
        guard let a = node.article?.article_results?.result else { return nil }
        let title = a.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let desc = a.preview_text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let info = a.cover_media?.media_info
        var thumbAspect: CGFloat? = nil
        if let w = info?.original_img_width, let h = info?.original_img_height, h > 0 {
            thumbAspect = CGFloat(w) / CGFloat(h)
        }
        let item = MediaItem(url: info?.original_img_url, grad: grad(for: info?.original_img_url ?? title),
                             videoURL: nil, alt: nil, aspect: thumbAspect)
        let handle = node.core?.user_results?.result?.screenName
        let articleURL: String?
        if let tweetId = node.rest_id, let handle {
            articleURL = "https://x.com/\(handle)/status/\(tweetId)"
        } else {
            articleURL = nil
        }
        return Media(type: .link, title: title, desc: desc, domain: "Article", url: articleURL, item: item)
    }

    /// Display host for a URL ("https://www.riverside.co/x" → "riverside.co").
    private static func hostName(_ urlStr: String?) -> String? {
        guard let urlStr, let host = URL(string: urlStr)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Pick the highest-bitrate mp4 variant for video playback.
    private static func bestVariant(_ variants: [GQLVideoVariant]?) -> String? {
        guard let variants else { return nil }
        return variants
            .filter { $0.content_type == "video/mp4" && $0.url != nil }
            .max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })?.url
    }

    private static func grad(for url: String) -> Gradient {
        gradients[hash(url) % gradients.count]
    }

    private static func displayText(_ text: String, range: [Int]?) -> String {
        guard let range, range.count == 2, range[0] >= 0, range[1] >= range[0] else { return text }
        guard let start = text.index(text.startIndex, offsetBy: range[0], limitedBy: text.endIndex),
              let end = text.index(text.startIndex, offsetBy: range[1], limitedBy: text.endIndex) else {
            return text
        }
        return String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func legacyText(_ legacy: TweetLegacy?) -> String {
        displayText(legacy?.full_text ?? "", range: legacy?.display_text_range)
    }

    static func fullText(_ node: TweetResultNode) -> String {
        if let note = node.note_tweet?.note_tweet_results?.result?.text, !note.isEmpty { return note }
        return legacyText(node.legacy)
    }

    static func urlEntities(_ node: TweetResultNode) -> [GQLURLEntity] {
        if let noteUrls = node.note_tweet?.note_tweet_results?.result?.entity_set?.urls, !noteUrls.isEmpty {
            return noteUrls
        }
        return node.legacy?.entities?.urls ?? []
    }

    static func expandURLs(in text: String, entities: [GQLURLEntity]) -> (String, [String: String]) {
        var result = text
        var urlMap: [String: String] = [:]
        for e in entities {
            guard let tco = e.url, let expanded = e.expanded_url else { continue }
            result = result.replacingOccurrences(of: tco, with: expanded)
            urlMap[expanded] = expanded
        }
        return (result, urlMap)
    }

    /// Maps a timeline node into a `Post`. Resolves retweets to the original
    /// author (recording `repostedBy`) and attaches quoted tweets.
    static func post(from rawNode: TweetResultNode) -> Post? {
        let node = rawNode.unwrapped
        // Retweet: show the original, credited as reposted.
        if let rt = node.legacy?.retweeted_status_result?.result?.unwrapped {
            if let base = post(from: rt) {
                let reposter = node.core?.user_results?.result
                base.repostedBy = reposter?.displayName ?? reposter?.screenName
                return base
            }
        }
        guard let legacy = node.legacy, let id = node.rest_id else { return nil }
        let author = person(from: node.core?.user_results?.result)

        let postMedia = media(from: legacy) ?? article(from: node) ?? card(from: node)
        var quote: Quote?
        var quoteSrcId: String?
        if let q = node.quoted_status_result?.result?.unwrapped, let qLegacy = q.legacy {
            quoteSrcId = q.rest_id
            let qAuthor = person(from: q.core?.user_results?.result)
            let qMedia = media(from: qLegacy) ?? article(from: q) ?? card(from: q)
            let (qText, _) = expandURLs(in: fullText(q), entities: urlEntities(q))
            quote = Quote(author: qAuthor,
                          time: relativeTime(qLegacy.created_at),
                          text: qText,
                          media: qMedia,
                          createdAt: TimelineDate.date(fromTwitter: qLegacy.created_at))
        }

        let stats = Stats(
            replies: legacy.reply_count,
            reposts: legacy.retweet_count ?? 0,
            likes: legacy.favorite_count ?? 0,
            views: node.views?.count.map { formatCount($0) },
            quotes: legacy.quote_count
        )

        let (expandedText, urlMap) = expandURLs(in: fullText(node), entities: urlEntities(node))
        let p = Post(
            id: id,
            author: author,
            time: relativeTime(legacy.created_at),
            text: expandedText,
            media: postMedia,
            stats: stats,
            liked: legacy.favorited ?? false,
            reposted: legacy.retweeted ?? false,
            bookmarked: legacy.bookmarked ?? false,
            quote: quote,
            quoteSrcId: quoteSrcId,
            replyToId: legacy.in_reply_to_status_id_str,
            conversationId: legacy.conversation_id_str,
            createdAt: TimelineDate.date(fromTwitter: legacy.created_at)
        )
        p.urlMap = urlMap
        return p
    }

    static func posts(from nodes: [TweetResultNode]) -> [Post] {
        var seen = Set<String>()
        var out: [Post] = []
        for n in nodes {
            guard let p = post(from: n), !seen.contains(p.id) else { continue }
            seen.insert(p.id)
            out.append(p)
        }
        return out
    }

    /// Map grouped timeline entries into a flat `[Post]`, flagging consecutive
    /// posts of a conversation thread so the feed can draw a connecting line.
    /// Reposts/quotes break a thread (they're standalone), so only chains of
    /// plain tweets are connected.
    static func posts(fromGroups groups: [[TweetResultNode]]) -> [Post] {
        var seen = Set<String>()
        var out: [Post] = []
        for group in groups {
            var thread: [Post] = []
            for n in group {
                guard let p = post(from: n), p.repostedBy == nil, seen.insert(p.id).inserted else { continue }
                thread.append(p)
            }
            if thread.count >= 2 {
                for (i, p) in thread.enumerated() {
                    p.connectTop = i > 0
                    p.connectBottom = i < thread.count - 1
                }
            }
            out.append(contentsOf: thread)
        }
        return out
    }

    static func tweetIds(from nodes: [TweetResultNode]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for node in nodes {
            collectTweetIds(from: node, seen: &seen, out: &out)
        }
        return out
    }

    static func tweetIds(fromGroups groups: [[TweetResultNode]]) -> [String] {
        tweetIds(from: groups.flatMap { $0 })
    }

    private static func collectTweetIds(from rawNode: TweetResultNode?, seen: inout Set<String>, out: inout [String]) {
        guard let rawNode else { return }
        let node = rawNode.unwrapped
        if let id = node.rest_id, seen.insert(id).inserted {
            out.append(id)
        }
        collectTweetIds(from: node.legacy?.retweeted_status_result?.result, seen: &seen, out: &out)
        collectTweetIds(from: node.quoted_status_result?.result, seen: &seen, out: &out)
    }

    // MARK: - v2 REST notifications (legacy globalObjects shape)

    /// Build a `Person` from a flat legacy user record (v2 `globalObjects.users`).
    static func person(fromLegacy user: UserLegacy?, id: String?) -> Person {
        let handle = user?.screen_name ?? "unknown"
        let name = user?.name ?? handle
        let token = colorTokens[hash(handle) % colorTokens.count]
        let verified = (user?.verified ?? false) || (user?.ext_is_blue_verified ?? false)
        return Person(id: id, name: name, handle: handle, colorToken: token,
                      verified: verified, platform: .x,
                      avatarURL: user?.profile_image_url_https)
    }

    /// Build a `Post` from a flat legacy tweet record. Author and (optional)
    /// quote are resolved out of the same `users`/`tweets` maps.
    static func post(fromLegacy legacy: TweetLegacy, id: String,
                     users: [String: UserLegacy], tweets: [String: TweetLegacy]) -> Post {
        let author = person(fromLegacy: legacy.user_id_str.flatMap { users[$0] }, id: legacy.user_id_str)
        let postMedia = media(from: legacy)
        var quote: Quote?
        var legacyQuoteSrcId: String?
        if let qid = legacy.quoted_status_id_str, let q = tweets[qid] {
            legacyQuoteSrcId = qid
            let qAuthor = person(fromLegacy: q.user_id_str.flatMap { users[$0] }, id: q.user_id_str)
            let qMedia = media(from: q)
            quote = Quote(author: qAuthor,
                          time: relativeTime(q.created_at),
                          text: legacyText(q),
                          media: qMedia,
                          createdAt: TimelineDate.date(fromTwitter: q.created_at))
        }
        let stats = Stats(replies: legacy.reply_count,
                          reposts: legacy.retweet_count ?? 0,
                          likes: legacy.favorite_count ?? 0,
                          views: nil,
                          quotes: legacy.quote_count)
        return Post(id: id, author: author, time: relativeTime(legacy.created_at),
                    text: legacyText(legacy), media: postMedia, stats: stats,
                    liked: legacy.favorited ?? false, reposted: legacy.retweeted ?? false,
                    bookmarked: legacy.bookmarked ?? false, quote: quote,
                    quoteSrcId: legacyQuoteSrcId,
                    createdAt: TimelineDate.date(fromTwitter: legacy.created_at))
    }

    /// Parse the v2 notifications payload into the notification feed. Notification
    /// objects become aggregated like/repost/follow rows; bare tweet entries become
    /// reply/mention/quote engagement cards. Anything unmappable is skipped.
    static func notifications(from top: NotifTopLevel) -> [NotifItem] {
        let users = top.globalObjects?.users ?? [:]
        let tweets = top.globalObjects?.tweets ?? [:]
        let notifs = top.globalObjects?.notifications ?? [:]
        var out: [NotifItem] = []
        var seen = Set<String>()

        for instr in top.timeline?.instructions ?? [] {
            for entry in instr.addEntries?.entries ?? [] {
                guard let content = entry.content?.item?.content else { continue }

                // Aggregated notification (like / repost / follow).
                if let ref = content.notification, let nid = ref.id, let data = notifs[nid] {
                    guard let kind = notifKind(forIcon: data.icon?.id) else { continue }
                    let actorIds = data.template?.aggregateUserActionsV1?.fromUsers?.compactMap { $0.user?.id }
                        ?? ref.fromUsers ?? []
                    let actors = actorIds.map { person(fromLegacy: users[$0], id: $0) }
                    guard !actors.isEmpty else { continue }
                    let targetId = ref.targetTweets?.first
                        ?? data.template?.aggregateUserActionsV1?.targetObjects?.first?.tweet?.id
                    let post = targetId.flatMap { tweets[$0] }.map {
                        TwitterDataMapper.post(fromLegacy: $0, id: targetId!, users: users, tweets: tweets)
                    }
                    let single = kind == .follow && actors.count == 1
                    let bio = single ? actorIds.first.flatMap { users[$0]?.description } : nil
                    guard seen.insert(nid).inserted else { continue }
                    out.append(NotifItem(id: nid, kind: kind, actors: actors, count: actors.count,
                                         time: relativeTimeMs(data.timestampMs), unread: true,
                                         post: post, bio: bio, single: single))
                    continue
                }

                // Bare tweet entry (reply / mention / quote).
                if let tid = content.tweet?.id, let legacy = tweets[tid] {
                    guard let author = legacy.user_id_str else { continue }
                    let kind: NotifKind
                    var post: Post?
                    if let qid = legacy.quoted_status_id_str, tweets[qid] != nil {
                        kind = .quote
                        post = TwitterDataMapper.post(fromLegacy: legacy, id: tid, users: users, tweets: tweets)
                    } else if let parentId = legacy.in_reply_to_status_id_str {
                        kind = .reply
                        post = tweets[parentId].map {
                            TwitterDataMapper.post(fromLegacy: $0, id: parentId, users: users, tweets: tweets)
                        }
                    } else {
                        kind = .mention
                        post = TwitterDataMapper.post(fromLegacy: legacy, id: tid, users: users, tweets: tweets)
                    }
                    let actor = person(fromLegacy: users[author], id: author)
                    let key = "t_\(tid)"
                    guard seen.insert(key).inserted else { continue }
                    out.append(NotifItem(id: key, kind: kind, actors: [actor], count: 1,
                                         time: relativeTime(legacy.created_at), unread: true,
                                         post: post, text: kind == .reply ? legacy.full_text : nil))
                }
            }
        }
        return out
    }

    private static func notifKind(forIcon icon: String?) -> NotifKind? {
        switch icon {
        case "heart_icon": return .like
        case "retweet_icon": return .repost
        case "person_icon": return .follow
        default: return nil
        }
    }

    /// Relative time from an epoch-millis string ("1700000000000" → "2m").
    private static func relativeTimeMs(_ ms: String?) -> String {
        guard let ms, let millis = Double(ms) else { return "" }
        let date = Date(timeIntervalSince1970: millis / 1000)
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

    // MARK: - Rettiwt-ported entities

    /// Map a list of GraphQL user nodes into `Person`s (followers / following / likers / ...).
    static func people(from nodes: [UserResultNode]) -> [Person] {
        var seen = Set<String>()
        var out: [Person] = []
        for n in nodes {
            let p = person(from: n)
            let key = p.id ?? p.handle
            guard seen.insert(key).inserted else { continue }
            out.append(p)
        }
        return out
    }

    static func list(from gql: GQLList?) -> TwitterList? {
        guard let gql, let id = gql.id_str else { return nil }
        return TwitterList(
            id: id,
            name: gql.name ?? "",
            description: (gql.description?.isEmpty == false) ? gql.description : nil,
            memberCount: gql.member_count ?? 0,
            subscriberCount: gql.subscriber_count ?? 0,
            isFollowing: gql.following ?? false,
            isMember: gql.is_member ?? false,
            mode: gql.mode,
            createdById: gql.user_results?.result?.rest_id,
            createdAt: dateFromMs(gql.created_at)
        )
    }

    static func space(from gql: GQLAudioSpace?) -> TwitterSpace? {
        guard let gql, let m = gql.metadata, let id = m.rest_id else { return nil }
        let p = gql.participants
        return TwitterSpace(
            id: id,
            state: m.state,
            title: m.title,
            mediaKey: m.media_key,
            createdAt: dateFromMs(m.created_at),
            startedAt: dateFromMs(m.started_at),
            endedAt: dateFromMs(m.ended_at),
            scheduledStart: dateFromMs(m.scheduled_start),
            creatorId: m.creator_id,
            participantCount: p?.total ?? m.participant_count,
            totalLiveListeners: m.total_live_listeners,
            totalReplayWatched: m.total_replay_watched,
            isSubscribed: gql.is_subscribed,
            admins: (p?.admins ?? []).map(spaceParticipant),
            speakers: (p?.speakers ?? []).map(spaceParticipant),
            listeners: (p?.listeners ?? []).map(spaceParticipant)
        )
    }

    private static func spaceParticipant(_ p: GQLSpaceParticipant) -> TwitterSpaceParticipant {
        TwitterSpaceParticipant(id: nil, screenName: p.twitter_screen_name,
                                displayName: p.display_name, avatarURL: p.avatar_url,
                                isVerified: p.is_verified)
    }

    static func userAbout(from gql: GQLAboutResult?) -> TwitterUserAbout? {
        guard let gql, let id = gql.rest_id ?? gql.id else { return nil }
        return TwitterUserAbout(
            id: id,
            userName: gql.core?.screen_name ?? "",
            fullName: gql.core?.name ?? "",
            createdAt: TimelineDate.date(fromTwitter: gql.core?.created_at),
            profileImage: gql.avatar?.image_url,
            profileImageShape: gql.profile_image_shape,
            isVerified: gql.is_blue_verified ?? false,
            isProtected: gql.privacy?.protected
        )
    }

    static func scheduledTweets(from items: [GQLScheduledTweet]?) -> [TwitterScheduledTweet] {
        (items ?? []).compactMap { item in
            guard let id = item.rest_id else { return nil }
            return TwitterScheduledTweet(id: id,
                                         status: item.tweet_create_request?.status,
                                         state: item.scheduling_info?.state,
                                         executeAt: item.scheduling_info?.execute_at.map {
                                             Date(timeIntervalSince1970: $0)
                                         })
        }
    }

    // ── Direct messages (REST 1.1, dynamic-keyed JSON) ──

    /// Parse a DM inbox payload (`inbox_initial_state` or `inbox_timeline`).
    static func dmInbox(fromJSON json: [String: Any]) -> DMInbox {
        if let initial = json["inbox_initial_state"] as? [String: Any] {
            return DMInbox(conversations: dmConversations(from: initial),
                           cursor: initial["cursor"] as? String)
        }
        if let timeline = json["inbox_timeline"] as? [String: Any] {
            return DMInbox(conversations: dmConversations(from: timeline),
                           cursor: timeline["min_entry_id"] as? String)
        }
        return DMInbox(conversations: [], cursor: nil)
    }

    /// Parse a single conversation payload (`conversation_timeline`).
    static func dmConversation(fromJSON json: [String: Any]) -> DMConversation? {
        guard let ct = json["conversation_timeline"] as? [String: Any] else { return nil }
        let convs = dmConversations(from: ct)
        return convs.first
    }

    private static func dmConversations(from container: [String: Any]) -> [DMConversation] {
        let rawConvs = container["conversations"] as? [String: Any] ?? [:]
        let entries = container["entries"] as? [[String: Any]] ?? []

        var messagesByConv: [String: [DMMessage]] = [:]
        for entry in entries {
            guard let msg = entry["message"] as? [String: Any],
                  let m = dmMessage(from: msg) else { continue }
            messagesByConv[m.conversationId, default: []].append(m)
        }

        var out: [DMConversation] = []
        for (_, value) in rawConvs {
            guard let conv = value as? [String: Any],
                  let id = conv["conversation_id"] as? String else { continue }
            let participants = (conv["participants"] as? [[String: Any]] ?? [])
                .compactMap { $0["user_id"] as? String }
            let type = (conv["type"] as? String) ?? "ONE_TO_ONE"
            out.append(DMConversation(id: id, type: type,
                                      name: conv["name"] as? String,
                                      avatarURL: conv["avatar_image_https"] as? String,
                                      participants: participants,
                                      messages: messagesByConv[id] ?? []))
        }
        return out
    }

    private static func dmMessage(from msg: [String: Any]) -> DMMessage? {
        let data = msg["message_data"] as? [String: Any]
        let id = (data?["id"] as? String) ?? (msg["id"].map { "\($0)" }) ?? ""
        guard !id.isEmpty else { return nil }
        let convId = (msg["conversation_id"] as? String) ?? (data?["conversation_id"] as? String) ?? ""
        let sender = (data?["sender_id"] as? String) ?? (msg["sender_id"] as? String) ?? ""
        let text = (data?["text"] as? String) ?? (msg["text"] as? String) ?? ""
        let timeStr = (data?["time"] as? String) ?? (msg["time"] as? String)
        let created = timeStr.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0 / 1000) }
        return DMMessage(id: id, conversationId: convId, senderId: sender,
                         recipientId: data?["recipient_id"] as? String, text: text, createdAt: created)
    }

    /// Best-effort analytics overview parse (AccountOverviewQuery is deeply nested).
    static func analytics(fromJSON json: [String: Any]) -> TwitterAnalytics {
        let payload = (json["data"] as? [String: Any]) ?? json
        var followers: Int?
        var verified: Int?
        if let counts = findFirst(payload, key: "relationship_counts") as? [String: Any] {
            followers = counts["followers"] as? Int
        }
        if let v = findFirst(payload, key: "verified_follower_count") {
            verified = (v as? Int) ?? Int("\(v)")
        }
        return TwitterAnalytics(followers: followers, verifiedFollowers: verified, raw: payload)
    }

    /// Depth-first search for the first value under `key` anywhere in a JSON tree.
    private static func findFirst(_ node: Any, key: String) -> Any? {
        if let dict = node as? [String: Any] {
            if let v = dict[key] { return v }
            for (_, v) in dict { if let found = findFirst(v, key: key) { return found } }
        } else if let arr = node as? [Any] {
            for v in arr { if let found = findFirst(v, key: key) { return found } }
        }
        return nil
    }

    private static func dateFromMs(_ ms: Double?) -> Date? {
        guard let ms, ms > 0 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    private static func formatCount(_ raw: String) -> String {
        guard let n = Int(raw) else { return raw }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}
