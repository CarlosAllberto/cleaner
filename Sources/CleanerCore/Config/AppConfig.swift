import Foundation

/// Único lugar com nome, bundle ID e nomes de pasta do app. Troque aqui para renomear.
public struct AppConfig: Sendable {
    public static let appName = "Cleaner"
    public static let bundleID = "br.com.treendz.cleaner"
    public static let quarantineDirName = "Quarentena"
    public static let sessionsDirName = "Sessoes"
    public static var externalQuarantineDirName: String { ".\(appName)-Quarentena" }
    public static let manifestFormatVersion = 1

    public let supportDir: URL
    public let home: URL
    public var retentionDays: Int
    /// Varia entre versões do WhatsApp; a UI permite trocar.
    public var whatsAppRoot: URL

    public init(supportDir: URL, home: URL, retentionDays: Int = 7, whatsAppRoot: URL? = nil) {
        self.whatsAppRoot = whatsAppRoot ?? home.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared")
        self.supportDir = supportDir
        self.home = home
        self.retentionDays = retentionDays
    }

    public static func standard() -> AppConfig {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return AppConfig(
            supportDir: home.appendingPathComponent("Library/Application Support/\(appName)"),
            home: home)
    }

    public var quarantineRoot: URL { supportDir.appendingPathComponent(Self.quarantineDirName) }
    public var sessionsDir: URL { supportDir.appendingPathComponent(Self.sessionsDirName) }
    public var logFile: URL { supportDir.appendingPathComponent("auditoria.jsonl") }
}

public enum CleanerError: Error, Equatable {
    case corruptManifest(String)
    case unsupportedVersion(Int)
    case sessionNotFound(UUID)
    case rejected(String)
}
