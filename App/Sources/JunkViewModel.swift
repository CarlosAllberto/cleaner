import SwiftUI
import CleanerCore

@MainActor
final class JunkViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }

    @Published var phase = Phase.idle
    @Published var items: [CleanItem] = []
    @Published var selection = Set<URL>()
    @Published var inaccessible: [URL] = []
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?
    @Published var showUndoToast = false

    let engine = AppSettings.engine
    private lazy var module = SystemJunkModule(engine: engine)

    var selectedItems: [CleanItem] { items.filter { selection.contains($0.url) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() async {
        phase = .scanning; result = nil; errorMessage = nil
        do {
            let r = try await module.scan()
            items = r.items; inaccessible = r.inaccessible; selection = []
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

    /// "Liberar agora": expira a sessão e devolve o espaço de verdade.
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

/// "1 item" / "3 itens", com plural no catálogo.
func itemsText(_ n: Int) -> String { String(localized: "\(n) itens") }

func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}
