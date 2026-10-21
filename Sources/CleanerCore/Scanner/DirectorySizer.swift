import Foundation

public enum DirectorySizer {
    /// Tamanho alocado em disco. `inaccessible` indica varredura incompleta (ex.: sem Acesso Total ao Disco).
    public static func size(of url: URL) -> (bytes: Int64, inaccessible: Bool) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        let fm = FileManager.default
        var total: Int64 = 0
        var denied = false

        func own(_ u: URL) -> Int64 {
            Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        guard FS.kind(of: url) == .directory else { return (own(url), false) }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                    errorHandler: { _, _ in denied = true; return true }) else { return (0, true) }
        for case let u as URL in e { total += own(u) }
        return (total, denied)
    }
}
