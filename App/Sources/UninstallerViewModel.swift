import SwiftUI
import CleanerCore

@MainActor
final class UninstallerViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }

    @Published var phase = Phase.idle
    @Published var apps: [InstalledApp] = []
    @Published var plan: UninstallPlan?
    @Published var selection = Set<URL>()
    @Published var broad = false
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?

    let engine = AppSettings.engine
    private var appURL: URL?

    var items: [UninstallItem] { plan?.items ?? [] }
    var selectedItems: [CleanItem] { items.filter { selection.contains($0.item.url) }.map(\.item) }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    func loadApps() { apps = UninstallerModule.installedApps(config: engine.config) }

    func choose(_ url: URL) async {
        appURL = url
        await scan()
    }

    /// Também roda ao ligar/desligar a busca ampla.
    func scan() async {
        guard let url = appURL else { return }
        phase = .scanning; result = nil; errorMessage = nil
        let module = UninstallerModule(engine: engine, app: url, includeBroad: broad)
        do {
            // Varredura de disco fora da main thread.
            let p = try await Task.detached { try module.plan() }.value
            plan = p
            selection = Set(p.items.filter { $0.risk == .exact && $0.blockedReason == nil }.map(\.item.url))
            phase = .ready
        } catch {
            errorMessage = (error as? CleanerError).map { if case .rejected(let m) = $0 { return m } else { return "\($0)" } } ?? "\(error)"
            phase = .idle
        }
    }

    func clean() async {
        guard let url = appURL else { return }
        let chosen = selectedItems
        phase = .cleaning
        do {
            // Mesma sessão para o .app e todos os resíduos: restaurar devolve tudo junto.
            let module = UninstallerModule(engine: engine, app: url, includeBroad: broad)
            result = (permanent && !dryRun) ? try await module.cleanPermanently(items: chosen)
                                            : try await module.clean(items: chosen, dryRun: dryRun)
            phase = .done
        } catch { errorMessage = "\(error)"; phase = .ready }
    }

    func undo() async {
        guard let id = result?.sessionID else { return }
        do {
            _ = try await engine.restorer.restore(sessionID: id) { _ in .suffix }
            result = nil
            await scan()
        } catch { errorMessage = "\(error)" }
    }

    func releaseNow() {
        guard let id = result?.sessionID else { return }
        do { result?.freedBytes = try engine.expiry.expire(id) } catch { errorMessage = "\(error)" }
    }

    func reset() { phase = .idle; plan = nil; appURL = nil; result = nil; loadApps() }
}
