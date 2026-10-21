import Foundation
#if canImport(AppKit)
import AppKit
#endif

public enum SafetyLevel: Sendable { case safe, caution, unsafe }

public struct SafetyVerdict: Sendable, Equatable {
    public let level: SafetyLevel
    /// Uma frase simples, para quem não é técnico.
    public let reason: String

    public init(_ level: SafetyLevel, _ reason: String) {
        self.level = level
        self.reason = reason
    }
}

/// Só leitura: diz, pelo caminho e pelo nome, se apagar um item à mão é seguro. Não apaga nada; só consulta
/// o LaunchServices (com cache) para dar nome ao app dono de uma pasta com bundle ID.
/// Regras em ordem; a primeira que casar vence. Todo caminho recebe uma frase concreta.
public enum SafetyAdvisor {
    static let system = SafetyVerdict(.unsafe, "Gerenciado pelo macOS. Apagar pode impedir o Mac de iniciar ou atualizar.")
    static let icloud = SafetyVerdict(.unsafe, "Está no iCloud: apagar aqui apaga também na nuvem.")
    static let appleApp = SafetyVerdict(.unsafe, "Pertence ao Mail/Mensagens: apagar à mão pode corromper o app.")
    static let secrets = SafetyVerdict(.unsafe, "Guarda senhas e chaves.")
    static let mediaLibrary = SafetyVerdict(.unsafe, "Biblioteca do Fotos/Música: apague pelo próprio app.")
    static let database = SafetyVerdict(.unsafe, "Banco de dados de um app.")
    static let appData = SafetyVerdict(.unsafe, "Dados e configurações de um app.")
    static let cache = SafetyVerdict(.safe, "Cache temporário: o app recria quando precisar.")
    static let logs = SafetyVerdict(.safe, "Registro de atividade: pode apagar.")
    static let installer = SafetyVerdict(.safe, "Instalador já baixado.")
    static let personal = SafetyVerdict(.caution, "Arquivo pessoal: confira antes de apagar.")
    static let application = SafetyVerdict(.caution, "App: use o Desinstalador para remover junto com os restos.")
    static let swap = SafetyVerdict(.unsafe, "Memória virtual do macOS (swap). É recriada e esvaziada sozinha ao reiniciar.")
    static let preboot = SafetyVerdict(.unsafe, "Arquivos que o Mac usa para ligar e instalar atualizações. Gerenciado pelo macOS.")
    static let homebrew = SafetyVerdict(.caution, "Pacotes do Homebrew. Remova com `brew uninstall` e libere espaço com `brew cleanup`.")
    static let temp = SafetyVerdict(.caution, "Arquivos temporários do macOS e dos apps. O sistema limpa sozinho ao reiniciar; apagar com apps abertos pode travá-los.")
    static let library = SafetyVerdict(.unsafe, "Pasta de dados dos apps e do macOS. Não apague a pasta inteira.")
    static let librarySupport = SafetyVerdict(.caution, "Pasta de suporte que o macOS e os apps usam para guardar dados. Apagar pode fazer algum app perder dados ou configurações.")
    static let systemSupport = SafetyVerdict(.unsafe, "Componente do macOS ou de um app, instalado para todos os usuários. Apagar à mão pode fazer apps ou recursos do sistema pararem.")
    static let outside = SafetyVerdict(.unsafe, "Fica fora da sua pasta pessoal e pertence ao macOS ou a um app. Apague só pelo app que o instalou.")
    static let simRuntimes = SafetyVerdict(.caution, "Runtimes de simulador do Xcode. Remova pelo Xcode > Settings > Platforms.")

    static let systemRoots = ["/System", "/usr", "/bin", "/sbin", "/private/var/db", "/System/Volumes/Preboot",
                              "/System/Volumes/VM", "/System/Volumes/Data/System"].map { URL(fileURLWithPath: $0) }
    static let cacheNames: Set<String> = ["Caches", "Cache", "Code Cache", "GPUCache", "CachedData", "DerivedData", "_cacache"]

    /// Pastas de ~/Library cujos filhos têm nome de bundle ID; o primeiro valor diz se guardam conteúdo (documentos, conversas).
    static let appFolders: [String: Bool] = ["Application Support": true, "Containers": true, "Group Containers": true,
                                             "Preferences": false, "HTTPStorages": false, "WebKit": false, "Cookies": false,
                                             "LaunchAgents": false, "Application Scripts": false]

    static func internalMacOS(_ name: String) -> SafetyVerdict {
        SafetyVerdict(.unsafe, "Dados internos do macOS (\(name)). O sistema gerencia sozinho; apagar pode quebrar recursos do Mac.")
    }

    static func addOn(_ what: String) -> SafetyVerdict {
        SafetyVerdict(.caution, "\(what) que você ou um app instalou. Apagar remove esse complemento.")
    }

    static let addOns: [String: SafetyVerdict] = [
        "ColorPickers": addOn("Seletores de cor"), "Colors": addOn("Paletas de cores"),
        "Compositions": addOn("Composições do Quartz"), "Input Methods": addOn("Métodos de digitação"),
        "Internet Plug-Ins": addOn("Plug-ins de navegador"), "Keyboard Layouts": addOn("Layouts de teclado"),
        "PDF Services": addOn("Ações de PDF do menu Imprimir"), "PreferencePanes": addOn("Painéis de ajustes"),
        "Screen Savers": addOn("Protetores de tela"), "Scripts": addOn("Scripts"),
        "Services": addOn("Itens do menu Serviços"), "Sounds": addOn("Sons de alerta"),
        "QuickLook": addOn("Plugins da Visualização Rápida"), "Spotlight": addOn("Plugins do Spotlight"),
        "Contextual Menu Items": addOn("Itens do menu de contexto"), "Image Capture": addOn("Drivers de câmera e scanner"),
        "Printers": SafetyVerdict(.caution, "Impressoras e drivers de impressão. Apagar faz a impressora parar até você reinstalá-la."),
        "Audio": SafetyVerdict(.caution, "Plugins e drivers de áudio (GarageBand, Logic, interfaces de som). Apagar tira esses recursos dos apps."),
        "Fonts": SafetyVerdict(.caution, "Fontes instaladas. Apagar tira essas fontes dos apps; gerencie pelo Catálogo de Fontes."),
        "Google": SafetyVerdict(.caution, "Atualizador automático do Google Chrome e de outros apps do Google."),
    ]

    /// Filhos de ~/Library (vale também para o que estiver dentro deles).
    static let userLibrary: [String: SafetyVerdict] = addOns.merging([
        "Application Support": SafetyVerdict(.unsafe, "Dados de todos os apps. Não apague a pasta inteira; restos de apps removidos saem pela ferramenta Resíduos."),
        "Containers": SafetyVerdict(.unsafe, "Dados dos apps da App Store e da Apple, um por pasta. Apagar faz os apps perderem documentos e configurações."),
        "Group Containers": SafetyVerdict(.unsafe, "Dados compartilhados entre apps do mesmo fabricante (ex.: Office, WhatsApp, Notas). Apagar pode perder documentos e conversas."),
        "Preferences": SafetyVerdict(.unsafe, "Configurações dos apps e do macOS. Apagar volta tudo ao padrão."),
        "Saved Application State": SafetyVerdict(.safe, "Janelas que os apps reabrem ao iniciar. Pode apagar: os apps só abrem sem restaurar as janelas."),
        "Cookies": SafetyVerdict(.caution, "Cookies de sites. Apagar desconecta você dos sites no Safari e em outros apps."),
        "HTTPStorages": SafetyVerdict(.caution, "Cookies e dados de sites guardados pelos apps. Apagar faz os apps pedirem login de novo."),
        "WebKit": SafetyVerdict(.caution, "Dados de sites guardados pelo Safari e por apps. Apagar desconecta você dos sites e apaga dados offline deles."),
        "Application Scripts": SafetyVerdict(.caution, "Scripts de automação dos apps da App Store. Ocupa pouco; apagar desativa essas automações."),
        "Autosave Information": SafetyVerdict(.caution, "Cópias de documentos ainda não salvos (TextEdit, Pages etc.). Apagar pode perder rascunhos."),
        "LaunchAgents": SafetyVerdict(.caution, "Programas que abrem sozinhos quando você entra no Mac. Desative em Ajustes do Sistema > Geral > Itens de Início."),
        "Fonts": SafetyVerdict(.caution, "Fontes que você instalou. Apagar tira essas fontes dos apps; gerencie pelo Catálogo de Fontes."),
        "FontCollections": SafetyVerdict(.caution, "Coleções do Catálogo de Fontes. Ocupa pouco."),
        "Python": SafetyVerdict(.caution, "Pacotes do Python instalados com `pip install --user`. Apagar desinstala esses pacotes."),
        "Developer": SafetyVerdict(.caution, "Dados do Xcode: simuladores, builds e Archives. Limpe pelo próprio Xcode, não apague a pasta inteira."),
        "Metadata": SafetyVerdict(.caution, "Índices de busca do Spotlight e dos apps. São recriados, mas as buscas ficam incompletas por um tempo."),
        "Spelling": SafetyVerdict(.caution, "Palavras que o corretor ortográfico aprendeu com você. Ocupa pouco."),
        "Translation": SafetyVerdict(.caution, "Idiomas baixados para tradução. Remova em Ajustes do Sistema > Geral > Idioma e Região > Idiomas de Tradução."),
        "org.swift.swiftpm": SafetyVerdict(.caution, "Configurações e coleções do Swift Package Manager (Xcode)."),
        "Favorites": SafetyVerdict(.caution, "Atalhos de favoritos do Finder. Ocupa pouco."),
        "SafariSafeBrowsing": SafetyVerdict(.safe, "Lista de sites perigosos do Safari. É baixada de novo sozinha."),
        "CloudStorage": SafetyVerdict(.unsafe, "Arquivos do Google Drive, Dropbox, OneDrive etc. Apagar aqui pode apagar também na nuvem."),
        "Contacts": SafetyVerdict(.unsafe, "Seus contatos. Apagar pode perder contatos que não estão no iCloud."),
        "Calendars": SafetyVerdict(.unsafe, "Seus calendários e eventos."),
        "Reminders": SafetyVerdict(.unsafe, "Seus lembretes."),
        "Safari": SafetyVerdict(.unsafe, "Favoritos, histórico e abas do Safari."),
        "Shortcuts": SafetyVerdict(.unsafe, "Seus atalhos do app Atalhos."),
        "Workflows": SafetyVerdict(.unsafe, "Atalhos e automações do app Atalhos."),
        "Passes": SafetyVerdict(.unsafe, "Cartões e ingressos da Carteira (Wallet)."),
        "Finance": SafetyVerdict(.unsafe, "Dados do Apple Pay e da Carteira."),
        "FinanceBackup": SafetyVerdict(.unsafe, "Cópia dos dados do Apple Pay e da Carteira."),
        "HomeKit": SafetyVerdict(.unsafe, "Configuração da sua casa no app Casa."),
        "Photos": SafetyVerdict(.unsafe, "Bibliotecas do app Fotos. Apague fotos pelo próprio app."),
        "Accounts": SafetyVerdict(.unsafe, "Contas configuradas no Mac (iCloud, Google, e-mail). Apagar desconecta as contas."),
        "IdentityServices": SafetyVerdict(.unsafe, "Identidade do iMessage e do FaceTime neste Mac. Apagar pode desativar Mensagens e FaceTime."),
        "Biome": SafetyVerdict(.unsafe, "Histórico de uso que o macOS coleta para Siri, Tempo de Uso e sugestões. O sistema controla o tamanho sozinho."),
        "DuetExpertCenter": SafetyVerdict(.unsafe, "Previsões de apps e ações que o macOS aprende com o seu uso. Gerenciado pelo sistema."),
        "Suggestions": SafetyVerdict(.unsafe, "Sugestões de contatos e eventos que o macOS tira de e-mails e mensagens. Gerenciado pelo sistema."),
        "Trial": SafetyVerdict(.unsafe, "Testes de recursos que a Apple ativa no seu Mac. O sistema limpa sozinho."),
        "IntelligencePlatform": SafetyVerdict(.unsafe, "Dados do Apple Intelligence e da Siri sobre o seu uso. Gerenciado pelo sistema."),
        "PersonalizationPortrait": SafetyVerdict(.unsafe, "Perfil de interesses usado pelas sugestões do macOS. Gerenciado pelo sistema."),
        "Assistant": SafetyVerdict(.unsafe, "Dados da Siri e do ditado. Gerenciado pelo sistema."),
        "Assistants": SafetyVerdict(.unsafe, "Dados da Siri e do ditado. Gerenciado pelo sistema."),
        "Daemon Containers": SafetyVerdict(.unsafe, "Dados isolados de serviços internos do macOS. Gerenciado pelo sistema."),
        "Speech": SafetyVerdict(.unsafe, "Vozes e dados de fala do macOS. Gerenciado pelo sistema."),
        "KeyboardServices": SafetyVerdict(.unsafe, "Substituições de texto e palavras aprendidas pelo teclado."),
        "LanguageModeling": SafetyVerdict(.unsafe, "Palavras que o teclado aprendeu para sugerir e corrigir."),
    ]) { $1 }.merging(["Accessibility", "AppleMediaServices", "ContainerManager", "CoreFollowUp", "DataDeliveryServices",
                       "DoNotDisturb", "FrontBoard", "GameKit", "homeenergyd", "Intents", "LockdownMode", "MediaAnalysis",
                       "News", "PPM", "PrivateCloudCompute", "ResponseKit", "Sharing", "StatusKit", "studentd",
                       "UnifiedAssetFramework", "Weather", "Stocks"].map { ($0, internalMacOS($0)) }) { $1 }

    static let developer: [String: SafetyVerdict] = [
        "Xcode/Archives": SafetyVerdict(.caution, "Archives do Xcode: cópias das versões que você publicou, usadas para ler relatórios de erro. Apague as antigas no Xcode > Window > Organizer."),
        "CoreSimulator/Devices": SafetyVerdict(.caution, "Simuladores do Xcode (iPhone, iPad) com apps e dados de teste. Apague os antigos no Xcode > Window > Devices and Simulators ou com `xcrun simctl delete unavailable`."),
        "Xcode/UserData": SafetyVerdict(.caution, "Configurações do Xcode (temas, atalhos e trechos de código)."),
        "XCTestDevices": SafetyVerdict(.safe, "Cópias de simuladores criadas pelos testes do Xcode. Pode apagar com o Xcode fechado."),
    ]

    static let shellConfig = SafetyVerdict(.caution, "Configuração do Terminal (shell). Apagar desfaz atalhos e caminhos configurados.")
    static let claudeCode = SafetyVerdict(.caution, "Dados do Claude Code: configurações, histórico de conversas e plugins. Apagar zera tudo isso.")

    /// Itens ocultos da home (vale também para o que estiver dentro deles).
    static let dotFiles: [String: SafetyVerdict] = [
        ".Trash": SafetyVerdict(.caution, "Itens que você mandou para o Lixo. Esvazie pelo Finder (Esvaziar Lixo)."),
        ".npm": SafetyVerdict(.safe, "Cache e registros do npm. Limpe com `npm cache clean --force`."),
        ".bun": SafetyVerdict(.caution, "Bun (JavaScript) e o cache de pacotes dele. Apagar desinstala o Bun; o cache sai com `bun pm cache rm`."),
        ".cargo": SafetyVerdict(.caution, "Rust: comandos instalados com `cargo install` e pacotes baixados. Apagar desinstala esses comandos."),
        ".rustup": SafetyVerdict(.caution, "Compiladores do Rust instalados pelo rustup. Remova versões com `rustup toolchain remove`."),
        ".local": SafetyVerdict(.caution, "Programas e dados de ferramentas de linha de comando (ex.: pipx, Claude Code). Apagar pode quebrar esses comandos."),
        ".config": SafetyVerdict(.caution, "Configurações de ferramentas de linha de comando (git, gh etc.). Apagar zera as preferências delas."),
        ".claude": claudeCode,
        ".codex": SafetyVerdict(.caution, "Dados do Codex (OpenAI): login, configurações e histórico de sessões."),
        ".cursor": SafetyVerdict(.caution, "Extensões e configurações do editor Cursor. Apagar remove as extensões instaladas."),
        ".vscode": SafetyVerdict(.caution, "Extensões do VS Code. Apagar remove as extensões instaladas."),
        ".expo": SafetyVerdict(.caution, "Login e cache da ferramenta Expo (apps React Native)."),
        ".docker": SafetyVerdict(.caution, "Configurações e logins do Docker. As imagens ficam em outro lugar; limpe com `docker system prune`."),
        ".orbstack": SafetyVerdict(.caution, "Configurações do OrbStack (Docker e Linux no Mac). Limpe imagens e máquinas pelo próprio OrbStack."),
        ".nvm": SafetyVerdict(.caution, "Versões do Node.js instaladas pelo nvm. Remova as antigas com `nvm uninstall <versão>`."),
        ".pyenv": SafetyVerdict(.caution, "Versões do Python instaladas pelo pyenv. Remova as antigas com `pyenv uninstall <versão>`."),
        ".gem": SafetyVerdict(.caution, "Pacotes do Ruby (gems) instalados por você. Remova com `gem uninstall` ou `gem cleanup`."),
        ".m2": SafetyVerdict(.caution, "Bibliotecas Java baixadas pelo Maven. São baixadas de novo no próximo build, que fica mais lento."),
        ".gradle": SafetyVerdict(.caution, "Cache e configurações do Gradle (Android/Java). O cache é baixado de novo no próximo build."),
        ".android": SafetyVerdict(.caution, "Emuladores e chaves de depuração do Android Studio. Apague emuladores pelo Device Manager do Android Studio."),
        ".cocoapods": SafetyVerdict(.safe, "Lista de pacotes do CocoaPods. É baixada de novo com `pod repo update`."),
        ".swiftpm": SafetyVerdict(.caution, "Configurações do Swift Package Manager (Xcode)."),
        ".oh-my-zsh": SafetyVerdict(.caution, "Oh My Zsh: temas e plugins do Terminal. Apagar desfaz a personalização do Terminal."),
        ".zsh_history": SafetyVerdict(.safe, "Histórico de comandos do Terminal. Apagar só limpa o histórico."),
        ".bash_history": SafetyVerdict(.safe, "Histórico de comandos do Terminal. Apagar só limpa o histórico."),
        ".zsh_sessions": SafetyVerdict(.safe, "Histórico de cada janela do Terminal. Pode apagar."),
        ".bash_sessions": SafetyVerdict(.safe, "Histórico de cada janela do Terminal. Pode apagar."),
        ".zshrc": shellConfig, ".zshenv": shellConfig, ".zprofile": shellConfig, ".zlogin": shellConfig, ".profile": shellConfig,
        ".bashrc": shellConfig, ".bash_profile": shellConfig, ".tcshrc": shellConfig, ".cshrc": shellConfig,
        ".gitconfig": SafetyVerdict(.caution, "Configuração do Git (seu nome, e-mail e atalhos)."),
        ".viminfo": SafetyVerdict(.safe, "Histórico do editor Vim. Pode apagar."),
        ".DS_Store": SafetyVerdict(.safe, "Arquivo invisível do Finder com a posição dos ícones. É recriado sozinho."),
        ".CFUserTextEncoding": SafetyVerdict(.caution, "Arquivo minúsculo do macOS com o idioma do teclado. É recriado sozinho; não libera espaço."),
        ".thumbnails": SafetyVerdict(.safe, "Miniaturas de imagens geradas por apps. São recriadas quando precisar."),
        ".localized": SafetyVerdict(.caution, "Arquivo minúsculo que faz o Finder mostrar o nome da pasta no seu idioma. Não libera espaço."),
    ]

    /// Filhos de /Library (vale também para o que estiver dentro deles).
    static let sharedLibrary: [String: SafetyVerdict] = addOns.merging([
        "Application Support": SafetyVerdict(.unsafe, "Dados de apps e drivers usados por todos os usuários do Mac. Apague só os de um app que você removeu."),
        "Developer": SafetyVerdict(.caution, "Ferramentas de desenvolvedor da Apple (Command Line Tools e simuladores do Xcode)."),
        "Updates": SafetyVerdict(.caution, "Atualizações do macOS já baixadas, esperando instalação. O macOS apaga sozinho depois de instalar."),
        "LaunchDaemons": SafetyVerdict(.caution, "Serviços que apps instalaram para rodar em segundo plano. Remova pelo desinstalador do app ou em Ajustes do Sistema > Geral > Itens de Início."),
        "LaunchAgents": SafetyVerdict(.caution, "Programas que apps instalaram para abrir junto com o Mac. Remova pelo desinstalador do app ou em Ajustes do Sistema > Geral > Itens de Início."),
        "PrivilegedHelperTools": SafetyVerdict(.caution, "Ajudantes com permissão de administrador instalados por apps. Remova junto com o app, pelo desinstalador dele."),
        "Frameworks": SafetyVerdict(.unsafe, "Componentes compartilhados que apps instalados precisam para abrir."),
        "Preferences": SafetyVerdict(.unsafe, "Configurações do macOS e dos apps para todos os usuários."),
        "Managed Preferences": SafetyVerdict(.unsafe, "Configurações impostas pela empresa ou escola que gerencia o Mac."),
        "Receipts": SafetyVerdict(.caution, "Recibos de instalação de pacotes (.pkg). Ocupa pouco; o macOS usa para atualizar."),
        "Java": SafetyVerdict(.caution, "Java instalado no Mac. Apagar quebra apps que precisam de Java."),
        "User Pictures": SafetyVerdict(.caution, "Fotos de perfil que o macOS oferece para as contas de usuário."),
        "Keychains": secrets, "Security": secrets,
    ]) { $1 }.merging(["Extensions", "SystemExtensions", "DriverExtensions", "StagedExtensions", "StagedDriverExtensions",
                       "KernelCollections", "Filesystems"].map {
        ($0, SafetyVerdict(.unsafe, "Drivers e extensões do sistema. Apagar à mão pode impedir o Mac de iniciar; remova pelo app que os instalou."))
    }) { $1 }

    public static func assess(_ url: URL, config: AppConfig) -> SafetyVerdict {
        var u = FS.normalize(url)
        // /var, /tmp e /etc são symlinks para /private/...; compara sempre pelo caminho real.
        if ["var", "tmp", "etc"].contains(u.pathComponents.dropFirst().first ?? "") {
            u = URL(fileURLWithPath: "/private" + u.path)
        }
        let c = Array(u.pathComponents.dropFirst())
        let name = u.lastPathComponent.lowercased()
        let home = FS.normalize(config.home)
        let lib = home.appendingPathComponent("Library")
        func under(_ root: URL) -> Bool { u.path == root.path || PathPolicy.isInside(u, root) }
        func under(_ path: String) -> Bool { under(URL(fileURLWithPath: path)) }
        func underHome(_ rels: String...) -> Bool { rels.contains { under(home.appendingPathComponent($0)) } }
        /// Componentes depois de `root`, ou nil se não estiver dentro dele.
        func rel(_ root: URL) -> [String]? { PathPolicy.isInside(u, root) ? Array(u.pathComponents.dropFirst(root.pathComponents.count)) : nil }

        // Antes da regra de sistema: /usr/local e os volumes de swap/boot têm frase própria.
        if ["/opt/homebrew", "/usr/local/Homebrew", "/usr/local/Cellar", "/usr/local/Caskroom"].contains(where: under) { return homebrew }
        if under("/usr/local") {
            return SafetyVerdict(.caution, "Programas de linha de comando instalados por você ou por instaladores. Apagar pode quebrar comandos do Terminal.")
        }
        if under("/System/Volumes/VM") || under("/private/var/vm") { return swap }
        if under("/System/Volumes/Preboot") { return preboot }

        if [".DS_Store", ".localized"].contains(u.lastPathComponent) { return dotFiles[u.lastPathComponent]! }

        // Não apague
        if systemRoots.contains(where: under) || c.contains("AssetsV2") { return system }
        if underHome("Library/Mobile Documents") { return icloud }
        if underHome("Library/Mail", "Library/Messages") { return appleApp }
        if underHome("Library/Keychains", ".ssh", ".gnupg") { return secrets }
        if c.contains(where: { comp in [".photoslibrary", ".musiclibrary", ".tvlibrary"].contains { comp.lowercased().hasSuffix($0) } }) {
            return mediaLibrary
        }
        if c.contains(where: { PathPolicy.isProtectedName($0, in: u.path) })
            || (under(lib) && [".sqlite", ".sqlite-wal", ".sqlite-shm", ".db"].contains { name.hasSuffix($0) }) {
            return database
        }

        // Seguro
        if underHome("Library/Logs") || under("/Library/Logs") || under("/private/var/log") { return logs }
        if c.contains(where: cacheNames.contains) || underHome(".cache")
            || zip(c, c.dropFirst()).contains(where: { $0 == "Xcode" && $1.hasSuffix("DeviceSupport") })
            || (c.count >= 6 && c.prefix(3) == ["private", "var", "folders"] && c[5] == "C") {
            return cache
        }
        if underHome("Downloads"), [".dmg", ".pkg", ".zip"].contains(where: name.hasSuffix) { return installer }

        // ~/Library
        if u.path == lib.path { return library }
        if let r = rel(lib), let top = r.first {
            if top == "Developer", let hit = developer.first(where: { r.dropFirst().starts(with: $0.key.split(separator: "/").map(String.init)) }) {
                return hit.value
            }
            if let keepsContent = appFolders[top], r.count >= 2 {
                let bid = top == "Containers" ? r[1] : OrphansModule.bundleID(of: r[1], in: top)
                if let bid { return appVerdict(bid, keepsContent: keepsContent, orphanSource: OrphansModule.sources.contains(top)) }
                if keepsContent { return appData }
            }
            if let v = userLibrary[top] { return v }
            if let bid = OrphansModule.bundleID(of: top, in: "") { return appVerdict(bid, keepsContent: false, orphanSource: false) }
            return librarySupport
        }

        // Cuidado
        if under(URL(fileURLWithPath: "/Applications")) || underHome("Applications") { return application }
        if let top = rel(home)?.first {
            if top.hasPrefix(".") {
                if let v = dotFiles[top] { return v }
                if top.hasPrefix(".zcompdump") { return SafetyVerdict(.safe, "Cache do autocompletar do Terminal. É recriado ao abrir o Terminal.") }
                if top.hasPrefix(".claude") { return claudeCode }
                return SafetyVerdict(.caution, "Configurações da ferramenta \(top.dropFirst()). Apagar zera as preferências dela.")
            }
            return personal
        }

        // Fora da home
        if let r = rel(URL(fileURLWithPath: "/Library")), let top = r.first {
            if top == "Developer", r.count >= 2 {
                if r[1] == "CommandLineTools" {
                    return SafetyVerdict(.caution, "Command Line Tools do Xcode (git, compiladores). Apagar quebra o git e o Homebrew até reinstalar com `xcode-select --install`.")
                }
                if r[1] == "CoreSimulator" { return simRuntimes }
            }
            return sharedLibrary[top] ?? systemSupport
        }
        if let r = rel(URL(fileURLWithPath: "/private/var")), let top = r.first {
            if top == "folders" || top == "tmp" { return temp }
            return internalMacOS(top)
        }
        if under("/private/tmp") { return temp }
        if under("/opt/local") { return SafetyVerdict(.caution, "Pacotes do MacPorts. Remova com `sudo port uninstall` e limpe com `sudo port reclaim`.") }
        if let top = rel(URL(fileURLWithPath: "/opt"))?.first {
            return SafetyVerdict(.caution, "Programa instalado fora da App Store (\(top)). Remova pelo desinstalador dele.")
        }
        return outside
    }

    /// Pasta de ~/Library com nome de bundle ID: diz de qual app é, ou que o app sumiu.
    /// `keepsContent`: guarda documentos/conversas, então apagar com o app instalado é perigoso (unsafe);
    /// nas demais (preferências, cookies) o app só volta ao padrão (caution).
    static func appVerdict(_ bid: String, keepsContent: Bool, orphanSource: Bool) -> SafetyVerdict {
        if let app = appName(bid) {
            return keepsContent ? SafetyVerdict(.unsafe, "Dados do app \(app). Apagar pode fazer o app perder configurações e conteúdo.")
                                : SafetyVerdict(.caution, "Dados do app \(app). Apagar pode fazer o app perder configurações.")
        }
        if bid.lowercased().hasPrefix("com.apple.") {
            return SafetyVerdict(.unsafe, "Componente do macOS (\(bid)). O sistema gerencia sozinho; apagar pode quebrar algum recurso.")
        }
        if orphanSource {
            return SafetyVerdict(.caution, "Restos do app \(bid), que não está mais instalado. A ferramenta Resíduos remove com segurança.")
        }
        return SafetyVerdict(.caution, "Dados de \(bid), um app ou ferramenta que não está instalado como app. Apagar pode zerar as configurações dele.")
    }

    private static let lock = NSLock()
    private static var appNames: [String: String?] = [:]

    /// Nome do app instalado com esse bundle ID, ou com um prefixo dele (helpers e widgets: `<id>.xyz`). Cacheado.
    static func appName(_ bid: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = appNames[bid] { return hit }
        var found: String?
        #if canImport(AppKit)
        var parts = bid.split(separator: ".")
        while found == nil, parts.count >= 2 {
            if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: parts.joined(separator: ".")) {
                let n = FileManager.default.displayName(atPath: app.path)
                found = n.hasSuffix(".app") ? String(n.dropLast(4)) : n
            }
            parts.removeLast()
        }
        #endif
        appNames[bid] = .some(found)
        return found
    }
}
