import Foundation

public enum FullDiskAccess {
    public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Tenta abrir uma pasta que só o Acesso Total ao Disco deixa ler.
    /// ~/Library/Safari existe em todo Mac; o TCC.db do usuário sumiu no macOS 27.
    public static func isGranted(probe: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Safari")) -> Bool {
        let fd = open(probe.path, O_RDONLY)
        if fd >= 0 { close(fd); return true }
        return false
    }
}
