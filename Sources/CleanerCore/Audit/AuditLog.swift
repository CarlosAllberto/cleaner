import Foundation

/// Log JSONL local de tudo que foi movido, restaurado, expirado ou recusado.
public final class AuditLog: @unchecked Sendable {
    private struct Entry: Codable {
        let ts: String, event: String
        let session: String?, path: String?, detail: String?
    }

    private let url: URL
    private let lock = NSLock()

    public init(url: URL) { self.url = url }

    public func log(_ event: String, session: UUID? = nil, path: String? = nil, detail: String? = nil) {
        let entry = Entry(ts: ISO8601DateFormatter().string(from: Date()), event: event,
                          session: session?.uuidString, path: path, detail: detail)
        guard var line = try? JSONEncoder().encode(entry) else { return }
        line.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line)
    }
}
