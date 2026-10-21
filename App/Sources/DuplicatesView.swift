import SwiftUI
import AppKit
import CleanerCore

struct DuplicatesView: View {
    @StateObject private var model = DuplicatesViewModel()
    @State private var confirming = false
    @State private var confirmingRelease = false
    @State private var selected: URL?
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle, .scanning: progress("Procurando arquivos repetidos…")
            case .cleaning: progress("Movendo para a quarentena…")
            case .ready: review
            case .done: done
            }
        }
        .overlay(alignment: .bottom) { if model.showUndoToast { toast } }
        .animation(.default, value: model.showUndoToast)
        .navigationTitle("Duplicados")
        .toolbar {
            Button { Task { await model.refresh() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(model.phase == .scanning || model.phase == .cleaning)
        }
        .task { if model.phase == .idle { await model.scan() } }
        .alert("Erro", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 12) { ProgressView(); Text(text) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var review: some View {
        VStack(spacing: 0) {
            Text("Cópias iguais do mesmo arquivo. Mantemos sempre uma cópia.")
                .foregroundStyle(.secondary).padding(8).frame(maxWidth: .infinity, alignment: .leading)
            if !model.inaccessible.isEmpty {
                Label("Varredura incompleta: sem permissão para ler \(model.inaccessible.count) pasta(s). Conceda Acesso Total ao Disco.",
                      systemImage: "exclamationmark.triangle")
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2))
            }
            if model.groups.isEmpty {
                Text("Nenhum arquivo repetido encontrado").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selected) { ForEach(model.groups) { group in
                    SwiftUI.Section {
                        ForEach(group.files) { item in row(item, group) }
                    } header: {
                        HStack {
                            Text(group.files[0].url.lastPathComponent)
                            Spacer()
                            Text("\(group.files.count) cópias · \(formatBytes(group.size)) cada").monospacedDigit()
                        }
                    }
                } }
                .quickLookOnSpace(selection: $selected, preview: $previewURL, in: model.groups.flatMap { $0.files.map(\.url) })
            }
            Divider()
            HStack {
                Button("Selecionar cópias extras") { model.selectExtras() }
                Button("Nenhum") { model.selection = [] }
                Spacer()
                Toggle("Simulação", isOn: $model.dryRun)
                PermanentDeleteToggle(isOn: $model.permanent)
                Text("\(itemsText(model.selectedItems.count)) · \(formatBytes(model.selectedBytes))").monospacedDigit()
                Button("Revisar e limpar…") { confirming = true }
                    .buttonStyle(.borderedProminent).disabled(model.selection.isEmpty)
            }
            .padding(12)
        }
        .confirmationDialog(
            model.dryRun ? LocalizedStringKey("Simular a limpeza?")
                : "Mover \(itemsText(model.selectedItems.count)) (\(formatBytes(model.selectedBytes))) para a quarentena?",
            isPresented: $confirming, titleVisibility: .visible) {
            Button(model.dryRun ? LocalizedStringKey("Simular") : "Mover para a quarentena") { Task { await model.clean() } }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(model.dryRun ? LocalizedStringKey("Nada será movido.") : "Você pode desfazer em até \(model.engine.config.retentionDays) dias.")
        }
    }

    private func row(_ item: CleanItem, _ group: DuplicateGroup) -> some View {
        HStack {
            Toggle(isOn: Binding(
                get: { model.selection.contains(item.url) },
                set: { on in if on { model.selection.insert(item.url) } else { model.selection.remove(item.url) } }
            )) { Text(item.url.lastPathComponent) }
            .toggleStyle(.checkbox).labelsHidden()
            .disabled(!model.canSelect(item, in: group))
            FileThumbnail(url: item.url)
            VStack(alignment: .leading) {
                Text(item.url.lastPathComponent)
                Text(item.label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            PreviewButton(url: item.url) { selected = item.url; previewURL = item.url }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                .buttonStyle(.link)
        }
    }

    private var done: some View {
        let r = model.result
        return VStack(spacing: 12) {
            Image(systemName: r?.dryRun == true ? "eye" : "checkmark.circle").font(.system(size: 44)).foregroundStyle(.green)
            if r?.dryRun == true {
                Text("Simulação: \(formatBytes(r?.movedBytes ?? 0)) seriam movidos (\(itemsText(r?.moved ?? 0)))").font(.title3)
            } else {
                Text("\(formatBytes(r?.movedBytes ?? 0)) movidos / \(formatBytes(r?.freedBytes ?? 0)) liberados").font(.title2)
                if (r?.freedBytes ?? 0) == 0 {
                    Text("Liberados em definitivo em \(model.engine.config.retentionDays) dias.").foregroundStyle(.secondary)
                }
            }
            if let s = r?.skipped, !s.isEmpty { Text("\(s.count) itens ignorados por segurança").foregroundStyle(.secondary) }
            if let f = r?.failed, !f.isEmpty { Text("\(f.count) itens falharam").foregroundStyle(.red) }
            HStack {
                if r?.dryRun == false { ShareResultButton(moved: r?.movedBytes ?? 0, freed: r?.freedBytes ?? 0) }
                if r?.dryRun == false, r?.sessionID != nil, (r?.freedBytes ?? 0) == 0 {
                    Button("Desfazer") { Task { await model.undo() } }
                    Button("Liberar agora…") { confirmingRelease = true }
                }
                Button("Voltar") { Task { await model.scan() } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Apagar definitivamente agora?", isPresented: $confirmingRelease, titleVisibility: .visible) {
            Button("Liberar agora (sem desfazer)", role: .destructive) { model.releaseNow() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Os itens da quarentena serão apagados e não poderão ser restaurados.") }
    }

    private var toast: some View {
        HStack {
            Text("\(formatBytes(model.result?.movedBytes ?? 0)) movidos para a quarentena")
            Button("Desfazer") { Task { await model.undo() } }
        }
        .padding(12).background(.regularMaterial, in: Capsule()).shadow(radius: 4).padding()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
