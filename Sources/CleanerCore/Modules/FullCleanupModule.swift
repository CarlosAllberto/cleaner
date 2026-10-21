import Foundation

/// Grupo de um item da Limpeza Completa (vai em `CleanItem.label`).
public enum FullCleanupGroup: String, CaseIterable, Sendable {
    case caches, xcode, devCaches, appCaches, leftovers

    public init?(_ item: CleanItem) { self.init(rawValue: item.label) }
}

/// Limpeza em um clique: caches e logs (sem Downloads nem Lixeira), resíduos de apps removidos,
/// caches do Xcode, de ferramentas de programação e de apps. Cada item é revalidado no escopo `.fullCleanup`.
public struct FullCleanupModule: CleanupModule {
    public let id = ModuleID.fullCleanup
    public let quarantine: QuarantineService
    let config: AppConfig
    let policy: PathPolicy
    let junk: SystemJunkModule
    let orphans: OrphansModule

    public init(engine: Engine, orphans: OrphansModule? = nil) {
        self.quarantine = engine.quarantine
        self.config = engine.config
        self.policy = engine.policy
        self.junk = SystemJunkModule(engine: engine)
        self.orphans = orphans ?? OrphansModule(engine: engine)
    }

    /// Só filhos diretos destas pastas. Nunca Archives nem dispositivos do simulador.
    public static func xcodeDirs(_ lib: URL) -> [URL] {
        [lib.appendingPathComponent("Developer/Xcode/DerivedData"),
         lib.appendingPathComponent("Developer/CoreSimulator/Caches")]
    }

    /// Caches de ferramentas de programação (baixados de novo quando preciso). Só filhos diretos.
    public static func devCacheDirs(_ home: URL) -> [URL] {
        [".npm/_cacache", ".cache", ".gradle/caches", ".cargo/registry/cache", "Library/pnpm/store",
         ".bun/install/cache", "Library/Developer/Xcode/iOS DeviceSupport",
         "Library/Developer/Xcode/macOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport"]
            .map { home.appendingPathComponent($0) }
    }

    /// Nomes de pasta de cache (Chromium/Electron) aceitos em `Application Support/<App>/` ou `<Vendor>/<App>/`.
    static let appCacheNames: Set<String> = ["Cache", "Code Cache", "GPUCache", "CachedData", "DawnCache",
                                             "DawnGraphiteCache", "GrShaderCache", "ShaderCache"]

    /// Pastas de cache de apps: cada uma vira um item, rotulado com o nome do app.
    func appCacheDirs(_ lib: URL) -> [(url: URL, app: String)] {
        func dirs(_ u: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? [])
                .filter { FS.kind(of: $0) == .directory }
        }
        func caches(in app: URL) -> [URL] {
            dirs(app).compactMap { d in
                if Self.appCacheNames.contains(d.lastPathComponent) { return d }
                let cs = d.appendingPathComponent("CacheStorage")
                return d.lastPathComponent == "Service Worker" && FS.kind(of: cs) == .directory ? cs : nil
            }
        }
        var out: [(URL, String)] = []
        for app in dirs(lib.appendingPathComponent("Application Support")) {
            out += caches(in: app).map { ($0, app.lastPathComponent) }
            for sub in dirs(app) { out += caches(in: sub).map { ($0, sub.lastPathComponent) } }
        }
        for c in dirs(lib.appendingPathComponent("Containers")) {
            let dir = c.appendingPathComponent("Data/Library/Caches")
            for u in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                out.append((u, c.lastPathComponent))
            }
        }
        return out
    }

    public func scan() async throws -> ScanResult {
        var result = ScanResult()
        var tagged: [(CleanItem, FullCleanupGroup)] = []

        // Resíduos primeiro: num cache repetido, "resto de app" é o rótulo mais útil.
        let o = try await orphans.scanDetailed()
        result.inaccessible += o.result.inaccessible
        for item in o.result.items where !o.blocked.contains(item.url) { tagged.append((item, .leftovers)) }

        let j = try await junk.scan()
        result.inaccessible += j.inaccessible
        for item in j.items { tagged.append((item, .caches)) }

        let lib = config.home.appendingPathComponent("Library")
        var found: [(url: URL, group: String, g: FullCleanupGroup)] = []
        for (dirs, g) in [(Self.xcodeDirs(lib), FullCleanupGroup.xcode), (Self.devCacheDirs(config.home), .devCaches)] {
            for dir in dirs {
                for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                    found.append((url, dir.lastPathComponent, g))
                }
            }
        }
        found += appCacheDirs(lib).map { ($0.url, $0.app, .appCaches) }
        for f in found {
            let s = DirectorySizer.size(of: f.url)
            if s.inaccessible { result.inaccessible.append(f.url) }
            tagged.append((CleanItem(url: f.url, size: s.bytes, kind: FS.kind(of: f.url), label: "", group: f.group), f.g))
        }

        // Revalida no escopo próprio; sem duplicados e sem itens dentro de outro item.
        var kept: [CleanItem] = []
        var seen = Set<String>()
        for (item, g) in tagged {
            guard case .allowed(let real) = policy.check(item.url, module: id), seen.insert(real.path).inserted
            else { continue }
            kept.append(CleanItem(url: real, size: item.size, kind: item.kind, modificationDate: item.modificationDate,
                                  label: g.rawValue, group: item.group ?? item.label))
        }
        kept = kept.filter { k in !kept.contains { PathPolicy.isInside(k.url, $0.url) } }
        result.items = kept.sorted { $0.size > $1.size }
        return result
    }
}
