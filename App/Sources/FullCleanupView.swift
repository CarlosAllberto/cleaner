import SwiftUI
import CleanerCore

struct FullCleanupView: View {
    @StateObject private var model = FullCleanupViewModel()
    @State private var confirming = false
    @State private var confirmingRelease = false
    @State private var expanded = Set<FullCleanupGroup>()

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle, .scanning: scanning
            case .cleaning: progress("Movendo para a quarentena…")
            case .ready: review
            case .done: done
            }
        }
        .overlay(alignment: .bottom) { if model.showUndoToast { toast } }
        .animation(.default, value: model.showUndoToast)
        .navigationTitle("Limpeza Completa")
        .toolbar {
            Button { Task { await model.refresh() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(model.busy)
        }
        .task { if model.phase == .idle { await model.scan() } }
        .alert("Erro", isPresented: .constant(model.errorMessage != nil)) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: 12) { ProgressView(); Text(text) }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Varredura: diz o que está sendo olhado, em vez de só girar.
    private var scanning: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Procurando o que pode ser limpo…").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(FullCleanupGroup.allCases, id: \.self) { g in
                    Label(info(g).title, systemImage: info(g).icon).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func info(_ g: FullCleanupGroup) -> (title: LocalizedStringKey, icon: String, detail: LocalizedStringKey) {
        switch g {
        case .caches: return ("Caches e registros", "internaldrive",
                              "Arquivos temporários que os apps recriam sozinhos quando precisam.")
        case .leftovers: return ("Restos de apps removidos", "puzzlepiece.extension",
                                 "Configurações e dados deixados por apps que não estão mais no Mac.")
        case .xcode: return ("Arquivos temporários do Xcode", "hammer",
                             "Compilações e caches do Xcode. Seus projetos e arquivos de distribuição não são tocados.")
        case .devCaches: return ("Caches de programação", "shippingbox",
                                 "Downloads que ferramentas de programação guardam e baixam de novo quando precisam.")
        case .appCaches: return ("Caches de apps", "square.stack.3d.up",
                                 "Arquivos temporários de apps como Cursor, Slack e Claude. Eles são recriados ao abrir o app.")
        }
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !model.inaccessible.isEmpty {
                    Label("Varredura incompleta: sem permissão para ler \(model.inaccessible.count) pasta(s). Conceda Acesso Total ao Disco.",
                          systemImage: "exclamationmark.triangle")
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                }
                if model.groups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(.tint)
                        Text("Tudo limpo! Não há nada para remover agora.").font(.title2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    hero
                    Text("O que vamos limpar").font(.title3.weight(.semibold))
                    ForEach(model.groups, id: \.self) { card($0) }
                }
            }
            .padding(20)
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

    /// Total grande, uma frase tranquilizadora, o botão principal e as opções secundárias.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Você pode liberar \(formatBytes(model.selectedBytes))")
                        .font(.title.weight(.bold)).monospacedDigit()
                    Text("Só apagamos arquivos que os apps recriam sozinhos. Tudo pode ser desfeito por \(model.engine.config.retentionDays) dias no Histórico.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 16) {
                Button { confirming = true } label: {
                    Label("Limpar \(formatBytes(model.selectedBytes))", systemImage: "sparkles")
                        .font(.title3.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.selectedItems.isEmpty)
                Spacer(minLength: 8)
                Toggle("Simulação", isOn: $model.dryRun)
                PermanentDeleteToggle(isOn: $model.permanent)
            }
            .toggleStyle(.checkbox)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
    }

    private func card(_ g: FullCleanupGroup) -> some View {
        let i = info(g)
        let items = model.items(in: g)
        let on = model.enabled.contains(g)
        let open = expanded.contains(g)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: i.icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(i.title).font(.headline)
                        Spacer()
                        Text(formatBytes(model.bytes(in: g))).font(.headline).monospacedDigit()
                    }
                    Text(i.detail).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("", isOn: Binding(
                    get: { on },
                    set: { v in if v { model.enabled.insert(g) } else { model.enabled.remove(g) } }
                ))
                .toggleStyle(.switch).labelsHidden()
            }
            .opacity(on ? 1 : 0.5)
            Button {
                withAnimation { if open { expanded.remove(g) } else { expanded.insert(g) } }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0))
                    Text("Ver \(itemsText(items.count))")
                }
                .foregroundStyle(.tint).contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.callout).padding(.leading, 44)
            if open {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(verbatim: location(item.url)).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.head)
                            }
                            Spacer()
                            Text(formatBytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout).help(item.url.path)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
    }

    /// Pasta onde o item está, com a home abreviada para "~".
    private func location(_ url: URL) -> String {
        let dir = url.deletingLastPathComponent().path, home = model.engine.config.home.path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
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
