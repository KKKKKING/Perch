import AppKit
@testable import Perch
import XCTest

/// The NSTableView timeline computes each row's height with `measuredHeight`
/// (no view construction) and separately builds the on-screen cell. If those two
/// heights disagree, rows clip or leave gaps. These tests pin the invariant:
/// `measuredHeight(for:) == built frame height` for representative posts.
final class PostCellHeightTests: XCTestCase {
    private let width: CGFloat = 360

    private func person(verified: Bool = false) -> Person {
        Person(id: "u1", name: "Lena Wolfe", handle: "lenawolfe",
               colorToken: "indigo-700", verified: verified, platform: .x)
    }

    private func assertHeightMatches(_ post: Post, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        let cell = PostCellView(post: post, width: width, callbacks: PostCallbacks())
        let built = cell.frame.height                 // place: true (display)
        let measured = cell.measuredHeight(for: post) // place: false (row height)
        XCTAssertEqual(built, measured, accuracy: 0.5, "\(msg): built \(built) vs measured \(measured)", file: file, line: line)
    }

    func testPlainPost() {
        assertHeightMatches(
            Post(id: "1", author: person(), time: "1m", text: "Short and sweet.",
                 stats: Stats(replies: 2, reposts: 1, likes: 9)),
            "plain")
    }

    func testVerifiedAuthor() {
        assertHeightMatches(
            Post(id: "2", author: person(verified: true), time: "3m",
                 text: "A verified author with a moderately long body that wraps onto more than a single visual line in this column width.",
                 stats: Stats(replies: 0, reposts: 0, likes: 0)),
            "verified + wrapping")
    }

    func testFoldedLongPost() {
        let long = Array(repeating: "Line of text that is long enough to wrap.", count: 30).joined(separator: "\n")
        assertHeightMatches(
            Post(id: "3", author: person(), time: "1h", text: long,
                 stats: Stats(replies: 5, reposts: 3, likes: 40)),
            "folded long post")
    }

    func testReposted() {
        assertHeightMatches(
            Post(id: "4", author: person(), time: "2h", repostedBy: "Someone", text: "Reposted body.",
                 stats: Stats(replies: 1, reposts: 8, likes: 12)),
            "reposted badge line")
    }

    func testImageMedia() {
        var media = Media(type: .images)
        media.items = [MediaItem(Gradient("#1c1c22", "#0e0e12")), MediaItem(Gradient("#222", "#111"))]
        assertHeightMatches(
            Post(id: "5", author: person(), time: "4h", text: "Two images attached.", media: media,
                 stats: Stats(replies: 0, reposts: 2, likes: 30)),
            "image media")
    }

    func testLinkCard() {
        var media = Media(type: .link)
        media.title = "An interesting article title that may wrap to two lines in the card"
        media.desc = "A description that summarizes the linked content for the preview card."
        media.domain = "example.com"
        media.url = "https://example.com/article"
        media.item = MediaItem(Gradient("#333", "#111"))
        assertHeightMatches(
            Post(id: "6", author: person(), time: "5h", text: "Check this out.", media: media,
                 stats: Stats(replies: 0, reposts: 0, likes: 4)),
            "link card")
    }

    func testVideoMediaSource() {
        var media = Media(type: .video)
        media.dur = "0:30"
        media.item = MediaItem(Gradient("#333", "#111"))
        media.source = Person(id: "u2", name: "The Type Files", handle: "typefiles",
                              colorToken: "orange-700", verified: true, platform: .x)
        assertHeightMatches(
            Post(id: "7", author: person(), time: "6h", text: "A promoted quoted video.", media: media,
                 stats: Stats(replies: 0, reposts: 1, likes: 5)),
            "video media source")
    }

    func testQuote() {
        let q = Quote(author: person(verified: true), time: "6h",
                      text: "The quoted post body that is fairly long and wraps across a couple of lines for good measure.",
                      media: nil)
        let post = Post(id: "8", author: person(), time: "6h", text: "Quoting this.",
                        stats: Stats(replies: 0, reposts: 1, likes: 5))
        post.quote = q
        assertHeightMatches(post, "quote")
    }
}
