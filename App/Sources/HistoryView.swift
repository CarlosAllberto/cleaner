import SwiftUI
import CleanerCore

struct HistoryView: View {
    @StateObject private var model = HistoryViewModel()
    @State private var confirmingRelease = false

    var body: some View {
        // HSplitView dentro do detail do NavigationSplitView briga com a sidebar e a esmaga.
        HStack(spacing: 0) {
            sessionList.frame(width: 280)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Histórico")
        .toolbar {
            Button { model.reload() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
        }
        .onAppear { model.reload() }
        .alert("Erro", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog(pendingTitle, isPresented: .constant(model.pending != nil), titleVisibility: .visible,
                            presenting: model.pending) { p in
            if p.conflicts.isEmpty {
                Button("Restaurar mesmo assim") { Task { await model.confirm(p, policy: .keepCurrent) } }
            } else {
                Button("Manter o atual") { Task { await model.confirm(p, policy: .keepCurrent) } }
                Button("Substituir (o atual vai para a quarentena)") { Task { await model.confirm(p, policy: .replace) } }
                Button("Restaurar com sufixo") { Task { await model.confirm(p, policy: .suffix) } }
            }
            Button("Cancelar", role: .cancel) { model.pending = nil }
        } message: { p in Text(pendingMessage(p)) }
    }

    private var sessionList: some View {
        List(model.sessions, selection: $model.selectedID) { s in
            VStack(alignment: .leading, spacing: 2) {
                Text(moduleName(s.module)).font(.headline)
                Text(s.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Text("\(itemsText(s.itemCount)) · \(formatBytes(s.bytes)) · \(remainingText(s))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(s.id)
        }
        .overlay {
            if model.sessions.isEmpty {
                Text("Nenhuma limpeza para desfazer.").foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let s = model.selected {
            VStack(spacing: 0) {
                if let msg = model.summary {
                    Label(msg, systemImage: "checkmark.circle").padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.green.opacity(0.15))
                }
                List(s.items) { item in
                    let lost = item.status == .unrecoverable
                    HStack {
                        Toggle(isOn: Binding(
                            get: { model.selection.contains(item.id) },
                            set: { on in if on { model.selection.insert(item.id) } else { model.selection.remove(item.id) } }
                        )) { Text(URL(fileURLWithPath: item.originalPath).lastPathComponent) }
                        .toggleStyle(.checkbox).labelsHidden().disabled(lost)
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: item.originalPath).lastPathComponent)
                            Text(lost ? String(localized: "Não recuperável: o item não está mais na quarentena") : item.originalPath)
                                .font(.caption).foregroundStyle(lost ? .orange : .secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(formatBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack {
                    Button("Liberar agora…", role: .destructive) { confirmingRelease = true }
                    Button("Selecionar tudo") { model.selection = Set(s.items.filter { $0.status != .unrecoverable }.map(\.id)) }
                    Button("Nenhum") { model.selection = [] }.disabled(model.selection.isEmpty)
                    Spacer()
                    Button("Restaurar selecionados") { model.requestRestore(s, items: model.selection) }
                        .disabled(model.selection.isEmpty)
                    Button("Restaurar tudo") { model.requestRestore(s, items: nil) }
                        .buttonStyle(.borderedProminent).disabled(s.itemCount == 0)
                }
                .padding(12)
            }
            .confirmationDialog("Apagar definitivamente agora?", isPresented: $confirmingRelease, titleVisibility: .visible) {
                Button("Liberar agora (sem desfazer)", role: .destructive) { model.release(s) }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Os itens desta limpeza serão apagados e não poderão ser restaurados.") }
        } else {
            Text("Selecione uma limpeza").foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var pendingTitle: LocalizedStringKey {
        guard let p = model.pending else { return "" }
        return p.conflicts.isEmpty ? "Apps em execução" : "\(p.conflicts.count) item(ns) já existem no destino"
    }

    private func pendingMessage(_ p: HistoryViewModel.Pending) -> String {
        var t = ""
        if !p.conflicts.isEmpty { t += String(localized: "O que fazer com os arquivos que já estão no lugar? ") }
        if !p.runningApps.isEmpty {
            t += String(localized: "Em execução: \(p.runningApps.joined(separator: ", ")). Feche o app antes de restaurar as preferências, senão ele pode sobrescrevê-las.")
        }
        return t
    }
}
