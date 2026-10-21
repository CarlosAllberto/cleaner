import SwiftUI
import CleanerCore

@main
struct CleanerApp: App {
    init() { AppSettings.scheduler.start() }

    var body: some Scene {
        WindowGroup { ContentView() }
            .windowResizability(.contentMinSize)
        Settings { SettingsView() }
    }
}
