import XCTest
@testable import CleanerCore

final class ExpirySchedulerTests: XCTestCase {
    private final class Clock: @unchecked Sendable {
        var t = Date()
    }

    func testExpireDueOnlyTakesExpiredSessionsAndLogs() async throws {
        let clock = Clock()
        let e = Env(now: { clock.t })
        let id = try await e.engine.quarantine.quarantine([e.cache("a.txt", "12345")], module: .systemJunk).sessionID!
        let sched = ExpiryScheduler(engine: e.engine, now: { clock.t })

        XCTAssertEqual(sched.expireDue(), ExpiryReport())
        clock.t = clock.t.addingTimeInterval(8 * 86_400)
        let r = sched.expireDue()
        XCTAssertEqual(r.sessions, 1)
        XCTAssertEqual(r.bytes, try e.manifest(id).items[0].size)
        XCTAssertEqual(try e.manifest(id).items[0].status, .expired)
        XCTAssertTrue(e.text(e.config.logFile)?.contains("scheduled-expiry") == true)
    }

    func testEmptyNowExpiresActiveSessionsBeforeDeadline() async throws {
        let e = Env()
        let id = try await e.engine.quarantine.quarantine([e.cache("a.txt", "123")], module: .systemJunk).sessionID!
        let r = ExpiryScheduler(engine: e.engine).emptyNow()
        XCTAssertEqual(r, ExpiryReport(sessions: 1, bytes: try e.manifest(id).items[0].size))
        XCTAssertEqual(try e.manifest(id).items[0].status, .expired)
        XCTAssertEqual(ExpiryScheduler(engine: e.engine).emptyNow(), ExpiryReport())
    }

    func testStartRunsImmediatelyThenAfterEachSleepAndStops() async throws {
        let e = Env()
        let ticks = expectation(description: "dois ciclos")
        ticks.expectedFulfillmentCount = 2
        let sched = ExpiryScheduler(engine: e.engine, interval: 3600, sleep: { _ in
            ticks.fulfill()
            try await Task.sleep(nanoseconds: 10_000_000)
        })
        sched.start()
        await fulfillment(of: [ticks], timeout: 5)
        sched.stop()
    }
}
