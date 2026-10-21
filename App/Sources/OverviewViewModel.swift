import SwiftUI
import CleanerCore

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var result: OverviewResult?
    @Published var storage: StorageBreakdown?
    @Published var loading = false

    private let config = AppSettings.engine.config

    func refresh() async {
        loading = true
        async let s = SystemOverview.measureStorage(config: config)
        result = await SystemOverview.measure(config: config)
        storage = await s
        loading = false
    }
}
