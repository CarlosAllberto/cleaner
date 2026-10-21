import SwiftUI
import CleanerCore

struct JunkView: View {
    @ObservedObject var model: JunkViewModel
    @State private var confirming = false
    @State private var confirmingRelease = false

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle: start
            case .scanning: progress("Procurando lixo…")
            case .cleaning: progress("Movendo para a quarentena…")
            case .ready: review
            case .done: done
            }
        }
        .overlay(alignment: .bottom) { if model.showUndoToast { toast } }
        .animation(.default, value: model.showUndoToast)
        .navigationTitle("Lixo do Sistema")
        .toolbar {
            Button { Task { await model.scan() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(model.phase == .scanning || model.phase == .cleaning)
        }
        .task { if model.phase == .idle { await model.scan() } }
        .alert("Erro", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var start: some View {
        VStack(spacing: 12) {
            Text("Caches e logs").font(.title3)
            Text("Nada é apagado de imediato: os itens vão para uma quarentena e podem ser restaurados.")
                .foregroundStyle(.secondary)
            Button("Procurar") { Task { await model.scan() } }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 12) { ProgressView(); Text(text) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var review: some View {
        VStack(spacing: 0) {
            if !model.inaccessible.isEmpty {
                Label("Varredura incompleta: sem permissão para ler \(model.inaccessible.count) pasta(s). Conceda Acesso Total ao Disco.",
                      systemImage: "exclamationmark.triangle")
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.yellow.opacity(0.2))
            }
            List(model.items) { item in
                Toggle(isOn: Binding(
                    get: { model.selection.contains(item.url) },
                    set: { on in if on { model.selection.insert(item.url) } else { model.selection.remove(item.url) } }
                )) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.url.lastPathComponent)
                            Text(item.label).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            HStack {
                Button("Selecionar tudo") { model.selection = Set(model.items.map(\.url)) }
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
                    Button("Liberar agora…") { confirmingRelease = true }.disabled((r?.freedBytes ?? 0) > 0)
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
