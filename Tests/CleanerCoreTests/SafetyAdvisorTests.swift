import XCTest
@testable import CleanerCore

final class SafetyAdvisorTests: XCTestCase {
    let env = Env()

    private func verdict(_ rel: String) -> SafetyVerdict {
        let url = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : env.home.appendingPathComponent(rel)
        return SafetyAdvisor.assess(url, config: env.config)
    }

    private func assert(_ paths: [String], _ expected: SafetyVerdict, file: StaticString = #filePath, line: UInt = #line) {
        for p in paths { XCTAssertEqual(verdict(p), expected, p, file: file, line: line) }
    }

    private func assert(_ paths: [String], _ level: SafetyLevel, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
        for p in paths {
            let v = verdict(p)
            XCTAssertEqual(v.level, level, p, file: file, line: line)
            XCTAssertTrue(v.reason.contains(reason), "\(p): \(v.reason)", file: file, line: line)
        }
    }

    func testUnsafe() {
        assert(["/System/Library/Kernels", "/usr/lib", "/bin/ls", "/sbin/mount", "/private/var/db/uuidtext",
                "/var/db/x", "/System/Volumes/Data/System/Library", "/private/var/MobileAsset/AssetsV2/x"], SafetyAdvisor.system)
        assert(["/System/Volumes/VM/swapfile0", "/private/var/vm/sleepimage"], SafetyAdvisor.swap)
        assert(["/System/Volumes/Preboot"], SafetyAdvisor.preboot)
        assert(["Library/Mobile Documents/com~apple~CloudDocs/a.pdf"], SafetyAdvisor.icloud)
        assert(["Library/Mail/V10", "Library/Messages/Attachments"], SafetyAdvisor.appleApp)
        assert(["Library/Keychains/login.keychain-db", ".ssh/id_ed25519", ".gnupg", "/Library/Keychains"], SafetyAdvisor.secrets)
        assert(["Pictures/Photos Library.photoslibrary", "Music/Music/Music Library.musiclibrary",
                "Movies/TV/TV Library.tvlibrary/x"], SafetyAdvisor.mediaLibrary)
        assert(["Library/Group Containers/x/ChatStorage.sqlite", "Library/Application Support/App/store.sqlite",
                "Library/Safari/History.db"], SafetyAdvisor.database)
        assert(["Library/Application Support/Slack", "Library/Application Support/Slack/IndexedDB",
                "Library/Group Containers/UBF8T346G9.Office"], SafetyAdvisor.appData)
        assert(["Library"], SafetyAdvisor.library)
    }

    func testSafe() {
        assert(["Library/Caches/com.spotify.client", "Library/Application Support/Slack/Cache",
                "Library/Application Support/Code/Code Cache", "Library/Application Support/Chrome/Default/GPUCache",
                "Library/Application Support/Code/CachedData", "Library/Developer/Xcode/DerivedData",
                ".npm/_cacache", ".cache/pip", "Library/Developer/CoreSimulator/Caches",
                "Library/Developer/Xcode/iOS DeviceSupport", "/private/var/folders/ab/xyz/C/com.apple.x",
                "/var/folders/ab/xyz/C", "/Library/Caches"], SafetyAdvisor.cache)
        assert(["Library/Logs/DiagnosticReports", "/Library/Logs", "/private/var/log/system.log"], SafetyAdvisor.logs)
        assert(["Downloads/Zoom.pkg", "Downloads/app.dmg", "Downloads/x.zip"], SafetyAdvisor.installer)
    }

    func testCaution() {
        assert(["Documents/tese.docx", "Desktop", "Downloads/foto.jpg", "Pictures/a.png", "Movies", "Music/x.mp3",
                "Projetos/app"], SafetyAdvisor.personal)
        assert(["/Applications/Slack.app", "Applications/Tool.app"], SafetyAdvisor.application)
        assert(["/opt/homebrew", "/opt/homebrew/Cellar/node", "/usr/local/Cellar"], SafetyAdvisor.homebrew)
        assert(["/private/var/folders/ab/xyz/T", "/private/tmp", "/tmp/x"], SafetyAdvisor.temp)
        assert(["/Library/Developer/CoreSimulator/Volumes/iOS_22A", "/Library/Developer/CoreSimulator/Images"], SafetyAdvisor.simRuntimes)
    }

    // Uma checagem por família de regra nova.
    func testSpecificRules() {
        assert(["Library/Saved Application State/com.x.y.savedState"], .safe, "reabrem")
        assert(["Library/Preferences", "Library/Preferences/ByHost"], .unsafe, "Configurações dos apps")
        assert(["Library/CloudStorage/GoogleDrive-a"], .unsafe, "nuvem")
        assert(["Library/Biome", "Library/Trial", "Library/DuetExpertCenter"], .unsafe, "sistema")
        assert(["Library/StatusKit"], .unsafe, "Dados internos do macOS (StatusKit)")
        assert(["Library/Screen Savers", "/Library/Screen Savers"], .caution, "Protetores de tela")
        assert(["Library/Developer/Xcode/Archives/2024-01-01"], .caution, "Organizer")
        assert(["Library/Developer/CoreSimulator/Devices"], .caution, "simctl")
        assert(["Library/Developer/XCTestDevices"], .safe, "testes do Xcode")
        assert(["Library/Developer"], .caution, "Xcode")
        assert(["/Library/Developer/CommandLineTools"], .caution, "xcode-select")
        assert(["/Library/Updates"], .caution, "Atualizações do macOS")
        assert(["/Library/SystemExtensions"], .unsafe, "Drivers")
        assert(["/Library/LaunchDaemons/com.x.helper.plist"], .caution, "segundo plano")
        assert(["/private/var/networkd", "/var/protected"], .unsafe, "Dados internos do macOS")
        assert(["/opt/local/bin"], .caution, "MacPorts")
        assert(["/opt/X11"], .caution, "(X11)")
        assert(["/usr/local/bin/tool"], .caution, "linha de comando")
        assert([".npm"], .safe, "npm cache clean")
        assert([".rustup"], .caution, "rustup")
        assert([".claude", ".claude.json", ".claude.json.backup"], .caution, "Claude Code")
        assert([".zshrc", ".profile"], .caution, "shell")
        assert([".zsh_history"], .safe, "Histórico")
        assert([".zcompdump-Mac-5.9"], .safe, "autocompletar")
        assert([".Trash"], .caution, "Lixo")
        assert(["Library/.DS_Store", "Documents/.DS_Store"], .safe, "Finder")
        assert(["Library/org.swift.swiftpm"], .caution, "Swift Package Manager")
        assert(["/Volumes/Externo/x", "/cores"], .unsafe, "fora da sua pasta pessoal")
    }

    func testFallbacks() {
        assert([".minhaferramenta", ".minhaferramenta/config.json"], .caution, "Configurações da ferramenta minhaferramenta.")
        assert(["Library/PastaQualquer"], SafetyAdvisor.librarySupport)
        assert(["/Library/Qualquer"], SafetyAdvisor.systemSupport)
        assert(["Library/org.example.ferramenta"], .caution, "Dados de org.example.ferramenta")
    }

    func testBundleIDFolders() {
        // Safari vem com o macOS: sempre instalado.
        assert(["Library/Containers/com.apple.Safari", "Library/Group Containers/group.com.apple.Safari"], .unsafe, "Dados do app ")
        assert(["Library/Preferences/com.apple.Safari.plist", "Library/HTTPStorages/com.apple.Safari"], .caution, "Dados do app ")
        assert(["Library/Application Support/com.example.semapp", "Library/Preferences/com.example.semapp.plist",
                "Library/Containers/com.example.semapp/Data/Documents"], .caution,
               "Restos do app com.example.semapp, que não está mais instalado. A ferramenta Resíduos remove com segurança.")
        assert(["Library/Containers/com.apple.naoexiste.extension", "Library/com.apple.naoexiste"], .unsafe, "Componente do macOS")
        assert(["Library/Cookies/com.example.semapp.binarycookies"], .caution, "Dados de com.example.semapp")
    }

    func testFirstMatchWins() {
        assert(["Library/Caches/x"], SafetyAdvisor.cache)
        assert(["Library/Mobile Documents/Caches"], SafetyAdvisor.icloud)
        assert(["/System/Library/Caches"], SafetyAdvisor.system)
        assert(["Library/Containers/com.x/Data/Library/Caches"], SafetyAdvisor.cache)
        assert(["Library/Containers/com.x/Data/Library/foo.sqlite"], SafetyAdvisor.database)
        assert(["/usr/local"], .caution, "linha de comando")   // antes da regra de /usr
        assert(["/System/Volumes/VM"], SafetyAdvisor.swap)      // antes da regra de /System
        assert(["Library/Developer/Xcode/Archives/x/Caches"], SafetyAdvisor.cache)
    }

    /// Itens reais vistos em Dados do Sistema num Mac de desenvolvedor: nenhum fica sem explicação.
    func testInventoryNeverUnknown() {
        let paths = [
            ".agents", ".bun", ".cargo", ".CFUserTextEncoding", ".codex", ".config", ".copilot", ".cursor", ".DS_Store",
            ".expo", ".gem", ".gemini", ".gitconfig", ".local", ".npm", ".oh-my-zsh", ".rustup", ".swiftpm", ".thumbnails",
            ".viminfo", ".vscode", ".zsh_sessions", ".docker", ".orbstack", ".nvm", ".pyenv", ".m2", ".android",
            "Library/Accessibility", "Library/Application Scripts", "Library/Assistants", "Library/Autosave Information",
            "Library/Contacts", "Library/Daemon Containers", "Library/Fonts", "Library/Group Containers", "Library/HTTPStorages",
            "Library/IdentityServices", "Library/LaunchAgents", "Library/Metadata", "Library/Python", "Library/Suggestions",
            "Library/WebKit", "Library/Cookies", "Library/Translation", "Library/com.apple.iTunesCloud", "Library/org.swift.swiftpm",
            "/Library/Application Support", "/Library/Audio", "/Library/Fonts", "/Library/Frameworks", "/Library/Apple",
            "/Library/PrivilegedHelperTools", "/Library/Receipts", "/Library/Google", "/Library/OSAnalytics",
            "/private/var/vm", "/private/var/folders", "/private/var/containers", "/private/var/protected", "/private/var/tmp",
            "/opt/homebrew", "/usr/local", "/System/Volumes/Data/System/Library/AssetsV2",
        ]
        for p in paths { XCTAssertFalse(verdict(p).reason.contains("Não sabemos"), p) }
    }
}
