import SwiftUI

/// Só aparece se a opção avançada estiver ligada em Configurações. Ligar pede confirmação extra.
struct PermanentDeleteToggle: View {
    @Binding var isOn: Bool
    @AppStorage(AppSettings.allowPermanentDeleteKey) private var allowed = false
    @State private var asking = false

    var body: some View {
        if allowed {
            Toggle("Apagar definitivamente", isOn: Binding(get: { isOn }, set: { on in
                if on { asking = true } else { isOn = false }
            }))
            .confirmationDialog("Apagar sem desfazer?", isPresented: $asking, titleVisibility: .visible) {
                Button("Apagar definitivamente", role: .destructive) { isOn = true }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Os itens serão apagados na hora e não poderão ser restaurados.") }
        }
    }
}
