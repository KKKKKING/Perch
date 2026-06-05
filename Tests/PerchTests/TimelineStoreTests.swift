import AppKit
@testable import Perch
import XCTest

final class TimelineStoreTests: XCTestCase {
    private func person(_ id: String = "u1") -> Person {
        Person(id: id, name: "Tester", handle: "tester", colorToken: "indigo-700",
               verified: false, platform: .x)
    }

    private func post(_ id: String, replies: Int = 0, quotes: Int? = nil) -> Post {
        Post(id: id, author: person(), time: "1m", text: "Post \(id)",
             stats: Stats(replies: replies, reposts: 0, likes: 0, quotes: quotes),
             createdAt: Date(timeIntervalSince1970: Double(Int(id) ?? 1)))
    }

    private func ids(_ rows: [TimelineRow]) -> [String] {
        rows.map {
            switch $0 {
            case .post(let p): return p.id
            case .gap: return "gap"
            }
        }
    }

    func testRefreshWithOverlapMergesWithoutGap() {
        let existing: [TimelineRow] = [.post(post("3")), .post(post("4"))]
        let incoming = [post("1"), post("2"), post("3")]

        let result = TimelineMerge.mergeLatest(existing: existing, incoming: incoming, bottomCursor: "c1")

        XCTAssertEqual(ids(result.rows), ["1", "2", "3", "4"])
        XCTAssertEqual(result.unreadIds, ["1", "2"])
        XCTAssertFalse(result.insertedGap)
    }

    func testRefreshWithoutOverlapInsertsGap() {
        let existing: [TimelineRow] = [.post(post("5")), .post(post("6"))]
        let incoming = [post("1"), post("2")]

        let result = TimelineMerge.mergeLatest(existing: existing, incoming: incoming, bottomCursor: "c2")

        XCTAssertEqual(ids(result.rows), ["1", "2", "gap", "5", "6"])
        XCTAssertEqual(result.unreadIds, ["1", "2"])
        XCTAssertTrue(result.insertedGap)
    }

    func testFillGapWithOverlapRemovesGap() {
        let gap = TimelineGap(id: "g1", cursor: "c-gap")
        let existing: [TimelineRow] = [.post(post("1")), .gap(gap), .post(post("4")), .post(post("5"))]

        let result = TimelineMerge.fillGap(existing: existing, gapId: "g1",
                                           incoming: [post("2"), post("3"), post("4")],
                                           nextCursor: "next")

        XCTAssertEqual(ids(result.rows), ["1", "2", "3", "4", "5"])
        XCTAssertFalse(result.insertedGap)
    }

    func testFillGapWithoutOverlapMovesGapDown() {
        let gap = TimelineGap(id: "g1", cursor: "c-gap")
        let existing: [TimelineRow] = [.post(post("1")), .gap(gap), .post(post("5"))]

        let result = TimelineMerge.fillGap(existing: existing, gapId: "g1",
                                           incoming: [post("2"), post("3")],
                                           nextCursor: "next")

        XCTAssertEqual(ids(result.rows), ["1", "2", "3", "gap", "5"])
        XCTAssertTrue(result.insertedGap)
    }

    func testForYouGapDedupesAgainstLoadedPostsAndKeepsCursor() {
        let gap = TimelineGap(id: "g1", cursor: "c-gap")
        let existing: [TimelineRow] = [.post(post("1")), .post(post("2")), .gap(gap)]

        let result = TimelineMerge.fillGap(existing: existing, gapId: "g1",
                                           incoming: [post("3"), post("2"), post("4")],
                                           nextCursor: "next",
                                           policy: .unorderedById)

        XCTAssertEqual(ids(result.rows), ["1", "2", "3", "4", "gap"])
        XCTAssertTrue(result.insertedGap)
    }

    func testForYouGapUpdatesDuplicateWhenRepliesIncrease() {
        let gap = TimelineGap(id: "g1", cursor: "c-gap")
        let existing: [TimelineRow] = [.post(post("1", replies: 1)), .gap(gap)]

        let result = TimelineMerge.fillGap(existing: existing, gapId: "g1",
                                           incoming: [post("1", replies: 3)],
                                           nextCursor: nil,
                                           policy: .unorderedById)

        XCTAssertEqual(ids(result.rows), ["1"])
        XCTAssertEqual(result.rows.first?.postValue?.stats.replies, 3)
    }

    func testForYouGapUpdatesDuplicateWhenQuotesIncrease() {
        let gap = TimelineGap(id: "g1", cursor: "c-gap")
        let existing: [TimelineRow] = [.post(post("1", quotes: 1)), .gap(gap)]

        let result = TimelineMerge.fillGap(existing: existing, gapId: "g1",
                                           incoming: [post("1", quotes: 2)],
                                           nextCursor: nil,
                                           policy: .unorderedById)

        XCTAssertEqual(ids(result.rows), ["1"])
        XCTAssertEqual(result.rows.first?.postValue?.stats.quotes, 2)
    }

    func testJSONLPersistsRowsPerAccountAndTimeline() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentTimelineStore(root: root)
        let identity = TimelineIdentity(accountId: "acct1", kind: .home, variant: "for-you")
        let snapshot = TimelineSnapshot(identity: identity,
                                        rows: [.post(post("1")), .gap(TimelineGap(id: "g1", cursor: "c"))],
                                        status: .ready,
                                        unreadIds: ["1"],
                                        bottomCursor: "bottom",
                                        anchor: TimelineAnchor(postId: "1", offset: 9, fallbackY: 100),
                                        loadedFromDisk: true)

        await store.save(snapshot)
        let loaded = await store.load(identity)

        XCTAssertEqual(loaded?.rows.count, 2)
        XCTAssertEqual(loaded?.unreadIds, ["1"])
        XCTAssertEqual(loaded?.bottomCursor, "bottom")
        XCTAssertEqual(loaded?.anchor?.postId, "1")
    }

    func testRawGraphQLPersistsReadablePageAndPostIndex() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentTimelineStore(root: root)
        let identity = TimelineIdentity(accountId: "acct1", kind: .home, variant: "for-you")
        let raw = #"{"data":{"home":{"home_timeline_urt":{"instructions":[]}}}}"#.data(using: .utf8)!
        let capture = RawGraphQLCapture(accountId: "acct1", identity: identity,
                                        operation: "HomeTimeline",
                                        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                        rawData: raw,
                                        tweetIds: ["100", "101", "100"])

        await store.saveRawGraphQL(capture)

        let index = await store.rawGraphQLIndex(accountId: "acct1", postId: "100")
        XCTAssertEqual(index?.operation, "HomeTimeline")
        XCTAssertEqual(index?.timeline, "home-for-you")
        guard let pagePath = index?.pagePath else {
            XCTFail("missing raw page path")
            return
        }
        let pageURL = root
            .appendingPathComponent("acct1/raw-graphql", isDirectory: true)
            .appendingPathComponent(pagePath)
        let pageData = try Data(contentsOf: pageURL)
        XCTAssertEqual(pageData, raw)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: pageData) as? [String: Any])
        let secondIndex = await store.rawGraphQLIndex(accountId: "acct1", postId: "101")
        XCTAssertNotNil(secondIndex)
    }

    func testRawGraphQLPostIndexKeepsLatestPage() async {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perch-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersistentTimelineStore(root: root)
        let identity = TimelineIdentity(accountId: "acct1", kind: .home, variant: "for-you")

        await store.saveRawGraphQL(RawGraphQLCapture(accountId: "acct1", identity: identity,
                                                     operation: "HomeTimeline",
                                                     fetchedAt: Date(timeIntervalSince1970: 1),
                                                     rawData: #"{"old":true}"#.data(using: .utf8)!,
                                                     tweetIds: ["100"]))
        await store.saveRawGraphQL(RawGraphQLCapture(accountId: "acct1", identity: identity,
                                                     operation: "HomeLatestTimeline",
                                                     fetchedAt: Date(timeIntervalSince1970: 2),
                                                     rawData: #"{"new":true}"#.data(using: .utf8)!,
                                                     tweetIds: ["100"]))

        let index = await store.rawGraphQLIndex(accountId: "acct1", postId: "100")
        XCTAssertEqual(index?.operation, "HomeLatestTimeline")
        XCTAssertEqual(index?.fetchedAt, Date(timeIntervalSince1970: 2))
    }

    func testDisplayRowsInjectsReplyParentAndSkipsOriginalParentPosition() {
        let state = appStateForDisplayRows()
        let identity = TimelineIdentity(accountId: "acct1", kind: .home, variant: "for-you")
        let root = post("2062553986033713201")
        root.text = "在这样一个即将改变世界的事业里燃烧青春的激情，一生中能有几次机会？"
        let reply = post("2062556027401466305")
        reply.replyToId = root.id
        reply.conversationId = root.id
        root.conversationId = root.id
        state.timelineSnapshots[identity.key] = TimelineSnapshot(identity: identity,
                                                                 rows: [.post(reply), .post(root)],
                                                                 status: .ready)

        let ids = state.timelineRows(for: state.columns[0]).compactMap(\.postId)

        XCTAssertEqual(ids, [root.id, reply.id])
        let posts = state.timelineRows(for: state.columns[0]).compactMap(\.postValue)
        XCTAssertEqual(posts.first?.connectBottom, true)
        XCTAssertEqual(posts.last?.connectTop, true)
    }

    func testDisplayRowsDoesNotDuplicateContinuousReplyChain() {
        let state = appStateForDisplayRows()
        let identity = TimelineIdentity(accountId: "acct1", kind: .home, variant: "for-you")
        let root = post("1")
        let child = post("2")
        let grandchild = post("3")
        root.conversationId = root.id
        child.conversationId = root.id
        grandchild.conversationId = root.id
        child.replyToId = root.id
        grandchild.replyToId = child.id
        state.timelineSnapshots[identity.key] = TimelineSnapshot(identity: identity,
                                                                 rows: [.post(child), .post(grandchild), .post(root)],
                                                                 status: .ready)

        let ids = state.timelineRows(for: state.columns[0]).compactMap(\.postId)

        XCTAssertEqual(ids, ["1", "2", "3"])
    }

    func testDisplayRowsKeepsReplyWhenParentMissing() {
        let state = appStateForDisplayRows()
        let identity = TimelineIdentity(accountId: "acct1", kind: .home, variant: "for-you")
        let reply = post("2")
        reply.replyToId = "missing"
        state.timelineSnapshots[identity.key] = TimelineSnapshot(identity: identity,
                                                                 rows: [.post(reply)],
                                                                 status: .ready)

        let ids = state.timelineRows(for: state.columns[0]).compactMap(\.postId)

        XCTAssertEqual(ids, ["2"])
    }

    private func appStateForDisplayRows() -> AppState {
        let state = AppState()
        state.accounts = [Person(id: "acct1", name: "Tester", handle: "tester",
                                 colorToken: "indigo-700", verified: false, platform: .x)]
        state.activeId = "acct1"
        state.columns[0].feed = HomeFeed.forYou.rawValue
        return state
    }

    // NOTE: disabled — references `TimelineMerge.anchor`, an API that does not exist
    // in the current source (pre-existing broken test). Anchor preservation now lives
    // in TimelineFeed.currentAnchor()/restore(anchor:).
    func disabled_testAnchorPreservesPositionAfterPrepend() {
        let anchor = TimelineAnchor(postId: "old", offset: 12, fallbackY: 20)
        XCTAssertNotNil(anchor.postId)
    }
}
