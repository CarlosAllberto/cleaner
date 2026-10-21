import Foundation

public struct ScanResult: Sendable {
    public var items: [CleanItem] = []
    /// Pastas que não puderam ser lidas: a varredura está incompleta.
    public var inaccessible: [URL] = []
    public init(items: [CleanItem] = [], inaccessible: [URL] = []) {
        self.items = items; self.inaccessible = inaccessible
    }
}

public protocol CleanupModule: Sendable {
    var id: ModuleID { get }
    var quarantine: QuarantineService { get }
    func scan() async throws -> ScanResult
    func clean(items: [CleanItem], dryRun: Bool) async throws -> CleanResult
    /// Requisito (não só extensão) para que overrides com checagens extras rodem também via `any CleanupModule`.
    func cleanPermanently(items: [CleanItem]) async throws -> CleanResult
}

public extension CleanupModule {
    func clean(items: [CleanItem], dryRun: Bool) async throws -> CleanResult {
        try await quarantine.quarantine(items, module: id, dryRun: dryRun)
    }
}

public extension CleanupModule {
    /// Opção avançada, desligada por padrão na UI: quarentena com retenção zero (sem desfazer).
    func cleanPermanently(items: [CleanItem]) async throws -> CleanResult {
        try await quarantine.deletePermanently(items, module: id)
    }
}
