import Foundation
import UniformTypeIdentifiers

/// Tipo do arquivo pela extensão, para filtros e ícones da UI.
public enum LargeFileKind: Sendable, CaseIterable {
    case video, image, audio, archive, diskImage, document, other

    public init(_ url: URL) {
        guard let t = UTType(filenameExtension: url.pathExtension) else { self = .other; return }
        if t.conforms(to: .movie) { self = .video }
        else if t.conforms(to: .image) { self = .image }
        else if t.conforms(to: .audio) { self = .audio }
        else if t.conforms(to: .diskImage) { self = .diskImage }
        else if t.conforms(to: .archive) || t.identifier == "com.apple.installer-package-archive" { self = .archive }
        else if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .presentation)
                    || t.conforms(to: .spreadsheet) || t.conforms(to: .compositeContent) { self = .document }
        else { self = .other }
    }
}

/// Os maiores arquivos da pasta pessoal (fora Library e pastas ocultas). Só lista; mover é da QuarantineService.
public struct LargeFilesModule: CleanupModule {
    public let id = ModuleID.largeFiles
    public let quarantine: QuarantineService
    let policy: PathPolicy
    let minBytes: Int64

    /// Opções de tamanho mínimo oferecidas na UI.
    public static let thresholds: [Int64] = [50, 100, 500, 1000].map { $0 * 1_000_000 }  // decimal, como o Finder

    public init(engine: Engine, minBytes: Int64 = 100_000_000) {
        self.quarantine = engine.quarantine
        self.policy = engine.policy
        self.minBytes = minBytes
    }

    /// Arquivos comuns >= minBytes (tamanho ocupado no disco), do maior para o menor. `label` = pasta de topo.
    public func scan() async throws -> ScanResult { walk() }

    func walk() -> ScanResult {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                                      .totalFileAllocatedSizeKey, .contentModificationDateKey]
        var items: [CleanItem] = []
        var inaccessible: [URL] = []
        var seen = Set<String>()
        for root in policy.scopes[id]?.allowedRoots ?? [] {
            let label = FileManager.default.displayName(atPath: root.path)
            guard let e = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in inaccessible.append(url); return true }) else { continue }
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true, v.isSymbolicLink != true,
                      let allocated = v.totalFileAllocatedSize.map(Int64.init), allocated >= minBytes,  // 0 = só na nuvem
                      case .allowed(let real) = policy.check(url, module: id),
                      seen.insert(real.path).inserted else { continue }
                items.append(CleanItem(url: real, size: allocated, kind: .file,
                                       modificationDate: v.contentModificationDate, label: label))
            }
        }
        return ScanResult(items: items.sorted { $0.size > $1.size }, inaccessible: inaccessible)
    }

    /// Aviso de segurança, menos o "arquivo pessoal" (aqui todo arquivo é pessoal; seria só ruído).
    public static func advice(for url: URL, config: AppConfig) -> SafetyVerdict? {
        let v = SafetyAdvisor.assess(url, config: config)
        return v == SafetyAdvisor.personal ? nil : v
    }
}
