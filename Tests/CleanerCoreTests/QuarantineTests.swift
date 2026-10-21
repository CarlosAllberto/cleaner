import XCTest
@testable import CleanerCore

final class QuarantineTests: XCTestCase {
    func testMovesToQuarantineAndRecordsManifest() async throws {
        let e = Env()
        let item = e.cache("app/dado.bin", "12345")
        let r = try await e.engine.quarantine.quarantine([item], module: .systemJunk)
        XCTAssertEqual(r.moved, 1)
        XCTAssertEqual(r.freedBytes, 0, "espaço só volta após expirar")
        XCTAssertGreaterThan(r.movedBytes, 0)
        XCTAssertFalse(e.exists(item.url))
        let m = try e.manifest(r.sessionID!)
        let mi = m.items[0]
        XCTAssertEqual(mi.status, .moved)
        XCTAssertTrue(e.exists(URL(fileURLWithPath: mi.quarantinePath)))
        XCTAssertTrue(mi.quarantinePath.hasPrefix(e.config.quarantineRoot.path))
        XCTAssertEqual(m.expiresAt.timeIntervalSince(m.createdAt), 7 * 86_400, accuracy: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: e.config.logFile.path))
    }

    func testManifestIsOnDiskBeforeEachMove() async throws {
        let seen = Box<[ItemStatus?]>([])
        let box = seen
        let holder = Box<Env?>(nil)
        let e = Env(beforeMove: { sid, mi in
            let m = try? holder.value!.manifest(sid)
            box.value.append(m?.items.first { $0.id == mi.id }?.status)
        })
        holder.value = e
        let r = try await e.engine.quarantine.quarantine([e.cache("a"), e.cache("b")], module: .systemJunk)
        XCTAssertEqual(r.moved, 2)
        XCTAssertEqual(seen.value, [.pending, .pending], "manifesto com os itens já estava gravado antes de mover")
    }

    func testFailureInTheMiddleLeavesConsistentManifest() async throws {
        let victim = Box<URL?>(nil)
        let e = Env(beforeMove: { _, mi in
            if mi.originalPath == victim.value?.path { try? FileManager.default.removeItem(atPath: mi.originalPath) }
        })
        let a = e.cache("a"), b = e.cache("b"), c = e.cache("c")
        victim.value = b.url
        // a ordem de movimento segue a do manifesto; apaga b antes do seu movimento
        let r = try await e.engine.quarantine.quarantine([a, b, c], module: .systemJunk)
        let m = try e.manifest(r.sessionID!)
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertEqual(m.items.filter { $0.status == .moved }.count, 2)
        XCTAssertEqual(m.items.filter { $0.status == .failed }.count, 1)
        for mi in m.items where mi.status == .moved { XCTAssertTrue(e.exists(URL(fileURLWithPath: mi.quarantinePath))) }
    }

    func testDeniedItemsAreNeverMoved() async throws {
        let e = Env()
        let doc = e.item(e.file("Documents/tese.docx"))
        let r = try await e.engine.quarantine.quarantine([doc], module: .systemJunk)
        XCTAssertEqual(r.moved, 0)
        XCTAssertEqual(r.skipped.count, 1)
        XCTAssertNil(r.sessionID)
        XCTAssertTrue(e.exists(doc.url))
    }

    func testDryRunTouchesNothing() async throws {
        let e = Env()
        let item = e.cache("a")
        let r = try await e.engine.quarantine.quarantine([item], module: .systemJunk, dryRun: true)
        XCTAssertTrue(r.dryRun)
        XCTAssertEqual(r.moved, 1)
        XCTAssertNil(r.sessionID)
        XCTAssertTrue(e.exists(item.url))
        XCTAssertTrue(e.engine.store.loadAll().isEmpty)
    }

    func testNestedSelectionMovesOnlyOuterItem() async throws {
        let e = Env()
        e.file("Library/Caches/pasta/filho.txt")
        let outer = e.item(e.home.appendingPathComponent("Library/Caches/pasta"))
        let inner = e.item(e.home.appendingPathComponent("Library/Caches/pasta/filho.txt"))
        let r = try await e.engine.quarantine.quarantine([inner, outer], module: .systemJunk)
        XCTAssertEqual(r.moved, 1)
        XCTAssertEqual(r.skipped.count, 1)
        XCTAssertEqual(try e.manifest(r.sessionID!).items.count, 1)
    }

    func testSymlinkIsMovedNotItsTarget() async throws {
        let e = Env()
        let target = e.file("Library/Caches/real/dado")
        let link = e.home.appendingPathComponent("Library/Caches/atalho")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let r = try await e.engine.quarantine.quarantine([e.item(link)], module: .systemJunk)
        XCTAssertEqual(r.moved, 1)
        XCTAssertFalse(e.exists(link))
        XCTAssertTrue(e.exists(target), "o alvo do symlink não pode ser tocado")
        XCTAssertEqual(try e.manifest(r.sessionID!).items[0].kind, .symlink)
    }

    func testPermanentDeleteGoesThroughManifestAndFreesSpace() async throws {
        let e = Env()
        let item = e.cache("a", "bytes")
        let r = try await e.engine.quarantine.deletePermanently([item], module: .systemJunk)
        XCTAssertEqual(r.moved, 1)
        XCTAssertEqual(r.freedBytes, r.movedBytes)
        let mi = try e.manifest(r.sessionID!).items[0]
        XCTAssertEqual(mi.status, .expired)
        XCTAssertFalse(e.exists(URL(fileURLWithPath: mi.quarantinePath)))
        XCTAssertFalse(e.exists(item.url))
    }

    func testExternalVolumeUsesItsOwnQuarantine() async throws {
        let ext = Box<URL?>(nil)
        let fake = VolumeResolver { url in
            if let x = ext.value, url.path == x.path || PathPolicy.isInside(url, x) { return x }
            return URL(fileURLWithPath: "/System/Volumes/Data")
        }
        // o "volume externo" é uma pasta de teste; o escopo do módulo aponta para ela
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let extRoot = URL(fileURLWithPath: FS.realpath(base.path)!)
        ext.value = extRoot
        let scope = ModuleScope(allowedRoots: [extRoot.appendingPathComponent("lixo")])
        let e = Env(volumes: fake, scopes: [.systemJunk: scope])
        let f = e.file("lixo/arquivo.txt", under: extRoot)
        let r = try await e.engine.quarantine.quarantine([e.item(f)], module: .systemJunk)
        XCTAssertEqual(r.moved, 1)
        let q = URL(fileURLWithPath: try e.manifest(r.sessionID!).items[0].quarantinePath)
        XCTAssertTrue(q.path.hasPrefix(extRoot.appendingPathComponent(AppConfig.externalQuarantineDirName).path))
        XCTAssertTrue(e.exists(q))
        // restaura e expira também funcionam com a quarentena do volume
        let out = try await e.engine.restorer.restore(sessionID: r.sessionID!)
        XCTAssertEqual(out.restored.count, 1)
        XCTAssertTrue(e.exists(f))
    }
}

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}
