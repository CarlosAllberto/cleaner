import Foundation

public enum WhatsAppCategory: String, CaseIterable, Sendable {
    case photos, videos, audio, documents

    static let extensions: [WhatsAppCategory: Set<String>] = [
        .photos: ["jpg", "jpeg", "png", "heic", "webp", "gif"],
        .videos: ["mp4", "mov", "m4v", "3gp"],
        .audio: ["opus", "m4a", "mp3", "aac", "ogg", "caf", "amr"],
        .documents: ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "zip", "rar", "csv", "pages", "numbers", "key"],
    ]

    public static func of(_ url: URL) -> WhatsAppCategory? {
        let ext = url.pathExtension.lowercased()
        return allCases.first { extensions[$0]!.contains(ext) }
    }
}

/// Filtros da tela (puros, testáveis).
public struct WhatsAppFilter: Sendable {
    public var categories: Set<WhatsAppCategory>
    public var olderThanDays: Int?
    public var minBytes: Int64

    public init(categories: Set<WhatsAppCategory> = Set(WhatsAppCategory.allCases), olderThanDays: Int? = nil, minBytes: Int64 = 0) {
        self.categories = categories; self.olderThanDays = olderThanDays; self.minBytes = minBytes
    }

    public func apply(_ items: [CleanItem], now: Date = Date()) -> [CleanItem] {
        let cutoff = olderThanDays.map { now.addingTimeInterval(-TimeInterval($0) * 86_400) }
        return items.filter { item in
            guard let cat = WhatsAppCategory(rawValue: item.label), categories.contains(cat), item.size >= minBytes else { return false }
            if let cutoff { return (item.modificationDate ?? .distantFuture) < cutoff }
            return true
        }
    }
}

/// Só mídia e documentos do contêiner do WhatsApp. Bancos de mensagens nunca entram (nem aqui, nem na PathPolicy).
/// `label` = categoria, `group` = conversa (pasta logo abaixo de Media/).
public struct WhatsAppModule: CleanupModule {
    public let id = ModuleID.whatsapp
    public let quarantine: QuarantineService
    let root: URL

    public init(engine: Engine) {
        self.quarantine = engine.quarantine
        self.root = engine.config.whatsAppRoot
    }

    public func scan() async throws -> ScanResult {
        var result = ScanResult()
        guard FileManager.default.fileExists(atPath: root.path) else { return result }
        var denied = false
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [],
                                                      errorHandler: { _, _ in denied = true; return true }) else {
            result.inaccessible = [root]; return result
        }
        for case let url as URL in e {
            guard let cat = WhatsAppCategory.of(url), !PathPolicy.isProtectedName(url.lastPathComponent, in: url.path),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            result.items.append(CleanItem(url: url, size: Int64(v.totalFileAllocatedSize ?? 0), kind: .file,
                                          modificationDate: v.contentModificationDate, label: cat.rawValue,
                                          group: conversation(of: url)))
        }
        if denied { result.inaccessible = [root] }
        result.items.sort { $0.size > $1.size }
        return result
    }

    func conversation(of url: URL) -> String {
        let comps = url.pathComponents
        guard let i = comps.firstIndex(of: "Media"), i + 2 < comps.count else { return "Outros" }
        return comps[i + 1]
    }

    public static func bytesByCategory(_ items: [CleanItem]) -> [WhatsAppCategory: Int64] {
        items.reduce(into: [:]) { acc, it in
            if let c = WhatsAppCategory(rawValue: it.label) { acc[c, default: 0] += it.size }
        }
    }

    public static func bytesByConversation(_ items: [CleanItem]) -> [(conversation: String, bytes: Int64)] {
        Dictionary(grouping: items, by: { $0.group ?? "Outros" })
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.size }) }
            .sorted { $0.1 > $1.1 }
    }
}
