import Foundation
import CryptoKit

/// Where a signed IPA is published so iOS can install it. Either the owner's own server or a storage bucket.
public protocol InstallHost {
    func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL
}

extension OTAUploader: InstallHost {
    public func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await upload(ipa: ipa, bundleIdentifier: bundleIdentifier, version: version, build: build, title: title, progress: progress)
    }
}

/// Publishes to any S3-compatible bucket (Cloudflare R2, Backblaze B2, Oracle Object Storage, MinIO, AWS).
/// The bucket stays private: iOS gets links that name one object and stop working after six hours.
public struct S3Host: InstallHost {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static let linkLifetime = 6 * 3600

    public let id: String
    let credentials: S3Credentials
    let bucket: String
    let session: URLSession
    let now: () -> Date

    /// A default argument cannot throw, so the link id is resolved inside the body instead of in the signature.
    public init(credentials: S3Credentials, bucket: String, session: URLSession = .shared, id: String? = nil,
                now: @escaping () -> Date = Date.init) throws {
        self.id = try id ?? OTASessionID.make()
        self.credentials = credentials; self.bucket = bucket; self.session = session; self.now = now
    }

    private func objectURL(_ name: String) -> URL {
        credentials.endpoint.appendingPathComponent("\(bucket)/ota/\(id)/\(name)")
    }

    public func publish(ipa: URL, bundleIdentifier: String, version: String, build: String, title: String,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await put("app.ipa", file: ipa, type: "application/octet-stream", progress: progress)
        do {
            let ipaLink = S3Signer.presignGET(objectURL("app.ipa"), credentials: credentials, expires: Self.linkLifetime, date: now())
            let xml = OTAManifest.build(bundleIdentifier: bundleIdentifier, bundleVersion: build.isEmpty ? version : build, title: title, ipaURL: ipaLink)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-\(id).plist")
            try Data(xml.utf8).write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await put("manifest.plist", file: tmp, type: "text/xml", progress: { _ in })
            let manifestLink = S3Signer.presignGET(objectURL("manifest.plist"), credentials: credentials, expires: Self.linkLifetime, date: now())
            try await verifyReachable(manifestLink)
            // iOS fetches the app through its own signed URL. Read the stored tail back so a proxy that
            // truncated or swapped the object cannot hand over a link that fails on the phone.
            try await verifyServedIPA(ipaLink, local: ipa)
            return OTALink.installURL(manifest: manifestLink)
        } catch {
            await cleanup()
            throw error
        }
    }

    /// Lists at most one object, which proves the endpoint, region, bucket name and keys all agree.
    public func checkAccess() async throws {
        var parts = URLComponents(url: credentials.endpoint.appendingPathComponent(bucket), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "list-type", value: "2"), URLQueryItem(name: "max-keys", value: "1")]
        var r = S3Signer.signedRequest(method: "GET", url: parts.url!, payloadSHA256: Self.emptySHA, credentials: credentials, date: now())
        r.timeoutInterval = 20
        let result: (body: Data, code: Int)
        do { result = try await InstallTransport.send(r, session: session) }
        catch { throw Failure(message: "Could not reach the bucket: \(error.localizedDescription)") }
        guard result.code == 200 else { throw Self.explain(result.code, body: String(decoding: result.body.prefix(4096), as: UTF8.self)) }
    }

    /// Compatibility best-effort path for a failed publication. Durable callers use cleanupConfirmed.
    public func cleanup() async { try? await cleanupConfirmed() }

    /// Both objects must be confirmed deleted (or already absent) before a retention record is removed.
    public func cleanupConfirmed() async throws {
        var failure: Error?
        for name in ["app.ipa", "manifest.plist"] {
            do { try await delete(name) } catch { if failure == nil { failure = error } }
        }
        if let failure { throw failure }
    }

    private func delete(_ name: String) async throws {
        var r = S3Signer.signedRequest(method: "DELETE", url: objectURL(name), payloadSHA256: Self.emptySHA, credentials: credentials, date: now())
        r.timeoutInterval = 20
        // Never redirect a credential-bearing destructive request to a different destination.
        let (_, code) = try await InstallTransport.send(r, session: session)
        guard (200..<300).contains(code) || code == 404 else {
            throw Failure(message: "Bucket cleanup was not confirmed (HTTP \(code)). Its record is kept for retry.")
        }
    }

    private static let emptySHA = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    private func put(_ name: String, file: URL, type: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        var r = S3Signer.signedRequest(method: "PUT", url: objectURL(name), payloadSHA256: try OTAUploader.sha256Hex(of: file),
                                       credentials: credentials, date: now(), headers: ["Content-Type": type])
        r.timeoutInterval = 600
        let result: (body: Data, code: Int)
        do { result = try await InstallTransport.sendUpload(r, file: file, session: session, progress: progress) }
        catch { throw Failure(message: "Could not reach the bucket: \(error.localizedDescription)") }
        guard (200..<300).contains(result.code) else { throw Self.explain(result.code, body: String(decoding: result.body.prefix(4096), as: UTF8.self)) }
    }

    /// Reads back the last 64 KiB of the stored object and compares it with the uploaded file.
    /// The bucket must answer the ranged GET; one that cannot confirm its own bytes does not get a link.
    private func verifyServedIPA(_ link: URL, local: URL) async throws {
        let size = (try? local.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, let handle = try? FileHandle(forReadingFrom: local) else {
            throw Failure(message: "The signed app could not be read back before the install link was handed over.")
        }
        defer { try? handle.close() }
        let window = min(64 * 1024, size)
        do { try handle.seek(toOffset: UInt64(size - window)) } catch {
            throw Failure(message: "The signed app could not be read back before the install link was handed over.")
        }
        guard let expected = (try? handle.read(upToCount: window)) ?? nil, expected.count == window else {
            throw Failure(message: "The signed app could not be read back before the install link was handed over.")
        }
        var r = URLRequest(url: link)
        r.timeoutInterval = 60
        r.setValue("bytes=\(size - window)-\(size - 1)", forHTTPHeaderField: "Range")
        let result: (body: Data, code: Int)
        do {
            // A server that ignores the range is allowed to answer with the whole object; the budget stops a
            // multi-hundred-megabyte second download before it starts.
            result = try await InstallTransport.send(r, session: session,
                                                     budget: InstallTransport.Budget(maxBytes: max(window, 1024 * 1024), deadline: 60))
        } catch InstallTransport.Failure.tooLarge {
            throw Failure(message: "The bucket did not return the requested part of the stored app, so Wax could not confirm what it holds. Check the endpoint or the proxy in front of the bucket; no install link was handed over.")
        } catch {
            throw Failure(message: "Could not read the stored app back from the bucket: \(error.localizedDescription)")
        }
        guard result.code == 206 || result.code == 200 else {
            throw Failure(message: "The bucket stored the app but did not return it (HTTP \(result.code)). No install link was handed over.")
        }
        guard result.body == expected else {
            throw Failure(message: "The bucket returned different bytes than Wax uploaded, so the app would not install. Check for a proxy or a failed upload; no link was handed over.")
        }
    }

    private func verifyReachable(_ manifest: URL) async throws {
        var r = URLRequest(url: manifest); r.timeoutInterval = 20
        let result: (body: Data, code: Int)
        do { result = try await InstallTransport.send(r, session: session) }
        catch { throw Failure(message: "Could not reach the bucket to check the link: \(error.localizedDescription)") }
        guard result.code == 200, InstallTransport.looksLikeManifest(result.body) else {
            throw Failure(message: "The bucket stored the files but the install link did not open (HTTP \(result.code)). Check the endpoint and region.")
        }
    }

    /// Turns the bucket's XML error into a sentence that says which setting to fix.
    static func explain(_ code: Int, body: String) -> Failure {
        func tag(_ name: String) -> String? {
            guard let a = body.range(of: "<\(name)>"), let b = body.range(of: "</\(name)>", range: a.upperBound..<body.endIndex) else { return nil }
            return String(body[a.upperBound..<b.lowerBound])
        }
        let c = tag("Code") ?? ""
        if c == "ExpiredToken" || c == "TokenRefreshRequired" {
            return Failure(message: "The bucket's access keys have expired. Make new keys and enter them in Settings.")
        }
        if c == "AuthorizationHeaderMalformed" || c == "InvalidRegion" || body.lowercased().contains("region") {
            return Failure(message: "The region looks wrong. The bucket said: \(tag("Message") ?? "check the Region setting").")
        }
        if c == "InvalidAccessKeyId" || c == "SignatureDoesNotMatch" || code == 401 || code == 403 {
            return Failure(message: "The bucket rejected the access key or secret key. Check both in Settings.")
        }
        if c == "NoSuchBucket" || code == 404 { return Failure(message: "That bucket was not found at this endpoint. Check the bucket name and endpoint.") }
        return Failure(message: "The bucket returned an error (HTTP \(code)\(c.isEmpty ? "" : ", \(c)")).")
    }
}
