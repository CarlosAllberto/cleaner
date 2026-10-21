import Foundation

public struct ModuleScope: Sendable {
    public var allowedRoots: [URL]
    /// Se verdadeiro, pastas candidatas são varridas em busca de nomes protegidos (bancos do WhatsApp).
    public var deepNameCheck: Bool
    /// Raízes da denylist que só este módulo pode atravessar (ex.: ~/Documents para Duplicados).
    public var denyExceptions: [URL]

    public init(allowedRoots: [URL], deepNameCheck: Bool = false, denyExceptions: [URL] = []) {
        self.allowedRoots = allowedRoots
        self.deepNameCheck = deepNameCheck
        self.denyExceptions = denyExceptions
    }
}

public enum PolicyDecision: Equatable, Sendable {
    case allowed(URL)   // caminho já resolvido (pai sem symlinks)
    case denied(String)
}

/// Allowlist por módulo + denylist global. A denylist sempre vence.
public struct PathPolicy: Sendable {
    public var scopes: [ModuleID: ModuleScope]
    private let denyRoots: [URL]

    public init(config: AppConfig, scopes: [ModuleID: ModuleScope]? = nil, extraDenyRoots: [URL] = []) {
        let home = config.home
        let lib = home.appendingPathComponent("Library")
        let system = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/private/var/db",
                      "/Library/Apple", "/Library/Extensions"].map { URL(fileURLWithPath: $0) }
        let homeRel = ["Documents", "Desktop", "Pictures", "Movies", "Music", ".ssh", ".gnupg",
                       "Library/Keychains", "Library/Mobile Documents", "Library/Messages"]
            .map { home.appendingPathComponent($0) }
        self.denyRoots = (system + homeRel + [config.supportDir] + extraDenyRoots).map(Self.resolve)

        let orphanRoots = ["Application Support", "Preferences", "Containers", "Group Containers",
                           "Saved Application State", "Caches", "LaunchAgents", "HTTPStorages", "WebKit"]
            .map { lib.appendingPathComponent($0) }
        let userFolders = ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"]
            .map { home.appendingPathComponent($0) }
        let homeFolders = Self.userHomeFolders(home)
        self.scopes = scopes ?? [
            .systemJunk: ModuleScope(allowedRoots: [lib.appendingPathComponent("Caches"),
                                                    lib.appendingPathComponent("Logs")]),
            .whatsapp: ModuleScope(
                allowedRoots: [config.whatsAppRoot],
                deepNameCheck: true),
            .orphans: ModuleScope(allowedRoots: orphanRoots, deepNameCheck: true),
            .fullCleanup: ModuleScope(allowedRoots: orphanRoots + [lib.appendingPathComponent("Logs")] + FullCleanupModule.xcodeDirs(lib)
                                      + FullCleanupModule.devCacheDirs(home), deepNameCheck: true),
            .uninstaller: ModuleScope(
                allowedRoots: orphanRoots + [URL(fileURLWithPath: "/Applications"),
                                             home.appendingPathComponent("Applications")],
                deepNameCheck: true),
            .duplicates: ModuleScope(
                allowedRoots: userFolders,
                deepNameCheck: true,
                denyExceptions: userFolders),
            .largeFiles: ModuleScope(
                allowedRoots: homeFolders,
                deepNameCheck: true,
                denyExceptions: userFolders),
        ]
    }

    /// Pastas visíveis direto na home, menos Library (Documents, Downloads, ~/Projetos…). Lidas uma vez, ao criar a política.
    static func userHomeFolders(_ home: URL) -> [URL] {
        let kids = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil,
                                                                 options: .skipsHiddenFiles)) ?? []
        return kids.filter { $0.lastPathComponent != "Library" && FS.kind(of: $0) == .directory }
    }

    // MARK: - Decisão

    public func check(_ url: URL, module: ModuleID) -> PolicyDecision {
        guard let scope = scopes[module] else { return .denied("módulo sem escopo") }
        let std = FS.normalize(url)
        guard std.path.hasPrefix("/"), std.path != "/" else { return .denied("caminho inválido") }

        // Resolve só o pai: o item em si pode ser um symlink e é ele que será movido.
        let candidate = Self.resolve(std.deletingLastPathComponent()).appendingPathComponent(std.lastPathComponent)
        let except = Set(scope.denyExceptions.map { Self.resolve($0).path })
        if let reason = denyReason(candidate, except: except) { return .denied(reason) }

        let roots = scope.allowedRoots.map(Self.resolve)
        guard roots.contains(where: { Self.isInside(candidate, $0) }) else {
            return .denied("fora do escopo do módulo")
        }

        if FS.kind(of: candidate) == .symlink, let real = FS.realpath(candidate.path) {
            let target = URL(fileURLWithPath: real)
            if denyReason(target, except: except) != nil || !roots.contains(where: { Self.isInside(target, $0) }) {
                return .denied("symlink aponta para fora do escopo")
            }
        }

        if scope.deepNameCheck, FS.kind(of: candidate) == .directory, let hit = protectedDescendant(of: candidate) {
            return .denied("contém item protegido: \(hit)")
        }
        return .allowed(candidate)
    }

    private func denyReason(_ candidate: URL, except: Set<String> = []) -> String? {
        for root in denyRoots where !except.contains(root.path) {
            if candidate.path == root.path || Self.isInside(candidate, root) { return "caminho protegido" }
            if Self.isInside(root, candidate) { return "contém caminho protegido" }
        }
        if candidate.pathComponents.contains(where: { Self.isProtectedName($0, in: candidate.path) }) {
            return "arquivo protegido (banco de dados)"
        }
        return nil
    }

    private func protectedDescendant(of dir: URL) -> String? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in e where Self.isProtectedName(url.lastPathComponent, in: url.path) {
            return url.lastPathComponent
        }
        return nil
    }

    static func isProtectedName(_ name: String, in path: String) -> Bool {
        let n = name.lowercased()
        if n.hasPrefix("chatstorage") { return true }
        guard path.lowercased().contains("whatsapp") else { return false }
        return [".sqlite", ".sqlite-wal", ".sqlite-shm", ".db"].contains { n.hasSuffix($0) }
    }

    // MARK: - Caminhos

    /// realpath do ancestral existente mais próximo + componentes restantes (funciona p/ caminhos que ainda não existem).
    static func resolve(_ url: URL) -> URL {
        var rest: [String] = []
        var cur = FS.normalize(url)
        while true {
            if let real = FS.realpath(cur.path) {
                return rest.reversed().reduce(URL(fileURLWithPath: real)) { $0.appendingPathComponent($1) }
            }
            if cur.path == "/" { return FS.normalize(url) }
            rest.append(cur.lastPathComponent)
            cur = cur.deletingLastPathComponent()
        }
    }

    /// `child` está estritamente dentro de `root`, comparando por componente.
    public static func isInside(_ child: URL, _ root: URL) -> Bool {
        let c = child.pathComponents, r = root.pathComponents
        return c.count > r.count && Array(c.prefix(r.count)) == r
    }
}
