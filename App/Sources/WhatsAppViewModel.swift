import SwiftUI
import CleanerCore

@MainActor
final class WhatsAppViewModel: ObservableObject {
    enum Phase { case idle, scanning, ready, cleaning, done }
    enum AgeOption: Int, CaseIterable, Identifiable {
        case any = 0, d30 = 30, m6 = 180, y1 = 365
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .any: String(localized: "Qualquer idade")
            case .d30: String(localized: "Mais de 30 dias")
            case .m6: String(localized: "Mais de 6 meses")
            case .y1: String(localized: "Mais de 1 ano")
            }
        }
    }
    enum SizeOption: Int, CaseIterable, Identifiable {
        case any = 0, mb1 = 1, mb10 = 10, mb50 = 50
        var id: Int { rawValue }
        var title: String { self == .any ? String(localized: "Qualquer tamanho") : String(localized: "Mais de \(rawValue) MB") }
    }

    @Published var phase = Phase.idle
    @Published var all: [CleanItem] = []
    @Published var inaccessible: [URL] = []
    @Published var selection = Set<URL>()
    @Published var categories = Set(WhatsAppCategory.allCases)
    @Published var age = AgeOption.any
    @Published var size = SizeOption.any
    @Published var dryRun = false
    @Published var permanent = false
    @Published var result: CleanResult?
    @Published var errorMessage: String?

    let engine = AppSettings.engine
    private lazy var module = WhatsAppModule(engine: engine)

    var rootPath: String { engine.config.whatsAppRoot.path }
    var rootExists: Bool { FileManager.default.fileExists(atPath: rootPath) }
    var filtered: [CleanItem] {
        WhatsAppFilter(categories: categories, olderThanDays: age == .any ? nil : age.rawValue,
                       minBytes: Int64(size.rawValue) * 1_000_000).apply(all)
    }
    var selectedItems: [CleanItem] { all.filter { selection.contains($0.url) } }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var byCategory: [WhatsAppCategory: Int64] { WhatsAppModule.bytesByCategory(all) }

    func scan() async {
        phase = .scanning; result = nil; errorMessage = nil
        do {
            let r = try await module.scan()
            all = r.items; inaccessible = r.inaccessible; selection = []
            phase = .ready
        } catch { errorMessage = "\(error)"; phase = .idle }
    }

    func clean() async {
        phase = .cleaning
        do {
            result = (permanent && !dryRun) ? try await module.cleanPermanently(items: selectedItems) : try await module.clean(items: selectedItems, dryRun: dryRun)
            phase = .done
        } catch { errorMessage = "\(error)"; phase = .ready }
    }

    func undo() async {
        guard let id = result?.sessionID else { return }
        do {
            _ = try await engine.restorer.restore(sessionID: id) { _ in .suffix }
            await scan()
        } catch { errorMessage = "\(error)" }
    }

    func chooseRoot(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: AppSettings.whatsAppRootKey)
        errorMessage = String(localized: "Caminho salvo. Reabra o app para aplicar.")
    }
}
