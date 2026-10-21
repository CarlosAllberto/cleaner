import Foundation
import XCTest
@testable import CleanerCore

/// Ambiente descartável: home falsa dentro de um diretório temporário. Nunca toca no Mac real.
final class Env {
    let root: URL
    let home: URL
    let config: AppConfig
    let engine: Engine

    init(retentionDays: Int = 7, volumes: VolumeResolver = .system, scopes: [ModuleID: ModuleScope]? = nil,
         now: @escaping @Sendable () -> Date = { Date() },
         beforeMove: (@Sendable (UUID, ManifestItem) -> Void)? = nil) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: FS.realpath(tmp.path)!)
        home = root.appendingPathComponent("home")
        config = AppConfig(supportDir: home.appendingPathComponent("Library/Application Support/Cleaner"),
                           home: home, retentionDays: retentionDays)
        for d in ["Library/Caches", "Library/Logs", "Documents", "Downloads", ".Trash"] {
            try! FileManager.default.createDirectory(at: home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        let policy = PathPolicy(config: config, scopes: scopes)
        engine = Engine(config: config, policy: policy, volumes: volumes, now: now, beforeMove: beforeMove)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func file(_ rel: String, _ content: String = "conteudo", under base: URL? = nil) -> URL {
        let url = (base ?? home).appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! content.data(using: .utf8)!.write(to: url)
        return url
    }

    func item(_ url: URL) -> CleanItem {
        CleanItem(url: url, size: DirectorySizer.size(of: url).bytes, kind: FS.kind(of: url))
    }

    func cache(_ name: String, _ content: String = "lixo de cache") -> CleanItem {
        item(file("Library/Caches/\(name)", content))
    }

    func exists(_ url: URL) -> Bool { FS.exists(url) }
    func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    func manifest(_ id: UUID) throws -> Manifest { try engine.store.load(id) }

    /// Reescreve o JSON do manifesto no disco (simula adulteração).
    func tamper(_ id: UUID, _ edit: (inout [String: Any]) -> Void) throws {
        let url = engine.store.url(for: id)
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        edit(&obj)
        try JSONSerialization.data(withJSONObject: obj).write(to: url)
    }
}
