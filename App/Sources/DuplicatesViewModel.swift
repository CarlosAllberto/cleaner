import SwiftUI
import CleanerCore

@MainActor
final class DuplicatesViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }

    @Published var phase = Phase.idle
    @Published var groups: [DuplicateGroup] = []
    @Published var selection = Set<URL>()
    @Published var inaccessible: [URL] = []
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?
    @Published var showUndoToast = false

    let engine = AppSettings.engine
    private lazy var module = DuplicatesModule(engine: engine)

    var selectedItems: [CleanItem] { groups.flatMap(\.files).filter { selection.contains($0.url) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    /// Cópias extras: todas menos a mais antiga de cada grupo.
    func selectExtras() { selection = Set(groups.flatMap { $0.files.dropFirst().map(\.url) }) }

    /// Nunca deixa marcar todas as cópias de um grupo.
    func canSelect(_ item: CleanItem, in group: DuplicateGroup) -> Bool {
        selection.contains(item.url) || group.files.filter { !selection.contains($0.url) }.count > 1
    }

    func scan() async {
        phase = .scanning; result = nil; errorMessage = nil
        do {
            let r = try await module.scanGroups()
            groups = r.groups; inaccessible = r.inaccessible
            selectExtras()
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
