@testable import Perch
import XCTest

private actor InvocationCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

final class BadgeCountRequestCoalescerTests: XCTestCase {
    func testConcurrentRequestsForSameKeyShareOneOperation() async throws {
        let coalescer = BadgeCountRequestCoalescer()
        let counter = InvocationCounter()

        async let first = coalescer.run(key: "acct") {
            await counter.increment()
            try await Task.sleep(nanoseconds: 100_000_000)
            return 7
        }

        try await Task.sleep(nanoseconds: 10_000_000)

        async let second = coalescer.run(key: "acct") {
            await counter.increment()
            return 9
        }

        let values = try await (first, second)
        let invocationCount = await counter.count()
        XCTAssertEqual(values.0, 7)
        XCTAssertEqual(values.1, 7)
        XCTAssertEqual(invocationCount, 1)
    }
}
