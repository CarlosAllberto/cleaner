import XCTest
@testable import CleanerCore

final class PathPolicyTests: XCTestCase {
    func allowed(_ d: PolicyDecision) -> Bool { if case .allowed = d { return true }; return false }

    func testAllowsItemInsideScope() {
        let e = Env()
        let f = e.file("Library/Caches/app/cache.bin")
        XCTAssertTrue(allowed(e.engine.policy.check(f, module: .systemJunk)))
    }

    func testDeniesProtectedAndOutOfScope() {
        let e = Env()
        let doc = e.file("Documents/tese.docx")
        let other = e.file("Outra/arquivo.txt")
        let p = e.engine.policy
        XCTAssertFalse(allowed(p.check(doc, module: .systemJunk)))
        XCTAssertFalse(allowed(p.check(other, module: .systemJunk)))
        XCTAssertFalse(allowed(p.check(URL(fileURLWithPath: "/System/Library/CoreServices"), module: .systemJunk)))
        XCTAssertFalse(allowed(p.check(URL(fileURLWithPath: "/"), module: .systemJunk)))
    }

    func testDeniesScopeRootItselfAndSupportDir() {
        let e = Env()
        let p = e.engine.policy
        XCTAssertFalse(allowed(p.check(e.home.appendingPathComponent("Library/Caches"), module: .systemJunk)))
        XCTAssertFalse(allowed(p.check(e.config.quarantineRoot, module: .orphans)))
        XCTAssertFalse(allowed(p.check(e.config.supportDir, module: .orphans)))
    }

    func testDotDotEscapeIsDenied() {
        let e = Env()
        e.file("Documents/segredo.txt")
        let sneaky = e.home.appendingPathComponent("Library/Caches/../../Documents/segredo.txt")
        XCTAssertFalse(allowed(e.engine.policy.check(sneaky, module: .systemJunk)))
    }

    func testSymlinkPointingOutsideScopeIsDenied() throws {
        let e = Env()
        let target = e.file("Documents/importante.txt")
        let link = e.home.appendingPathComponent("Library/Caches/atalho")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertFalse(allowed(e.engine.policy.check(link, module: .systemJunk)))
    }

    func testSymlinkInsideScopeIsAllowed() throws {
        let e = Env()
        let target = e.file("Library/Caches/real/dado")
        let link = e.home.appendingPathComponent("Library/Caches/atalho")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertTrue(allowed(e.engine.policy.check(link, module: .systemJunk)))
    }

    func testItemBehindSymlinkedParentIsDenied() throws {
        let e = Env()
        e.file("Documents/pasta/arquivo")
        let link = e.home.appendingPathComponent("Library/Caches/portal")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: e.home.appendingPathComponent("Documents"))
        XCTAssertFalse(allowed(e.engine.policy.check(link.appendingPathComponent("pasta/arquivo"), module: .systemJunk)))
    }

    func testWhatsAppDatabasesAreProtected() {
        let e = Env()
        let wa = e.home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared")
        let db = e.file("ChatStorage.sqlite", under: wa)
        let wal = e.file("ChatStorage.sqlite-wal", under: wa)
        let contacts = e.file("ContactsV2.sqlite", under: wa)
        let media = e.file("Message/Media/foto.jpg", under: wa)
        let p = e.engine.policy
        XCTAssertFalse(allowed(p.check(db, module: .whatsapp)))
        XCTAssertFalse(allowed(p.check(wal, module: .whatsapp)))
        XCTAssertFalse(allowed(p.check(contacts, module: .whatsapp)))
        XCTAssertTrue(allowed(p.check(media, module: .whatsapp)))
    }

    func testFolderContainingWhatsAppDatabaseIsDenied() {
        let e = Env()
        let wa = e.home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared")
        e.file("sub/ChatStorage.sqlite", under: wa)
        e.file("sub/outro.jpg", under: wa)
        XCTAssertFalse(allowed(e.engine.policy.check(wa.appendingPathComponent("sub"), module: .whatsapp)))
    }

    func testModuleScopesAreIsolated() {
        let e = Env()
        let f = e.file("Library/Caches/x")
        XCTAssertFalse(allowed(e.engine.policy.check(f, module: .whatsapp)))
    }
}
