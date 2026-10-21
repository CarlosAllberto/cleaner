import Foundation

/// Único ponto que apaga definitivamente. Só toca em itens do manifesto cujo caminho
/// passou por `ManifestValidator.quarantineURL`.
public struct ExpiryService: Sendable {
    let store: SessionStore
    let validator: ManifestValidator
    let audit: AuditLog

    /// Devolve os bytes liberados de fato.
    @discardableResult
    public func expire(_ sessionID: UUID) throws -> Int64 {
        var manifest = try store.load(sessionID)
        var freed: Int64 = 0
        var sessionDirs = Set<URL>()

        for i in manifest.items.indices where manifest.items[i].status == .moved || manifest.items[i].status == .pending {
            let item = manifest.items[i]
            guard let qurl = try? validator.quarantineURL(for: item, sessionID: sessionID) else {
                audit.log("expire-rejected", session: sessionID, path: item.quarantinePath)
                continue
            }
            sessionDirs.insert(qurl.deletingLastPathComponent())
            if FS.exists(qurl) {
                do { try Self.remove(qurl) }
                catch {
                    audit.log("expire-failed", session: sessionID, path: qurl.path, detail: "\(error)")
                    continue
                }
                freed += item.size
                audit.log("expired", session: sessionID, path: item.originalPath, detail: "\(item.size)")
            }
            manifest.items[i].status = .expired
        }
        try store.save(manifest)
        sessionDirs.forEach(FS.rmdirIfEmpty)
        return freed
    }

    /// Caches como o do dotslash guardam pastas sem permissão de escrita, e aí não dá para apagar o que
    /// há dentro. Se a primeira tentativa falhar, devolve u+w às pastas (só dentro do item, sem seguir
    /// symlinks) e tenta de novo.
    static func remove(_ url: URL) throws {
        let fm = FileManager.default
        do { try fm.removeItem(at: url) } catch {
            makeDirWritable(url)
            if let e = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                for case let u as URL in e { makeDirWritable(u) }
            }
            try fm.removeItem(at: url)
        }
    }

    private static func makeDirWritable(_ u: URL) {
        var st = stat()
        guard lstat(u.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR, st.st_mode & S_IWUSR == 0 else { return }
        chmod(u.path, st.st_mode | S_IWUSR | S_IXUSR)
    }

    /// Expira sessões vencidas. Devolve os ids processados.
    @discardableResult
    public func expireDue(now: Date = Date()) -> [UUID] {
        store.loadAll().filter { $0.expiresAt <= now && !$0.activeItems.isEmpty }.compactMap { m in
            (try? expire(m.sessionID)) != nil ? m.sessionID : nil
        }
    }
}
