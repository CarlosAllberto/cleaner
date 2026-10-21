import Foundation

public enum UninstallRisk: String, Sendable {
    case exact  // bundle ID idêntico
    case broad  // só o nome do app bate: maior risco de pegar o que não é do app
}

public struct UninstallItem: Sendable, Identifiable {
    public var id: URL { item.url }
    public let item: CleanItem
    public let risk: UninstallRisk
    /// Motivo da PathPolicy. Itens bloqueados aparecem na lista mas o QuarantineService os ignora.
    public let blockedReason: String?
}

public struct UninstallPlan: Sendable {
    public let bundleID: String
    public let appName: String
    public let items: [UninstallItem]
    public var group: String { "app:\(bundleID)" }
}

public struct InstalledApp: Sendable, Identifiable, Hashable {
    public var id: URL { url }
    public let url: URL
    public let name: String
}

/// Remove um .app e seus resíduos por bundle ID exato. Tudo vai na mesma sessão (group `app:<id>`).
public struct UninstallerModule: CleanupModule {
    public let id = ModuleID.uninstaller
    public let quarantine: QuarantineService
    let config: AppConfig
    let policy: PathPolicy
    let appURL: URL
    let includeBroad: Bool

    public init(engine: Engine, app: URL, includeBroad: Bool = false) {
        self.quarantine = engine.quarantine
        self.config = engine.config
        self.policy = engine.policy
        self.appURL = app
        self.includeBroad = includeBroad
    }

    public func scan() async throws -> ScanResult { ScanResult(items: try plan().items.map(\.item)) }

    /// Lê o Info.plist, recusa apps do sistema/Apple e lista o .app + resíduos.
    public func plan() throws -> UninstallPlan {
        let app = FS.normalize(appURL)
        guard app.pathExtension == "app" else { throw CleanerError.rejected("não é um .app") }
        let real = URL(fileURLWithPath: FS.realpath(app.path) ?? app.path)
        if [app, real].contains(where: { $0.path.hasPrefix("/System/") }) {
            throw CleanerError.rejected("apps do sistema não podem ser desinstalados")
        }
        let plist = (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]) ?? [:]
        guard let bid = plist["CFBundleIdentifier"] as? String, !bid.isEmpty, !bid.contains("/") else {
            throw CleanerError.rejected("Info.plist sem CFBundleIdentifier")
        }
        if bid.lowercased().hasPrefix("com.apple.") { throw CleanerError.rejected("apps da Apple não podem ser desinstalados") }
        if bid == AppConfig.bundleID { throw CleanerError.rejected("o Cleaner não desinstala a si mesmo") }
        let fileName = app.deletingPathExtension().lastPathComponent
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? fileName

        let lib = config.home.appendingPathComponent("Library")
        func sub(_ d: String) -> URL { lib.appendingPathComponent(d) }

        var found: [(URL, String, UninstallRisk)] = [(app, "Aplicativo", .exact)]
        func children(_ dir: URL) -> [URL] {
            (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        }
        // Exato: o nome do arquivo tem de ser igual ao id (ou `<prefixo>.<id>` nos Group Containers).
        let exact: [(String, String, (String) -> Bool)] = [
            ("Application Support", "Dados", { $0 == bid }),
            ("Preferences", "Preferências", { $0 == "\(bid).plist" }),
            ("Containers", "Container", { $0 == bid }),
            ("Group Containers", "Container de grupo", { $0 == bid || $0.hasSuffix(".\(bid)") }),
            ("Saved Application State", "Estado salvo", { $0 == "\(bid).savedState" }),
            ("Caches", "Cache", { $0 == bid }),
            ("HTTPStorages", "Armazenamento HTTP", { $0 == bid || $0 == "\(bid).binarycookies" }),
            ("WebKit", "WebKit", { $0 == bid }),
            ("LaunchAgents", "Agente de inicialização", { $0 == "\(bid).plist" }),
        ]
        for (dir, label, match) in exact {
            for u in children(sub(dir)) where match(u.lastPathComponent) { found.append((u, label, .exact)) }
        }
        if includeBroad {
            let names = Set([name, fileName].map { $0.lowercased() }).filter { $0.count >= 3 }
            for dir in ["Application Support", "Caches", "Logs", "Containers"] {
                for u in children(sub(dir)) where names.contains(u.lastPathComponent.lowercased()) {
                    found.append((u, "Busca ampla: \(dir)", .broad))
                }
            }
            for u in children(sub("Preferences")) where u.pathExtension == "plist"
                && names.contains(u.deletingPathExtension().lastPathComponent.lowercased()) {
                found.append((u, "Busca ampla: Preferências", .broad))
            }
        }

        var seen = Set<String>()
        let group = "app:\(bid)"
        let items = found.compactMap { (url, label, risk) -> UninstallItem? in
            var blocked: String?
            var target = url
            switch policy.check(url, module: id) {
            case .allowed(let r): target = r
            case .denied(let why): blocked = why
            }
            guard seen.insert(target.path).inserted else { return nil }
            let item = CleanItem(url: target, size: DirectorySizer.size(of: target).bytes, kind: FS.kind(of: target),
                                 modificationDate: (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                                 label: label, group: group)
            return UninstallItem(item: item, risk: risk, blockedReason: blocked)
        }
        return UninstallPlan(bundleID: bid, appName: name, items: items)
    }

    /// .app em /Applications e ~/Applications (um nível), por nome.
    public static func installedApps(config: AppConfig) -> [InstalledApp] {
        let dirs = [URL(fileURLWithPath: "/Applications"), config.home.appendingPathComponent("Applications")]
        let apps = dirs.flatMap { dir in
            ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "app" }
        }
        return apps.map { InstalledApp(url: $0, name: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
