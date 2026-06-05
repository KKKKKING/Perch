import AppKit
@testable import Perch
import XCTest

/// Exercises the NSTableView-backed timeline data path headlessly: row counts,
/// cell types, positive heights, contiguous stacking, and empty-state swap.
final class TimelineFeedTests: XCTestCase {
    private func person() -> Person {
        Person(id: "u1", name: "Lena Wolfe", handle: "lenawolfe",
               colorToken: "indigo-700", verified: false, platform: .x)
    }

    private func post(_ id: String) -> Post {
        Post(id: id, author: person(), time: "1m", text: "Body of post \(id) that wraps a little.",
             stats: Stats(replies: 1, reposts: 2, likes: 3))
    }

    private func makeFeed(width: CGFloat = 360) -> (TimelineFeed, NSTableView, NSWindow) {
        let feed = TimelineFeed(width: width, isX: true, isSearch: false, type: "home",
                                callbacks: PostCallbacks(), onRetry: {}, onGap: { _ in })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        feed.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        window.contentView?.addSubview(feed.scrollView)
        return (feed, feed.scrollView.documentView as! NSTableView, window)
    }

    func testRowCountAndCellTypes() {
        let (feed, table, _) = makeFeed()
        let rows: [TimelineRow] = [.post(post("1")), .post(post("2")),
                                   .gap(TimelineGap(cursor: "c1")), .post(post("3"))]
        feed.update(rows: rows, status: .ready, refreshing: false)
        XCTAssertEqual(table.numberOfRows, 4)

        let col = table.tableColumns[0]
        XCTAssertTrue(feed.tableView(table, viewFor: col, row: 0) is PostCellView)
        XCTAssertTrue(feed.tableView(table, viewFor: col, row: 2) is TimelineGapView)
        XCTAssertTrue(feed.tableView(table, viewFor: col, row: 3) is PostCellView)
    }

    func testHeightsPositiveAndContiguous() {
        let (feed, table, _) = makeFeed()
        let rows = (1...8).map { TimelineRow.post(post("\($0)")) }
        feed.update(rows: rows, status: .ready, refreshing: false)
        table.layoutSubtreeIfNeeded()

        var expectedY: CGFloat = 0
        for r in 0..<table.numberOfRows {
            let h = feed.tableView(table, heightOfRow: r)
            XCTAssertGreaterThan(h, 0, "row \(r) height")
            let rect = table.rect(ofRow: r)
            XCTAssertEqual(rect.minY, expectedY, accuracy: 0.5, "row \(r) should stack contiguously")
            XCTAssertEqual(rect.height, h, accuracy: 0.5, "row \(r) rect height matches delegate height")
            expectedY += h
        }
    }

    func testEmptyStateSwapsAwayFromTable() {
        let (feed, _, _) = makeFeed()
        feed.update(rows: [.post(post("1"))], status: .ready, refreshing: false)
        XCTAssertTrue(feed.scrollView.documentView is NSTableView)

        feed.update(rows: [], status: .empty, refreshing: false)
        XCTAssertFalse(feed.scrollView.documentView is NSTableView, "empty timeline shows a placeholder, not the table")

        feed.update(rows: [.post(post("2"))], status: .ready, refreshing: false)
        XCTAssertTrue(feed.scrollView.documentView is NSTableView, "rows restore the table")
    }

    func testAnchorRoundTrip() {
        let (feed, table, _) = makeFeed()
        let rows = (1...20).map { TimelineRow.post(post("\($0)")) }
        feed.update(rows: rows, status: .ready, refreshing: false)
        table.layoutSubtreeIfNeeded()

        // Scroll so row 5 sits just below the top edge, then capture + restore.
        let target = table.rect(ofRow: 5).minY + 7
        feed.scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
        feed.scrollView.reflectScrolledClipView(feed.scrollView.contentView)

        let anchor = feed.currentAnchor()
        XCTAssertEqual(anchor.postId, "6")          // row 5 → post id "6"
        XCTAssertEqual(anchor.offset, 7, accuracy: 0.5)

        feed.scrollView.contentView.scroll(to: .zero)
        feed.restore(anchor: anchor)
        XCTAssertEqual(feed.scrollView.contentView.bounds.origin.y, target, accuracy: 0.5)
    }
}
