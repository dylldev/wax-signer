import Foundation
import Network
import Security

/// Installs an app by serving it to iOS from this phone. A name that resolves to 127.0.0.1 and a publicly trusted
/// certificate for it let `itms-services` fetch the manifest and the IPA from a listener bound to loopback only.
/// No server, bucket or account is involved. See docs/superpowers/specs/2026-10-17-loopback-domain-spike.md.
public final class LoopbackHost: InstallHost, @unchecked Sendable {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    private let identity: SecIdentity
    private let intermediates: [SecCertificate]
    private let hostName: String
    private let lifetime: TimeInterval
    private let queue = DispatchQueue(label: "wax.loopback")
    private var listener: NWListener?
    private var ipaFile: URL?
    private var manifest = Data()
    private var id = ""
    private var stopTimer: DispatchWorkItem?
    private var served = false
    private var sent: [ClosedRange<Int>] = []      // byte ranges of the IPA that have gone out in full
    private var fileSize = 0
    private var finished: Bool { fileSize > 0 && sent == [0...(fileSize - 1)] }

    /// True once iOS has asked this phone for the IPA. If the install link was opened but this stays false, the
    /// name did not resolve to the phone (for example a network that rewrites DNS) and the install did not come from here.
    public var servedIPA: Bool { queue.sync { served } }

    /// `ranges` (sorted, disjoint) with `new` added and neighbours that touch or overlap joined.
    static func merged(_ ranges: [ClosedRange<Int>], adding new: ClosedRange<Int>) -> [ClosedRange<Int>] {
        let sorted = (ranges + [new]).sorted { $0.lowerBound < $1.lowerBound }
        var out: [ClosedRange<Int>] = []
        var current = sorted[0]
        for r in sorted.dropFirst() {
            if r.lowerBound <= current.upperBound + 1 { current = current.lowerBound...max(current.upperBound, r.upperBound) }
            else { out.append(current); current = r }
        }
        out.append(current)
        return out
    }

    /// Waits until the last byte of the IPA has gone out (iOS may fetch it in several ranges), the host stops, or
    /// `timeout` passes. True only when the whole file was sent.
    public func waitForTransfer(timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let (done, running) = queue.sync { (finished, listener != nil) }
            if done { return true }
            if !running { return false }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return queue.sync { finished }
    }

    /// What to tell the person when the transfer did not finish. `served` is whether iOS ever fetched the IPA here.
    public static func transferFailureMessage(served: Bool) -> String {
        served
            ? "The download stopped before the end, so nothing was installed. Try again."
            : "iOS never asked this phone for the app, so nothing was installed. You may have cancelled the install prompt. "
              + "If not, this network may be redirecting the install name: try another network, switch Install host to My server, "
              + "or Export the signed IPA from the IPA tab."
    }

    /// `p12` holds the certificate chain and private key for `host`.
    public init(p12: Data, password: String, host: String, lifetime: TimeInterval = 900) throws {
        var items: CFArray?
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        if #available(iOS 18, macOS 15, *) { options[kSecImportToMemoryOnly as String] = true }   // keep the key out of the Keychain
        let status = SecPKCS12Import(p12 as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let entry = (items as? [[String: Any]])?.first,
              let identity = entry[kSecImportItemIdentity as String] else {
            throw Failure(message: "The install certificate could not be read (error \(status)).")
        }
        self.identity = identity as! SecIdentity      // CFTypeRef of the right type: guarded by the import status above
        self.intermediates = Array(((entry[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []).dropFirst())
        self.hostName = host
        self.lifetime = lifetime
    }

    public func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        stop()
        queue.sync { served = false }
        // The certificate feed is remote input: never let it point the install link anywhere but at this phone.
        guard Self.resolvesOnlyToLoopback(hostName) else {
            throw Failure(message: "The install name “\(hostName)” does not point at this iPhone, so Wax will not use it. Use another install host.")
        }
        let id = try OTASessionID.make()
        let tls = NWProtocolTLS.Options()
        guard let secIdentity = sec_identity_create_with_certificates(identity, intermediates as CFArray) else {
            throw Failure(message: "The install certificate could not be used.")
        }
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
        let params = NWParameters(tls: tls)
        params.requiredInterfaceType = .loopback          // never reachable from the network
        let listener: NWListener
        do { listener = try NWListener(using: params) } catch { throw Failure(message: "Could not start the install listener: \(error.localizedDescription)") }
        listener.newConnectionHandler = { [weak self] c in self?.serve(c) }

        let port: UInt16 = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            var done = false
            listener.stateUpdateHandler = { state in
                guard !done else { return }
                switch state {
                case .ready:
                    done = true
                    if let p = listener.port?.rawValue { cont.resume(returning: p) } else { cont.resume(throwing: Failure(message: "The install listener has no port.")) }
                case .failed(let e): done = true; cont.resume(throwing: Failure(message: "The install listener failed: \(e.localizedDescription)"))
                case .cancelled: done = true; cont.resume(throwing: Failure(message: "The install listener was cancelled."))
                default: break
                }
            }
            listener.start(queue: queue)
        }
        let base = "https://\(hostName):\(port)/\(id)"
        let xml = OTAManifest.build(bundleIdentifier: bundleIdentifier, bundleVersion: build.isEmpty ? version : build, title: title,
                                    ipaURL: URL(string: "\(base)/app.ipa")!)
        queue.sync {
            self.listener = listener; self.ipaFile = ipa; self.id = id; self.manifest = Data(xml.utf8)
            self.sent = []; self.served = false
            self.fileSize = (try? FileManager.default.attributesOfItem(atPath: ipa.path)[.size] as? Int) ?? 0
            let timer = DispatchWorkItem { [weak self] in self?.stopLocked() }
            stopTimer = timer
            queue.asyncAfter(deadline: .now() + lifetime, execute: timer)
        }
        progress(1)
        return OTALink.installURL(manifest: URL(string: "\(base)/manifest.plist")!)
    }

    /// True when every address `name` resolves to is a loopback address (127.0.0.0/8 or ::1).
    static func resolvesOnlyToLoopback(_ name: String) -> Bool {
        var hints = addrinfo(); hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return false }
        defer { freeaddrinfo(result) }
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let n = node {
            guard let addr = n.pointee.ai_addr else { return false }
            switch Int32(addr.pointee.sa_family) {
            case AF_INET:
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
                if ip >> 24 != 127 { return false }
            case AF_INET6:
                let loop = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { p -> Bool in
                    var a = p.pointee.sin6_addr; return withUnsafeBytes(of: &a) { Array($0) } == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
                }
                if !loop { return false }
            default: return false
            }
            node = n.pointee.ai_next
        }
        return true
    }

    /// Closes the listener. Safe to call more than once.
    public func stop() { queue.sync { stopLocked() } }

    private func stopLocked() {
        stopTimer?.cancel(); stopTimer = nil
        listener?.cancel(); listener = nil
        ipaFile = nil; sent = []; fileSize = 0
    }

    // MARK: Serving

    private func serve(_ c: NWConnection) {
        c.start(queue: queue)
        readRequest(c, buffer: Data())
    }

    private func readRequest(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { c.cancel(); return }
            var buf = buffer; if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(c, head: String(decoding: buf[..<end.lowerBound], as: UTF8.self))
            } else if error != nil || isComplete || buf.count > 16_384 {
                c.cancel()
            } else {
                self.readRequest(c, buffer: buf)
            }
        }
    }

    private func respond(_ c: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ").map(String.init)
        guard parts.count >= 2 else { return reply(c, 400, "Bad Request") }
        let method = parts[0], path = parts[1].split(separator: "?").first.map(String.init) ?? ""
        guard method == "GET" || method == "HEAD" else { return reply(c, 405, "Method Not Allowed") }
        let isHead = method == "HEAD"
        if path == "/\(id)/manifest.plist" {
            return reply(c, 200, "OK", type: "text/xml", body: isHead ? nil : manifest, length: manifest.count)
        }
        guard path == "/\(id)/app.ipa", let file = ipaFile,
              let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) else { return reply(c, 404, "Not Found") }
        if !isHead { served = true }
        var lower = 0, upper = size - 1, partial = false
        if let range = lines.first(where: { $0.lowercased().hasPrefix("range:") }) {
            guard let r = Self.byteRange(range, size: size) else { return reply(c, 416, "Range Not Satisfiable", extra: "Content-Range: bytes */\(size)\r\n") }
            (lower, upper, partial) = (r.lowerBound, r.upperBound, true)
        }
        let length = upper - lower + 1
        var headers = "Accept-Ranges: bytes\r\n"
        if partial { headers += "Content-Range: bytes \(lower)-\(upper)/\(size)\r\n" }
        let status = partial ? "206 Partial Content" : "200 OK"
        let preface = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nContent-Length: \(length)\r\n\(headers)Connection: close\r\n\r\n"
        guard !isHead else { return c.send(content: Data(preface.utf8), completion: .contentProcessed { _ in c.cancel() }) }
        guard let handle = try? FileHandle(forReadingFrom: file) else { return reply(c, 404, "Not Found") }
        try? handle.seek(toOffset: UInt64(lower))
        c.send(content: Data(preface.utf8), completion: .contentProcessed { [weak self] e in
            if e != nil { try? handle.close(); c.cancel() } else { self?.stream(c, handle, remaining: length, range: lower...upper) }
        })
    }

    private func stream(_ c: NWConnection, _ handle: FileHandle, remaining: Int, range: ClosedRange<Int>) {
        guard remaining > 0, let chunk = try? handle.read(upToCount: min(256 * 1024, remaining)), !chunk.isEmpty else {
            try? handle.close(); return c.cancel()
        }
        let last = remaining == chunk.count
        c.send(content: chunk, completion: .contentProcessed { [weak self] e in
            if e != nil { try? handle.close(); c.cancel(); return }
            if last, let self { self.sent = Self.merged(self.sent, adding: range) }
            self?.stream(c, handle, remaining: remaining - chunk.count, range: range)
        })
    }

    private func reply(_ c: NWConnection, _ code: Int, _ reason: String, type: String = "text/plain", body: Data? = nil, length: Int? = nil, extra: String = "") {
        let text = Data(reason.utf8)
        let payload = body ?? (length == nil ? text : nil)
        let head = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(length ?? payload?.count ?? 0)\r\n\(extra)Connection: close\r\n\r\n"
        c.send(content: Data(head.utf8) + (payload ?? Data()), completion: .contentProcessed { _ in c.cancel() })
    }

    /// One `bytes=a-b`, `bytes=a-` or `bytes=-n` range, clipped to the file, or nil when it cannot be satisfied.
    static func byteRange(_ header: String, size: Int) -> ClosedRange<Int>? {
        guard size > 0, let eq = header.firstIndex(of: "=") else { return nil }
        let spec = header[header.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        guard !spec.contains(",") else { return nil }
        let bounds = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard bounds.count == 2 else { return nil }
        if bounds[0].isEmpty {
            guard let n = Int(bounds[1]), n > 0 else { return nil }
            return max(0, size - n)...(size - 1)
        }
        guard let a = Int(bounds[0]), a < size else { return nil }
        let b = bounds[1].isEmpty ? size - 1 : min(Int(bounds[1]) ?? size - 1, size - 1)
        return a <= b ? a...b : nil
    }
}
