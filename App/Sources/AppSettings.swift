import Foundation
import CleanerCore

enum AppSettings {
    static let whatsAppRootKey = "whatsAppRoot"
    static let retentionDaysKey = "retentionDays"
    static let allowPermanentDeleteKey = "allowPermanentDelete"
    static let defaultRetentionDays = 7

    /// Config única do app. Trocar o caminho do WhatsApp vale após reabrir o app.
    static var config: AppConfig {
        var c = AppConfig.standard()
        let days = UserDefaults.standard.integer(forKey: retentionDaysKey)
        c.retentionDays = days > 0 ? days : defaultRetentionDays
        if let p = UserDefaults.standard.string(forKey: whatsAppRootKey) { c.whatsAppRoot = URL(fileURLWithPath: p) }
        return c
    }

    static let engine = Engine(config: config)
    static let scheduler = ExpiryScheduler(engine: engine)
}
