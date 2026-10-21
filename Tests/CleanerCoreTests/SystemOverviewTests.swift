import XCTest
@testable import CleanerCore

final class SystemOverviewTests: XCTestCase {
    func testMedeCategoriasOrdenadasSemRemoverNada() async {
        let env = Env()
        let big = env.file("Library/Caches/app/blob", String(repeating: "x", count: 200_000))
        env.file("Library/Logs/a.log", "log")
        env.file("Downloads/d.zip", String(repeating: "y", count: 50_000))
        env.file(".Trash/t", "t")
        env.file("Library/Developer/Xcode/DerivedData/x", "x")
        env.file("Library/Developer/CoreSimulator/y", "y")
        env.file("Library/Mail/V10/m", "m")

        let r = await SystemOverview.measure(config: env.config)
        XCTAssertEqual(r.categories.count, 5)
        XCTAssertEqual(r.categories.first?.id, "caches")
        XCTAssertEqual(r.categories.map(\.bytes), r.categories.map(\.bytes).sorted(by: >))
        let by = Dictionary(uniqueKeysWithValues: r.categories.map { ($0.id, $0) })
        XCTAssertNil(by["downloads"], "Downloads contam em Documentos")
        XCTAssertNil(by["trash"], "Lixeira não é limpável pelo app")
        XCTAssertEqual(by["whatsapp"]!.bytes, 0) // pasta inexistente
        // Xcode soma DerivedData + CoreSimulator
        XCTAssertGreaterThanOrEqual(by["xcode"]!.bytes, 2 * 4096)
        XCTAssertEqual(r.total, r.categories.reduce(0) { $0 + $1.bytes })
        XCTAssertFalse(r.incomplete)
        XCTAssertTrue(env.exists(big))
    }

    func testArmazenamentoFechaComUsadoDoVolume() async {
        let env = Env()
        env.file("Documents/a.pdf", String(repeating: "d", count: 100_000))
        env.file("Desktop/b.txt", "b")
        env.file("Apps/X.app/bin", "x")

        let s = await SystemOverview.measureStorage(config: env.config, applications: env.home.appendingPathComponent("Apps"))
        let by = Dictionary(uniqueKeysWithValues: s.categories.map { ($0.id, $0.bytes) })
        XCTAssertGreaterThanOrEqual(by["documents"]!, 100_000)
        XCTAssertGreaterThan(by["apps"]!, 0)
        XCTAssertGreaterThan(by["macos"]!, 0)
        XCTAssertGreaterThan(s.capacity, s.available)
        // Dados do Sistema fecha a conta: soma das categorias = usado no volume.
        XCTAssertEqual(s.categories.reduce(0) { $0 + $1.bytes }, s.used)
    }

    func testMaioresFilhosOrdenadosComLimiteEExclusao() async {
        let env = Env()
        env.file("Documents/grande.bin", String(repeating: "g", count: 300_000))
        env.file("Documents/pasta/medio.bin", String(repeating: "m", count: 100_000))
        env.file("Documents/.oculto", String(repeating: "o", count: 50_000))
        let fora = env.file("Documents/excluido/x.bin", String(repeating: "x", count: 900_000)).deletingLastPathComponent()
        let docs = env.home.appendingPathComponent("Documents")
        let sumida = env.home.appendingPathComponent("NaoExiste")

        let all = await SystemOverview.largestChildren(of: [docs, sumida], excluding: [fora])
        XCTAssertEqual(all.map(\.url.lastPathComponent), ["grande.bin", "pasta", ".oculto"])
        XCTAssertEqual(all.map(\.isDirectory), [false, true, false])
        let top = await SystemOverview.largestChildren(of: [docs], excluding: [fora], limit: 2)
        XCTAssertEqual(top.map(\.url.lastPathComponent), ["grande.bin", "pasta"])

        let s = await SystemOverview.measureStorage(config: env.config, applications: env.home.appendingPathComponent("Apps"))
        let documents = s.categories.first { $0.id == "documents" }!
        XCTAssertEqual(documents.roots.map(\.lastPathComponent), ["Documents", "Desktop", "Downloads"])
    }

    func testDadosDoSistemaIncluiHomeForaDasCategoriasELibrary() async {
        let env = Env()
        env.file(".npm/cache/x", String(repeating: "n", count: 80_000))
        env.file("Documents/d", String(repeating: "d", count: 90_000))
        env.file("Library/Application Support/App/y", String(repeating: "a", count: 40_000))
        let sys = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: sys.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try? Data("z".utf8).write(to: sys.appendingPathComponent("assets/z"))
        defer { try? FileManager.default.removeItem(at: sys) }

        let items = await SystemOverview.systemDataItems(
            config: env.config, excluding: [env.home.appendingPathComponent("Documents")],
            systemRoots: [sys], volumes: [])
        let names = items.map(\.url.lastPathComponent)
        XCTAssertEqual(names.first, ".npm")
        XCTAssertTrue(names.contains("Application Support")) // filho de ~/Library, não a Library inteira
        XCTAssertFalse(names.contains("Library"))
        XCTAssertFalse(names.contains("Documents"))
        XCTAssertTrue(names.contains("assets")) // filho de uma raiz do sistema
    }
}
