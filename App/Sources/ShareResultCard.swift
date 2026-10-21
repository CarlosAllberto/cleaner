import SwiftUI
import AppKit
import CleanerCore

/// Cartão "X GB movidos / Y GB liberados" para compartilhar.
struct ShareResultCard: View {
    let moved: Int64
    let freed: Int64

    private func gb(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.white)
            Text("\(gb(moved)) movidos").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(gb(freed)) liberados").font(.system(size: 22, weight: .medium, design: .rounded))
                .opacity(0.9)
            Text(AppConfig.appName).font(.footnote).opacity(0.7)
        }
        .foregroundStyle(.white)
        .frame(width: 480, height: 300)
        .background(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    @MainActor
    func png() -> Data? {
        let r = ImageRenderer(content: self)
        r.scale = 2
        guard let cg = r.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

/// Botão reutilizável: `ShareResultButton(moved:freed:)` nas telas de resultado.
struct ShareResultButton: View {
    let moved: Int64
    let freed: Int64
    @State private var file: URL?

    var body: some View {
        Group {
            if let file {
                ShareLink(item: file, preview: SharePreview("Resultado da limpeza", image: Image(nsImage: NSImage(contentsOf: file) ?? NSImage()))) {
                    Label("Compartilhar", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: "\(moved)-\(freed)") {
            guard let data = ShareResultCard(moved: moved, freed: freed).png() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cleaner-resultado.png")
            try? data.write(to: url)
            file = url
        }
    }
}
