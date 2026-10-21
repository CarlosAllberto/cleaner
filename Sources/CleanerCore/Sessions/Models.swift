import Foundation

public enum ModuleID: String, Codable, CaseIterable, Sendable {
    case systemJunk, whatsapp, orphans, uninstaller, duplicates, fullCleanup, largeFiles
}

public enum ItemKind: String, Codable, Sendable { case file, directory, symlink }

public enum ItemStatus: String, Codable, Sendable {
    case pending        // no manifesto, ainda não movido (ou crash antes de registrar)
    case moved
    case failed         // nunca saiu do lugar
    case unrecoverable  // sumiu da quarentena
    case expired        // apagado definitivamente
}

/// Candidato a limpeza, produzido pelos módulos. Só o QuarantineService mexe no disco.
public struct CleanItem: Sendable, Hashable, Identifiable {
    public var id: URL { url }
    public let url: URL
    public let size: Int64
    public let kind: ItemKind
    public let modificationDate: Date?
    public let label: String
    public let group: String?

    public init(url: URL, size: Int64, kind: ItemKind, modificationDate: Date? = nil,
                label: String = "", group: String? = nil) {
        self.url = url; self.size = size; self.kind = kind
        self.modificationDate = modificationDate; self.label = label; self.group = group
    }
}

public struct ManifestItem: Codable, Sendable, Identifiable {
    public let id: UUID
    public let originalPath: String
    public let quarantinePath: String
    public let size: Int64
    public let volume: String
    public let kind: ItemKind
    public let permissions: Int
    public let creationDate: Date?
    public let modificationDate: Date?
    public let checksum: String?
    public let group: String?
    public var status: ItemStatus
    public var failureReason: String?
}

public struct Manifest: Codable, Sendable {
    public var formatVersion: Int
    public let sessionID: UUID
    public let createdAt: Date
    public let expiresAt: Date
    public let module: ModuleID
    public var items: [ManifestItem]

    public var activeItems: [ManifestItem] { items.filter { $0.status == .moved || $0.status == .pending } }
    public var activeBytes: Int64 { activeItems.reduce(0) { $0 + $1.size } }
}
