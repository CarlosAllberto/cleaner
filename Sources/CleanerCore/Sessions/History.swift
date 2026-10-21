import Foundation

public struct HistorySession: Sendable, Identifiable {
    public var id: UUID { sessionID }
    public let sessionID: UUID
    public let module: ModuleID
    public let createdAt: Date
    public let expiresAt: Date
    public let itemCount: Int
    public let bytes: Int64
    public let items: [ManifestItem]

    public func remaining(now: Date = Date()) -> TimeInterval { max(0, expiresAt.timeIntervalSince(now)) }
}

public struct RestoreConflict: Sendable, Identifiable {
    public var id: UUID { item.id }
    public let item: ManifestItem
    /// Onde o item voltaria (já validado pela política).
    public let destination: URL
}

public extension SessionStore {
    /// Sessões com algo restaurável ou irrecuperável (para avisar), mais recentes primeiro.
    func historySessions() -> [HistorySession] {
        loadAll().compactMap { m in
            let items = m.items.filter { [.moved, .pending, .unrecoverable].contains($0.status) }
            guard !items.isEmpty else { return nil }
            return HistorySession(sessionID: m.sessionID, module: m.module, createdAt: m.createdAt,
                                  expiresAt: m.expiresAt, itemCount: m.activeItems.count,
                                  bytes: m.activeBytes, items: items)
        }.sorted { $0.createdAt > $1.createdAt }
    }
}

public extension Restorer {
    /// Itens (moved/pending, dentro de `items` se dado) cujo destino já existe. Não toca no disco.
    func conflicts(sessionID: UUID, items: Set<UUID>? = nil) throws -> [RestoreConflict] {
        let m = try store.load(sessionID)
        return m.activeItems.compactMap { item in
            guard items?.contains(item.id) ?? true,
                  let dest = try? validator.originalURL(for: item, module: m.module), FS.exists(dest) else { return nil }
            return RestoreConflict(item: item, destination: dest)
        }
    }
}

public extension ManifestItem {
    /// Bundle id quando o item é um plist em ~/Library/Preferences (`com.x.y.plist`).
    var preferencesBundleID: String? {
        let u = URL(fileURLWithPath: originalPath)
        guard u.deletingLastPathComponent().lastPathComponent == "Preferences", u.pathExtension == "plist" else { return nil }
        return u.deletingPathExtension().lastPathComponent
    }
}
