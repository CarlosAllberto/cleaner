import Foundation

/// Persistência de manifestos. Gravação atômica (tmp + rename via `.atomic`).
/// ponytail: sem fsync explícito nem lock entre processos; a UI serializa as operações.
public final class SessionStore: @unchecked Sendable {
    private let config: AppConfig

    public init(config: AppConfig) { self.config = config }

    func url(for id: UUID) -> URL { config.sessionsDir.appendingPathComponent("\(id.uuidString).json") }

    public func save(_ manifest: Manifest) throws {
        try FileManager.default.createDirectory(at: config.sessionsDir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(manifest).write(to: url(for: manifest.sessionID), options: .atomic)
    }

    public func load(_ id: UUID) throws -> Manifest {
        guard let data = try? Data(contentsOf: url(for: id)) else { throw CleanerError.sessionNotFound(id) }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let m: Manifest
        do { m = try dec.decode(Manifest.self, from: data) }
        catch { throw CleanerError.corruptManifest("JSON inválido: \(error.localizedDescription)") }
        guard m.formatVersion == AppConfig.manifestFormatVersion else {
            throw CleanerError.unsupportedVersion(m.formatVersion)
        }
        guard m.sessionID == id else { throw CleanerError.corruptManifest("id não bate com o nome do arquivo") }
        return m
    }

    public func delete(_ id: UUID) { try? FileManager.default.removeItem(at: url(for: id)) }

    /// Todos os manifestos legíveis; os inválidos são ignorados (e nunca usados).
    public func loadAll() -> [Manifest] {
        let files = (try? FileManager.default.contentsOfDirectory(at: config.sessionsDir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { f in
            guard f.pathExtension == "json", let id = UUID(uuidString: f.deletingPathExtension().lastPathComponent) else { return nil }
            return try? load(id)
        }
    }
}

/// Valida, item a item, que um manifesto não aponta para fora do escopo.
public struct ManifestValidator: Sendable {
    let config: AppConfig
    let policy: PathPolicy
    let volumes: VolumeResolver

    /// Caminho de quarentena precisa ser exatamente `<raiz de quarentena>/<sessão>/<id do item>`.
    public func quarantineURL(for item: ManifestItem, sessionID: UUID) throws -> URL {
        guard item.quarantinePath.hasPrefix("/") else { throw CleanerError.rejected("caminho de quarentena relativo") }
        let url = FS.normalize(URL(fileURLWithPath: item.quarantinePath))
        let session = url.deletingLastPathComponent()
        guard url.lastPathComponent == item.id.uuidString, session.lastPathComponent == sessionID.uuidString else {
            throw CleanerError.rejected("caminho de quarentena não pertence à sessão")
        }
        let container = session.deletingLastPathComponent()
        if container.path == FS.normalize(config.quarantineRoot).path { return url }
        if container.lastPathComponent == AppConfig.externalQuarantineDirName {
            let vol = container.deletingLastPathComponent()
            if FS.normalize(volumes.volumeRoot(vol)).path == vol.path { return url }
        }
        throw CleanerError.rejected("caminho de quarentena fora da quarentena")
    }

    /// Destino da restauração: precisa passar pela allowlist/denylist do módulo de origem.
    public func originalURL(for item: ManifestItem, module: ModuleID) throws -> URL {
        guard item.originalPath.hasPrefix("/") else { throw CleanerError.rejected("caminho original relativo") }
        switch policy.check(URL(fileURLWithPath: item.originalPath), module: module) {
        case .allowed(let url): return url
        case .denied(let why): throw CleanerError.rejected("destino proibido: \(why)")
        }
    }
}
