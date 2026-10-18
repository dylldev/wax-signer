import Foundation

public enum DownloadError: Error, Equatable, LocalizedError {
    case http(Int), linkExpired, notAnIPA, notSaved
    public var errorDescription: String? {
        switch self {
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
    /// Injectable so a failure to keep the download can be exercised; production always uses the app's temp directory.
    private let stagingDirectory: @Sendable () -> URL

    public init(session: URLSession = .shared,
                stagingDirectory: @escaping @Sendable () -> URL = { FileManager.default.temporaryDirectory }) {
        self.session = session
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

    private struct Fetched { let file: URL; let status: Int }

    private func fetch(_ url: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Fetched {
        let delegate = Delegate(progress: progress, stagingDirectory: stagingDirectory)
        var request = URLRequest(url: url); request.timeoutInterval = 120
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Fetched, Error>) in
                delegate.continuation = cont
                let task = session.downloadTask(with: request)
                task.delegate = delegate
                delegate.task = task
                task.resume()
            }
        } onCancel: { delegate.cancel() }
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

    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let progress: @Sendable (Double) -> Void
        let stagingDirectory: @Sendable () -> URL
        var continuation: CheckedContinuation<Fetched, Error>?
        var task: URLSessionDownloadTask?
        private var saved: URL?
        private var status = 0
        private let lock = NSLock()
        init(progress: @escaping @Sendable (Double) -> Void, stagingDirectory: @escaping @Sendable () -> URL) {
            self.progress = progress
            self.stagingDirectory = stagingDirectory
        }

        func cancel() { task?.cancel() }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                        totalBytesWritten written: Int64, totalBytesExpectedToWrite expected: Int64) {
            if expected > 0 { progress(min(1, Double(written) / Double(expected))) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            // The system deletes `location` when this returns, so keep our own copy now.
            let keep = stagingDirectory().appendingPathComponent("wax-dl-\(UUID().uuidString)")
            do { try FileManager.default.moveItem(at: location, to: keep); lock.withLock { saved = keep } } catch {}
            status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            let (file, code) = lock.withLock { (saved, status) }
            let cont = continuation; continuation = nil
            if let error { if let file { try? FileManager.default.removeItem(at: file) }; cont?.resume(throwing: error); return }
            // No error and no saved file means we could not keep the bytes we were handed. Saying "HTTP 0" here
            // would send the user to blame their source for a failure on this phone.
            guard let file else { cont?.resume(throwing: DownloadError.notSaved); return }
            progress(1)
            cont?.resume(returning: Fetched(file: file, status: code))
        }
    }
}
