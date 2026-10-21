import Foundation
import CryptoKit

/// Primitivas de disco. `rename` nunca copia (EXDEV vira erro) e nunca sobrescreve (RENAME_EXCL).
enum FS {
    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    static func kind(of url: URL) -> ItemKind {
        let type = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
        switch type {
        case .typeSymbolicLink: return .symlink
        case .typeDirectory: return .directory
        default: return .file
        }
    }

    /// Normaliza "." e ".." só pelo texto. `standardizedFileURL` tira "/private" conforme o caminho existe, o que quebra comparações.
    static func normalize(_ url: URL) -> URL {
        var out: [String] = []
        for c in url.pathComponents.dropFirst() where c != "." && c != "/" {
            if c == ".." { _ = out.popLast() } else { out.append(c) }
        }
        return URL(fileURLWithPath: "/" + out.joined(separator: "/"))
    }

    static func rename(_ from: URL, _ to: URL) throws {
        if renamex_np(from.path, to.path, UInt32(RENAME_EXCL)) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// Só remove diretório vazio (rmdir falha caso contrário).
    static func rmdirIfEmpty(_ url: URL) { _ = rmdir(url.path) }

    static func realpath(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return Darwin.realpath(path, &buf) != nil ? String(cString: buf) : nil
    }

    static let checksumMaxBytes: Int64 = 50 * 1024 * 1024

    static func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct VolumeResolver: Sendable {
    /// Raiz (ponto de montagem) do volume que contém `url` (ou o ancestral existente mais próximo).
    public var volumeRoot: @Sendable (URL) -> URL

    public init(volumeRoot: @escaping @Sendable (URL) -> URL) { self.volumeRoot = volumeRoot }

    public static let system = VolumeResolver { url in
        var cur = url
        while !FileManager.default.fileExists(atPath: cur.path) && cur.path != "/" {
            cur = cur.deletingLastPathComponent()
        }
        return (try? cur.resourceValues(forKeys: [.volumeURLKey]).volume) ?? URL(fileURLWithPath: "/")
    }
}
