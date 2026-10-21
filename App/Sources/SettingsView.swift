import SwiftUI
import CleanerCore

struct SettingsView: View {
    @AppStorage(AppSettings.retentionDaysKey) private var retentionDays = AppSettings.defaultRetentionDays
    @AppStorage(AppSettings.allowPermanentDeleteKey) private var allowPermanentDelete = false
    @State private var quarantineBytes: Int64 = 0
    @State private var confirmEmpty = false
    @State private var confirmPermanent = false
    @State private var language = Self.currentLanguage
    @State private var languageChanged = false

    private static var currentLanguage: String {
        (UserDefaults.standard.stringArray(forKey: "AppleLanguages")?.first ?? "pt-BR").hasPrefix("en") ? "en" : "pt-BR"
    }

    var body: some View {
        Form {
            SwiftUI.Section("Quarentena") {
                Stepper(value: $retentionDays, in: 1...90) {
                    Text("Guardar por \(retentionDays) dias antes de apagar")
                }
                Text("Vale para novas limpezas; sessões já feitas mantêm o prazo original.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Tamanho da quarentena",
                               value: ByteCountFormatter.string(fromByteCount: quarantineBytes, countStyle: .file))
                Button("Esvaziar quarentena agora…", role: .destructive) { confirmEmpty = true }
                    .disabled(quarantineBytes == 0)
            }
            SwiftUI.Section("Idioma") {
                Picker("Idioma", selection: $language) {
                    Text("Português (Brasil)").tag("pt-BR")
                    Text("English").tag("en")
                }
                .onChange(of: language) { new in
                    UserDefaults.standard.set([new], forKey: "AppleLanguages")
                    languageChanged = true
                }
                if languageChanged {
                    Text("Feche e reabra o app para aplicar o idioma.").font(.caption).foregroundStyle(.secondary)
                }
            }
            SwiftUI.Section("Avançado") {
                Toggle("Apagar definitivamente (sem desfazer)", isOn: Binding(
                    get: { allowPermanentDelete },
                    set: { on in if on { confirmPermanent = true } else { allowPermanentDelete = false } }))
                Text("Com isto ligado, as limpezas podem pular a quarentena e apagar de vez. Não há como restaurar.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: refresh)
        .confirmationDialog("Esvaziar a quarentena?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Apagar \(ByteCountFormatter.string(fromByteCount: quarantineBytes, countStyle: .file)) para sempre",
                   role: .destructive) {
                AppSettings.scheduler.emptyNow()
                refresh()
            }
        } message: {
            Text("Os itens guardados serão apagados definitivamente e não poderão mais ser restaurados.")
        }
        .confirmationDialog("Ligar apagar definitivamente?", isPresented: $confirmPermanent, titleVisibility: .visible) {
            Button("Entendo, ligar mesmo assim", role: .destructive) { allowPermanentDelete = true }
        } message: {
            Text("Arquivos apagados desse modo NÃO vão para a quarentena e NÃO podem ser desfeitos.")
        }
    }

    private func refresh() {
        quarantineBytes = AppSettings.engine.store.loadAll().reduce(0) { $0 + $1.activeBytes }
    }
}
