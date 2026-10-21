import Foundation

/// Caches e logs. Cada filho direto das pastas vira um item. A Lixeira do macOS nunca é tocada.
public struct SystemJunkModule: CleanupModule {
    public let id = ModuleID.systemJunk
    public let quarantine: QuarantineService
    let config: AppConfig
    let policy: PathPolicy

    public init(engine: Engine) {
        self.quarantine = engine.quarantine
        self.config = engine.config
        self.policy = engine.policy
    }

    public func scan() async throws -> ScanResult {
        let lib = config.home.appendingPathComponent("Library")
        let sources: [(label: String, dir: URL)] = [
            ("Caches", lib.appendingPathComponent("Caches")),
            ("Logs", lib.appendingPathComponent("Logs")),
        ]

        var result = ScanResult()
        var candidates: [(URL, String, Date?)] = []
        for s in sources {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: s.dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else {
                if FileManager.default.fileExists(atPath: s.dir.path) { result.inaccessible.append(s.dir) }
                continue
            }
            for url in children where url.lastPathComponent != AppConfig.bundleID {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                guard case .allowed(let real) = policy.check(url, module: id) else { continue }
                candidates.append((real, s.label, mod))
            }
        }

        let sized = await withTaskGroup(of: (CleanItem, Bool).self) { group in
            for (url, label, mod) in candidates {
                group.addTask {
                    let s = DirectorySizer.size(of: url)
                    return (CleanItem(url: url, size: s.bytes, kind: FS.kind(of: url),
                                      modificationDate: mod, label: label), s.inaccessible)
                }
            }
            var out: [(CleanItem, Bool)] = []
            for await r in group { out.append(r) }
            return out
        }
        result.items = sized.map(\.0).sorted { $0.size > $1.size }
        result.inaccessible += sized.filter(\.1).map(\.0.url)
        return result
    }
}
