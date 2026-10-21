import XCTest
@testable import CleanerCore

final class OrphansTests: XCTestCase {
    func env() -> (e: Env, engine: Engine, apps: URL) {
        let e = Env()
        let lib = e.home.appendingPathComponent("Library")
        let roots = OrphansModule.sources.map { lib.appendingPathComponent($0) }
        let policy = PathPolicy(config: e.config, scopes: [.orphans: ModuleScope(allowedRoots: roots, deepNameCheck: true)])
        return (e, Engine(config: e.config, policy: policy), e.home.appendingPathComponent("Applications"))
    }

    func makeApp(_ apps: URL, _ name: String, id: String) {
        let app = apps.appendingPathComponent("\(name).app/Contents")
        try! FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        (["CFBundleIdentifier": id] as NSDictionary).write(to: app.appendingPathComponent("Info.plist"), atomically: true)
    }

    func old(_ url: URL, days: Int = 60) {
        try! FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-Double(days) * 86_400)],
                                               ofItemAtPath: url.path)
    }

    func module(_ engine: Engine, _ apps: URL, ls: @escaping @Sendable (String) -> Bool = { _ in false }) -> OrphansModule {
        OrphansModule(engine: engine, appDirs: [apps], launchServices: ls)
    }

    func testInstalledAppIsNotOrphanButSimilarIDIs() async throws {
        let (e, engine, apps) = env()
        makeApp(apps, "Bar", id: "com.foo.Bar")
        old(e.file("Library/Application Support/com.foo.Bar/d").deletingLastPathComponent())
        old(e.file("Library/Application Support/com.foo.BarPro/d").deletingLastPathComponent())
        let items = try await module(engine, apps).scan().items
        XCTAssertEqual(items.map(\.group), ["orphan:com.foo.BarPro"])
    }

    func testLaunchServicesCountsAsInstalled() async throws {
        let (e, engine, apps) = env()
        old(e.file("Library/Caches/com.foo.Ls/d").deletingLastPathComponent())
        let items = try await module(engine, apps, ls: { $0 == "com.foo.Ls" }).scan().items
        XCTAssertTrue(items.isEmpty)
    }

    func testIgnoresAppleBadFormatAndRecent() async throws {
        let (e, engine, apps) = env()
        old(e.file("Library/Caches/com.apple.Thing/d").deletingLastPathComponent())
        old(e.file("Library/Application Support/Google Chrome/d").deletingLastPathComponent())
        e.file("Library/Application Support/com.foo.Recent/d")  // modificado agora
        let items = try await module(engine, apps).scan().items
        XCTAssertTrue(items.isEmpty)
    }

    func testDerivesIDsFromFileNames() async throws {
        let (e, engine, apps) = env()
        let p = e.file("Library/Preferences/com.a.One.plist")
        let s = e.file("Library/Saved Application State/com.a.Two.savedState/d").deletingLastPathComponent()
        let g = e.file("Library/Group Containers/group.com.a.Three/d").deletingLastPathComponent()
        [p, s, g].forEach { old($0) }
        let groups = Set(try await module(engine, apps).scan().items.compactMap(\.group))
        XCTAssertEqual(groups, ["orphan:com.a.One", "orphan:com.a.Two", "orphan:com.a.Three"])
    }

    func testWhatsAppDatabaseIsProtected() async throws {
        let (e, engine, apps) = env()
        let db = e.file("Library/Application Support/net.whatsapp.WhatsApp/ChatStorage.sqlite", "msgs")
        old(db.deletingLastPathComponent())
        let m = module(engine, apps)
        let (r, blocked) = try await m.scanDetailed()
        XCTAssertEqual(blocked.count, 1)
        let res = try await m.clean(items: r.items, dryRun: false)
        XCTAssertEqual(res.moved, 0)
        XCTAssertEqual(res.skipped.count, 1)
        XCTAssertTrue(e.exists(db))
    }

    func testCleanQuarantinesAndRestores() async throws {
        let (e, engine, apps) = env()
        let d = e.file("Library/Caches/com.gone.App/d").deletingLastPathComponent()
        let p = e.file("Library/Preferences/com.gone.App.plist")
        old(d); old(p)
        let m = module(engine, apps)
        let res = try await m.clean(items: try await m.scan().items, dryRun: false)
        XCTAssertEqual(res.moved, 2)
        XCTAssertFalse(e.exists(d)); XCTAssertFalse(e.exists(p))
        XCTAssertEqual(Set(try engine.store.load(res.sessionID!).items.map(\.group)), ["orphan:com.gone.App"])
        _ = try await engine.restorer.restore(sessionID: res.sessionID!)
        XCTAssertTrue(e.exists(d)); XCTAssertTrue(e.exists(p))
    }
}
