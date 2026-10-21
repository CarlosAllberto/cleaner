import XCTest
@testable import CleanerCore

final class SystemJunkModuleTests: XCTestCase {
    func testScanListsCachesLogsAndNeverTrashOrDownloads() async throws {
        let e = Env()
        e.file("Library/Caches/grande/blob", String(repeating: "x", count: 50_000))
        e.file("Library/Caches/pequeno", "x")
        e.file("Library/Caches/\(AppConfig.bundleID)/meu", "nao listar")
        e.file("Library/Logs/app.log")
        e.file(".Trash/velho.txt")
        let old = e.file("Downloads/antigo.dmg")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-200 * 86_400)],
                                              ofItemAtPath: old.path)

        let r = try await SystemJunkModule(engine: e.engine).scan()
        let names = r.items.map(\.url.lastPathComponent)
        XCTAssertEqual(Set(names), ["grande", "pequeno", "app.log"], "Lixeira nunca é listada")
        XCTAssertEqual(names.first, "grande", "ordenado por tamanho")
        XCTAssertTrue(r.inaccessible.isEmpty)
        XCTAssertNotEqual(e.engine.policy.check(old, module: .systemJunk), .allowed(old))
        let trash = e.home.appendingPathComponent(".Trash/velho.txt")
        XCTAssertNotEqual(e.engine.policy.check(trash, module: .systemJunk), .allowed(trash))
    }

    func testCleanThroughModuleGoesToQuarantine() async throws {
        let e = Env()
        e.file("Library/Caches/x/dado")
        let m = SystemJunkModule(engine: e.engine)
        let items = try await m.scan().items
        let res = try await m.clean(items: items, dryRun: false)
        XCTAssertEqual(res.moved, 1)
        XCTAssertFalse(e.exists(e.home.appendingPathComponent("Library/Caches/x")))
    }
}
