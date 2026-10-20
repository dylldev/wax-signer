import Foundation
import Security
import CryptoKit

/// Over-the-air install: Wax uploads a signed IPA and a manifest to an HTTPS server the owner controls, then asks
/// iOS to install from there with `itms-services://`. iOS refuses to install from a server on the same phone,
/// so the server must be another host with a publicly trusted certificate.
public enum OTAManifest {
    public static func build(bundleIdentifier: String, bundleVersion: String, title: String, ipaURL: URL) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }
        let version = bundleVersion.isEmpty ? "1" : bundleVersion
        let name = title.isEmpty ? bundleIdentifier : title
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>items</key><array><dict>
        <key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>\(esc(ipaURL.absoluteString))</string></dict></array>
        <key>metadata</key><dict><key>bundle-identifier</key><string>\(esc(bundleIdentifier))</string><key>bundle-version</key><string>\(esc(version))</string><key>kind</key><string>software</string><key>title</key><string>\(esc(name))</string></dict>
        </dict></array></dict></plist>
        """
    }
}

public enum OTALink {
    public static func installURL(manifest: URL) -> URL {
        // The manifest URL is one query value: `&`, `=`, `+` and `#` inside it must not end or split it.
        let value = manifest.absoluteString.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#"))) ?? manifest.absoluteString
        return URL(string: "itms-services://?action=download-manifest&url=\(value)")!
    }
}

public enum OTASessionID {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Injectable so the failure paths are testable; production always uses the system generator.
    static var fillRandom: (inout [UInt8]) -> OSStatus = { SecRandomCopyBytes(kSecRandomDefault, $0.count, &$0) }

    /// 128 random bits, base64url: unguessable, and the only thing protecting the download link.
    /// Throws rather than trapping: a generator failure must fail one install the user can retry, not kill the app.
    /// All-zero entropy is refused for the same reason -- a generator that reports success and hands back a constant
    /// would publish a link secret anyone could guess.
    public static func make() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard fillRandom(&bytes) == errSecSuccess else {
            throw Failure(message: "Secure random numbers are not available on this iPhone, so Wax cannot make a safe install link. Use My server or Bucket instead.")
        }
        guard bytes.contains(where: { $0 != 0 }) else {
            throw Failure(message: "Wax could not make a safe install link on this iPhone. Use My server or Bucket instead.")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct OTAEndpoint: Equatable, Sendable {
    public struct Invalid: Error, LocalizedError {
        public let reason: String
        public var errorDescription: String? { reason }
    }
    public let base: URL

    public init(_ text: String) throws {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: s), c.scheme == "https", let host = c.host, !host.isEmpty else {
            throw Invalid(reason: "The install server must be an https:// address.")
        }
        guard c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else {
            throw Invalid(reason: "The install server address must not contain credentials, a query or a fragment.")
        }
        var t = c; t.path = c.path.hasSuffix("/") ? String(c.path.dropLast()) : c.path
        guard let url = t.url else { throw Invalid(reason: "That address could not be read.") }
        base = url
    }

    public func uploadURL(id: String, name: String) -> URL { base.appendingPathComponent("ota-up/u/\(id)/\(name)") }
    public var healthURL: URL { base.appendingPathComponent("ota-up/health") }
    func hasURL(sha256: String) -> URL { base.appendingPathComponent("ota-up/has/\(sha256)") }
    func deleteURL(id: String) -> URL { base.appendingPathComponent("ota-up/u/\(id)") }
    public func publicURL(id: String, name: String) -> URL { base.appendingPathComponent("ota/\(id)/\(name)") }
}

public struct OTAUploader {
    public struct Failure: Error, LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    let endpoint: OTAEndpoint
    let token: String
    let session: URLSession

    public init(endpoint: OTAEndpoint, token: String, session: URLSession = .shared) {
        self.endpoint = endpoint; self.token = token; self.session = session
    }

    /// Uploads the IPA, then the manifest, and returns the link that makes iOS offer the install.
    /// If the manifest cannot be stored the IPA is removed again, so nothing is left on the server.
    public func upload(ipa: URL, bundleIdentifier: String, version: String, build: String = "", title: String,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let sha = try Self.sha256Hex(of: ipa)
        let id: String
        var reused = false
        if let existing = await existingSession(sha256: sha) {
            id = existing; reused = true; progress(1)          // the server already holds this exact file
        } else {
            id = try OTASessionID.make()
            try await put(endpoint.uploadURL(id: id, name: "app.ipa"), file: ipa, sha256: sha, progress: progress)
        }
        do {
            let xml = OTAManifest.build(bundleIdentifier: bundleIdentifier, bundleVersion: build.isEmpty ? version : build, title: title,
                                        ipaURL: endpoint.publicURL(id: id, name: "app.ipa"))
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("manifest-\(id).plist")
            try Data(xml.utf8).write(to: tmp)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try await put(endpoint.uploadURL(id: id, name: "manifest.plist"), file: tmp, progress: { _ in })
            // A 201 only proves the upload service took the files. Prove iOS will be able to fetch them too.
            try await verifyReachable(manifest: endpoint.publicURL(id: id, name: "manifest.plist"))
        } catch {
            if !reused {    // a reused folder held this IPA before; an earlier install link may still depend on it
                var r = URLRequest(url: endpoint.deleteURL(id: id)); r.httpMethod = "DELETE"
                r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                _ = try? await session.data(for: r)
            }
            throw error
        }
        return OTALink.installURL(manifest: endpoint.publicURL(id: id, name: "manifest.plist"))
    }

    /// The id of a session whose IPA the server has already verified to have this hash, or nil (also when the
    /// server is older and does not know the lookup).
    public func existingSession(sha256: String) async -> String? {
        var r = URLRequest(url: endpoint.hasURL(sha256: sha256)); r.timeoutInterval = 20
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: r), (response as? HTTPURLResponse)?.statusCode == 200,
              let id = (try? JSONDecoder().decode([String: String].self, from: data))?["id"], !id.isEmpty else { return nil }
        return id
    }

    static func sha256Hex(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file); defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Fetches the manifest the way iOS will. Catches a web folder that does not match the upload folder, which
    /// otherwise looks like a successful upload followed by "Unable to install".
    public func verifyReachable(manifest: URL) async throws {
        var r = URLRequest(url: manifest); r.timeoutInterval = 20
        let result: (body: Data, code: Int)
        do { result = try await InstallTransport.send(r, session: session) }
        catch { throw Failure(message: "Could not reach the install server to check the link: \(error.localizedDescription)") }
        guard result.code == 200, InstallTransport.looksLikeManifest(result.body) else {
            throw Failure(message: "The server accepted the upload but the install link is not reachable (HTTP \(result.code)). Check that the server's web folder matches the upload folder.")
        }
    }

    /// Asks the server whether the token is accepted, so a wrong or rotated token is found when it is saved, not after signing.
    public func checkToken() async throws {
        var r = URLRequest(url: endpoint.healthURL); r.timeoutInterval = 20
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let result: (body: Data, code: Int)
        do { result = try await InstallTransport.send(r, session: session) }
        catch { throw Failure(message: "Could not reach the install server: \(error.localizedDescription)") }
        switch result.code {
        case 200, 204: return
        case 401: throw Failure(message: "The install server rejected the token. Check it in the install settings.")
        case let code: throw Failure(message: "The install server answered the token check with HTTP \(code). Is the upload service running behind the proxy?")
        }
    }

    private func put(_ url: URL, file: URL, sha256: String? = nil, progress: @escaping @Sendable (Double) -> Void) async throws {
        var r = URLRequest(url: url); r.httpMethod = "PUT"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.timeoutInterval = 600
        if let sha256 { r.setValue(sha256, forHTTPHeaderField: "X-Wax-SHA256") }
        let result: (body: Data, code: Int)
        do { result = try await InstallTransport.sendUpload(r, file: file, session: session, progress: progress) }
        catch { throw Failure(message: "Could not reach the install server: \(error.localizedDescription)") }
        let code = result.code
        switch code {
        case 201: return
        case 401: throw Failure(message: "The install server rejected the token. Check it in the install settings.")
        case 413: throw Failure(message: "This IPA is too large for the install server's limit.")
        case 507: throw Failure(message: "The install server is full. Try again in a few minutes.")
        default: throw Failure(message: "The install server returned an error (HTTP \(code)).")
        }
    }
}

/// One line that carries the install server and its token, so a new copy of Wax is set up with a single paste.
/// Format: `WAXINSTALL1 <https server> <token>`. The token is never included in an error message.
public enum OTASetup {
    public struct Invalid: Error, LocalizedError {
        public let reason: String
        public var errorDescription: String? { reason }
    }
    public struct Parsed: Equatable, Sendable { public let server: String; public let token: String }

    private static let tag = "WAXINSTALL1"
    /// The server refuses shorter tokens, so the app must too, or every upload would fail with an unexplained 401.
    public static let minimumTokenLength = 32

    public static func make(server: String, token: String) -> String { "\(tag) \(server) \(token)" }

    public static func parse(_ text: String) throws -> Parsed {
        let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 3, parts[0] == tag else {
            throw Invalid(reason: "That is not an install setup line. It should look like: \(tag) https://your-server <token>")
        }
        let endpoint: OTAEndpoint
        do { endpoint = try OTAEndpoint(parts[1]) } catch {
            throw Invalid(reason: "The server address in the setup line is not a valid https:// address.")
        }
        let token = parts[2]
        guard token.count >= minimumTokenLength, token.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            throw Invalid(reason: "The token in the setup line looks wrong (it needs 32 or more characters and only letters, digits, dots, dashes and underscores).")
        }
        return Parsed(server: endpoint.base.absoluteString, token: token)
    }
}

/// Profiles with a fixed app ID (like most reseller profiles) make Wax re-label the app being signed. When that
/// label is the running Wax's own ID, installing would replace Wax itself with the other app.
public enum BundleIDGuard {
    /// Every bundle ID Wax has ever shipped, oldest first. Never prune this: a phone running an old build is still
    /// running that old ID, and this set is what distinguishes "Wax replacing itself" from "a stranger replacing Wax".
    static let waxIDs: Set<String> = [
        "dev.localsigner.app",              // first builds
        "io.github.dylankirkgirg.wax",      // 0.11.0 through 0.13.0
        "io.github.dylldev.wax",            // current
        "dev.localsigner.wax.dev",          // development
    ]

    public static func replacesRunningWax(originalID: String, finalID: String, runningID: String?) -> Bool {
        guard let runningID, finalID == runningID else { return false }
        return !waxIDs.contains(originalID)      // Wax's own builds updating themselves are fine
    }

    public static let explanation =
        "Installing this app would replace Wax itself: your profile only allows one app ID, and this copy of Wax is using it. "
        + "Install it from the other copy of Wax, or import a wildcard profile (one that allows any app ID)."
}
