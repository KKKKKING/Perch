import Foundation

// Lightweight, view-friendly DTOs for the Rettiwt-ported operations that return
// entities Perch did not previously model (lists, spaces, about profiles, scheduled
// tweets, direct messages, analytics). They mirror Rettiwt-API's `models/data/*`
// shapes, keeping the most useful fields; deep/rarely-used structures fall back to
// the raw JSON dictionary.

/// A Twitter List (ListByRestId / ListsManagementPageTimeline).
struct TwitterList {
    let id: String
    let name: String
    var description: String?
    var memberCount: Int
    var subscriberCount: Int
    var isFollowing: Bool
    var isMember: Bool
    var mode: String?
    var createdById: String?
    var createdAt: Date?
}

/// A participant in a Space.
struct TwitterSpaceParticipant {
    var id: String?
    var screenName: String?
    var displayName: String?
    var avatarURL: String?
    var isVerified: Bool?
}

/// A Space (AudioSpaceById).
struct TwitterSpace {
    let id: String
    var state: String?
    var title: String?
    var mediaKey: String?
    var createdAt: Date?
    var startedAt: Date?
    var endedAt: Date?
    var scheduledStart: Date?
    var creatorId: String?
    var participantCount: Int?
    var totalLiveListeners: Int?
    var totalReplayWatched: Int?
    var isSubscribed: Bool?
    var admins: [TwitterSpaceParticipant]
    var speakers: [TwitterSpaceParticipant]
    var listeners: [TwitterSpaceParticipant]
}

/// A user's "about" profile (AboutAccountQuery).
struct TwitterUserAbout {
    let id: String
    var userName: String
    var fullName: String
    var createdAt: Date?
    var profileImage: String?
    var profileImageShape: String?
    var isVerified: Bool
    var isProtected: Bool?
}

/// A scheduled tweet (FetchScheduledTweets).
struct TwitterScheduledTweet {
    let id: String
    var status: String?
    var state: String?
    var executeAt: Date?
}

/// A single direct message (REST 1.1 dm payloads).
struct DMMessage {
    let id: String
    var conversationId: String
    var senderId: String
    var recipientId: String?
    var text: String
    var createdAt: Date?
}

/// A direct-message conversation with its (preview / full) messages.
struct DMConversation {
    let id: String
    var type: String
    var name: String?
    var avatarURL: String?
    var participants: [String]
    var messages: [DMMessage]
}

/// The direct-message inbox (inbox_initial_state / inbox_timeline).
struct DMInbox {
    var conversations: [DMConversation]
    var cursor: String?
}

/// The connected user's analytics overview (AccountOverviewQuery). Deep metric
/// series are kept as raw JSON; the common scalars are surfaced directly.
struct TwitterAnalytics {
    var followers: Int?
    var verifiedFollowers: Int?
    var raw: [String: Any]
}
