import Foundation

/// Liga as peças. A UI e os testes criam um Engine e usam `quarantine`, `restorer`, `expiry`.
public final class Engine: Sendable {
    public let config: AppConfig
    public let policy: PathPolicy
    public let store: SessionStore
    public let audit: AuditLog
    public let expiry: ExpiryService
    public let quarantine: QuarantineService
    public let restorer: Restorer

    public init(config: AppConfig = .standard(), policy: PathPolicy? = nil, volumes: VolumeResolver = .system,
                now: @escaping @Sendable () -> Date = { Date() },
                beforeMove: (@Sendable (UUID, ManifestItem) -> Void)? = nil) {
        let policy = policy ?? PathPolicy(config: config)
        let store = SessionStore(config: config)
        let audit = AuditLog(url: config.logFile)
        let validator = ManifestValidator(config: config, policy: policy, volumes: volumes)
        let expiry = ExpiryService(store: store, validator: validator, audit: audit)
        let quarantine = QuarantineService(config: config, policy: policy, store: store, audit: audit,
                                           volumes: volumes, expiry: expiry, now: now, beforeMove: beforeMove)
        self.config = config; self.policy = policy; self.store = store; self.audit = audit
        self.expiry = expiry; self.quarantine = quarantine
        self.restorer = Restorer(store: store, validator: validator, policy: policy,
                                 quarantine: quarantine, audit: audit)
    }
}
