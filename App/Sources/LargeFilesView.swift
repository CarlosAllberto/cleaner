import SwiftUI
import AppKit
import CleanerCore

struct LargeFilesView: View {
    @StateObject private var model = LargeFilesViewModel()
    @State private var confirming = false
    @State private var confirmingRelease = false
    @State private var selected: URL?
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle, .scanning: progress("Procurando arquivos grandes…")
            case .cleaning: progress("Movendo para a quarentena…")
            case .ready: review
            case .done: done
            }
        }
        .overlay(alignment: .bottom) { if model.showUndoToast { toast } }
        .animation(.default, value: model.showUndoToast)
        .navigationTitle("Arquivos Pesados")
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
        VStack(alignment: .leading, spacing: 0) {
            hero.padding([.horizontal, .top], 20).padding(.bottom, 12)
            if !model.inaccessible.isEmpty {
                Label("Varredura incompleta: sem permissão para ler \(model.inaccessible.count) pasta(s). Conceda Acesso Total ao Disco.",
                      systemImage: "exclamationmark.triangle")
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20).padding(.bottom, 12)
            }
            let visible = model.visibleItems
            if visible.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.tint)
                    Text("Nenhum arquivo grande encontrado").font(.title2.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selected) { ForEach(visible) { row($0) } }
                    .quickLookOnSpace(selection: $selected, preview: $previewURL, in: visible.map(\.url))
            }
            Divider()
            HStack {
                Button("Nenhum") { model.selection = [] }.disabled(model.selection.isEmpty)
                Spacer()
                Toggle("Simulação", isOn: $model.dryRun)
                PermanentDeleteToggle(isOn: $model.permanent)
                Text("\(itemsText(model.selectedItems.count)) · \(formatBytes(model.selectedBytes))").monospacedDigit()
                Button("Revisar e limpar…") { confirming = true }
                    .buttonStyle(.borderedProminent).disabled(model.selection.isEmpty)
            }
            .toggleStyle(.checkbox)
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

    /// Total grande, a frase tranquilizadora e os filtros.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.exclamationmark").font(.system(size: 40)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(formatBytes(model.totalBytes)) em \(model.items.count) arquivos grandes")
                        .font(.title.weight(.bold)).monospacedDigit()
                    Text("Os maiores arquivos da sua pasta pessoal. Nada é apagado na hora: tudo vai para o Histórico e pode ser desfeito por \(model.engine.config.retentionDays) dias.")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                Picker("Maiores que", selection: $model.minBytes) {
                    ForEach(LargeFilesModule.thresholds, id: \.self) { Text(formatBytes($0)).tag($0) }
                }
                .fixedSize()
                .onChange(of: model.minBytes) { _ in Task { await model.scan() } }
                Picker("Tipo", selection: $model.filter) {
                    ForEach(LargeFilesViewModel.KindFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .fixedSize()
                Spacer()
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
    }

    private func row(_ item: CleanItem) -> some View {
        let advice = LargeFilesModule.advice(for: item.url, config: model.engine.config)
        return HStack {
            Toggle(isOn: Binding(
                get: { model.selection.contains(item.url) },
                set: { on in if on { model.selection.insert(item.url) } else { model.selection.remove(item.url) } }
            )) { Text(item.url.lastPathComponent) }
            .toggleStyle(.checkbox).labelsHidden()
            FileThumbnail(url: item.url)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(caption(item)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let advice { Text(verbatim: advice.reason).font(.caption2).foregroundStyle(color(advice)) }
            }
            .help(item.url.path)
            Spacer()
            Text(formatBytes(item.size)).monospacedDigit()
            PreviewButton(url: item.url) { selected = item.url; previewURL = item.url }
            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                .buttonStyle(.link)
        }
        .tag(item.url)
    }

    /// "Downloads · modificado em 3 de mar. de 2025".
    private func caption(_ item: CleanItem) -> String {
        guard let d = item.modificationDate else { return item.label }
        return String(localized: "\(item.label) · modificado em \(d.formatted(date: .abbreviated, time: .omitted))")
    }

    private func color(_ v: SafetyVerdict) -> Color {
        switch v.level {
        case .safe: .green
        case .caution: .orange
        case .unsafe: .red
        }
    }

    private var done: some View {
        let r = model.result
        let freed = r?.freedBytes ?? 0
        return VStack(spacing: 14) {
            Image(systemName: r?.dryRun == true ? "eye" : "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(.green)
            if r?.dryRun == true {
                Text("Simulação: \(formatBytes(r?.movedBytes ?? 0)) seriam movidos (\(itemsText(r?.moved ?? 0)))").font(.title2)
            } else if freed > 0 {
                Text("Pronto! \(formatBytes(freed)) liberados").font(.largeTitle.weight(.bold))
            } else {
                Text("Pronto! \(formatBytes(r?.movedBytes ?? 0)) limpos").font(.largeTitle.weight(.bold))
                Text("Ficam no Histórico por \(model.engine.config.retentionDays) dias, caso você mude de ideia. Depois o espaço é liberado sozinho.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            if let s = r?.skipped, !s.isEmpty { Text("\(s.count) itens ignorados por segurança").foregroundStyle(.secondary) }
            if let f = r?.failed, !f.isEmpty { Text("\(f.count) itens falharam").foregroundStyle(.red) }
            HStack {
                if r?.dryRun == false { ShareResultButton(moved: r?.movedBytes ?? 0, freed: freed) }
                if r?.dryRun == false, r?.sessionID != nil, freed == 0 {
                    Button("Desfazer") { Task { await model.undo() } }
                    Button("Liberar agora…") { confirmingRelease = true }
                }
                Button("Voltar") { Task { await model.scan() } }.buttonStyle(.borderedProminent)
            }
            .controlSize(.large).padding(.top, 6)
        }
        .padding(20)
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
