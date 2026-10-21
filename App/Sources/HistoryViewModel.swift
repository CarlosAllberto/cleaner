import AppKit
import SwiftUI
import CleanerCore

@MainActor
final class HistoryViewModel: ObservableObject {
    /// Restauração à espera da decisão do usuário (conflitos e/ou apps abertos).
    struct Pending {
        let sessionID: UUID
        let items: Set<UUID>?
        let conflicts: [RestoreConflict]
        let runningApps: [String]
    }

    @Published var sessions: [HistorySession] = []
    @Published var selectedID: UUID?
    @Published var selection = Set<UUID>()
    @Published var pending: Pending?
    @Published var summary: String?
    @Published var errorMessage: String?

    let engine = AppSettings.engine

    var selected: HistorySession? { sessions.first { $0.id == selectedID } }

    func reload() {
        sessions = engine.store.historySessions()
        if selected == nil { selectedID = sessions.first?.id }
        selection = []
    }

    /// Ponto de entrada de "Restaurar tudo" (`items == nil`) e "Restaurar selecionados".
    func requestRestore(_ session: HistorySession, items: Set<UUID>?) {
        summary = nil
        do {
            let conflicts = try engine.restorer.conflicts(sessionID: session.id, items: items)
            let apps = runningApps(in: session, items: items)
            if conflicts.isEmpty && apps.isEmpty { Task { await restore(session.id, items, .keepCurrent) } }
            else { pending = Pending(sessionID: session.id, items: items, conflicts: conflicts, runningApps: apps) }
        } catch { errorMessage = "\(error)" }
    }

    func confirm(_ p: Pending, policy: ConflictPolicy) async {
        pending = nil
        await restore(p.sessionID, p.items, policy)
    }

    private func restore(_ id: UUID, _ items: Set<UUID>?, _ policy: ConflictPolicy) async {
        do {
            let o = try await engine.restorer.restore(sessionID: id, items: items) { _ in policy }
            var parts = [String(localized: "\(o.restored.count) restaurado(s)")]
            if !o.keptCurrent.isEmpty { parts.append(String(localized: "\(o.keptCurrent.count) mantido(s) como estão")) }
            if !o.unrecoverable.isEmpty { parts.append(String(localized: "\(o.unrecoverable.count) não recuperável(is)")) }
            let bad = o.rejected.count + o.failed.count
            if bad > 0 { parts.append(String(localized: "\(bad) com problema")) }
            if !o.warnings.isEmpty { parts.append(String(localized: "\(o.warnings.count) aviso(s) de checksum")) }
            summary = parts.joined(separator: " · ")
        } catch { errorMessage = "\(error)" }
        reload()
    }

    /// "Liberar agora": expira a sessão e devolve o espaço de verdade.
    func release(_ session: HistorySession) {
        do {
            let freed = try engine.expiry.expire(session.id)
            summary = String(localized: "\(formatBytes(freed)) liberados")
        } catch { errorMessage = "\(error)" }
        reload()
    }

    /// Só para preferências: o app aberto pode regravar o plist por cima do restaurado.
    private func runningApps(in session: HistorySession, items: Set<UUID>?) -> [String] {
        session.items.compactMap { item in
            guard items?.contains(item.id) ?? true, item.status != .unrecoverable,
                  let bid = item.preferencesBundleID,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first else { return nil }
            return app.localizedName ?? bid
        }
    }
}

func moduleName(_ m: ModuleID) -> String {
    switch m {
    case .systemJunk: String(localized: "Lixo do Sistema")
    case .whatsapp: "WhatsApp"
    case .orphans: String(localized: "Restos de apps")
    case .uninstaller: String(localized: "Desinstalador")
    case .duplicates: String(localized: "Duplicados")
    case .fullCleanup: String(localized: "Limpeza Completa")
    case .largeFiles: String(localized: "Arquivos Pesados")
    }
}

func remainingText(_ s: HistorySession) -> String {
    let r = s.remaining()
    if r <= 0 { return String(localized: "expira em breve") }
    let f = DateComponentsFormatter()
    f.allowedUnits = r >= 86_400 ? [.day, .hour] : [.hour, .minute]
    f.unitsStyle = .full; f.maximumUnitCount = 2
    return String(localized: "expira em \(f.string(from: r) ?? "")")
}
