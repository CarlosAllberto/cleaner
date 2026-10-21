import SwiftUI
import AppKit
import CleanerCore

struct OverviewView: View {
    @ObservedObject var model: OverviewViewModel
    /// Troca a seção da barra lateral.
    let open: (Section) -> Void

    var body: some View {
        Group {
            if let r = model.result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if r.incomplete {
                            Label("Varredura incompleta: sem permissão de leitura. Conceda Acesso Total ao Disco.", systemImage: "exclamationmark.triangle")
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if let s = model.storage {
                            hero(s)
                            storage(s)
                        }
                        cleanable(r)
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) { ProgressView(); Text("Medindo o disco…") }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Visão Geral")
        .toolbar {
            Button { Task { await model.refresh() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                .disabled(model.loading)
        }
        .task { if model.result == nil { await model.refresh() } }
    }

    /// Frase simples sobre o espaço livre, um semáforo e o atalho para a limpeza completa.
    private func hero(_ s: StorageBreakdown) -> some View {
        let free = Double(s.available) / Double(Swift.max(s.capacity, 1))
        let (tint, icon, status): (Color, String, LocalizedStringKey) =
            free >= 0.2 ? (.green, "checkmark.circle.fill", "Espaço sobrando")
            : free >= 0.1 ? (.orange, "exclamationmark.circle.fill", "Ficando cheio")
            : (.red, "exclamationmark.triangle.fill", "Quase sem espaço")
        return HStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("Seu Mac tem \(format(s.available)) livres de \(format(s.capacity))")
                    .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(status).foregroundStyle(tint)
            }
            Spacer(minLength: 12)
            Button { open(.fullCleanup) } label: {
                Label("Fazer limpeza completa", systemImage: "sparkles").padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
    }

    /// Cartões do que dá para liberar, cada um levando à ferramenta que limpa.
    private func cleanable(_ r: OverviewResult) -> some View {
        let parts = r.categories.filter { $0.bytes > 0 }
        return VStack(alignment: .leading, spacing: 12) {
            Text("O que dá para liberar").font(.title3.weight(.semibold))
            if parts.isEmpty {
                Text("Tudo limpo por aqui.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(parts) { card($0) }
                }
            }
        }
    }

    private func card(_ c: OverviewCategory) -> some View {
        let info = cardInfo(c.id)
        return Button { open(info.section) } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: info.icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(c.displayTitle).font(.headline)
                        if c.inaccessible {
                            Image(systemName: "lock.fill").foregroundStyle(.orange).help("Sem permissão para ler tudo")
                        }
                        Spacer()
                        Text(format(c.bytes)).font(.headline).monospacedDigit()
                    }
                    Text(info.text).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func cardInfo(_ id: String) -> (icon: String, text: LocalizedStringKey, section: Section) {
        switch id {
        case "whatsapp": ("message", "Fotos, vídeos e áudios recebidos nas conversas", .whatsapp)
        case "caches": ("archivebox", "Arquivos temporários que os apps recriam sozinhos", .junk)
        case "logs": ("doc.text", "Registros de atividade que o Mac quase nunca usa", .junk)
        case "ios-backups": ("iphone", "Cópias de segurança antigas do iPhone ou iPad", .fullCleanup)
        case "xcode": ("hammer", "Arquivos de programação que podem ser refeitos", .fullCleanup)
        default: ("folder", "Arquivos que podem ser revisados", .fullCleanup)
        }
    }

    /// Barra empilhada no estilo de Ajustes > Geral > Armazenamento.
    private func storage(_ s: StorageBreakdown) -> some View {
        let parts = s.categories.filter { $0.bytes > 0 }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.volumeName).font(.title3.weight(.semibold))
                Spacer()
                Text("\(format(s.used)) usados de \(format(s.capacity))").foregroundStyle(.secondary)
            }
            GeometryReader { g in
                let w = { (c: OverviewCategory) in g.size.width * CGFloat(c.bytes) / CGFloat(Swift.max(s.capacity, 1)) }
                HStack(spacing: 1) {
                    // Segmentos com menos de 2 pt viravam só o vão de 1 pt entre cores, parecendo barras escuras.
                    ForEach(parts.filter { w($0) >= 2 }) { c in
                        link(c) { color(c.id) }.frame(width: w(c))
                    }
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(height: 28).clipShape(RoundedRectangle(cornerRadius: 8))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(parts) { c in
                    link(c) {
                        HStack(spacing: 6) {
                            Circle().fill(color(c.id)).frame(width: 8, height: 8)
                            Text(c.displayTitle)
                            Text(format(c.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }.font(.callout).contentShape(Rectangle())
                    }
                }
                HStack(spacing: 6) {
                    Circle().fill(Color.secondary.opacity(0.3)).frame(width: 8, height: 8)
                    Text("Disponível")
                    Text(format(s.available)).monospacedDigit().foregroundStyle(.secondary)
                }.font(.callout)
            }
        }
    }

    /// Apps abre o Desinstalador; a Lixeira abre no Finder (o app não mexe nela); o resto, a seção da categoria.
    private func link(_ c: OverviewCategory, @ViewBuilder label: () -> some View) -> some View {
        Button {
            switch c.id {
            case "apps": open(.uninstaller)
            case "trash": NSWorkspace.shared.open(c.path) // ~/.Trash, vindo de measureStorage
            default: open(Section(rawValue: c.id) ?? .overview)
            }
        } label: { label() }
        .buttonStyle(.plain)
        .help(c.id == "trash" ? String(localized: "Esvazie pela Lixeira do Finder") : "\(c.displayTitle): \(format(c.bytes))")
        .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
    }

    private func color(_ id: String) -> Color {
        switch id {
        case "apps": .red
        case "documents": .orange
        case "icloud": .cyan
        case "photos": .yellow
        case "media": .pink
        case "mail": .blue
        case "messages": .green
        case "developer": .purple
        case "trash": .brown
        case "macos": .gray
        default: Color(white: 0.6) // Dados do Sistema
        }
    }

    private func format(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
}

extension OverviewCategory {
    /// Títulos vêm do core em pt-BR; traduzidos aqui pelo id.
    var displayTitle: String {
        switch id {
        case "ios-backups": String(localized: "Backups de iPhone")
        case "mail": String(localized: "Anexos do Mail")
        case "trash": String(localized: "Lixeira")
        case "documents": String(localized: "Documentos")
        case "photos": String(localized: "Fotos")
        case "media": String(localized: "Música e TV")
        case "messages": String(localized: "Mensagens")
        case "developer": String(localized: "Desenvolvedor")
        case "system-data": String(localized: "Dados do Sistema")
        default: titulo // WhatsApp, Caches, Logs, Xcode, Apps, iCloud Drive, Mail, macOS
        }
    }
}
