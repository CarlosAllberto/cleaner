import SwiftUI
import CleanerCore

struct UninstallerView: View {
    @ObservedObject var model: UninstallerViewModel
    @State private var confirming = false
    @State private var confirmingRelease = false
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle: pick
            case .scanning: progress("Procurando arquivos do aplicativo…")
            case .cleaning: progress("Movendo para a quarentena…")
            case .ready: review
            case .done: done
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard model.phase == .idle || model.phase == .ready, let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in await model.choose(url) } }
            }
            return true
        }
        .overlay { if dropTargeted { RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3).padding(4) } }
        .navigationTitle("Desinstalador")
        .toolbar {
            Button { refresh() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(model.phase == .scanning || model.phase == .cleaning)
        }
        .onAppear { if model.apps.isEmpty { model.loadApps() } }
        .alert("Erro", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    /// Na lista, recarrega os apps; na revisão, refaz a busca; no fim, volta ao início.
    private func refresh() {
        switch model.phase {
        case .ready: Task { await model.scan() }
        case .done: model.reset()
        default: model.loadApps()
        }
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 12) { ProgressView(); Text(text) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pick: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.app").font(.system(size: 32)).foregroundStyle(.secondary)
                Text("Arraste um aplicativo (.app) para cá ou escolha na lista").font(.title3)
                Text("O app e seus arquivos associados vão para a quarentena e podem ser restaurados juntos.")
                    .foregroundStyle(.secondary)
            }
            .padding()
            List(model.apps) { app in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 24, height: 24)
                    Text(app.name)
                    Spacer()
                    Button("Escolher") { Task { await model.choose(app.url) } }
                }
            }
        }
    }

    private var review: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.plan?.appName ?? "").font(.title3)
                Text(model.plan?.bundleID ?? "").foregroundStyle(.secondary)
                Spacer()
                Button("Trocar app") { model.reset() }
            }
            .padding(12)
            List(model.items) { entry in
                Toggle(isOn: Binding(
                    get: { model.selection.contains(entry.item.url) },
                    set: { on in
                        if on { model.selection.insert(entry.item.url) } else { model.selection.remove(entry.item.url) }
                    })) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.item.url.lastPathComponent)
                            Text(entry.item.url.deletingLastPathComponent().path).font(.caption)
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if entry.risk == .broad { Label("Maior risco", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        if let why = entry.blockedReason { Text("Ignorado: \(why)").font(.caption).foregroundStyle(.secondary) }
                        Text(entry.item.label).font(.caption).foregroundStyle(.secondary)
                        Text(formatBytes(entry.item.size)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .disabled(entry.blockedReason != nil)
            }
            Divider()
            HStack {
                Toggle("Busca ampla (maior risco)", isOn: $model.broad)
                    .help("Inclui pastas que só batem pelo nome do app. Podem ser de outro programa.")
                    .onChange(of: model.broad) { _ in Task { await model.scan() } }
                Spacer()
                Toggle("Simulação", isOn: $model.dryRun)
                PermanentDeleteToggle(isOn: $model.permanent)
                Text("\(itemsText(model.selectedItems.count)) · \(formatBytes(model.selectedBytes))").monospacedDigit()
                Button("Revisar e desinstalar…") { confirming = true }
                    .buttonStyle(.borderedProminent).disabled(model.selection.isEmpty)
            }
            .padding(12)
        }
        .confirmationDialog(
            model.dryRun ? LocalizedStringKey("Simular a desinstalação?")
                : "Mover \(itemsText(model.selectedItems.count)) (\(formatBytes(model.selectedBytes))) para a quarentena?",
            isPresented: $confirming, titleVisibility: .visible) {
            Button(model.dryRun ? LocalizedStringKey("Simular") : "Desinstalar") { Task { await model.clean() } }
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
                Button("Voltar") { model.reset() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Apagar definitivamente agora?", isPresented: $confirmingRelease, titleVisibility: .visible) {
            Button("Liberar agora (sem desfazer)", role: .destructive) { model.releaseNow() }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Os itens da quarentena serão apagados e não poderão ser restaurados.") }
    }
}
