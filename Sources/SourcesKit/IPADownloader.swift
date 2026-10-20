import Foundation

public enum DownloadError: Error, Equatable, LocalizedError {
    case http(Int), linkExpired, notAnIPA, notSaved, tooLarge, tooSlow, insufficientStorage, notHTTPS
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "The IPA exceeded the download size limit. Choose a smaller IPA."
        case .tooSlow: "The IPA download took too long. Retry on a faster connection."
        case .insufficientStorage: "There is not enough storage for the download. Free space and retry."
        case .notHTTPS: "The IPA URL and its redirects must use HTTPS."
        case .http(let c): "The download server answered with an error (HTTP \(c))."
        case .linkExpired: "The download link has expired and the source did not give a fresh one. Try again in a moment."
        case .notAnIPA: "The download is not an IPA file (the server may want a sign-in or sent a web page)."
        case .notSaved: "The app downloaded but Wax could not save it. Check that the phone has free space, then try again."
        }
    }
}

/// Downloads one IPA. Some sources hand out links that expire; a 401 or 403 asks the source for a fresh link once.
public struct IPADownloader: Sendable {
    private let session: URLSession
    private let budget: DownloadBudget
    /// Injectable so a failure to keep the download can be exercised; production always uses the app's temp directory.
    private let stagingDirectory: @Sendable () -> URL

    public init(session: URLSession = .shared,
                stagingDirectory: @escaping @Sendable () -> URL = { FileManager.default.temporaryDirectory },
                budget: DownloadBudget = DownloadBudget()) {
        self.session = session; self.budget = budget
        self.stagingDirectory = stagingDirectory
    }

    /// Returns the file's location inside `directory`. Nothing is left behind when the download fails.
    public func download(_ app: SourceApp, to directory: URL,
                         refetch: @Sendable () async throws -> SourceApp,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        var current = app
        for attempt in 0..<2 {
            let result = try await fetch(current.downloadURL, progress: progress)
            switch result.status {
            case 200..<300:
                defer { try? FileManager.default.removeItem(at: result.file) }
                guard Self.isZip(result.file) else { throw DownloadError.notAnIPA }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let dest = Self.uniqueDestination(in: directory, name: current.name, version: current.version)
                try FileManager.default.moveItem(at: result.file, to: dest)
                return dest
            case 401, 403:
                try? FileManager.default.removeItem(at: result.file)
                if attempt == 1 { throw DownloadError.linkExpired }
                current = try await refetch()
            default:
                try? FileManager.default.removeItem(at: result.file)
                throw DownloadError.http(result.status)
            }
        }
        throw DownloadError.linkExpired
    }

    // MARK: Pieces

    private func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> BoundedDownload.Result {
        var request = URLRequest(url: url); request.timeoutInterval = 120
        do { return try await BoundedDownload.fetch(request, session: session, budget: budget, staging: stagingDirectory, progress: progress) }
        catch BoundedDownloadError.tooLarge { throw DownloadError.tooLarge }
        catch BoundedDownloadError.deadline { throw DownloadError.tooSlow }
        catch BoundedDownloadError.diskSpace { throw DownloadError.insufficientStorage }
        catch BoundedDownloadError.unsafeURL { throw DownloadError.notHTTPS }
        catch BoundedDownloadError.notSaved { throw DownloadError.notSaved }
    }

    static func isZip(_ file: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? h.close() }
        return (try? h.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    static func uniqueDestination(in dir: URL, name: String, version: String) -> URL {
        let stem = ("\(name)-\(version)").filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        let base = stem.isEmpty ? "app" : stem
        var url = dir.appendingPathComponent("\(base).ipa"), n = 1
        while FileManager.default.fileExists(atPath: url.path) { n += 1; url = dir.appendingPathComponent("\(base)-\(n).ipa") }
        return url
    }

}
