import Foundation

public struct ExpiryReport: Sendable, Equatable {
    public var sessions = 0
    public var bytes: Int64 = 0
}

/// Expira sessões vencidas na abertura e a cada `interval` enquanto o app roda.
/// Também esvazia toda a quarentena sob demanda. A remoção em si é do `ExpiryService`.
public final class ExpiryScheduler: @unchecked Sendable {
    private let store: SessionStore
    private let expiry: ExpiryService
    private let audit: AuditLog
    private let now: @Sendable () -> Date
    private let interval: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(engine: Engine, interval: TimeInterval = 3600,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
                    try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
                }) {
        store = engine.store; expiry = engine.expiry; audit = engine.audit
        self.interval = interval; self.now = now; self.sleep = sleep
    }

    /// Roda já e repete a cada hora. Chamar de novo reinicia o ciclo.
    /// `onRun` recebe cada relatório que expirou algo.
    public func start(onRun: (@Sendable (ExpiryReport) -> Void)? = nil) {
        lock.lock(); defer { lock.unlock() }
        task?.cancel()
        task = Task { [self] in
            while !Task.isCancelled {
                let r = expireDue()
                if r.sessions > 0 { onRun?(r) }
                do { try await sleep(interval) } catch { return }
            }
        }
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        task?.cancel(); task = nil
    }

    deinit { task?.cancel() }

    /// Expira só as sessões vencidas.
    @discardableResult
    public func expireDue() -> ExpiryReport {
        let t = now()
        return run(store.loadAll().filter { $0.expiresAt <= t }, event: "scheduled-expiry")
    }

    /// "Esvaziar quarentena agora": expira todas as sessões com itens ativos.
    @discardableResult
    public func emptyNow() -> ExpiryReport {
        run(store.loadAll(), event: "empty-quarantine")
    }

    private func run(_ sessions: [Manifest], event: String) -> ExpiryReport {
        var r = ExpiryReport()
        for m in sessions where !m.activeItems.isEmpty {
            guard let freed = try? expiry.expire(m.sessionID) else { continue }
            r.sessions += 1; r.bytes += freed
        }
        audit.log(event, detail: "sessions=\(r.sessions) bytes=\(r.bytes)")
        return r
    }
}
