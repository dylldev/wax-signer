import Foundation

/// Bounded response bodies for install control requests and upload replies. File upload bytes remain streamed by URLSession.
enum InstallTransport {
    struct Budget: Sendable {
        let maxBytes: Int
        let deadline: TimeInterval
        init(maxBytes: Int = 1024 * 1024, deadline: TimeInterval = 20) { self.maxBytes = maxBytes; self.deadline = deadline }
    }
    enum Failure: LocalizedError {
        case tooLarge, deadline, invalidBudget, unsafeURL, unsupportedSession, missingResponse
        var errorDescription: String? {
            switch self {
            case .tooLarge: "The install host response is too large. Check the host address and retry."
            case .deadline: "The install host exceeded the total time limit. Retry on a faster connection."
            case .invalidBudget: "The install response limits are invalid."
            case .unsafeURL: "Install requests and redirects must use HTTPS; authenticated redirects must stay on the original host."
            case .unsupportedSession: "This custom delegate or background session cannot be used by the bounded install transport."
            case .missingResponse: "The install host did not return an HTTP response."
            }
        }
    }
    static func send(_ request: URLRequest, session: URLSession, budget: Budget = Budget()) async throws -> (body: Data, code: Int) {
        try await perform(request, file: nil, session: session, budget: budget, progress: { _ in })
    }
    static func sendUpload(_ request: URLRequest, file: URL, session: URLSession,
                           budget: Budget = Budget(deadline: 1800), progress: @escaping @Sendable (Double) -> Void) async throws -> (body: Data, code: Int) {
        try await perform(request, file: file, session: session, budget: budget, progress: progress)
    }
    private static func allowed(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.isEmpty == false && url?.user == nil && url?.password == nil
    }
    private static func origin(_ url: URL?) -> String? {
        guard let url, let host = url.host?.lowercased(), allowed(url) else { return nil }
        return host + ":" + String(url.port ?? 443)
    }
    private static func perform(_ request: URLRequest, file: URL?, session: URLSession, budget: Budget,
                                progress: @escaping @Sendable (Double) -> Void) async throws -> (body: Data, code: Int) {
        guard budget.maxBytes > 0, budget.maxBytes <= 64 * 1024 * 1024,
              budget.deadline.isFinite, budget.deadline > 0, budget.deadline <= 86400 else { throw Failure.invalidBudget }
        guard allowed(request.url) else { throw Failure.unsafeURL }
        // A dedicated delegate streams chunks. Do not silently discard a caller's trust policy or background lifecycle.
        guard session.delegate == nil, session.configuration.identifier == nil else { throw Failure.unsupportedSession }
        let receiver = Receiver(budget: budget, progress: progress)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { receiver.start(request, file: file, session: session, continuation: $0) }
        }, onCancel: { receiver.cancel(CancellationError()) })
    }
    static func looksLikeManifest(_ data: Data) -> Bool {
        String(decoding: data.prefix(2048), as: UTF8.self).contains("<plist")
    }

    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let budget: Budget
        private let progress: @Sendable (Double) -> Void
        private var continuation: CheckedContinuation<(body: Data, code: Int), Error>?
        private var network: URLSession?
        private var task: URLSessionTask?
        private var timer: DispatchSourceTimer?
        private var stopped: Error?
        private var response: HTTPURLResponse?
        private var body = Data()
        private var redirects = 0
        private var authenticated = false
        private var refusesRedirects = false
        private var originalOrigin: String?
        init(budget: Budget, progress: @escaping @Sendable (Double) -> Void) { self.budget = budget; self.progress = progress }
        func start(_ request: URLRequest, file: URL?, session: URLSession,
                   continuation: CheckedContinuation<(body: Data, code: Int), Error>) {
            let network = URLSession(configuration: session.configuration, delegate: self, delegateQueue: nil)
            let task: URLSessionTask
            if let file { task = network.uploadTask(with: request, fromFile: file) }
            else { task = network.dataTask(with: request) }
            let failure: Error? = lock.withLock {
                if let stopped { return stopped }
                self.continuation = continuation; self.network = network; self.task = task
                authenticated = request.value(forHTTPHeaderField: "Authorization") != nil
                refusesRedirects = request.httpMethod == "DELETE"
                originalOrigin = InstallTransport.origin(request.url)
                let timer = DispatchSource.makeTimerSource()
                timer.schedule(deadline: .now() + budget.deadline)
                timer.setEventHandler { [weak self] in self?.cancel(Failure.deadline) }
                self.timer = timer; timer.resume()
                return nil
            }
            if let failure { network.invalidateAndCancel(); continuation.resume(throwing: failure) }
            else { task.resume() }
        }
        func cancel(_ error: Error) { finish(error, canceled: true) }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            // Destructive cleanup never changes destination, even for same-origin redirects.
            if lock.withLock({ refusesRedirects }) { completionHandler(nil); return }
            let accept = lock.withLock {
                redirects += 1
                return stopped == nil && redirects <= 5 && InstallTransport.allowed(request.url)
                    && (!authenticated || InstallTransport.origin(request.url) == originalOrigin)
            }
            if !accept { cancel(Failure.unsafeURL) }
            completionHandler(accept ? request : nil)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            let error: Error? = lock.withLock {
                if let stopped { return stopped }
                guard let response = response as? HTTPURLResponse else { return Failure.missingResponse }
                guard InstallTransport.allowed(response.url) else { return Failure.unsafeURL }
                self.response = response
                // Darwin custom protocols can report unknown expectedContentLength despite a raw length header.
                // Both are advisory early checks; actual decoded chunks remain authoritative.
                if response.expectedContentLength > Int64(budget.maxBytes) { return Failure.tooLarge }
                if let header = response.value(forHTTPHeaderField: "Content-Length")?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !header.isEmpty, header.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                   UInt64(header).map({ $0 > UInt64(budget.maxBytes) }) ?? true { return Failure.tooLarge }
                return nil
            }
            if let error { cancel(error); completionHandler(.cancel) } else { completionHandler(.allow) }
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let error: Error? = lock.withLock {
                if let stopped { return stopped }
                // URLSession supplies decoded body chunks. Content-Length is only an early refusal hint.
                guard data.count <= budget.maxBytes - body.count else { return Failure.tooLarge }
                body.append(data); return nil
            }
            if let error { cancel(error) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend total: Int64) {
            let active = lock.withLock { continuation != nil && stopped == nil }
            if active, total > 0 { progress(min(1, max(0, Double(totalBytesSent) / Double(total)))) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(error) }
        private func finish(_ error: Error?, canceled: Bool = false) {
            let result = lock.withLock { () -> (CheckedContinuation<(body: Data, code: Int), Error>?, Data, HTTPURLResponse?, Error?, URLSession?) in
                if canceled, stopped == nil { stopped = error }
                let continuation = continuation; self.continuation = nil
                timer?.cancel(); timer = nil; task = nil
                let owned = network; network = nil
                let data = body; body = Data()
                return (continuation, data, response, stopped ?? error, owned)
            }
            result.4?.invalidateAndCancel()
            guard let continuation = result.0 else { return }
            if let error = result.3 { continuation.resume(throwing: error) }
            else if let response = result.2 { continuation.resume(returning: (result.1, response.statusCode)) }
            else { continuation.resume(throwing: Failure.missingResponse) }
        }
    }
}
