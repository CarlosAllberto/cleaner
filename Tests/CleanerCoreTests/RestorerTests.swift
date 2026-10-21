import XCTest
@testable import CleanerCore

final class RestorerTests: XCTestCase {
    func clean(_ e: Env, _ items: [CleanItem]) async throws -> UUID {
        try await e.engine.quarantine.quarantine(items, module: .systemJunk).sessionID!
    }

    func testRestoreRoundTrip() async throws {
        let e = Env()
        let item = e.cache("app/dado.txt", "original")
        let id = try await clean(e, [item])
        let out = try await e.engine.restorer.restore(sessionID: id)
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(item.url), "original")
        XCTAssertThrowsError(try e.manifest(id), "sessão vazia some")
    }

    func testRestoreRecreatesMissingParent() async throws {
        let e = Env()
        let item = e.cache("pai/filho.txt", "oi")
        let id = try await clean(e, [item])
        try FileManager.default.removeItem(at: e.home.appendingPathComponent("Library/Caches/pai"))
        let out = try await e.engine.restorer.restore(sessionID: id)
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(item.url), "oi")
    }

    func testConflictKeepCurrentLeavesItemInQuarantine() async throws {
        let e = Env()
        let item = e.cache("a.txt", "velho")
        let id = try await clean(e, [item])
        e.file("Library/Caches/a.txt", "novo")
        let out = try await e.engine.restorer.restore(sessionID: id) { _ in .keepCurrent }
        XCTAssertEqual(out.keptCurrent.count, 1)
        XCTAssertEqual(e.text(item.url), "novo")
        XCTAssertEqual(try e.manifest(id).items.count, 1)
    }

    func testConflictReplaceQuarantinesCurrentInsteadOfDeleting() async throws {
        let e = Env()
        let item = e.cache("a.txt", "velho")
        let id = try await clean(e, [item])
        e.file("Library/Caches/a.txt", "novo")
        let out = try await e.engine.restorer.restore(sessionID: id) { _ in .replace }
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(item.url), "velho")
        let sessions = e.engine.store.loadAll()
        XCTAssertEqual(sessions.count, 1, "o item atual foi para uma nova sessão")
        XCTAssertEqual(e.text(URL(fileURLWithPath: sessions[0].items[0].quarantinePath)), "novo")
    }

    func testConflictSuffixKeepsBoth() async throws {
        let e = Env()
        let item = e.cache("a.txt", "velho")
        let id = try await clean(e, [item])
        e.file("Library/Caches/a.txt", "novo")
        let out = try await e.engine.restorer.restore(sessionID: id) { _ in .suffix }
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(item.url), "novo")
        XCTAssertEqual(e.text(e.home.appendingPathComponent("Library/Caches/a (restaurado).txt")), "velho")
    }

    func testMissingQuarantineItemIsUnrecoverableNotFatal() async throws {
        let e = Env()
        let a = e.cache("a.txt"), b = e.cache("b.txt", "bbb")
        let id = try await clean(e, [a, b])
        let m = try e.manifest(id)
        let gone = m.items.first { $0.originalPath.hasSuffix("a.txt") }!
        try FileManager.default.removeItem(atPath: gone.quarantinePath)
        let out = try await e.engine.restorer.restore(sessionID: id)
        XCTAssertEqual(out.unrecoverable, [gone.id])
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(b.url), "bbb")
        let left = try e.manifest(id)
        XCTAssertEqual(left.items.map(\.status), [.unrecoverable])
    }

    func testPartialRestoreKeepsTheRest() async throws {
        let e = Env()
        let a = e.cache("a.txt"), b = e.cache("b.txt")
        let id = try await clean(e, [a, b])
        let m = try e.manifest(id)
        let pick = m.items.first { $0.originalPath.hasSuffix("a.txt") }!.id
        let out = try await e.engine.restorer.restore(sessionID: id, items: [pick])
        XCTAssertEqual(out.restored, [pick])
        XCTAssertTrue(e.exists(a.url))
        XCTAssertFalse(e.exists(b.url))
        let left = try e.manifest(id)
        XCTAssertEqual(left.items.count, 1)
        XCTAssertEqual(left.items[0].status, .moved)
    }

    func testPermissionsAreRestored() async throws {
        let e = Env()
        let url = e.file("Library/Caches/p.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let id = try await clean(e, [e.item(url)])
        _ = try await e.engine.restorer.restore(sessionID: id)
        let perms = (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testCorruptedManifestNeverRestores() async throws {
        let e = Env()
        let item = e.cache("a.txt")
        let id = try await clean(e, [item])
        try "lixo".write(to: e.engine.store.url(for: id), atomically: true, encoding: .utf8)
        do { _ = try await e.engine.restorer.restore(sessionID: id); XCTFail("deveria falhar") }
        catch { XCTAssertTrue(error is CleanerError) }
        XCTAssertFalse(e.exists(item.url))
    }

    func testTamperedOriginalPathToForbiddenLocationIsRejected() async throws {
        let e = Env()
        let id = try await clean(e, [e.cache("a.txt", "malicioso")])
        let target = e.home.appendingPathComponent("Documents/sobrescrito.txt")
        try e.tamper(id) { obj in
            var items = obj["items"] as! [[String: Any]]
            items[0]["originalPath"] = target.path
            obj["items"] = items
        }
        let out = try await e.engine.restorer.restore(sessionID: id)
        XCTAssertEqual(out.restored.count, 0)
        XCTAssertEqual(out.rejected.count, 1)
        XCTAssertFalse(e.exists(target))
    }

    func testTamperedOriginalPathOutsideModuleScopeIsRejected() async throws {
        let e = Env()
        let id = try await clean(e, [e.cache("a.txt")])
        let target = e.home.appendingPathComponent("Outra/a.txt")
        try e.tamper(id) { obj in
            var items = obj["items"] as! [[String: Any]]
            items[0]["originalPath"] = target.path
            obj["items"] = items
        }
        let out = try await e.engine.restorer.restore(sessionID: id)
        XCTAssertEqual(out.rejected.count, 1)
        XCTAssertFalse(e.exists(target.deletingLastPathComponent()))
    }

    func testTamperedQuarantinePathIsRejected() async throws {
        let e = Env()
        let id = try await clean(e, [e.cache("a.txt")])
        let victim = e.file("Documents/vitima.txt", "nao me mova")
        try e.tamper(id) { obj in
            var items = obj["items"] as! [[String: Any]]
            items[0]["quarantinePath"] = victim.path
            obj["items"] = items
        }
        let out = try await e.engine.restorer.restore(sessionID: id)
        XCTAssertEqual(out.rejected.count, 1)
        XCTAssertEqual(e.text(victim), "nao me mova")
    }
}
