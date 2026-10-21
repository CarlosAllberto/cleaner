import SwiftUI
import AppKit
import QuickLook
import QuickLookThumbnailing

/// Miniatura real do arquivo (QuickLook), com o ícone do Finder enquanto carrega ou se falhar.
/// Carrega só quando a linha aparece (`.task`), fora da main thread.
struct FileThumbnail: View {
    let url: URL
    var size: CGFloat = 36
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: image ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable().scaledToFit()
            .frame(width: size, height: size)
            .task(id: url) {
                let key = "\(size)|\(url.path)" as NSString
                if let cached = Self.cache.object(forKey: key) { image = cached; return }
                image = nil
                let request = QLThumbnailGenerator.Request(
                    fileAt: url, size: CGSize(width: size, height: size),
                    scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
                guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request),
                      !Task.isCancelled else { return }
                Self.cache.setObject(rep.nsImage, forKey: key)
                image = rep.nsImage
            }
    }
}

extension URL {
    /// Pastas não têm Quick Look: só arquivos são visualizados.
    var isFolder: Bool { (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
}

/// Botão "Visualizar" (olho) para quem usa o mouse. Passe `url` para sumir em pastas.
struct PreviewButton: View {
    var url: URL? = nil
    let action: () -> Void
    var body: some View {
        if url?.isFolder != true {
            Button(action: action) { Label("Visualizar", systemImage: "eye") }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("Visualizar")
        }
    }
}

extension View {
    /// Espaço abre/fecha o Quick Look do item selecionado, como no Finder. As setas no painel
    /// percorrem `urls` e a seleção da lista acompanha. Pastas são ignoradas.
    func quickLookOnSpace(selection: Binding<URL?>, preview: Binding<URL?>, in urls: [URL]) -> some View {
        background(
            // macOS 13 não tem onKeyPress: um botão invisível segura o atalho. Desativado sem
            // seleção, para não roubar o espaço do resto da janela.
            Button("") { preview.wrappedValue = preview.wrappedValue == nil ? selection.wrappedValue : nil }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(selection.wrappedValue?.isFolder != false)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        )
        .quickLookPreview(preview, in: urls.filter { !$0.isFolder })
        .onChange(of: preview.wrappedValue) {
            guard let u = $0 else { return }
            if u.isFolder { preview.wrappedValue = nil } else { selection.wrappedValue = u }
        }
    }
}
