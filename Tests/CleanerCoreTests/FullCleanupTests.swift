import XCTest
@testable import CleanerCore

final class FullCleanupTests: XCTestCase {
    func module(_ e: Env) -> FullCleanupModule {
        FullCleanupModule(engine: e.engine, orphans: OrphansModule(
            engine: e.engine, appDirs: [e.home.appendingPathComponent("Applications")], launchServices: { _ in false }))
    }

    func old(_ url: URL) {
        try! FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-200 * 86_400)],
                                               ofItemAtPath: url.path)
    }

    func testScanGroupsAndSkipsDownloadsAndArchives() async throws {
        let e = Env()
        e.file("Library/Caches/algum/blob")
        e.file("Library/Logs/app.log")
        e.file(".Trash/velho.txt")
        old(e.file("Downloads/antigo.dmg"))
        e.file("Library/Developer/Xcode/DerivedData/App-abc/Build/x")
        e.file("Library/Developer/CoreSimulator/Caches/dyld/x")
        let archive = e.file("Library/Developer/Xcode/Archives/2026/App.xcarchive")
        e.file("Library/Developer/CoreSimulator/Devices/UUID/data")
        old(e.file("Library/Application Support/com.foo.Gone/d").deletingLastPathComponent())
        old(e.file("Library/Caches/com.foo.Gone/d").deletingLastPathComponent())

        let items = try await module(e).scan().items
        let got = Set(items.map { "\($0.url.lastPathComponent):\(FullCleanupGroup($0)!.rawValue)" })
        XCTAssertEqual(got, ["algum:caches", "app.log:caches", "App-abc:xcode", "dyld:xcode",
                             "com.foo.Gone:leftovers"])
        XCTAssertEqual(items.filter { $0.url.lastPathComponent == "com.foo.Gone" }.count, 2, "Caches e App Support")
        XCTAssertEqual(Set(items.map(\.url)).count, items.count, "sem duplicados")

        let res = try await module(e).clean(items: items, dryRun: false)
        XCTAssertEqual(res.moved, items.count)
        XCTAssertTrue(e.exists(archive))
        XCTAssertTrue(e.exists(e.home.appendingPathComponent("Downloads/antigo.dmg")))
        XCTAssertFalse(e.exists(e.home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-abc")))
        XCTAssertEqual(try e.manifest(res.sessionID!).module, .fullCleanup)

        _ = try await e.engine.restorer.restore(sessionID: res.sessionID!) { _ in .suffix }
        XCTAssertEqual(e.text(e.home.appendingPathComponent("Library/Developer/Xcode/DerivedData/App-abc/Build/x")), "conteudo")
        XCTAssertTrue(e.exists(e.home.appendingPathComponent(".Trash/velho.txt")))
    }

    func testPolicyScope() {
        let e = Env()
        let h = e.home
        for rel in ["Downloads/a", "Documents/a", "Library/Developer/Xcode/Archives/a",
                    "Library/Developer/CoreSimulator/Devices/a", "Library/Application Support/Cleaner/a",
                    "Library/Keychains/a", "Desktop/a", ".Trash/a", ".npm/_logs/a", ".gradle/wrapper/a"] {
            XCTAssertNotEqual(e.engine.policy.check(h.appendingPathComponent(rel), module: .fullCleanup),
                              .allowed(h.appendingPathComponent(rel)), rel)
        }
        for rel in ["Library/Caches/a", "Library/Logs/a", "Library/Developer/Xcode/DerivedData/a",
                    "Library/Developer/CoreSimulator/Caches/a", "Library/Preferences/com.x.y.plist",
                    ".npm/_cacache/a", ".cache/a", "Library/Developer/Xcode/iOS DeviceSupport/a"] {
            XCTAssertEqual(e.engine.policy.check(h.appendingPathComponent(rel), module: .fullCleanup),
                           .allowed(h.appendingPathComponent(rel)), rel)
        }
        XCTAssertNotEqual(e.engine.policy.check(URL(fileURLWithPath: "/usr/lib/x"), module: .fullCleanup),
                          .allowed(URL(fileURLWithPath: "/usr/lib/x")))
    }

    func testDevAndAppCachesOnlyCacheFolders() async throws {
        let e = Env()
        let dev = [".npm/_cacache/content-v2/x", ".cache/pip/x", ".gradle/caches/modules-2/x",
                   ".cargo/registry/cache/idx/x", "Library/pnpm/store/v3/x", ".bun/install/cache/pkg/x",
                   "Library/Developer/Xcode/iOS DeviceSupport/17.0/x",
                   "Library/Developer/Xcode/macOS DeviceSupport/14.0/x",
                   "Library/Developer/Xcode/watchOS DeviceSupport/10.0/x"]
        for d in dev { e.file(d) }
        e.file(".npm/_logs/debug.log")
        e.file(".npm/config")
        let appSupport = ["Cursor/Cache/a", "Cursor/Code Cache/a", "Cursor/GPUCache/a", "Cursor/CachedData/a",
                          "Slack/DawnCache/a", "Slack/DawnGraphiteCache/a", "Slack/GrShaderCache/a",
                          "Slack/ShaderCache/a", "Claude/Service Worker/CacheStorage/a", "Vendor/App/Cache/a"]
        for a in appSupport { e.file("Library/Application Support/\(a)") }
        for keep in ["Cursor/Local Storage/a", "Cursor/IndexedDB/a", "Claude/Service Worker/Database/a",
                     "Slack/Cookies", "Vendor/App/Local Storage/a"] {
            e.file("Library/Application Support/\(keep)")
        }
        e.file("Library/Containers/com.x.app/Data/Library/Caches/blob/a")
        e.file("Library/Containers/com.x.app/Data/Library/Preferences/p.plist")
        // Todo app conta como instalado: nada vira resto, só os caches aparecem.
        let m = FullCleanupModule(engine: e.engine, orphans: OrphansModule(
            engine: e.engine, appDirs: [e.home.appendingPathComponent("Applications")], launchServices: { _ in true }))
        let items = try await m.scan().items
        let rel = { (g: FullCleanupGroup) in
            Set(items.filter { FullCleanupGroup($0) == g }.map { String($0.url.path.dropFirst(e.home.path.count + 1)) })
        }
        XCTAssertEqual(rel(.devCaches), Set(dev.map { ($0 as NSString).deletingLastPathComponent }))
        XCTAssertEqual(rel(.appCaches), Set(appSupport.map { "Library/Application Support/" + ($0 as NSString).deletingLastPathComponent }
                                             + ["Library/Containers/com.x.app/Data/Library/Caches/blob"]))
        XCTAssertEqual(items.first { $0.url.lastPathComponent == "Cache" && $0.url.path.contains("Vendor") }?.group, "App")
        XCTAssertFalse(items.contains { $0.url.path.contains("Local Storage") || $0.url.path.contains("IndexedDB")
                                        || $0.url.path.contains("/.npm/_logs") || $0.url.lastPathComponent == "config" })

        let npm = items.filter { $0.url.path.hasSuffix(".npm/_cacache/content-v2") }
        XCTAssertEqual(npm.count, 1)
        let res = try await m.clean(items: npm, dryRun: false)
        XCTAssertEqual(res.moved, 1)
        XCTAssertFalse(e.exists(npm[0].url))
        _ = try await e.engine.restorer.restore(sessionID: res.sessionID!) { _ in .suffix }
        XCTAssertEqual(e.text(e.home.appendingPathComponent(".npm/_cacache/content-v2/x")), "conteudo")
    }
}
