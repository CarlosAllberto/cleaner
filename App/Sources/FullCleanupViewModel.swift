import SwiftUI
import CleanerCore

@MainActor
final class FullCleanupViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }

    @Published var phase = Phase.idle
    @Published var items: [CleanItem] = []
    @Published var enabled = Set(FullCleanupGroup.allCases)
    @Published var inaccessible: [URL] = []
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?
    @Published var showUndoToast = false

    let engine = AppSettings.engine
    private lazy var module = FullCleanupModule(engine: engine)

    func items(in g: FullCleanupGroup) -> [CleanItem] { items.filter { FullCleanupGroup($0) == g } }
    func bytes(in g: FullCleanupGroup) -> Int64 { items(in: g).reduce(0) { $0 + $1.size } }
    /// Grupos com algo a limpar; os vazios ficam escondidos.
    var groups: [FullCleanupGroup] { FullCleanupGroup.allCases.filter { bytes(in: $0) > 0 } }
    var selectedItems: [CleanItem] { items.filter { FullCleanupGroup($0).map(enabled.contains) ?? false } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var busy: Bool { phase == .scanning || phase == .cleaning }

    func scan() async {
        phase = .scanning; result = nil; errorMessage = nil
        do {
            let r = try await module.scan()
            items = r.items; inaccessible = r.inaccessible
            phase = .ready
        } catch { errorMessage = "\(error)"; phase = .idle }
    }

    func refresh() async { await scan() }

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
