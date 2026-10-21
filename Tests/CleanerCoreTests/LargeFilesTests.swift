import XCTest
@testable import CleanerCore

final class LargeFilesTests: XCTestCase {
    let big = String(repeating: "a", count: 200_000)

    private func allowed(_ d: PolicyDecision) -> Bool { if case .allowed = d { return true }; return false }

    /// As pastas da home são lidas ao criar a política: cria os arquivos antes e monta um Engine novo.
    private func engine(_ e: Env) -> Engine { Engine(config: e.config, policy: PathPolicy(config: e.config)) }

    private func scan(_ e: Env) async throws -> [CleanItem] {
        try await LargeFilesModule(engine: engine(e), minBytes: 100_000).scan().items
    }

    func testFindsBigFilesInDocumentsAndCustomFolderSortedBySize() async throws {
        let e = Env()
        e.file("Documents/filme.mov", big)
        e.file("Projetos/app/build.zip", big + big)
        e.file("Documents/pequeno.txt", "pouco")
        let items = try await scan(e)
        XCTAssertEqual(items.map(\.url.lastPathComponent), ["build.zip", "filme.mov"])
        XCTAssertEqual(items.map(\.label), ["Projetos", "Documents"])
        XCTAssertNotNil(items.first?.modificationDate)
    }

    func testIgnoresHiddenPackagesLibraryAndDotFolders() async throws {
        let e = Env()
        let lib = e.file("Library/Application Support/x/big.bin", big)
        let conf = e.file(".config/big.bin", big)
        e.file("Documents/.oculto.bin", big)
        e.file("Pictures/Fotos.photoslibrary/originals/big.heic", big)
        let found = try await scan(e)
        XCTAssertTrue(found.isEmpty, "\(found.map(\.url.path))")
        let p = engine(e).policy
        XCTAssertFalse(allowed(p.check(lib, module: .largeFiles)))
        XCTAssertFalse(allowed(p.check(conf, module: .largeFiles)))
        XCTAssertFalse(allowed(p.check(e.home.appendingPathComponent("Library/LaunchAgents/x.plist"), module: .largeFiles)))
        XCTAssertFalse(allowed(p.check(e.home.appendingPathComponent("Library/Mobile Documents/a.mov"), module: .largeFiles)))
    }

    func testQuarantineAndRestoreFromDownloads() async throws {
        let e = Env()
        let f = e.file("Downloads/instalador.dmg", big)
        let eng = engine(e)
        let m = LargeFilesModule(engine: eng, minBytes: 100_000)
        let items = try await m.scan().items
        XCTAssertEqual(items.count, 1)
        let res = try await m.clean(items: items, dryRun: false)
        XCTAssertEqual(res.moved, 1)
        XCTAssertFalse(e.exists(f))
        let out = try await eng.restorer.restore(sessionID: try XCTUnwrap(res.sessionID))
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertEqual(e.text(f), big)
    }

    func testSystemJunkStillCannotTouchDocuments() {
        let e = Env()
        let doc = e.file("Documents/a.mov")
        let p = engine(e).policy
        XCTAssertTrue(allowed(p.check(doc, module: .largeFiles)))
        XCTAssertFalse(allowed(p.check(doc, module: .systemJunk)))
    }

    func testKind() {
        XCTAssertEqual(LargeFileKind(URL(fileURLWithPath: "/a.mov")), .video)
        XCTAssertEqual(LargeFileKind(URL(fileURLWithPath: "/a.dmg")), .diskImage)
        XCTAssertEqual(LargeFileKind(URL(fileURLWithPath: "/a.zip")), .archive)
        XCTAssertEqual(LargeFileKind(URL(fileURLWithPath: "/a.pdf")), .document)
        XCTAssertEqual(LargeFileKind(URL(fileURLWithPath: "/a.qqq")), .other)
    }
}
