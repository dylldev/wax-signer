import Foundation

/// Why a file picked from Files / iCloud Drive could not be read. Always names the file and the cause.
public enum ExternalFileError: Error, Equatable, LocalizedError {
    case accessDenied(String)
    case notFound(String)
    case downloadTimedOut(String, seconds: Int)
    case downloadFailed(String, detail: String)
    case unreadable(String, domain: String, code: Int, detail: String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied(let n):
            return "“\(n)” cannot be read: permission denied. Pick it again from Files, or move it to On My iPhone."
        case .notFound(let n):
            return "“\(n)” was not found. It may have been moved or deleted, or iCloud has not finished syncing it."
        case .downloadTimedOut(let n, let s):
            return "“\(n)” is still downloading from iCloud after \(s) seconds. Open Files, tap the file to download it, then try again."
        case .downloadFailed(let n, let d):
            return "iCloud could not download “\(n)”: \(d)"
        case .unreadable(let n, let domain, let code, let detail):
            return "“\(n)” could not be read (\(domain) \(code)): \(detail)"
        }
    }
}

/// What the importer needs to know about iCloud. The real implementation asks the system; tests substitute a fake.
public struct UbiquityProbe {
    public enum Status: Equatable { case notUbiquitous, current, notDownloaded }
    public var status: (URL) -> Status
    public var startDownload: (URL) throws -> Void
    public var downloadError: (URL) -> Error?

    public init(status: @escaping (URL) -> Status, startDownload: @escaping (URL) throws -> Void,
                downloadError: @escaping (URL) -> Error?) {
        self.status = status; self.startDownload = startDownload; self.downloadError = downloadError
    }

    public static let system = UbiquityProbe(
        status: { url in
            let fm = FileManager.default
            // Older iCloud placeholders: the real name does not exist, ".<name>.icloud" does.
            if !fm.fileExists(atPath: url.path) {
                let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
                return fm.fileExists(atPath: placeholder.path) ? .notDownloaded : .notUbiquitous
            }
            guard let v = try? url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                  v.isUbiquitousItem == true else { return .notUbiquitous }
            switch v.ubiquitousItemDownloadingStatus {
            case .current?, .downloaded?: return .current
            default: return .notDownloaded
            }
        },
        startDownload: { try FileManager.default.startDownloadingUbiquitousItem(at: $0) },
        downloadError: { (try? $0.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey]))?.ubiquitousItemDownloadingError })
}

public enum ExternalFile {
    /// Runs `body` with a URL that is safe to read:
    /// 1. security-scoped access is open for the whole call;
    /// 2. an iCloud item that is not on the device is downloaded first, and we wait for it;
    /// 3. the read happens inside a file coordination, as the system requires for items owned by a provider.
    ///
    /// Errors thrown by `body` are rethrown untouched, except plain "no such file" / "no permission"
    /// read errors, which become `ExternalFileError`. Nothing here logs or stores file contents.
    public static func withReadAccess<T>(to url: URL, probe: UbiquityProbe = .system, timeout: TimeInterval = 600,
                                         pollInterval: TimeInterval = 0.25, progress: ((String) -> Void)? = nil,
                                         _ body: (URL) throws -> T) throws -> T {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        if probe.status(url) == .notDownloaded {
            progress?("Downloading “\(name)” from iCloud…")
            do { try probe.startDownload(url) } catch {
                throw ExternalFileError.downloadFailed(name, detail: describe(error))
            }
            let deadline = Date().addingTimeInterval(timeout)
            while probe.status(url) == .notDownloaded {
                if let failure = probe.downloadError(url) {
                    throw ExternalFileError.downloadFailed(name, detail: describe(failure))
                }
                if Date() >= deadline { throw ExternalFileError.downloadTimedOut(name, seconds: Int(timeout)) }
                Thread.sleep(forTimeInterval: pollInterval)
            }
        }

        var coordinationError: NSError?
        var outcome: Result<T, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            outcome = Result {
                try checkReadable(readURL, name: name)
                return try body(readURL)
            }
        }
        if let coordinationError { throw map(coordinationError, name: name) }
        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw mapReadError(error, name: name)
        case nil: throw ExternalFileError.unreadable(name, domain: "ExternalFile", code: 0, detail: "the read did not run")
        }
    }

    /// Surfaces open/permission/directory problems with the file's name before any parser sees them.
    private static func checkReadable(_ url: URL, name: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw ExternalFileError.notFound(name)
        }
        if isDirectory.boolValue {
            throw ExternalFileError.unreadable(name, domain: "ExternalFile", code: 1, detail: "it is a folder, not a file")
        }
        do {
            let h = try FileHandle(forReadingFrom: url)
            try h.close()
        } catch {
            throw map(error as NSError, name: name)
        }
    }

    private static func mapReadError(_ error: Error, name: String) -> Error {
        guard error is CocoaError || (error as NSError).domain == NSCocoaErrorDomain || (error as NSError).domain == NSPOSIXErrorDomain
        else { return error }
        return map(error as NSError, name: name)
    }

    private static func map(_ e: NSError, name: String) -> ExternalFileError {
        if e.domain == NSCocoaErrorDomain {
            switch e.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError: return .notFound(name)
            // FileHandle reports a refused open as 513 (write-permission code) even for reads.
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError: return .accessDenied(name)
            default: break
            }
        }
        if e.domain == NSPOSIXErrorDomain {
            switch Int32(e.code) {
            case ENOENT: return .notFound(name)
            case EACCES, EPERM: return .accessDenied(name)
            default: break
            }
        }
        return .unreadable(name, domain: e.domain, code: e.code, detail: e.localizedDescription)
    }

    private static func describe(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.localizedDescription) (\(e.domain) \(e.code))"
    }
}

extension IPAInspector {
    /// Inspects an IPA the user picked from Files or iCloud Drive: downloads it if needed, reads it under
    /// coordination, then validates the archive. A file that could not be read is reported as such,
    /// never as a bad archive.
    public static func inspect(externalURL url: URL, probe: UbiquityProbe = .system, timeout: TimeInterval = 600,
                               pollInterval: TimeInterval = 0.25, progress: ((String) -> Void)? = nil) throws -> IPAMetadata {
        do {
            return try ExternalFile.withReadAccess(to: url, probe: probe, timeout: timeout,
                                                   pollInterval: pollInterval, progress: progress) { try inspect(url: $0) }
        } catch let e as ExternalFileError {
            throw IPAError.unreadable(e.errorDescription ?? "the file could not be read")
        }
    }
}
