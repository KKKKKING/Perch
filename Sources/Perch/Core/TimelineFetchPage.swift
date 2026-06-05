import Foundation

struct RawGraphQLCapture {
    let accountId: String
    let identity: TimelineIdentity
    let operation: String
    let fetchedAt: Date
    let rawData: Data
    let tweetIds: [String]
}

struct TimelineFetchPage {
    let posts: [Post]
    let cursor: String?
    let rawCapture: RawGraphQLCapture?
    let newAuthors: [Person]   // TimelineShowAlert avatars (home only); [] elsewhere
    let topCursor: String?     // fetch-newer (pull-to-refresh) cursor (home only); nil elsewhere
}
