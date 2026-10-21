import XCTest
@testable import CleanerCore

final class ExpiryTests: XCTestCase {
    func testExpireDeletesOnlyManifestItemsInsideQuarantine() async throws {
        let e = Env()
        let id = try await e.engine.quarantine.quarantine([e.cache("a.txt", "12345")], module: .systemJunk).sessionID!
        let mi = try e.manifest(id).items[0]
        // arquivo estranho na mesma pasta da sessão: não está no manifesto, não pode ser apagado
        let stranger = URL(fileURLWithPath: mi.quarantinePath).deletingLastPathComponent().appendingPathComponent("estranho.txt")
        try "fica".write(to: stranger, atomically: true, encoding: .utf8)

        let freed = try e.engine.expiry.expire(id)
        XCTAssertEqual(freed, mi.size)
        XCTAssertFalse(e.exists(URL(fileURLWithPath: mi.quarantinePath)))
        XCTAssertEqual(e.text(stranger), "fica")
        XCTAssertEqual(try e.manifest(id).items[0].status, .expired)
        XCTAssertEqual(try e.engine.expiry.expire(id), 0, "idempotente")
    }

    func testTamperedQuarantinePathIsNeverDeleted() async throws {
        let e = Env()
        let id = try await e.engine.quarantine.quarantine([e.cache("a.txt")], module: .systemJunk).sessionID!
        let victim = e.file("Documents/vitima.txt", "intacta")
        try e.tamper(id) { obj in
            var items = obj["items"] as! [[String: Any]]
            items[0]["quarantinePath"] = victim.path
            obj["items"] = items
        }
        try e.engine.expiry.expire(id)
        XCTAssertEqual(e.text(victim), "intacta")
    }

    func testTamperedPathInsideQuarantineButWrongSessionIsNotDeleted() async throws {
        let e = Env()
        let other = try await e.engine.quarantine.quarantine([e.cache("b.txt")], module: .systemJunk).sessionID!
        let id = try await e.engine.quarantine.quarantine([e.cache("a.txt")], module: .systemJunk).sessionID!
        let otherPath = try e.manifest(other).items[0].quarantinePath
        try e.tamper(id) { obj in
            var items = obj["items"] as! [[String: Any]]
            items[0]["quarantinePath"] = otherPath
            obj["items"] = items
        }
        try e.engine.expiry.expire(id)
        XCTAssertTrue(e.exists(URL(fileURLWithPath: otherPath)), "item de outra sessão não pode ser apagado")
    }

    func testExpireDueOnlyTouchesExpiredSessions() async throws {
        let e = Env(retentionDays: 7)
        let old = try await e.engine.quarantine.quarantine([e.cache("a.txt")], module: .systemJunk).sessionID!
        let later = Date().addingTimeInterval(8 * 86_400)
        let fresh = try await e.engine.quarantine.quarantine([e.cache("b.txt")], module: .systemJunk).sessionID!
        // sessão "fresh" ganha prazo maior
        try e.tamper(fresh) { $0["expiresAt"] = ISO8601DateFormatter().string(from: later.addingTimeInterval(30 * 86_400)) }
        let done = e.engine.expiry.expireDue(now: later)
        XCTAssertEqual(done, [old])
        XCTAssertEqual(try e.manifest(fresh).items[0].status, .moved)
    }

    func testExpireRemovesReadOnlyFolders() async throws {
        // Como o cache do dotslash: pastas r-x impedem apagar o que há dentro.
        let e = Env()
        let item = e.file("Library/Caches/dotslash/bd/x.app/Contents/bin").deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for rel in ["bd/x.app/Contents", "bd/x.app", "bd"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: item.appendingPathComponent(rel).path)
        }
        let id = try await e.engine.quarantine.quarantine([CleanItem(url: item, size: 7, kind: .directory)], module: .systemJunk).sessionID!
        let q = URL(fileURLWithPath: try e.manifest(id).items[0].quarantinePath)
        XCTAssertTrue(e.exists(q))

        try e.engine.expiry.expire(id)
        XCTAssertFalse(e.exists(q))
        XCTAssertEqual(try e.manifest(id).items[0].status, .expired)
    }
}
