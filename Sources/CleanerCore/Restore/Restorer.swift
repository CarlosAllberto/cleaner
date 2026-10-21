import Foundation

public enum ConflictPolicy: Sendable { case keepCurrent, replace, suffix }

public struct RestoreOutcome: Sendable {
    public var restored: [UUID] = []
    public var unrecoverable: [UUID] = []
    public var keptCurrent: [UUID] = []
    public var rejected: [UUID: String] = [:]
    public var failed: [UUID: String] = [:]
    public var warnings: [String] = []
}

public struct Restorer: Sendable {
    let store: SessionStore
    let validator: ManifestValidator
    let policy: PathPolicy
    let quarantine: QuarantineService
    let audit: AuditLog

    /// `items == nil` restaura a sessão toda. Itens restaurados saem do manifesto; o resto continua.
    public func restore(sessionID: UUID, items: Set<UUID>? = nil,
                        conflict: @Sendable (ManifestItem) -> ConflictPolicy = { _ in .keepCurrent }) async throws -> RestoreOutcome {
        var manifest = try store.load(sessionID)
        var out = RestoreOutcome()
        var done = Set<UUID>()
        var sessionDirs = Set<URL>()
        let fm = FileManager.default

        for i in manifest.items.indices {
            let item = manifest.items[i]
            guard items?.contains(item.id) ?? true, item.status == .moved || item.status == .pending else { continue }

            guard let qurl = try? validator.quarantineURL(for: item, sessionID: sessionID),
                  let dest0 = try? validator.originalURL(for: item, module: manifest.module) else {
                out.rejected[item.id] = "manifesto aponta para fora do escopo"
                audit.log("restore-rejected", session: sessionID, path: item.originalPath)
                continue
            }
            sessionDirs.insert(qurl.deletingLastPathComponent())
            guard FS.exists(qurl) else {
                manifest.items[i].status = .unrecoverable
                out.unrecoverable.append(item.id)
                audit.log("unrecoverable", session: sessionID, path: item.originalPath)
                continue
            }

            var dest = dest0
            if FS.exists(dest) {
                switch conflict(item) {
                case .keepCurrent:
                    out.keptCurrent.append(item.id); continue
                case .replace:
                    // O item atual também vai para a quarentena (nova sessão): nada é apagado.
                    let cur = CleanItem(url: dest, size: DirectorySizer.size(of: dest).bytes, kind: FS.kind(of: dest))
                    let r = try await quarantine.quarantine([cur], module: manifest.module)
                    guard r.moved == 1 else { out.failed[item.id] = "não foi possível mover o item atual"; continue }
                case .suffix:
                    dest = uniqueSibling(of: dest)
                }
            }

            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                // Revalida depois de criar os pais (e para o nome com sufixo).
                guard case .allowed(let final) = policy.check(dest, module: manifest.module) else {
                    out.rejected[item.id] = "destino proibido"; continue
                }
                if item.kind == .file, let sum = item.checksum, FS.sha256(of: qurl) != sum {
                    out.warnings.append("checksum diferente: \(item.originalPath)")
                }
                try FS.rename(qurl, final)
                if item.kind != .symlink {
                    var attrs: [FileAttributeKey: Any] = [.posixPermissions: item.permissions]
                    if let d = item.creationDate { attrs[.creationDate] = d }
                    if let d = item.modificationDate { attrs[.modificationDate] = d }
                    try? fm.setAttributes(attrs, ofItemAtPath: final.path)
                }
                out.restored.append(item.id); done.insert(item.id)
                audit.log("restored", session: sessionID, path: final.path)
            } catch {
                out.failed[item.id] = "\(error)"
                audit.log("restore-failed", session: sessionID, path: item.originalPath, detail: "\(error)")
            }
        }

        manifest.items.removeAll { done.contains($0.id) }
        if manifest.items.isEmpty { store.delete(sessionID) } else { try store.save(manifest) }
        // Limpa só pastas de sessão, e só se estiverem vazias.
        sessionDirs.forEach(FS.rmdirIfEmpty)
        return out
    }

    private func uniqueSibling(of url: URL) -> URL {
        let dir = url.deletingLastPathComponent(), ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let tag = n == 1 ? "restaurado" : "restaurado \(n)"
            let name = "\(base) (\(tag))" + (ext.isEmpty ? "" : ".\(ext)")
            let candidate = dir.appendingPathComponent(name)
            if !FS.exists(candidate) { return candidate }
            n += 1
        }
    }

}
