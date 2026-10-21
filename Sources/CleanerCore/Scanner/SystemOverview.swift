import Foundation

public struct OverviewCategory: Identifiable, Sendable, Equatable {
    public let id: String
    public let titulo: String
    public let bytes: Int64
    public let path: URL
    /// Pastas medidas além de `path`.
    public let extra: [URL]
    public let inaccessible: Bool
    public var roots: [URL] { [path] + extra }
}

/// Item medido por `largestChildren`.
public struct SizedItem: Identifiable, Sendable, Equatable {
    public let url: URL
    public let bytes: Int64
    public let isDirectory: Bool
    public var id: URL { url }
}

public struct OverviewResult: Sendable {
    public var categories: [OverviewCategory]
    /// Varredura incompleta (ex.: sem Acesso Total ao Disco).
    public var incomplete: Bool
    public var total: Int64 { categories.reduce(0) { $0 + $1.bytes } }
}

/// Armazenamento do volume da home, dividido como nos Ajustes do Sistema.
public struct StorageBreakdown: Sendable {
    public var volumeName: String
    public var capacity: Int64
    /// Inclui espaço purgeable, igual aos Ajustes.
    public var available: Int64
    /// Soma = `used`. "system-data" é o resto que nenhuma outra categoria explica.
    public var categories: [OverviewCategory]
    public var used: Int64 { capacity - available }
}

/// Só leitura: mede o tamanho por categoria. Nunca remove nem move nada.
public enum SystemOverview {
    typealias Spec = (id: String, titulo: String, path: URL, extra: [URL])

    public static func measure(config: AppConfig) async -> OverviewResult {
        let lib = config.home.appendingPathComponent("Library")
        let specs: [Spec] = [
            ("whatsapp", "WhatsApp", config.whatsAppRoot, []),
            ("caches", "Caches", lib.appendingPathComponent("Caches"), []),
            ("logs", "Logs", lib.appendingPathComponent("Logs"), []),
            ("ios-backups", "Backups de iPhone", lib.appendingPathComponent("Application Support/MobileSync"), []),
            ("xcode", "Xcode", lib.appendingPathComponent("Developer/Xcode/DerivedData"),
             [lib.appendingPathComponent("Developer/CoreSimulator")]),
        ]
        let cats = await sizes(specs)
        return OverviewResult(categories: cats.sorted { $0.bytes > $1.bytes }, incomplete: cats.contains { $0.inaccessible })
    }

    public static func measureStorage(config: AppConfig,
                                      applications: URL = URL(fileURLWithPath: "/Applications")) async -> StorageBreakdown {
        let home = config.home, lib = home.appendingPathComponent("Library")
        func h(_ p: String) -> URL { home.appendingPathComponent(p) }
        // ponytail: categorias por pasta fixa; arquivos grandes fora delas caem em Dados do Sistema.
        let specs: [Spec] = [
            ("apps", "Apps", applications, [h("Applications")]),
            ("documents", "Documentos", h("Documents"), [h("Desktop"), h("Downloads")]),
            ("icloud", "iCloud Drive", lib.appendingPathComponent("Mobile Documents"), []),
            ("photos", "Fotos", h("Pictures"), []),
            ("media", "Música e TV", h("Music"), [h("Movies")]),
            ("mail", "Mail", lib.appendingPathComponent("Mail"), []),
            ("messages", "Mensagens", lib.appendingPathComponent("Messages"), []),
            ("developer", "Desenvolvedor", lib.appendingPathComponent("Developer"), []),
            ("trash", "Lixeira", h(".Trash"), []),
        ]
        let v = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeLocalizedNameKey,
                                                   .volumeAvailableCapacityForImportantUsageKey])
        let capacity = Int64(v?.volumeTotalCapacity ?? 0)
        let available = v?.volumeAvailableCapacityForImportantUsage ?? 0
        var cats = await sizes(specs)
        let macOS = volumeSpaceUsed("/")
        cats.append(OverviewCategory(id: "macos", titulo: "macOS", bytes: macOS, path: URL(fileURLWithPath: "/"), extra: [], inaccessible: false))
        let rest = Swift.max(0, capacity - available - cats.reduce(0) { $0 + $1.bytes })
        cats.append(OverviewCategory(id: "system-data", titulo: "Dados do Sistema", bytes: rest, path: lib, extra: [], inaccessible: false))
        return StorageBreakdown(volumeName: v?.volumeLocalizedName ?? "Macintosh HD", capacity: capacity,
                                available: available, categories: cats.sorted { $0.bytes > $1.bytes })
    }

    /// Usado só por este volume APFS. O `statfs` devolve o usado do container inteiro.
    static func volumeSpaceUsed(_ path: String) -> Int64 {
        var req = attrlist(bitmapcount: u_short(ATTR_BIT_MAP_COUNT), reserved: 0, commonattr: 0,
                           volattr: attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED),
                           dirattr: 0, fileattr: 0, forkattr: 0)
        var buf = [UInt8](repeating: 0, count: 16) // u_int32_t tamanho + off_t
        guard getattrlist(path, &req, &buf, buf.count, 0) == 0 else { return 0 }
        return buf.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }

    /// Filhos diretos de `roots` (ocultos inclusos), do maior pra o menor. Raiz inexistente é ignorada;
    /// filho igual ou dentro de `excluding` fica de fora.
    /// O que compõe "Dados do Sistema": home fora das categorias, ~/Library, pastas do sistema no volume
    /// Data e os volumes auxiliares do container (Preboot, VM). Só leitura.
    public static func systemDataItems(config: AppConfig, excluding: [URL], limit: Int = 200,
                                       systemRoots: [URL] = ["/Library", "/private/var", "/opt", "/usr/local",
                                                             "/System/Volumes/Data/System/Library"].map { URL(fileURLWithPath: $0) },
                                       volumes: [String] = ["/System/Volumes/Preboot", "/System/Volumes/VM"]) async -> [SizedItem] {
        let lib = config.home.appendingPathComponent("Library")
        // ~/Library é aberta à parte; excluí-la da home não pode esconder seus filhos.
        async let home = largestChildren(of: [config.home], excluding: excluding + [lib], limit: limit)
        async let rest = largestChildren(of: [lib] + systemRoots, excluding: excluding, limit: limit)
        let vols = volumes.map { SizedItem(url: URL(fileURLWithPath: $0), bytes: volumeSpaceUsed($0), isDirectory: true) }
        return Array((await home + rest + vols).filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    public static func largestChildren(of roots: [URL], excluding: [URL] = [], limit: Int = 200) async -> [SizedItem] {
        let skip = excluding.map(FS.normalize)
        let children = roots.flatMap {
            (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }.filter { c in
            let n = FS.normalize(c)
            return !skip.contains { n.path == $0.path || PathPolicy.isInside(n, $0) }
        }
        let items = await withTaskGroup(of: SizedItem.self) { group in
            for c in children {
                group.addTask { SizedItem(url: c, bytes: DirectorySizer.size(of: c).bytes, isDirectory: FS.kind(of: c) == .directory) }
            }
            return await group.reduce(into: [SizedItem]()) { $0.append($1) }
        }
        return Array(items.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    static func sizes(_ specs: [Spec]) async -> [OverviewCategory] {
        await withTaskGroup(of: OverviewCategory.self) { group in
            for s in specs {
                group.addTask {
                    var bytes: Int64 = 0, denied = false
                    for u in [s.path] + s.extra {
                        let r = DirectorySizer.size(of: u)
                        bytes += r.bytes; denied = denied || r.inaccessible
                    }
                    return OverviewCategory(id: s.id, titulo: s.titulo, bytes: bytes, path: s.path, extra: s.extra, inaccessible: denied)
                }
            }
            return await group.reduce(into: [OverviewCategory]()) { $0.append($1) }
        }
    }
}
