import XCTest
@testable import CleanerCore

final class HistoryTests: XCTestCase {
    func testListsActiveSessionsWithRemainingTime() async throws {
        let t0 = Date()
        let env = Env(retentionDays: 7, now: { t0 })
        let r = try await env.engine.quarantine.quarantine([env.cache("a.bin", "12345"), env.cache("b.bin")], module: .systemJunk)
        let list = env.engine.store.historySessions()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].sessionID, r.sessionID)
        XCTAssertEqual(list[0].itemCount, 2)
        XCTAssertEqual(list[0].module, .systemJunk)
        XCTAssertEqual(list[0].bytes, r.movedBytes)
        XCTAssertEqual(list[0].remaining(now: t0.addingTimeInterval(86_400)), 6 * 86_400, accuracy: 1)
        XCTAssertEqual(list[0].remaining(now: t0.addingTimeInterval(9 * 86_400)), 0)
    }

    func testUnrecoverableShownAndEmptySessionsHidden() async throws {
        let env = Env()
        let r = try await env.engine.quarantine.quarantine([env.cache("a.bin")], module: .systemJunk)
        var m = try env.manifest(r.sessionID!)
        m.items[0].status = .unrecoverable
        try env.engine.store.save(m)
        let list = env.engine.store.historySessions()
        XCTAssertEqual(list.first?.items.first?.status, .unrecoverable)
        XCTAssertEqual(list.first?.itemCount, 0)
        m.items[0].status = .expired
        try env.engine.store.save(m)
        XCTAssertTrue(env.engine.store.historySessions().isEmpty)
    }

    func testConflictDetectionAndPolicyChoice() async throws {
        let env = Env()
        let a = env.cache("a.bin", "antigo"), b = env.cache("b.bin")
        let r = try await env.engine.quarantine.quarantine([a, b], module: .systemJunk)
        let id = r.sessionID!
        XCTAssertTrue(try env.engine.restorer.conflicts(sessionID: id).isEmpty)

        env.file("Library/Caches/a.bin", "novo")
        let c = try env.engine.restorer.conflicts(sessionID: id)
        XCTAssertEqual(c.map(\.destination.lastPathComponent), ["a.bin"])
        // Só conta os itens pedidos.
        let other = try env.manifest(id).items.first { $0.originalPath.hasSuffix("b.bin") }!.id
        XCTAssertTrue(try env.engine.restorer.conflicts(sessionID: id, items: [other]).isEmpty)

        let out = try await env.engine.restorer.restore(sessionID: id) { _ in .suffix }
        XCTAssertEqual(out.restored.count, 2)
        XCTAssertEqual(env.text(a.url), "novo")
        XCTAssertEqual(env.text(a.url.deletingLastPathComponent().appendingPathComponent("a (restaurado).bin")), "antigo")
    }

    func testPreferencesBundleID() async throws {
        let env = Env()
        let r = try await env.engine.quarantine.quarantine([env.cache("x.bin")], module: .systemJunk)
        let item = try env.manifest(r.sessionID!).items[0]
        XCTAssertNil(item.preferencesBundleID)
    }
}
