import Foundation

public struct SkippedItem: Sendable { public let url: URL; public let reason: String }

public struct CleanResult: Sendable {
    public var sessionID: UUID?
    public var moved = 0
    public var movedBytes: Int64 = 0
    /// Espaço realmente devolvido ao disco (só após expirar a quarentena).
    public var freedBytes: Int64 = 0
    public var skipped: [SkippedItem] = []
    public var failed: [SkippedItem] = []
    public var dryRun = false
}

/// Único código que move arquivos para fora do lugar. Módulos nunca tocam no disco.
public actor QuarantineService {
    private let config: AppConfig
    private let policy: PathPolicy
    private let store: SessionStore
    private let audit: AuditLog
    private let volumes: VolumeResolver
    private let expiry: ExpiryService
    private let now: @Sendable () -> Date
    private let beforeMove: (@Sendable (UUID, ManifestItem) -> Void)?

    init(config: AppConfig, policy: PathPolicy, store: SessionStore, audit: AuditLog, volumes: VolumeResolver,
         expiry: ExpiryService, now: @escaping @Sendable () -> Date,
         beforeMove: (@Sendable (UUID, ManifestItem) -> Void)?) {
        self.config = config; self.policy = policy; self.store = store; self.audit = audit
        self.volumes = volumes; self.expiry = expiry; self.now = now; self.beforeMove = beforeMove
    }

    public func quarantine(_ items: [CleanItem], module: ModuleID, dryRun: Bool = false) throws -> CleanResult {
        try run(items, module: module, dryRun: dryRun)
    }

    /// Opção avançada: quarentena com retenção zero. Passa pelo mesmo manifesto e pela mesma expiração.
    public func deletePermanently(_ items: [CleanItem], module: ModuleID) throws -> CleanResult {
        var result = try run(items, module: module, dryRun: false)
        if let id = result.sessionID { result.freedBytes = try expiry.expire(id) }
        return result
    }

    // MARK: -

    private struct Accepted { let item: CleanItem; let real: URL; let dir: URL }

    private func run(_ items: [CleanItem], module: ModuleID, dryRun: Bool) throws -> CleanResult {
        let sessionID = UUID()
        var result = CleanResult(dryRun: dryRun)

        // 1. Política: nada passa sem allowlist/denylist e symlink resolvido.
        var accepted: [Accepted] = []
        for item in items {
            switch policy.check(item.url, module: module) {
            case .denied(let why):
                result.skipped.append(SkippedItem(url: item.url, reason: why))
                audit.log("denied", session: sessionID, path: item.url.path, detail: why)
            case .allowed(let real):
                accepted.append(Accepted(item: item, real: real, dir: quarantineDir(for: real, session: sessionID)))
            }
        }

        // 2. Itens aninhados/duplicados: só o mais externo vai.
        accepted.sort { $0.real.pathComponents.count < $1.real.pathComponents.count }
        var kept: [Accepted] = []
        for a in accepted {
            if kept.contains(where: { $0.real.path == a.real.path || PathPolicy.isInside(a.real, $0.real) }) {
                result.skipped.append(SkippedItem(url: a.item.url, reason: "já incluído em outro item selecionado"))
            } else { kept.append(a) }
        }

        if dryRun {
            result.moved = kept.count
            result.movedBytes = kept.reduce(0) { $0 + $1.item.size }
            kept.forEach { audit.log("dryrun", path: $0.real.path, detail: "\($0.item.size)") }
            return result
        }

        // 3. Pastas de quarentena (por volume). Sem escrita no volume: recusa, nunca cai em copiar.
        var ready: [Accepted] = []
        for a in kept {
            do { try FileManager.default.createDirectory(at: a.dir, withIntermediateDirectories: true); ready.append(a) }
            catch { result.skipped.append(SkippedItem(url: a.item.url, reason: "sem escrita na quarentena do volume")) }
        }
        guard !ready.isEmpty else { return result }

        // 4. Manifesto gravado ANTES de qualquer movimento.
        var manifest = Manifest(
            formatVersion: AppConfig.manifestFormatVersion, sessionID: sessionID, createdAt: now(),
            expiresAt: now().addingTimeInterval(TimeInterval(config.retentionDays) * 86_400),
            module: module, items: ready.map { manifestItem(for: $0) })
        try store.save(manifest)
        result.sessionID = sessionID

        // 5. Move (rename no mesmo volume: sem cópia, sem espaço extra) e registra o status.
        var sinceSave = 0
        for i in manifest.items.indices {
            let mi = manifest.items[i]
            beforeMove?(sessionID, mi)
            do {
                try FS.rename(URL(fileURLWithPath: mi.originalPath), URL(fileURLWithPath: mi.quarantinePath))
                manifest.items[i].status = .moved
                result.moved += 1
                result.movedBytes += mi.size
                audit.log("moved", session: sessionID, path: mi.originalPath, detail: "\(mi.size)")
            } catch {
                manifest.items[i].status = .failed
                manifest.items[i].failureReason = "\(error)"
                result.failed.append(SkippedItem(url: URL(fileURLWithPath: mi.originalPath), reason: "\(error)"))
                audit.log("move-failed", session: sessionID, path: mi.originalPath, detail: "\(error)")
            }
            sinceSave += 1
            if sinceSave >= 25 { try? store.save(manifest); sinceSave = 0 }
        }
        try store.save(manifest)
        return result
    }

    private func quarantineDir(for real: URL, session: UUID) -> URL {
        let home = FS.normalize(volumes.volumeRoot(config.quarantineRoot)).path
        let vol = FS.normalize(volumes.volumeRoot(real))
        if vol.path == home { return config.quarantineRoot.appendingPathComponent(session.uuidString) }
        return vol.appendingPathComponent(AppConfig.externalQuarantineDirName)
            .appendingPathComponent(session.uuidString)
    }

    private func manifestItem(for a: Accepted) -> ManifestItem {
        let id = UUID()
        let attrs = (try? FileManager.default.attributesOfItem(atPath: a.real.path)) ?? [:]
        let kind = FS.kind(of: a.real)
        let checksum = (kind == .file && a.item.size <= FS.checksumMaxBytes) ? FS.sha256(of: a.real) : nil
        return ManifestItem(
            id: id, originalPath: a.real.path,
            quarantinePath: a.dir.appendingPathComponent(id.uuidString).path,
            size: a.item.size, volume: volumes.volumeRoot(a.real).path, kind: kind,
            permissions: (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0o644,
            creationDate: attrs[.creationDate] as? Date, modificationDate: attrs[.modificationDate] as? Date,
            checksum: checksum, group: a.item.group, status: .pending, failureReason: nil)
    }
}
