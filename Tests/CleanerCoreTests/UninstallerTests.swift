import XCTest
@testable import CleanerCore

final class UninstallerTests: XCTestCase {
    /// Escopo do desinstalador apontando para a home falsa (nunca para /Applications real).
    /// O Engine é recriado depois do Env porque o escopo depende do caminho da home falsa.
    func env() -> (e: Env, engine: Engine) {
        let e = Env()
        let lib = e.home.appendingPathComponent("Library")
        let roots = ["Application Support", "Preferences", "Containers", "Group Containers",
                     "Saved Application State", "Caches", "LaunchAgents", "HTTPStorages", "WebKit", "Logs"]
            .map { lib.appendingPathComponent($0) } + [e.home.appendingPathComponent("Applications")]
        let policy = PathPolicy(config: e.config, scopes: [.uninstaller: ModuleScope(allowedRoots: roots, deepNameCheck: true)])
        return (e, Engine(config: e.config, policy: policy))
    }

    @discardableResult
    func makeApp(_ e: Env, _ name: String, id: String) -> URL {
        let app = e.home.appendingPathComponent("Applications/\(name).app")
        try! FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": id, "CFBundleName": name]
        plist.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
        e.file("Contents/MacOS/bin", "x", under: app)
        return app
    }

    func residues(_ e: Env, _ id: String) {
        e.file("Library/Application Support/\(id)/d")
        e.file("Library/Preferences/\(id).plist")
        e.file("Library/Containers/\(id)/d")
        e.file("Library/Group Containers/group.\(id)/d")
        e.file("Library/Saved Application State/\(id).savedState/d")
        e.file("Library/Caches/\(id)/d")
        e.file("Library/HTTPStorages/\(id)/d")
        e.file("Library/WebKit/\(id)/d")
        e.file("Library/LaunchAgents/\(id).plist")
    }

    func testExactMatchIgnoresSimilarBundleID() throws {
        let (e, engine) = env()
        let app = makeApp(e, "Bar", id: "com.foo.Bar")
        residues(e, "com.foo.Bar"); residues(e, "com.foo.BarPro")
        let plan = try UninstallerModule(engine: engine, app: app).plan()
        XCTAssertEqual(plan.items.count, 10)
        XCTAssertTrue(plan.items.allSatisfy { $0.risk == .exact && $0.blockedReason == nil })
        XCTAssertFalse(plan.items.contains { $0.item.url.path.contains("BarPro") })
        XCTAssertTrue(plan.items.allSatisfy { $0.item.group == "app:com.foo.Bar" })
    }

    func testBroadSearchSeparateAndMarked() throws {
        let (e, engine) = env()
        let app = makeApp(e, "Bar", id: "com.foo.Bar")
        e.file("Library/Application Support/Bar/d")
        let off = try UninstallerModule(engine: engine, app: app).plan()
        XCTAssertEqual(off.items.count, 1)
        let on = try UninstallerModule(engine: engine, app: app, includeBroad: true).plan()
        XCTAssertEqual(on.items.filter { $0.risk == .broad }.map(\.item.url.lastPathComponent), ["Bar"])
    }

    func testRefusesAppleAndSystemApps() throws {
        let (e, engine) = env()
        let safari = makeApp(e, "Safari", id: "com.apple.Safari")
        XCTAssertThrowsError(try UninstallerModule(engine: engine, app: safari).plan())
        XCTAssertThrowsError(try UninstallerModule(engine: engine, app: URL(fileURLWithPath: "/System/Applications/Mail.app")).plan())
    }

    func testProtectedItemIsBlockedAndSkippedNotFailed() async throws {
        let (e, engine) = env()
        let app = makeApp(e, "WhatsApp", id: "net.whatsapp.WhatsApp")
        e.file("Library/Application Support/net.whatsapp.WhatsApp/ChatStorage.sqlite", "msgs")
        let m = UninstallerModule(engine: engine, app: app)
        let plan = try m.plan()
        let blocked = plan.items.first { $0.item.url.lastPathComponent == "net.whatsapp.WhatsApp" && $0.item.label == "Dados" }
        XCTAssertNotNil(blocked?.blockedReason)
        let res = try await m.clean(items: plan.items.map(\.item), dryRun: false)
        XCTAssertEqual(res.moved, 1)
        XCTAssertEqual(res.skipped.count, 1)
        XCTAssertTrue(res.failed.isEmpty)
        XCTAssertTrue(e.exists(e.home.appendingPathComponent("Library/Application Support/net.whatsapp.WhatsApp/ChatStorage.sqlite")))
    }

    func testSingleSessionAndRestoreBringsEverythingBack() async throws {
        let (e, engine) = env()
        let app = makeApp(e, "Bar", id: "com.foo.Bar")
        residues(e, "com.foo.Bar")
        let m = UninstallerModule(engine: engine, app: app)
        let res = try await m.clean(items: try await m.scan().items, dryRun: false)
        XCTAssertEqual(res.moved, 10)
        XCTAssertFalse(e.exists(app))
        XCTAssertFalse(e.exists(e.home.appendingPathComponent("Library/Preferences/com.foo.Bar.plist")))
        let man = try engine.store.load(res.sessionID!)
        XCTAssertEqual(Set(man.items.map(\.group)), ["app:com.foo.Bar"])

        let out = try await engine.restorer.restore(sessionID: res.sessionID!)
        XCTAssertEqual(out.restored.count, 10)
        XCTAssertTrue(e.exists(app.appendingPathComponent("Contents/Info.plist")))
        XCTAssertTrue(e.exists(e.home.appendingPathComponent("Library/Preferences/com.foo.Bar.plist")))
        XCTAssertTrue(e.exists(e.home.appendingPathComponent("Library/LaunchAgents/com.foo.Bar.plist")))
    }
}
