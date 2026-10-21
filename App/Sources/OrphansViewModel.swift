import SwiftUI
import CleanerCore

struct OrphanGroup: Identifiable {
    let bundleID: String
    let items: [CleanItem]
    var id: String { bundleID }
    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

@MainActor
final class OrphansViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }

    @Published var phase = Phase.idle
    @Published var groups: [OrphanGroup] = []
    @Published var blocked = Set<URL>()
    /// Bundle IDs marcados. Nada vem marcado por padrão.
    @Published var selection = Set<String>()
    @Published var inaccessible: [URL] = []
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?
    @Published var showUndoToast = false

    let engine = AppSettings.engine
    private lazy var module = OrphansModule(engine: engine)

    /// Itens dos apps marcados, sem os protegidos.
    var selectedItems: [CleanItem] {
        groups.filter { selection.contains($0.bundleID) }.flatMap(\.items).filter { !blocked.contains($0.url) }
    }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() async {
        phase = .scanning; result = nil; errorMessage = nil
        do {
            let (r, b) = try await module.scanDetailed()
            let by = Dictionary(grouping: r.items) { String(($0.group ?? "").dropFirst("orphan:".count)) }
            groups = by.map { OrphanGroup(bundleID: $0.key, items: $0.value) }.sorted { $0.size > $1.size }
            blocked = b; inaccessible = r.inaccessible; selection = []
            phase = .ready
        } catch { errorMessage = "\(error)"; phase = .idle }
    }

    func clean() async {
        let chosen = selectedItems
        phase = .cleaning
        do {
            let r = (permanent && !dryRun) ? try await module.cleanPermanently(items: chosen) : try await module.clean(items: chosen, dryRun: dryRun)
            result = r; phase = .done
            if !dryRun && r.sessionID != nil { toast() }
        } catch { errorMessage = "\(error)"; phase = .ready }
    }

    func undo() async {
        guard let id = result?.sessionID else { return }
        showUndoToast = false
        do {
            _ = try await engine.restorer.restore(sessionID: id) { _ in .suffix }
            result = nil
            await scan()
        } catch { errorMessage = "\(error)" }
    }

    func releaseNow() {
        guard let id = result?.sessionID else { return }
        do {
            result?.freedBytes = try engine.expiry.expire(id)
            showUndoToast = false
        } catch { errorMessage = "\(error)" }
    }

    private func toast() {
        showUndoToast = true
        Task { try? await Task.sleep(nanoseconds: 8_000_000_000); showUndoToast = false }
    }
}
