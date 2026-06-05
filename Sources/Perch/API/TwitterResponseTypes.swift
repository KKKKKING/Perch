import Foundation

// Codable structs matching the slice of X's GraphQL JSON that Perch consumes.
// Everything is optional because the API is sprawling and shapes drift between
// operations; the data mapper guards against missing pieces.

struct GQLResponse: Decodable {
    let data: GQLData?
    let errors: [GQLError]?
}

struct GQLError: Decodable {
    let message: String?
    let code: Int?
}

struct GQLData: Decodable {
    let home: GQLHome?
    let user: GQLUserResults?                                    // UserByRestId / UserByScreenName / UserTweets / Likes / Followers / ...
    let threaded_conversation_with_injections_v2: GQLTimeline?   // TweetDetail
    let bookmark_timeline_v2: GQLTimelineContainer?              // Bookmarks
    let bookmark_collection_timeline: GQLTimelineContainer?      // BookmarkFolderTimeline
    let search_by_raw_query: GQLSearch?                          // SearchTimeline
    let create_tweet: GQLCreateTweet?                            // CreateTweet
    let notetweet_create: GQLCreateTweet?                        // CreateNoteTweet
    let viewer: GQLViewer?                                       // BookmarkFoldersSlice / user lists / scheduled
    let viewer_v2: GQLViewerV2?                                  // NotificationsTimeline
    let tweetResult: GQLTweetResults?                            // TweetResultByRestId (single)
    let tweet_result_by_rest_id: GQLHistoryTweetResult?         // TweetEditHistory
    let favoriters_timeline: GQLTimelineContainer?              // Favoriters (likers)
    let retweeters_timeline: GQLTimelineContainer?              // Retweeters
    let list: GQLList?                                           // ListByRestId / ListLatestTweetsTimeline / ListMembers
    let audioSpace: GQLAudioSpace?                               // AudioSpaceById
    let user_result_by_screen_name: GQLAboutResults?            // AboutAccountQuery

    /// Timeline instructions from whichever root this particular operation populated.
    var timelineInstructions: [GQLInstruction]? {
        if let i = home?.home_timeline_urt?.instructions { return i }
        if let i = user?.result?.timeline_v2?.timeline?.instructions { return i }
        if let i = user?.result?.timeline?.timeline?.instructions { return i }
        if let i = threaded_conversation_with_injections_v2?.instructions { return i }
        if let i = bookmark_timeline_v2?.timeline?.instructions { return i }
        if let i = bookmark_collection_timeline?.timeline?.instructions { return i }
        if let i = search_by_raw_query?.search_timeline?.timeline?.instructions { return i }
        if let i = favoriters_timeline?.timeline?.instructions { return i }
        if let i = retweeters_timeline?.timeline?.instructions { return i }
        if let i = list?.tweets_timeline?.timeline?.instructions { return i }
        if let i = list?.members_timeline?.timeline?.instructions { return i }
        if let i = viewer?.list_management_timeline?.timeline?.instructions { return i }
        if let i = viewer_v2?.user_results?.result?.notification_timeline?.timeline?.instructions { return i }
        if let i = tweet_result_by_rest_id?.result?.edit_history_timeline?.timeline?.instructions { return i }
        return nil
    }
}

// ── Bookmark folders (BookmarkFoldersSlice) / user lists / scheduled tweets ──
struct GQLViewer: Decodable {
    let user_results: GQLUserResults?
    let list_management_timeline: GQLTimelineContainer?          // ListsManagementPageTimeline
    let scheduled_tweet_list: [GQLScheduledTweet]?               // FetchScheduledTweets
}

// ── Notifications GraphQL (NotificationsTimeline) ──
struct GQLViewerV2: Decodable {
    let user_results: GQLNotifUserResults?
}
struct GQLNotifUserResults: Decodable {
    let result: GQLNotifResult?
}
struct GQLNotifResult: Decodable {
    let rest_id: String?
    let notification_timeline: GQLNotificationTimeline?
}
struct GQLNotificationTimeline: Decodable {
    let id: String?
    let timeline: GQLTimeline?
}

// ── Tweet edit history (TweetEditHistory) ──
struct GQLHistoryTweetResult: Decodable {
    let result: GQLHistoryResult?
}
struct GQLHistoryResult: Decodable {
    let edit_history_timeline: GQLTimelineContainer?
}

// ── Scheduled tweets (FetchScheduledTweets) ──
struct GQLScheduledTweet: Decodable {
    let rest_id: String?
    let scheduling_info: GQLSchedulingInfo?
    let tweet_create_request: GQLScheduledRequest?
}
struct GQLSchedulingInfo: Decodable {
    let execute_at: Double?
    let state: String?
}
struct GQLScheduledRequest: Decodable {
    let status: String?
}

// ── List (ListByRestId / ListLatestTweetsTimeline / ListMembers) ──
struct GQLList: Decodable {
    let id_str: String?
    let name: String?
    let description: String?
    let member_count: Int?
    let subscriber_count: Int?
    let following: Bool?
    let is_member: Bool?
    let mode: String?
    let created_at: Double?
    let user_results: GQLUserResults?
    let tweets_timeline: GQLTimelineContainer?
    let members_timeline: GQLTimelineContainer?
}

// ── Space (AudioSpaceById) ──
struct GQLAudioSpace: Decodable {
    let metadata: GQLSpaceMetadata?
    let participants: GQLSpaceParticipants?
    let is_subscribed: Bool?
}
struct GQLSpaceMetadata: Decodable {
    let rest_id: String?
    let state: String?
    let title: String?
    let media_key: String?
    let created_at: Double?
    let started_at: Double?
    let ended_at: Double?
    let scheduled_start: Double?
    let creator_id: String?
    let total_live_listeners: Int?
    let total_replay_watched: Int?
    let participant_count: Int?
    let is_locked: Bool?
    let is_muted: Bool?
    let is_space_available_for_replay: Bool?
    let is_space_available_for_clipping: Bool?
}
struct GQLSpaceParticipants: Decodable {
    let total: Int?
    let admins: [GQLSpaceParticipant]?
    let speakers: [GQLSpaceParticipant]?
    let listeners: [GQLSpaceParticipant]?
}
struct GQLSpaceParticipant: Decodable {
    let twitter_screen_name: String?
    let display_name: String?
    let avatar_url: String?
    let is_verified: Bool?
}

// ── User about profile (AboutAccountQuery) ──
struct GQLAboutResults: Decodable {
    let result: GQLAboutResult?
    let id: String?
}
struct GQLAboutResult: Decodable {
    let __typename: String?
    let id: String?
    let rest_id: String?
    let core: GQLAboutCore?
    let avatar: UserAvatar?
    let profile_image_shape: String?
    let is_blue_verified: Bool?
    let privacy: GQLAboutPrivacy?
}
struct GQLAboutCore: Decodable {
    let name: String?
    let screen_name: String?
    let created_at: String?
}
struct GQLAboutPrivacy: Decodable {
    let protected: Bool?
}

struct GQLBookmarkCollectionsSlice: Decodable {
    let items: [GQLBookmarkFolderItem]?
    let slice_info: GQLSliceInfo?
}

struct GQLBookmarkFolderItem: Decodable {
    let id: String?
    let name: String?
}

struct GQLSliceInfo: Decodable {
    let next_cursor: String?
}

struct GQLHome: Decodable {
    let home_timeline_urt: GQLTimeline?
}

struct GQLTimeline: Decodable {
    let instructions: [GQLInstruction]?
}

struct GQLTimelineContainer: Decodable {
    let timeline: GQLTimeline?
}

struct GQLSearch: Decodable {
    let search_timeline: GQLTimelineContainer?
}

struct GQLCreateTweet: Decodable {
    let tweet_results: GQLTweetResults?
}

struct GQLInstruction: Decodable {
    let type: String?
    let entries: [GQLEntry]?
    let usersResults: [GQLUserResults]?   // TimelineShowAlert "new posts" avatars
    let alertType: String?                // "NewTweets"
    let displayLocation: String?          // "Top"
}

struct GQLEntry: Decodable {
    let entryId: String?
    let content: GQLContent?
}

struct GQLContent: Decodable {
    let entryType: String?
    let itemContent: GQLItemContent?
    let items: [GQLModuleItem]?
    let value: String?          // pagination cursor token (TimelineTimelineCursor)
    let cursorType: String?     // "Top" | "Bottom"
}

struct GQLModuleItem: Decodable {
    let item: GQLModuleItemInner?
}

struct GQLModuleItemInner: Decodable {
    let itemContent: GQLItemContent?
}

struct GQLItemContent: Decodable {
    let itemType: String?
    let tweet_results: GQLTweetResults?
    let user_results: GQLUserResults?          // user timelines (followers / following / likers / ...)
    let list: GQLList?                         // list timelines (ListsManagementPageTimeline)
}

// ── Bulk user details (UsersByRestIds) — `data.users` is an array ──
struct GQLBulkUsersResponse: Decodable {
    let data: GQLBulkUsersData?
    let errors: [GQLError]?
}
struct GQLBulkUsersData: Decodable {
    let users: [GQLUserResults]?
}

// ── Bulk tweet details (TweetResultsByRestIds) — `data.tweetResult` is an array ──
struct GQLBulkTweetResponse: Decodable {
    let data: GQLBulkTweetData?
    let errors: [GQLError]?
}
struct GQLBulkTweetData: Decodable {
    let tweetResult: [GQLTweetResults]?
}

struct GQLTweetResults: Decodable {
    let result: TweetResultNode?
}

/// A tweet node. May be a plain `Tweet`, or a `TweetWithVisibilityResults`
/// wrapper whose real payload lives under `.tweet`.
final class TweetResultNode: Decodable {
    let __typename: String?
    let rest_id: String?
    let core: UserCoreContainer?
    let legacy: TweetLegacy?
    let views: GQLViews?
    let quoted_status_result: GQLTweetResults?
    let tweet: TweetResultNode?           // present on TweetWithVisibilityResults
    let note_tweet: GQLNoteTweet?         // long-form full text
    let card: GQLCard?                    // link / article preview
    let article: GQLArticle?              // X Article (long-form native content)

    enum CodingKeys: String, CodingKey {
        case __typename, rest_id, core, legacy, views, quoted_status_result, tweet, note_tweet, card, article
    }

    /// Unwrap the visibility wrapper so callers always see the real tweet.
    var unwrapped: TweetResultNode {
        if __typename == "TweetWithVisibilityResults", let t = tweet { return t }
        return tweet ?? self
    }
}

struct GQLViews: Decodable {
    let count: String?
}

struct GQLNoteTweet: Decodable {
    let note_tweet_results: GQLNoteTweetResults?
}

// MARK: - Link / article card (tweet.card.legacy.binding_values)

struct GQLCard: Decodable {
    let legacy: GQLCardLegacy?
}

struct GQLCardLegacy: Decodable {
    let name: String?
    let url: String?
    let binding_values: [GQLBindingValue]?
}

struct GQLBindingValue: Decodable {
    let key: String?
    let value: GQLBindingValueData?
}

struct GQLBindingValueData: Decodable {
    let string_value: String?
    let image_value: GQLCardImage?
}

struct GQLCardImage: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

struct GQLNoteTweetResults: Decodable {
    let result: GQLNoteTweetResult?
}

struct GQLNoteTweetResult: Decodable {
    let text: String?
    let entity_set: GQLNoteTweetEntitySet?
}

struct GQLNoteTweetEntitySet: Decodable {
    let urls: [GQLURLEntity]?
}

// MARK: - X Article (tweet.article.article_results.result)

struct GQLArticle: Decodable {
    let article_results: GQLArticleResults?
}

struct GQLArticleResults: Decodable {
    let result: GQLArticleResult?
}

struct GQLArticleResult: Decodable {
    let rest_id: String?
    let title: String?
    let preview_text: String?
    let cover_media: GQLArticleMedia?
}

struct GQLArticleMedia: Decodable {
    let media_info: GQLArticleMediaInfo?
}

struct GQLArticleMediaInfo: Decodable {
    let original_img_url: String?
    let original_img_width: Int?
    let original_img_height: Int?
}

struct UserCoreContainer: Decodable {
    let user_results: GQLUserResults?
}

struct GQLUserResults: Decodable {
    let result: UserResultNode?
}

final class UserResultNode: Decodable {
    let rest_id: String?
    let is_blue_verified: Bool?
    let legacy: UserLegacy?
    let core: UserCoreFields?       // newer shape: name/screen_name moved here
    let avatar: UserAvatar?         // newest shape: profile image moved here
    let timeline_v2: GQLTimelineContainer?   // present on UserTweets / Likes
    let timeline: GQLTimelineContainer?      // older shape of the same
    let bookmark_collections_slice: GQLBookmarkCollectionsSlice?   // BookmarkFoldersSlice

    var screenName: String? { core?.screen_name ?? legacy?.screen_name }
    var displayName: String? { core?.name ?? legacy?.name }
    var verified: Bool { (is_blue_verified ?? false) || (legacy?.verified ?? false) }
    var avatarURL: String? { avatar?.image_url ?? legacy?.profile_image_url_https }
}

struct UserCoreFields: Decodable {
    let name: String?
    let screen_name: String?
}

struct UserAvatar: Decodable {
    let image_url: String?
}

struct UserLegacy: Decodable {
    let screen_name: String?
    let name: String?
    let verified: Bool?
    let ext_is_blue_verified: Bool?       // v2 REST users map
    let profile_image_url_https: String?
    let description: String?              // bio (follow notifications)
    let followers_count: Int?
    let friends_count: Int?
    let location: String?
    let created_at: String?
    // viewer-perspective relationship flags (present on authed user objects)
    let following: Bool?
    let followed_by: Bool?
    let blocking: Bool?
    let muting: Bool?
}

struct TweetLegacy: Decodable {
    let full_text: String?
    let created_at: String?
    let reply_count: Int?
    let retweet_count: Int?
    let favorite_count: Int?
    let quote_count: Int?
    let favorited: Bool?
    let retweeted: Bool?
    let bookmarked: Bool?
    let conversation_id_str: String?
    let in_reply_to_status_id_str: String?
    let display_text_range: [Int]?
    let user_id_str: String?              // v2 REST: author lives in globalObjects.users
    let quoted_status_id_str: String?     // v2 REST: quote target id
    let retweeted_status_result: GQLTweetResults?
    let extended_entities: GQLExtendedEntities?
    let entities: GQLEntities?
}

struct GQLEntities: Decodable {
    let media: [GQLMedia]?
    let urls: [GQLURLEntity]?
}

struct GQLURLEntity: Decodable {
    let url: String?            // t.co shortened
    let expanded_url: String?   // original destination
    let display_url: String?    // domain-only display form
}

struct GQLExtendedEntities: Decodable {
    let media: [GQLMedia]?
}

struct GQLOriginalInfo: Decodable {
    let width: Int?
    let height: Int?
}

struct GQLMedia: Decodable {
    let type: String?               // "photo" | "video" | "animated_gif"
    let media_url_https: String?
    let display_url: String?
    let expanded_url: String?
    let video_info: GQLVideoInfo?
    let ext_alt_text: String?
    let original_info: GQLOriginalInfo?
}

struct GQLVideoInfo: Decodable {
    let duration_millis: Int?
    let aspect_ratio: [Int]?        // [width, height]
    let variants: [GQLVideoVariant]?
}

struct GQLVideoVariant: Decodable {
    let bitrate: Int?
    let content_type: String?
    let url: String?
}

// MARK: - v2 REST notifications (2/notifications/all.json)
// Legacy "globalObjects + timeline.instructions" shape, ported from Flare's
// xqt `TopLevel.kt`. All optional; the mapper skips anything it can't resolve.

struct NotifTopLevel: Decodable {
    let globalObjects: NotifGlobalObjects?
    let timeline: NotifTimeline?
}

struct NotifGlobalObjects: Decodable {
    let users: [String: UserLegacy]?
    let tweets: [String: TweetLegacy]?
    let notifications: [String: NotifObject]?
}

struct NotifObject: Decodable {
    let id: String?
    let timestampMs: String?
    let icon: NotifIconRef?
    let message: NotifMessage?
    let template: NotifTemplate?
}

struct NotifIconRef: Decodable { let id: String? }

struct NotifMessage: Decodable { let text: String? }

struct NotifTemplate: Decodable {
    let aggregateUserActionsV1: NotifAggregate?
}

struct NotifAggregate: Decodable {
    let targetObjects: [NotifTargetObject]?
    let fromUsers: [NotifUserRef]?
}

struct NotifTargetObject: Decodable { let tweet: NotifIdRef? }
struct NotifUserRef: Decodable { let user: NotifIdRef? }
struct NotifIdRef: Decodable { let id: String? }

struct NotifTimeline: Decodable {
    let instructions: [NotifInstruction]?
}

struct NotifInstruction: Decodable {
    let addEntries: NotifAddEntries?
}

struct NotifAddEntries: Decodable {
    let entries: [NotifEntry]?
}

struct NotifEntry: Decodable {
    let entryId: String?
    let sortIndex: String?
    let content: NotifEntryContent?
}

struct NotifEntryContent: Decodable {
    let item: NotifItemWrap?
    let operation: NotifOperation?
}

struct NotifItemWrap: Decodable {
    let content: NotifItemContent?
}

struct NotifItemContent: Decodable {
    let tweet: NotifIdRef?              // mention/reply/quote → globalObjects.tweets[id]
    let notification: NotifEntryRef?   // aggregated → globalObjects.notifications[id]
}

struct NotifEntryRef: Decodable {
    let id: String?
    let fromUsers: [String]?
    let targetTweets: [String]?
}

struct NotifOperation: Decodable {
    let cursor: NotifCursor?
}

struct NotifCursor: Decodable {
    let value: String?
    let cursorType: String?            // "Top" | "Bottom"
}
