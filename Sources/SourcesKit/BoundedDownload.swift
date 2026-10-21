import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Actual transfer limits, independent of advertised source metadata or Content-Length.
public struct DownloadBudget: Sendable {
    public let maxBytes: Int64
    public let deadline: TimeInterval
    public let minimumFreeBytes: Int64
    public init(maxBytes: Int64 = 2 * 1024 * 1024 * 1024, deadline: TimeInterval = 1800,
                minimumFreeBytes: Int64 = 16 * 1024 * 1024) {
        self.maxBytes = maxBytes; self.deadline = deadline; self.minimumFreeBytes = minimumFreeBytes
    }
}

enum BoundedDownloadError: Error, LocalizedError {
    case tooLarge, deadline, diskSpace, notSaved, unsafeURL, invalidBudget, unsupportedDelegate
    var errorDescription: String? {
        switch self {
        case .unsupportedDelegate: "This custom delegate or background session cannot be used by the bounded download transport."
        case .tooLarge: "The download exceeded its size limit. Use a smaller IPA or source."
        case .deadline: "The download exceeded its total time limit. Retry on a faster connection."
        case .diskSpace: "There is not enough free storage for this download. Free space and retry."
        case .notSaved: "The download could not be retained. Check storage and retry."
        case .unsafeURL: "Downloads and redirects must use HTTPS, within the redirect limit."
        case .invalidBudget: "The configured download limits are invalid."
        }
    }
}

struct BoundedDownload {
    struct Result { let file: URL; let status: Int; let response: URLResponse }
    static func fetch(_ request: URLRequest, session: URLSession, budget: DownloadBudget,
                      staging: @escaping @Sendable () -> URL = { FileManager.default.temporaryDirectory },
                      progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> Result {
        guard budget.maxBytes > 0, budget.deadline.isFinite, budget.deadline > 0, budget.deadline <= 86400,
              budget.minimumFreeBytes >= 0 else { throw BoundedDownloadError.invalidBudget }
        // Preserve configuration (including protocol classes/cookies/TLS settings). Custom delegate trust
        // policies cannot be silently dropped by the dedicated streaming session.
        guard session.delegate == nil, session.configuration.identifier == nil else { throw BoundedDownloadError.unsupportedDelegate }
        guard allowed(request.url) else { throw BoundedDownloadError.unsafeURL }
        try freeSpace(in: staging(), budget: budget)
        let delegate = Receiver(budget: budget, staging: staging, progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(session: session, request: request, continuation: continuation)
            }
        } onCancel: { delegate.cancel(CancellationError()) }
    }
    private static func allowed(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.isEmpty == false && url?.user == nil && url?.password == nil
    }
    private static func freeSpace(in directory: URL, budget: DownloadBudget) throws {
        guard directory.isFileURL else { throw BoundedDownloadError.notSaved }
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: directory.path)
            guard let bytes = attributes[.systemFreeSize] as? NSNumber else { throw BoundedDownloadError.notSaved }
            if bytes.int64Value < budget.minimumFreeBytes { throw BoundedDownloadError.diskSpace }
        } catch let error as BoundedDownloadError { throw error }
        catch { throw BoundedDownloadError.notSaved }
    }
    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let budget: DownloadBudget
        private let staging: @Sendable () -> URL
        private let progress: @Sendable (Double) -> Void
        private var continuation: CheckedContinuation<Result, Error>?
        private var task: URLSessionDataTask?
        private var network: URLSession?
        private var stopped: Error?
        private var saved: URL?
        private var output: FileHandle?
        private var received: Int64 = 0
        private var response: URLResponse?
        private var timer: DispatchSourceTimer?
        private var redirects = 0
        private var lastDiskProbe: Int64 = 0
        init(budget: DownloadBudget, staging: @escaping @Sendable () -> URL, progress: @escaping @Sendable (Double) -> Void) {
            self.budget = budget; self.staging = staging; self.progress = progress
        }
        func start(session: URLSession, request: URLRequest, continuation: CheckedContinuation<Result, Error>) {
            let network = URLSession(configuration: session.configuration, delegate: self, delegateQueue: nil)
            let download = network.dataTask(with: request)
            let failure: Error? = lock.withLock {
                if let stopped { return stopped }
                let file = staging().appendingPathComponent("wax-dl-\(UUID().uuidString)")
                let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { return BoundedDownloadError.notSaved }
                saved = file; output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                self.continuation = continuation; task = download; self.network = network
                let clock = DispatchSource.makeTimerSource()
                clock.schedule(deadline: .now() + budget.deadline)
                clock.setEventHandler { [weak self] in self?.cancel(BoundedDownloadError.deadline) }
                timer = clock; clock.resume()
                return nil
            }
            if let failure { network.invalidateAndCancel(); continuation.resume(throwing: failure) }
            else { download.resume() }
        }
        func cancel(_ error: Error) {
            let download = lock.withLock { () -> URLSessionDataTask? in
                if stopped == nil { stopped = error }
                return task
            }
            finish(error) // complete even if the transport never sends a completion after cancellation
            download?.cancel()
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            let accept = lock.withLock { () -> Bool in redirects += 1; return redirects <= 5 && BoundedDownload.allowed(request.url) && stopped == nil }
            if !accept { cancel(BoundedDownloadError.unsafeURL) }
            completionHandler(accept ? request : nil)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let failure: Error? = lock.withLock {
                self.response = response
                if let stopped { return stopped }
                if !BoundedDownload.allowed(response.url) { return BoundedDownloadError.unsafeURL }
                if response.expectedContentLength > budget.maxBytes { return BoundedDownloadError.tooLarge }
                return nil
            }
            if let failure { cancel(failure); completionHandler(.cancel) }
            else { completionHandler(.allow) }
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            var fraction: Double?
            let failure: Error? = lock.withLock {
                if let stopped { return stopped }
                // NSURLSession delivers decoded body chunks. Check before writing, regardless of headers.
                guard Int64(data.count) <= budget.maxBytes - received else { return BoundedDownloadError.tooLarge }
                do {
                    guard let output else { return BoundedDownloadError.notSaved }
                    try output.write(contentsOf: data); received += Int64(data.count)
                    if received - lastDiskProbe >= 8 * 1024 * 1024 {
                        lastDiskProbe = received; try BoundedDownload.freeSpace(in: staging(), budget: budget)
                    }
                } catch { return (error as? BoundedDownloadError) ?? BoundedDownloadError.notSaved }
                if let expected = response?.expectedContentLength, expected > 0 { fraction = min(1, Double(received) / Double(expected)) }
                return nil
            }
            if let failure { cancel(failure) }
            else if let fraction { progress(fraction) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error) }
        private func finish(_ error: Error?) {
            let result = lock.withLock { () -> (CheckedContinuation<Result, Error>?, URL?, URLResponse?, Error?, URLSession?) in
                let cont = continuation; continuation = nil
                timer?.cancel(); timer = nil; self.task = nil
                let owned = network; network = nil
                let file = saved; saved = nil
                var failure = stopped ?? error
                do {
                    if failure == nil { try output?.synchronize() }
                    try output?.close()
                    if failure == nil, let file {
                        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                        guard (attributes[.size] as? NSNumber)?.int64Value == received else { throw BoundedDownloadError.notSaved }
                    }
                } catch { failure = failure ?? BoundedDownloadError.notSaved; try? output?.close() }
                output = nil
                return (cont, file, response, failure, owned)
            }
            result.4?.invalidateAndCancel()
            guard let continuation = result.0 else { return }
            if let failure = result.3 {
                if let file = result.1 { try? FileManager.default.removeItem(at: file) }
                continuation.resume(throwing: failure)
            } else if let file = result.1, let response = result.2 {
                progress(1)
                continuation.resume(returning: Result(file: file, status: (response as? HTTPURLResponse)?.statusCode ?? 0, response: response))
            } else {
                if let file = result.1 { try? FileManager.default.removeItem(at: file) }
                continuation.resume(throwing: BoundedDownloadError.notSaved)
            }
        }
    }
}
