import SwiftUI
import AppKit
import CleanerCore

/// Só leitura: lista o que mais ocupa numa categoria. Quem apaga é o usuário, pelo Finder.
struct CategoryView: View {
    let category: OverviewCategory
    let storage: StorageBreakdown
    @State private var items: [SizedItem]?
    @State private var selected: URL?
    @State private var previewURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(formatBytes(category.bytes)).font(.title3).monospacedDigit().foregroundStyle(.secondary)
                if let w = warning {
                    Label(w, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
                }
            }
            .padding()
            if category.id == "macos" {
                Text("O volume do sistema é selado e só de leitura. Ele não pode ser limpo e é gerenciado pelas atualizações do macOS.")
                    .foregroundStyle(.secondary).padding(.horizontal)
                Spacer()
            } else if let items {
                if items.isEmpty {
                    Text("Nada encontrado").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items, selection: $selected) { row($0) }
                        .quickLookOnSpace(selection: $selected, preview: $previewURL,
                                          in: items.filter { !$0.isDirectory }.map(\.url))
                    Divider()
                    HStack {
                        Text("Total listado")
                        Spacer()
                        Text(formatBytes(items.reduce(0) { $0 + $1.bytes })).monospacedDigit()
                    }
                    .font(.headline).padding(12)
                }
            } else {
                VStack(spacing: 12) { ProgressView(); Text("Medindo…") }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Sem isto, na página macOS (sem List) o VStack fica estreito e centralizado na janela.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(Section(rawValue: category.id)?.title ?? LocalizedStringKey(category.displayTitle))
        .toolbar {
            Button { Task { await measure() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(category.id == "macos" || items == nil)
        }
        .task { if items == nil { await measure() } }
    }

    private func measure() async {
        guard category.id != "macos" else { return }
        items = nil
        if category.id == "system-data" {
            let others = storage.categories.filter { $0.id != "system-data" && $0.id != "macos" }.flatMap(\.roots)
            items = await SystemOverview.systemDataItems(config: AppSettings.engine.config, excluding: others)
        } else {
            items = await SystemOverview.largestChildren(of: category.roots)
        }
    }

    private var warning: LocalizedStringKey? {
        switch category.id {
        case "mail": "Estes arquivos pertencem ao Mail. Removê-los à mão pode quebrar o app."
        case "messages": "Estes arquivos pertencem ao Mensagens. Removê-los à mão pode quebrar o app."
        case "icloud": "Estes arquivos estão no iCloud. Removê-los à mão apaga também a cópia na nuvem."
        default: nil
        }
    }

    /// Em pastas pessoais o medidor não ajuda; em Fotos só a biblioteca merece o selo.
    private func showsSafety(_ item: SizedItem) -> Bool {
        switch category.id {
        // Mail, Mensagens e iCloud já têm o aviso no topo.
        case "developer", "documents", "media", "mail", "messages", "icloud": false
        case "photos": item.url.pathExtension == "photoslibrary"
        default: true
        }
    }

    private func row(_ item: SizedItem) -> some View {
        let safety = showsSafety(item) ? SafetyAdvisor.assess(item.url, config: AppSettings.engine.config) : nil
        return HStack {
            if item.isDirectory {
                Image(systemName: "folder").foregroundStyle(.secondary).frame(width: 36)
            } else {
                FileThumbnail(url: item.url)
            }
            VStack(alignment: .leading) {
                Text(item.url.lastPathComponent)
                Text(item.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if let safety { Text(verbatim: safety.reason).font(.caption2).foregroundStyle(safety.color) }
            }
            Spacer()
            if let safety { SafetyBadge(verdict: safety) }
            Text(formatBytes(item.bytes)).monospacedDigit().foregroundStyle(.secondary)
            if !item.isDirectory {
                PreviewButton { selected = item.url; previewURL = item.url }
            }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        }
    }
}

private struct SafetyBadge: View {
    let verdict: SafetyVerdict
    var body: some View {
        Text(title).font(.caption.bold()).foregroundStyle(verdict.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(verdict.color.opacity(0.15), in: Capsule())
            .help(verdict.reason)
    }

    private var title: LocalizedStringKey {
        switch verdict.level {
        case .safe: "Seguro"
        case .caution: "Cuidado"
        case .unsafe: "Não apague"
        }
    }
}

private extension SafetyVerdict {
    var color: Color {
        switch level {
        case .safe: .green
        case .caution: .orange
        case .unsafe: .red
        }
    }
}
