import SwiftUI
import AppKit
import CleanerCore

/// Guia até Ajustes do Sistema > Privacidade e Segurança > Acesso Total ao Disco.
struct OnboardingView: View {
    @Binding var granted: Bool
    var dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Acesso Total ao Disco").font(.title2)
            Text("Sem essa permissão o \(AppConfig.appName) não consegue ler caches, lixeira e dados do WhatsApp, e a varredura fica incompleta.")
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Clique em “Abrir Ajustes do Sistema”.")
                Text("2. Ative o \(AppConfig.appName) em Acesso Total ao Disco.")
                Text("3. Volte para cá. Se o macOS pedir, reabra o app.")
            }
            Label(granted ? LocalizedStringKey("Permissão concedida") : "Permissão ainda não concedida",
                  systemImage: granted ? "checkmark.seal.fill" : "exclamationmark.triangle")
                .foregroundStyle(granted ? .green : .orange)
            HStack {
                Button("Abrir Ajustes do Sistema") { NSWorkspace.shared.open(URL(string: FullDiskAccess.settingsURL)!) }
                Spacer()
                Button(granted ? LocalizedStringKey("Concluir") : "Agora não") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 460)
    }
}
