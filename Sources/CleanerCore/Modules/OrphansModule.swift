import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Resíduos em ~/Library de apps que não estão mais instalados. Agrupa por bundle ID (`orphan:<id>`).
public struct OrphansModule: CleanupModule {
    public let id = ModuleID.orphans
    public let quarantine: QuarantineService
    let config: AppConfig
    let policy: PathPolicy
    let appDirs: [URL]
    let minAgeDays: Int
    let now: @Sendable () -> Date
    let launchServices: @Sendable (String) -> Bool

    public static func systemLaunchServices(_ bundleID: String) -> Bool {
        #if canImport(AppKit)
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        #else
        return false
        #endif
    }

    public init(engine: Engine, appDirs: [URL]? = nil, minAgeDays: Int = 30,
                now: @escaping @Sendable () -> Date = { Date() },
                launchServices: @escaping @Sendable (String) -> Bool = OrphansModule.systemLaunchServices) {
        self.quarantine = engine.quarantine
        self.config = engine.config
        self.policy = engine.policy
        self.appDirs = appDirs ?? [URL(fileURLWithPath: "/Applications"),
                                   engine.config.home.appendingPathComponent("Applications"),
                                   URL(fileURLWithPath: "/System/Applications")]
        self.minAgeDays = minAgeDays
        self.now = now
        self.launchServices = launchServices
    }

    /// Pasta de ~/Library -> rótulo exibido.
    static let sources = ["Application Support", "Preferences", "Containers", "Group Containers",
                          "Saved Application State", "Caches", "LaunchAgents", "HTTPStorages", "WebKit"]

    public func scan() async throws -> ScanResult { try await scanDetailed().result }

    /// `blocked`: itens recusados pela PathPolicy. Ficam na lista, mas o QuarantineService os ignora.
    public func scanDetailed() async throws -> (result: ScanResult, blocked: Set<URL>) {
        let installed = installedIDs()
        let cutoff = now().addingTimeInterval(-TimeInterval(minAgeDays) * 86_400)
        let lib = config.home.appendingPathComponent("Library")

        var result = ScanResult()
        var blocked = Set<URL>()
        var candidates: [(url: URL, label: String, bid: String, mod: Date?)] = []
        for label in Self.sources {
            let dir = lib.appendingPathComponent(label)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else {
                if FileManager.default.fileExists(atPath: dir.path) { result.inaccessible.append(dir) }
                continue
            }
            for url in children {
                guard let bid = Self.bundleID(of: url.lastPathComponent, in: label),
                      !bid.lowercased().hasPrefix("com.apple."), bid != AppConfig.bundleID,
                      !isInstalled(bid, installed) else { continue }
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let m = mod, m > cutoff { continue }
                switch policy.check(url, module: id) {
                case .allowed(let real): candidates.append((real, label, bid, mod))
                case .denied: blocked.insert(url); candidates.append((url, label, bid, mod))
                }
            }
        }

        let sized = await withTaskGroup(of: (CleanItem, Bool).self) { group in
            for c in candidates {
                group.addTask {
                    let s = DirectorySizer.size(of: c.url)
                    return (CleanItem(url: c.url, size: s.bytes, kind: FS.kind(of: c.url), modificationDate: c.mod,
                                      label: c.label, group: "orphan:\(c.bid)"), s.inaccessible)
                }
            }
            var out: [(CleanItem, Bool)] = []
            for await r in group { out.append(r) }
            return out
        }
        result.items = sized.map(\.0).sorted { $0.size > $1.size }
        result.inaccessible += sized.filter(\.1).map(\.0.url)
        return (result, blocked)
    }

    // MARK: - Bundle ID

    /// Deriva o bundle ID do nome da entrada; nil se não tiver formato de bundle ID.
    static func bundleID(of name: String, in folder: String) -> String? {
        var n = name
        for ext in [".plist", ".savedState", ".binarycookies"] where n.hasSuffix(ext) { n.removeLast(ext.count) }
        if folder == "Group Containers" {
            if n.hasPrefix("group.") { n.removeFirst(6) }
            else if let dot = n.firstIndex(of: "."), n.distance(from: n.startIndex, to: dot) == 10 {
                n = String(n[n.index(after: dot)...])  // prefixo de Team ID (ex.: ABCDE12345.com.foo.app)
            }
        }
        let parts = n.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }),
              parts[0].allSatisfy({ $0.isLetter && $0.isASCII }),
              n.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) else { return nil }
        return n
    }

    // MARK: - Apps instalados

    /// Instalado se o id é igual (ou é prefixo de helper `<id>.xyz`) a algum app indexado ou o LaunchServices o resolve.
    func isInstalled(_ bid: String, _ installed: Set<String>) -> Bool {
        let l = bid.lowercased()
        if installed.contains(l) || installed.contains(where: { l.hasPrefix($0 + ".") }) { return true }
        return launchServices(bid)
    }

    /// IDs (minúsculos) dos .app até 2 níveis de subpastas.
    func installedIDs() -> Set<String> {
        var ids = Set<String>()
        func walk(_ dir: URL, depth: Int) {
            for u in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                if u.pathExtension == "app" {
                    let plist = NSDictionary(contentsOf: u.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
                    if let b = plist?["CFBundleIdentifier"] as? String { ids.insert(b.lowercased()) }
                } else if depth < 2, FS.kind(of: u) == .directory { walk(u, depth: depth + 1) }
            }
        }
        for d in appDirs { walk(d, depth: 1) }
        return ids
    }
}
