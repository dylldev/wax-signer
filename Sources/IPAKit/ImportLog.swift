import Foundation

/// A small plain-text log of import steps, kept inside the app's own container so a failed import can be
/// diagnosed. It records step names, file names, sizes and error domains/codes. It never records file
/// contents, passwords, or paths outside the file name.
public final class ImportLog: @unchecked Sendable {
    public let fileURL: URL
    private let maxBytes: Int
    private let lock = NSLock()

    public init(fileURL: URL, maxBytes: Int = 64 * 1024) {
        self.fileURL = fileURL
        self.maxBytes = maxBytes
    }

    public func log(_ message: String, date: Date = Date()) {
        let clean = message.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let line = "\(ISO8601DateFormatter().string(from: date)) \(clean)\n"
        lock.lock(); defer { lock.unlock() }
        var data = (try? Data(contentsOf: fileURL)) ?? Data()
        data.append(Data(line.utf8))
        if data.count > maxBytes {
            // keep the newest half, starting at a line boundary
            var tail = data.suffix(maxBytes / 2)
            if let nl = tail.firstIndex(of: 0x0A) { tail = tail[tail.index(after: nl)...] }
            data = Data(tail)
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    public func recentLines(_ count: Int = 40) -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n").suffix(count).map(String.init))
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// "name.ext (1234 bytes)" without any directory component.
    public static func describe(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { "\($0) bytes" } ?? "size unknown"
        return "\(url.lastPathComponent) (\(size))"
    }

    /// "Domain code: message" for any error.
    public static func describe(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.domain) \(e.code): \(e.localizedDescription)"
    }
}
