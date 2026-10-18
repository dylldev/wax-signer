import Foundation
import CryptoKit
import Security

/// The certificate (and its key) for the name that points at this phone. The key is public on purpose: the name only
/// ever resolves to 127.0.0.1. A scheduled job renews it and publishes it as one small JSON file.
public struct CertificateBundle: Codable, Equatable, Sendable {
    public let name: String
    public let notAfter: Date
    /// PKCS#12 (certificate chain and private key), base64.
    public let p12: String
    public let password: String

    public var p12Data: Data { Data(base64Encoded: p12) ?? Data() }
}

public enum LoopbackConfig {
    /// The official install host is NOT in this repo: the build injects it from two Info.plist keys,
    /// `WAX_DEFAULT_FEED` (the certificate feed URL) and `WAX_INSTALL_DOMAIN` (the domain names the
    /// feed may publish, comma-separated; lowercased at load). A checkout built without them ships
    /// with no official feed — Settings starts empty, every feed the person enters is person-chosen
    /// (still chain-checked), and a leak of this repo reveals nothing about where the owner's feed
    /// lives or what it is allowed to publish.
    public static let defaultFeed = Bundle.main.object(forInfoDictionaryKey: "WAX_DEFAULT_FEED") as? String ?? ""
    public static let officialNames: Set<String> = officialNames(from: Bundle.main.object(forInfoDictionaryKey: "WAX_INSTALL_DOMAIN") as? String)

    /// One official-feed decision: the allow-list names and the feed URL they go with. Production uses the
    /// build-injected `LoopbackConfig` values; tests inject a stub pair instead of shipping literals.
    public struct Config {
        let names: Set<String>
        let feed: String
    }

    /// The build-supplied allow-list: lowercase names, trimmed, empty for an injected-nothing build.
    /// Exposed domain histories are irrelevant here by design: nothing in this repo may contain them.
    static func officialNames(from rawDomain: String?) -> Set<String> {
        let names = (rawDomain ?? "").lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Set(names)
    }

    /// Whether the text is an address Wax can fetch a certificate from (https only). A build with no official feed and
    /// nothing typed is not set up, and the screens must not say it is.
    public static func isUsableFeed(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return false }
        return true
    }

    /// The names a feed may publish, or nil when the person chose their own feed (any name, still checked for shape).
    /// Feeds are compared lowercased because the domain itself is case-insensitive on GitHub Pages and DuckDNS,
    /// but a string comparison is not.
    public static func allowedNames(for feed: URL, config: Config? = nil) -> Set<String>? {
        func key(_ u: URL) -> String? {
            guard let c = URLComponents(url: u, resolvingAgainstBaseURL: false), c.scheme?.lowercased() == "https",
                  let host = c.host?.lowercased() else { return nil }
            var path = c.path; while path.hasSuffix("/") { path.removeLast() }
            let port = (c.port == nil || c.port == 443) ? "" : ":\(c.port!)"
            return host + port + path
        }
        let names = config?.names ?? officialNames
        let published = config?.feed ?? defaultFeed
        guard !published.isEmpty, let mine = key(feed) else { return nil }          // no official feed in this build
        guard let feedURL = URL(string: published), let theirs = key(feedURL), mine.lowercased() == theirs.lowercased() else { return nil }
        return names        // may be empty: an official feed with no allowed names refuses every name (fails closed)
    }
}

public enum CertificateFeed {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Renew when fewer than this many days remain.
    public static let renewBefore: TimeInterval = 7 * 86400
    /// Even a certificate with plenty of life left is looked up again after this long, so a re-issued one (for example
    /// after a revocation) reaches the phone within a day.
    static let refreshAfter: TimeInterval = 86400
    /// A real feed is about 7 KB; anything near this is not one.
    static let maxBytes = 64 * 1024
    /// Public certificates last at most 200 days (less every year); a longer claim is not a real certificate.
    static let maxLifetime: TimeInterval = 400 * 86400

    /// Returns a usable certificate: the cached one while it has more than a week left, otherwise a fresh download.
    /// If the download fails, a cached certificate that has not expired yet is still used.
    /// Every certificate, fresh or cached, is chain-verified by the default verifier; `verify: nil` cannot
    /// disable that (it selects the real one). Non-nil is for test isolation: the feed fixtures cannot pass
    /// a system chain evaluation, and weaker default behaviour would be a shipped hole, not a test affordance.
    public static func load(feed: URL, cacheDirectory: URL, session: URLSession = .shared, now: Date = Date(),
                            allowedNames: Set<String>? = nil, bodyDeadline: TimeInterval = 20,
                            verify: ((CertificateBundle, Date) throws -> Void)? = nil) async throws -> CertificateBundle {
        guard feed.scheme?.lowercased() == "https" else { throw Failure(message: "The certificate feed must be an https:// address.") }
        let verifying = verify ?? Self.verify(_:now:)   // nil selects the real verifier; no caller can skip it
        let cacheFile = cacheDirectory.appendingPathComponent("install-certificate-\(cacheKey(feed)).json")
        let cached = (try? Data(contentsOf: cacheFile)).flatMap { try? decode($0, now: now, allowedNames: allowedNames) }
            .flatMap { bundle -> CertificateBundle? in      // a cache written by an older build gets the same check as a download
                return (try? verifying(bundle, now)) == nil ? nil : bundle
            }
        let cachedAt = (try? FileManager.default.attributesOfItem(atPath: cacheFile.path)[.modificationDate] as? Date) ?? .distantPast
        if let cached, cached.notAfter.timeIntervalSince(now) > renewBefore, now.timeIntervalSince(cachedAt) < refreshAfter { return cached }
        do {
            var request = URLRequest(url: feed); request.timeoutInterval = 20
            let (bytes, response) = try await session.bytes(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else { throw Failure(message: "The certificate feed answered HTTP \(code).") }
            var data = Data()
            let started = Date()
            for try await byte in bytes {
                if Date().timeIntervalSince(started) > bodyDeadline { throw Failure(message: "The certificate feed was too slow to answer.") }      // read at most maxBytes: a hostile feed cannot fill the phone's memory
                data.append(byte)
                if data.count > maxBytes { throw Failure(message: "The certificate feed is too large to be a certificate.") }
            }
            let fresh = try decode(data, now: now, allowedNames: allowedNames)
            try verifying(fresh, now)
            guard fresh.notAfter > now else { throw Failure(message: "The published install certificate has expired. It should be renewed soon; use another install host meanwhile.") }
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try data.write(to: cacheFile, options: .atomic)
            try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: cacheFile.path)
            return fresh
        } catch {
            if let cached, cached.notAfter > now { return cached }
            if let failure = error as? Failure { throw failure }
            throw Failure(message: "Could not download the install certificate: \(error.localizedDescription)")
        }
    }

    /// The certificate inside the file must open with the password, chain to a root iOS trusts, be valid now and be for
    /// `bundle.name`. Without this a feed could hand out a file whose labels say one thing and whose contents say another.
    static func verify(_ bundle: CertificateBundle, now: Date) throws {
        var items: CFArray?
        var options: [String: Any] = [kSecImportExportPassphrase as String: bundle.password]
        if #available(iOS 18, macOS 15, *) { options[kSecImportToMemoryOnly as String] = true }
        guard SecPKCS12Import(bundle.p12Data as CFData, options as CFDictionary, &items) == errSecSuccess,
              let entry = (items as? [[String: Any]])?.first,
              let chain = entry[kSecImportItemCertChain as String] as? [SecCertificate], !chain.isEmpty else {
            throw Failure(message: "The install certificate in the feed could not be opened.")
        }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateSSL(true, bundle.name as CFString), &trust) == errSecSuccess,
              let trust else { throw Failure(message: "The install certificate in the feed is not usable.") }
        SecTrustSetVerifyDate(trust, now as CFDate)
        guard SecTrustEvaluateWithError(trust, nil) else {
            throw Failure(message: "The install certificate in the feed is not valid for \(bundle.name) right now.")
        }
    }

    /// One cache file per feed address, so a different feed never reuses another feed's certificate.
    static func cacheKey(_ feed: URL) -> String {
        SHA256.hash(data: Data(feed.absoluteString.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func validName(_ name: String) -> Bool {
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        return !labels.isEmpty && name.count <= 253 && labels.allSatisfy {
            !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-")
                && $0.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }
        }
    }

    static func decode(_ data: Data, now: Date = Date(), allowedNames: Set<String>? = nil) throws -> CertificateBundle {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let bundle = try? decoder.decode(CertificateBundle.self, from: data), !bundle.name.isEmpty,
              Data(base64Encoded: bundle.p12)?.isEmpty == false else {
            throw Failure(message: "The install certificate file is not valid.")
        }
        guard validName(bundle.name), bundle.notAfter.timeIntervalSince(now) <= maxLifetime else {
            throw Failure(message: "The install certificate file is not valid.")
        }
        if let allowedNames, !allowedNames.contains(bundle.name.lowercased()) {
            throw Failure(message: "The certificate feed offered the name \(bundle.name), which this feed is not allowed to use.")
        }
        return bundle
    }
}
