import Foundation
import CryptoKit

/// Cópias com o mesmo conteúdo. `files.first` é a cópia sugerida para manter (a mais antiga).
public struct DuplicateGroup: Identifiable, Sendable {
    public let id: String  // SHA-256 do conteúdo
    public let size: Int64
    public let files: [CleanItem]
    public var wastedBytes: Int64 { size * Int64(files.count - 1) }
}

/// Arquivos repetidos nas pastas do usuário. Nunca deixa um grupo sem nenhuma cópia (`clean` re-confere no disco).
public struct DuplicatesModule: CleanupModule {
    public let id = ModuleID.duplicates
    public let quarantine: QuarantineService
    let config: AppConfig
    let policy: PathPolicy
    let minSize: Int64

    public init(engine: Engine, minSize: Int64 = 1024 * 1024) {
        self.quarantine = engine.quarantine
        self.config = engine.config
        self.policy = engine.policy
        self.minSize = minSize
    }

    static let folders = ["Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music"]

    struct Entry { let url: URL; let size: Int64; let created: Date?; let modified: Date? }

    /// Todas as cópias menos a que fica (a mais antiga de cada grupo).
    public func scan() async throws -> ScanResult {
        let r = try await scanGroups()
        return ScanResult(items: r.groups.flatMap { $0.files.dropFirst() }, inaccessible: r.inaccessible)
    }

    public func scanGroups() async throws -> (groups: [DuplicateGroup], inaccessible: [URL]) {
        let w = walk { $0 >= minSize }
        let home = PathPolicy.resolve(config.home).path
        let groups = Self.duplicateSets(w.entries).map { hash, files in
            DuplicateGroup(id: hash, size: files[0].size, files: Self.keepFirst(files).map { e in
                var dir = e.url.deletingLastPathComponent().path
                if dir.hasPrefix(home) { dir = "~" + dir.dropFirst(home.count) }
                return CleanItem(url: e.url, size: e.size, kind: .file, modificationDate: e.modified,
                                 label: dir, group: "dup:\(hash)")
            })
        }
        return (groups.sorted { $0.wastedBytes > $1.wastedBytes }, w.inaccessible)
    }

    public func clean(items: [CleanItem], dryRun: Bool) async throws -> CleanResult {
        let (safe, skipped) = keepingOneCopy(items)
        var r = try await quarantine.quarantine(safe, module: id, dryRun: dryRun)
        r.skipped += skipped
        return r
    }

    /// Esconde a versão da extensão quando chamado pelo tipo concreto: a regra de manter uma cópia vale aqui também.
    public func cleanPermanently(items: [CleanItem]) async throws -> CleanResult {
        let (safe, skipped) = keepingOneCopy(items)
        var r = try await quarantine.deletePermanently(safe, module: id)
        r.skipped += skipped
        return r
    }

    // MARK: - Regra de manter uma cópia

    /// Re-lê o disco: para cada conteúdo, precisa sobrar ao menos uma cópia fora da seleção. Se não sobrar, a mais antiga fica.
    func keepingOneCopy(_ items: [CleanItem]) -> (safe: [CleanItem], skipped: [SkippedItem]) {
        let sizes = Set(items.map(\.size))
        let sets = Self.duplicateSets(walk { sizes.contains($0) }.entries).values
        var byPath: [String: CleanItem] = [:]
        for i in items { byPath[FS.normalize(i.url).path] = i }

        var safe: [CleanItem] = []
        var skipped: [SkippedItem] = []
        var matched = Set<String>()
        for files in sets {
            let chosen = Self.keepFirst(files).filter { byPath[$0.url.path] != nil }
            guard !chosen.isEmpty else { continue }
            chosen.forEach { matched.insert($0.url.path) }
            let all = chosen.count == files.count
            if all { skipped.append(SkippedItem(url: chosen[0].url, reason: "última cópia: mantida")) }
            safe += chosen.dropFirst(all ? 1 : 0).compactMap { byPath[$0.url.path] }
        }
        for (path, item) in byPath where !matched.contains(path) {
            skipped.append(SkippedItem(url: item.url, reason: "não é mais uma cópia de outro arquivo"))
        }
        return (safe, skipped)
    }

    // MARK: - Varredura

    /// Arquivos comuns (sem ocultos, sem symlinks, sem conteúdo de pacotes) aceitos pela PathPolicy.
    func walk(_ sizeOK: (Int64) -> Bool) -> (entries: [Entry], inaccessible: [URL]) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                                      .totalFileAllocatedSizeKey, .creationDateKey, .contentModificationDateKey]
        var entries: [Entry] = []
        var inaccessible: [URL] = []
        var seen = Set<String>()
        for name in Self.folders {
            let root = config.home.appendingPathComponent(name)
            guard FS.exists(root), let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in inaccessible.append(url); return true }) else { continue }
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true,
                      let size = v.fileSize.map(Int64.init), sizeOK(size),
                      (v.totalFileAllocatedSize ?? 1) > 0 || size == 0,  // fora disso: só na nuvem (dataless)
                      case .allowed(let real) = policy.check(url, module: id),
                      seen.insert(real.path).inserted else { continue }
                entries.append(Entry(url: real, size: size, created: v.creationDate, modified: v.contentModificationDate))
            }
        }
        return (entries, inaccessible)
    }

    /// Tamanho → primeiros 64 KB → SHA-256 completo. Só devolve conteúdos com 2+ arquivos.
    // ponytail: hash sequencial; paralelizar por grupo de tamanho se ficar lento em discos grandes.
    static func duplicateSets(_ entries: [Entry]) -> [String: [Entry]] {
        func split(_ es: [Entry], _ key: (Entry) -> String?) -> [String: [Entry]] {
            Dictionary(grouping: es.compactMap { e in key(e).map { ($0, e) } }, by: \.0)
                .mapValues { $0.map(\.1) }.filter { $0.value.count > 1 }
        }
        var out: [String: [Entry]] = [:]
        for same in split(entries, { String($0.size) }).values {
            for prefix in split(same, { hash($0.url, limit: 64 * 1024) }).values {
                out.merge(split(prefix, { hash($0.url) })) { a, _ in a }
            }
        }
        return out
    }

    /// Mais antigo primeiro; empate → caminho mais curto.
    static func keepFirst(_ es: [Entry]) -> [Entry] {
        es.sorted {
            let a = $0.created ?? .distantFuture, b = $1.created ?? .distantFuture
            if a != b { return a < b }
            if $0.url.path.count != $1.url.path.count { return $0.url.path.count < $1.url.path.count }
            return $0.url.path < $1.url.path
        }
    }

    /// SHA-256 lido em blocos de 1 MB (sem carregar o arquivo inteiro). nil se não der para ler.
    static func hash(_ url: URL, limit: Int = .max) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var sha = SHA256()
        var left = limit
        do {
            while left > 0, let d = try h.read(upToCount: min(1 << 20, left)), !d.isEmpty {
                sha.update(data: d)
                left -= d.count
            }
        } catch { return nil }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
