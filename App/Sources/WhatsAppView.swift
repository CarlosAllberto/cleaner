import SwiftUI
import AppKit
import CleanerCore

struct WhatsAppView: View {
    @ObservedObject var model: WhatsAppViewModel
    @State private var reviewing = false
    @State private var understood = false
    @State private var selected: URL?
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle: start
            case .scanning: progress("Lendo a mídia do WhatsApp…")
            case .cleaning: progress("Movendo para a quarentena…")
            case .ready: list
            case .done: done
            }
        }
        .navigationTitle("WhatsApp")
        .toolbar {
            Button { Task { await model.scan() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(model.phase == .scanning || model.phase == .cleaning)
        }
        .task { if model.phase == .idle { await model.scan() } }
        .alert("Aviso", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(isPresented: $reviewing) { reviewSheet }
    }

    private var start: some View {
        VStack(spacing: 12) {
            Text("Mídia do WhatsApp").font(.title3)
            Text("Fotos, vídeos, áudios e documentos. Os bancos de mensagens nunca são tocados.")
                .foregroundStyle(.secondary)
            Text(model.rootPath).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
            if !model.rootExists { Label("Pasta não encontrada. Escolha o caminho do WhatsApp.", systemImage: "questionmark.folder").foregroundStyle(.orange) }
            HStack {
                Button("Escolher pasta…") { pickRoot() }
                Button("Procurar") { Task { await model.scan() } }.buttonStyle(.borderedProminent).disabled(!model.rootExists)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(_ t: LocalizedStringKey) -> some View {
        VStack(spacing: 12) { ProgressView(); Text(t) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if !model.inaccessible.isEmpty {
                Label("Varredura incompleta: sem permissão de leitura. Conceda Acesso Total ao Disco.", systemImage: "exclamationmark.triangle")
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2))
            }
            summary
            filters
            Divider()
            List(model.filtered, selection: $selected) { item in
                HStack {
                    Toggle(isOn: Binding(
                        get: { model.selection.contains(item.url) },
                        set: { on in if on { model.selection.insert(item.url) } else { model.selection.remove(item.url) } }
                    )) { Text(item.url.lastPathComponent) }
                    .toggleStyle(.checkbox).labelsHidden()
                    FileThumbnail(url: item.url)
                    VStack(alignment: .leading) {
                        Text(item.url.lastPathComponent).lineLimit(1)
                        Text(categoryTitle(item.label) + " · " + (item.group ?? String(localized: "Outros"))
                             + (item.modificationDate.map { " · " + $0.formatted(date: .abbreviated, time: .omitted) } ?? ""))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(formatBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    PreviewButton(url: item.url) { selected = item.url; previewURL = item.url }
                }
            }
            .quickLookOnSpace(selection: $selected, preview: $previewURL, in: model.filtered.map(\.url))
            Divider()
            HStack {
                Button("Marcar os \(model.filtered.count) filtrados") { model.selection.formUnion(model.filtered.map(\.url)) }
                Button("Desmarcar") { model.selection = [] }
                Spacer()
                Toggle("Simulação", isOn: $model.dryRun)
                PermanentDeleteToggle(isOn: $model.permanent)
                Text("\(itemsText(model.selectedItems.count)) · \(formatBytes(model.selectedBytes))").monospacedDigit()
                Button("Revisar…") { understood = false; reviewing = true }
                    .buttonStyle(.borderedProminent).disabled(model.selection.isEmpty)
            }
            .padding(12)
        }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(WhatsAppCategory.allCases, id: \.self) { c in
                VStack { Text(categoryTitle(c.rawValue)).font(.caption).foregroundStyle(.secondary)
                         Text(formatBytes(model.byCategory[c] ?? 0)).font(.headline).monospacedDigit() }
            }
            Spacer()
        }
        .padding(12)
    }

    private var filters: some View {
        HStack {
            ForEach(WhatsAppCategory.allCases, id: \.self) { c in
                Toggle(categoryTitle(c.rawValue), isOn: Binding(
                    get: { model.categories.contains(c) },
                    set: { on in if on { model.categories.insert(c) } else { model.categories.remove(c) } }
                )).toggleStyle(.button)
            }
            Picker("", selection: $model.age) { ForEach(WhatsAppViewModel.AgeOption.allCases) { Text($0.title).tag($0) } }.frame(width: 160)
            Picker("", selection: $model.size) { ForEach(WhatsAppViewModel.SizeOption.allCases) { Text($0.title).tag($0) } }.frame(width: 160)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }

    private var reviewSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revisar antes de mover").font(.title2)
            Text("\(itemsText(model.selectedItems.count)) · \(formatBytes(model.selectedBytes))")
            ForEach(WhatsAppCategory.allCases, id: \.self) { c in
                let items = model.selectedItems.filter { $0.label == c.rawValue }
                if !items.isEmpty { Text("\(categoryTitle(c.rawValue)): \(items.count) · \(formatBytes(items.reduce(0) { $0 + $1.size }))") }
            }
            Label("Atenção: se uma mídia já expirou nos servidores do WhatsApp, ela não pode ser baixada de novo. Isso vale mesmo depois do prazo da quarentena.",
                  systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Toggle("Entendo que isso pode ser irreversível depois da quarentena", isOn: $understood)
            HStack {
                Spacer()
                Button("Cancelar", role: .cancel) { reviewing = false }
                Button(model.dryRun ? LocalizedStringKey("Simular") : "Mover para a quarentena") {
                    reviewing = false; Task { await model.clean() }
                }
                .buttonStyle(.borderedProminent).disabled(!understood)
            }
        }
        .padding(20).frame(width: 480)
    }

    private var done: some View {
        let r = model.result
        return VStack(spacing: 12) {
            Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundStyle(.green)
            if r?.dryRun == true {
                Text("Simulação: \(formatBytes(r?.movedBytes ?? 0)) seriam movidos (\(itemsText(r?.moved ?? 0)))").font(.title3)
            } else {
                Text("\(formatBytes(r?.movedBytes ?? 0)) movidos / \(formatBytes(r?.freedBytes ?? 0)) liberados").font(.title2)
                Text("Liberados em definitivo em \(model.engine.config.retentionDays) dias.").foregroundStyle(.secondary)
            }
            if let s = r?.skipped, !s.isEmpty { Text("\(s.count) itens ignorados por segurança").foregroundStyle(.secondary) }
            HStack {
                if r?.dryRun == false { ShareResultButton(moved: r?.movedBytes ?? 0, freed: r?.freedBytes ?? 0) }
                if r?.dryRun == false, r?.sessionID != nil, (r?.freedBytes ?? 0) == 0 { Button("Desfazer") { Task { await model.undo() } } }
                Button("Voltar") { Task { await model.scan() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func categoryTitle(_ raw: String) -> String {
        switch raw {
        case "photos": String(localized: "Fotos")
        case "videos": String(localized: "Vídeos")
        case "audio": String(localized: "Áudios")
        default: String(localized: "Documentos")
        }
    }

    private func pickRoot() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.directoryURL = URL(fileURLWithPath: model.rootPath).deletingLastPathComponent()
        if p.runModal() == .OK, let url = p.url { model.chooseRoot(url) }
    }
}
