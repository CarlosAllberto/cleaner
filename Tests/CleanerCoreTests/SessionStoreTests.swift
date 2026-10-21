import XCTest
@testable import CleanerCore

final class SessionStoreTests: XCTestCase {
    func testRoundTrip() async throws {
        let e = Env()
        let r = try await e.engine.quarantine.quarantine([e.cache("a")], module: .systemJunk)
        let m = try e.manifest(r.sessionID!)
        XCTAssertEqual(m.formatVersion, 1)
        XCTAssertEqual(m.module, .systemJunk)
        XCTAssertEqual(m.items.count, 1)
        XCTAssertEqual(m.items[0].status, .moved)
        XCTAssertNotNil(m.items[0].checksum)
    }

    func testCorruptJSONThrows() async throws {
        let e = Env()
        let id = try await e.engine.quarantine.quarantine([e.cache("a")], module: .systemJunk).sessionID!
        try "{ isso não é json".write(to: e.engine.store.url(for: id), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try e.engine.store.load(id)) {
            guard case CleanerError.corruptManifest = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(e.engine.store.loadAll().isEmpty)
    }

    func testUnsupportedVersionThrows() async throws {
        let e = Env()
        let id = try await e.engine.quarantine.quarantine([e.cache("a")], module: .systemJunk).sessionID!
        try e.tamper(id) { $0["formatVersion"] = 99 }
        XCTAssertThrowsError(try e.engine.store.load(id)) { XCTAssertEqual($0 as? CleanerError, .unsupportedVersion(99)) }
    }

    func testSessionIDMustMatchFileName() async throws {
        let e = Env()
        let id = try await e.engine.quarantine.quarantine([e.cache("a")], module: .systemJunk).sessionID!
        try e.tamper(id) { $0["sessionID"] = UUID().uuidString }
        XCTAssertThrowsError(try e.engine.store.load(id))
    }
}
