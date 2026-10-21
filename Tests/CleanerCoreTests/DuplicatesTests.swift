import XCTest
@testable import CleanerCore

final class DuplicatesTests: XCTestCase {
    let big = String(repeating: "a", count: 100_000)

    private func allowed(_ d: PolicyDecision) -> Bool { if case .allowed = d { return true }; return false }

    func testFindsPairAcrossDocumentsAndDownloads() async throws {
        let e = Env()
        let a = e.file("Documents/relatorio.pdf", big)
        let b = e.file("Downloads/relatorio (1).pdf", big)
        let r = try await DuplicatesModule(engine: e.engine, minSize: 1).scanGroups()
        XCTAssertEqual(r.groups.count, 1)
        XCTAssertEqual(Set(r.groups[0].files.map(\.url.lastPathComponent)), [a.lastPathComponent, b.lastPathComponent])
        XCTAssertEqual(r.groups[0].wastedBytes, Int64(big.utf8.count))
    }

    func testIgnoresSameSizeDifferentContentAndSmallFiles() async throws {
        let e = Env()
        e.file("Documents/a.bin", big)
        e.file("Downloads/b.bin", String(repeating: "b", count: 100_000))
        e.file("Documents/p1.txt", "igual")
        e.file("Downloads/p2.txt", "igual")
        let r = try await DuplicatesModule(engine: e.engine, minSize: 1000).scanGroups()
        XCTAssertTrue(r.groups.isEmpty)
    }

    func testScanKeepsOneAndSelectingAllKeepsOne() async throws {
        let e = Env()
        let files = ["Documents/x.mov", "Downloads/x.mov", "Documents/sub/x copy.mov"].map { e.file($0, big) }
        let m = DuplicatesModule(engine: e.engine, minSize: 1)
        let scanned = try await m.scan().items
        XCTAssertEqual(scanned.count, 2, "uma cópia fica de fora do scan")

        let all = try await m.scanGroups().groups[0].files
        let res = try await m.clean(items: all, dryRun: false)
        XCTAssertEqual(res.moved, 2)
        XCTAssertEqual(res.skipped.map(\.reason), ["última cópia: mantida"])
        XCTAssertEqual(files.filter(e.exists).count, 1)
    }

    func testQuarantineAndRestoreFromDocuments() async throws {
        let e = Env()
        let keep = e.file("Downloads/foto.jpg", big)
        let dup = e.file("Documents/foto.jpg", big)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: keep.path)
        let m = DuplicatesModule(engine: e.engine, minSize: 1)
        let items = try await m.scan().items
        XCTAssertEqual(items.map(\.url.lastPathComponent), ["foto.jpg"])
        XCTAssertEqual(items.first?.url.deletingLastPathComponent().lastPathComponent, "Documents")

        let res = try await m.clean(items: items, dryRun: false)
        XCTAssertEqual(res.moved, 1)
        XCTAssertFalse(e.exists(dup))
        let out = try await e.engine.restorer.restore(sessionID: try XCTUnwrap(res.sessionID))
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(dup), big)
    }

    func testExceptionOnlyForDuplicates() {
        let e = Env()
        let doc = e.file("Documents/a.txt")
        let icloud = e.file("Library/Mobile Documents/com~apple~CloudDocs/a.txt")
        let keychain = e.file("Library/Keychains/login.keychain-db")
        XCTAssertTrue(allowed(e.engine.policy.check(doc, module: .duplicates)))
        XCTAssertFalse(allowed(e.engine.policy.check(doc, module: .systemJunk)))
        XCTAssertFalse(allowed(e.engine.policy.check(icloud, module: .duplicates)))
        XCTAssertFalse(allowed(e.engine.policy.check(keychain, module: .duplicates)))
    }
}
