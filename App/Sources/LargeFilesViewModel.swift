import SwiftUI
import CleanerCore

@MainActor
final class LargeFilesViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }

    enum KindFilter: CaseIterable, Hashable {
        case all, videos, images, archives, documents, others

        var title: LocalizedStringKey {
            switch self {
            case .all: "Todos"
            case .videos: "Vídeos"
            case .images: "Imagens"
            case .archives: "Instaladores e compactados"
            case .documents: "Documentos"
            case .others: "Outros"
            }
        }

        func matches(_ kind: LargeFileKind) -> Bool {
            switch self {
            case .all: true
            case .videos: kind == .video
            case .images: kind == .image
            case .archives: kind == .archive || kind == .diskImage
            case .documents: kind == .document
            case .others: kind == .audio || kind == .other
            }
        }
    }

    @Published var phase = Phase.idle
    @Published var items: [CleanItem] = []
    @Published var selection = Set<URL>()
    @Published var inaccessible: [URL] = []
    @Published var minBytes: Int64 = 100_000_000
    @Published var filter = KindFilter.all
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?
    @Published var showUndoToast = false

    let engine = AppSettings.engine
    private var module: LargeFilesModule { LargeFilesModule(engine: engine, minBytes: minBytes) }

    var visibleItems: [CleanItem] { items.filter { filter.matches(LargeFileKind($0.url)) } }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { items.filter { selection.contains($0.url) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func scan() async {
        phase = .scanning; result = nil; errorMessage = nil
        do {
            let r = try await module.scan()
            items = r.items; inaccessible = r.inaccessible
            selection = []
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
