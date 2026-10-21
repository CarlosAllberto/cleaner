import XCTest
@testable import CleanerCore

final class WhatsAppTests: XCTestCase {
    func makeEnv() -> (Env, URL) {
        let e = Env()
        return (e, e.config.whatsAppRoot)
    }

    func testScanClassifiesGroupsAndSkipsDatabases() async throws {
        let (e, wa) = makeEnv()
        e.file("Message/Media/5511@s.whatsapp.net/a/b/foto.jpg", "123", under: wa)
        e.file("Message/Media/5511@s.whatsapp.net/a/b/video.mp4", "1234567", under: wa)
        e.file("Message/Media/grupo@g.us/c/d/audio.opus", "1", under: wa)
        e.file("Message/Media/grupo@g.us/c/d/doc.pdf", "1", under: wa)
        e.file("ChatStorage.sqlite", "banco", under: wa)
        e.file("ChatStorage.sqlite-wal", "wal", under: wa)
        e.file("ContactsV2.sqlite", "contatos", under: wa)
        e.file("Message/Media/5511@s.whatsapp.net/a/b/nota.txt.sqlite", "x", under: wa)

        let r = try await WhatsAppModule(engine: e.engine).scan()
        XCTAssertEqual(Set(r.items.map(\.label)), ["photos", "videos", "audio", "documents"])
        XCTAssertEqual(r.items.count, 4)
        XCTAssertFalse(r.items.contains { $0.url.lastPathComponent.contains("sqlite") })
        XCTAssertEqual(Set(r.items.compactMap(\.group)), ["5511@s.whatsapp.net", "grupo@g.us"])
        XCTAssertEqual(WhatsAppModule.bytesByConversation(r.items).count, 2)
        XCTAssertGreaterThan(WhatsAppModule.bytesByCategory(r.items)[.videos] ?? 0, 0)
    }

    func testCleaningNeverTouchesDatabasesEvenIfSelected() async throws {
        let (e, wa) = makeEnv()
        let media = e.file("Message/Media/x@s.whatsapp.net/a/foto.jpg", "m", under: wa)
        let db = e.file("ChatStorage.sqlite", "banco", under: wa)
        let r = try await e.engine.quarantine.quarantine([e.item(media), e.item(db)], module: .whatsapp)
        XCTAssertEqual(r.moved, 1)
        XCTAssertEqual(r.skipped.count, 1)
        XCTAssertTrue(e.exists(db))
        XCTAssertFalse(e.exists(media))
    }

    func testFilterByAgeSizeAndCategory() {
        let now = Date()
        func it(_ n: String, _ label: String, _ size: Int64, ageDays: Int) -> CleanItem {
            CleanItem(url: URL(fileURLWithPath: "/x/\(n)"), size: size, kind: .file,
                      modificationDate: now.addingTimeInterval(-Double(ageDays) * 86_400), label: label)
        }
        let items = [it("velho.jpg", "photos", 5_000_000, ageDays: 400), it("novo.jpg", "photos", 5_000_000, ageDays: 10),
                     it("pequeno.jpg", "photos", 10, ageDays: 400), it("v.mp4", "videos", 9_000_000, ageDays: 400)]
        let f = WhatsAppFilter(categories: [.photos], olderThanDays: 180, minBytes: 1_000_000)
        XCTAssertEqual(f.apply(items, now: now).map(\.url.lastPathComponent), ["velho.jpg"])
        XCTAssertEqual(WhatsAppFilter().apply(items, now: now).count, 4)
    }

    func testConfigurableRoot() async throws {
        let e = Env()
        let custom = e.home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.v2")
        var cfg = e.config
        cfg.whatsAppRoot = custom
        let e2 = Engine(config: cfg)
        e.file("Message/Media/j/a/foto.png", "p", under: custom)
        let r = try await WhatsAppModule(engine: e2).scan()
        XCTAssertEqual(r.items.count, 1)
        let moved = try await e2.quarantine.quarantine(r.items, module: .whatsapp)
        XCTAssertEqual(moved.moved, 1)
    }

    func testFullDiskAccessProbe() throws {
        let e = Env()
        let readable = e.file("ok.db")
        XCTAssertTrue(FullDiskAccess.isGranted(probe: readable))
        XCTAssertFalse(FullDiskAccess.isGranted(probe: e.home.appendingPathComponent("nao-existe.db")))
        let locked = e.file("locked.db")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        XCTAssertFalse(FullDiskAccess.isGranted(probe: locked))
    }
}
