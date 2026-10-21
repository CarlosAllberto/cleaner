import SwiftUI
import AppKit
import CleanerCore

enum Section: String, CaseIterable, Identifiable {
    case overview = "Visão Geral", whatsapp = "WhatsApp", junk = "Lixo do Sistema"
    case orphans = "Resíduos", uninstaller = "Desinstalador", history = "Histórico"
    case fullCleanup = "Limpeza Completa", duplicates = "Duplicados", largeFiles = "Arquivos Pesados"
    // Categorias do armazenamento: rawValue = id da OverviewCategory.
    case systemData = "system-data", macos, developer, documents, media, photos, messages, mail, icloud
    var id: String { rawValue }
    static let tools: [Section] = [.fullCleanup, .junk, .orphans, .duplicates, .largeFiles, .uninstaller, .whatsapp, .history]
    static let storage: [Section] = [.systemData, .macos, .developer, .documents, .media, .photos, .messages, .mail, .icloud]
    var title: LocalizedStringKey {
        switch self {
        case .overview: "Visão Geral"
        case .whatsapp: "WhatsApp"
        case .junk: "Lixo do Sistema"
        case .orphans: "Resíduos"
        case .uninstaller: "Desinstalador"
        case .history: "Histórico"
        case .fullCleanup: "Limpeza Completa"
        case .duplicates: "Duplicados"
        case .largeFiles: "Arquivos Pesados"
        case .systemData: "Dados do Sistema"
        case .macos: "macOS"
        case .developer: "Desenvolvedor"
        case .documents: "Documentos"
        case .media: "Música e TV"
        case .photos: "Fotos"
        case .messages: "Mensagens"
        case .mail: "Mail"
        case .icloud: "iCloud Drive"
        }
    }
    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .whatsapp: "message"
        case .junk: "trash"
        case .orphans: "shippingbox"
        case .uninstaller: "xmark.app"
        case .history: "clock.arrow.circlepath"
        case .fullCleanup: "sparkles"
        case .duplicates: "doc.on.doc"
        case .largeFiles: "externaldrive.badge.exclamationmark"
        case .systemData: "gearshape.2"
        case .macos: "desktopcomputer"
        case .developer: "hammer"
        case .documents: "doc"
        case .media: "music.note"
        case .photos: "photo.on.rectangle"
        case .messages: "bubble.left"
        case .mail: "envelope"
        case .icloud: "icloud"
        }
    }
}

struct ContentView: View {
    @State private var selection: Section? = .overview
    @StateObject private var junk = JunkViewModel()
    @StateObject private var uninstaller = UninstallerViewModel()
    @StateObject private var whatsapp = WhatsAppViewModel()
    @StateObject private var overview = OverviewViewModel()
    @StateObject private var orphans = OrphansViewModel()
    @State private var fdaGranted = FullDiskAccess.isGranted()
    @State private var showOnboarding = !FullDiskAccess.isGranted()

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label(Section.overview.title, systemImage: Section.overview.icon).tag(Section.overview)
                SwiftUI.Section("Ferramentas") {
                    ForEach(Section.tools) { s in Label(s.title, systemImage: s.icon).tag(s) }
                }
                SwiftUI.Section("Armazenamento") {
                    ForEach(Section.storage) { s in Label(s.title, systemImage: s.icon).tag(s) }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection ?? .overview {
            case .junk: JunkView(model: junk)
            case .history: HistoryView()
            case .whatsapp: WhatsAppView(model: whatsapp)
            case .overview: OverviewView(model: overview) { selection = $0 }
            case .orphans: OrphansView(model: orphans)
            case .uninstaller: UninstallerView(model: uninstaller)
            case .fullCleanup: FullCleanupView()
            case .duplicates: DuplicatesView()
            case .largeFiles: LargeFilesView()
            case let s:
                if let st = overview.storage, let c = st.categories.first(where: { $0.id == s.rawValue }) {
                    CategoryView(category: c, storage: st).id(c.id)
                } else {
                    VStack(spacing: 12) { ProgressView(); Text("Medindo o disco…") }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .task { if overview.storage == nil && !overview.loading { await overview.refresh() } }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(granted: $fdaGranted) { showOnboarding = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fdaGranted = FullDiskAccess.isGranted()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !fdaGranted && !showOnboarding {
                HStack {
                    Label("Sem Acesso Total ao Disco: varredura incompleta.", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("Configurar") { showOnboarding = true }
                }
                .padding(8).background(.yellow.opacity(0.25))
            }
        }
    }
}
