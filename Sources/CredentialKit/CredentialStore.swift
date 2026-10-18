import Foundation
import Security

/// Imports, lists and deletes signing certificates and provisioning profiles.
///
/// What is kept where:
/// - private key + certificate: Keychain only (via `IdentityKeychain`)
/// - `index.json`: non-secret display metadata
/// - `profiles/<uuid>.mobileprovision`: the raw profile, because a signer must embed the original bytes
/// The .p12 password is used once to open the file and is never stored or logged.
public final class CredentialStore: @unchecked Sendable {
    private struct Index: Codable {
        var certificates: [CertificateInfo] = []
        var profiles: [ProfileInfo] = []
    }

    private let directory: URL
    private let keychain: IdentityKeychain
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var index = Index()

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private var profilesDirectory: URL { directory.appendingPathComponent("profiles", isDirectory: true) }
    private func profileURL(_ id: UUID) -> URL {
        profilesDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("mobileprovision")
    }

    public init(directory: URL, keychain: IdentityKeychain = SystemIdentityKeychain(),
                now: @escaping @Sendable () -> Date = { Date() }) throws {
        self.directory = directory
        self.keychain = keychain
        self.now = now
        do {
            try FileManager.default.createDirectory(at: profilesDirectory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var dir = directory
            try dir.setResourceValues(values)
        } catch {
            throw CredentialError.storage("cannot create storage directory")
        }
        if FileManager.default.fileExists(atPath: indexURL.path) {
            // A corrupt index is surfaced, never silently reset: resetting would orphan Keychain items.
            guard let data = try? Data(contentsOf: indexURL),
                  let loaded = try? Self.decoder.decode(Index.self, from: data) else {
                throw CredentialError.storage("index is unreadable")
            }
            index = loaded
        }
    }

    // MARK: Reading

    public func certificates() -> [CertificateInfo] { locked { index.certificates } }
    public func profiles() -> [ProfileInfo] { locked { index.profiles } }

    /// The identity (certificate + private key) for a future signing step. Returns a Keychain reference.
    public func identity(for certificateID: UUID) throws -> SecIdentity {
        guard locked({ index.certificates.contains { $0.id == certificateID } }) else { throw CredentialError.notFound }
        return try keychain.identity(id: certificateID)
    }

    /// The original profile bytes, for embedding by a future signing step.
    public func profileData(for profileID: UUID) throws -> Data {
        guard locked({ index.profiles.contains { $0.id == profileID } }) else { throw CredentialError.notFound }
        do { return try Data(contentsOf: profileURL(profileID)) } catch { throw CredentialError.storage("profile file missing") }
    }

    public func compatibility(certificateID: UUID, profileID: UUID) throws -> CompatibilityReport {
        let (cert, profile) = try locked { () -> (CertificateInfo, ProfileInfo) in
            guard let c = index.certificates.first(where: { $0.id == certificateID }),
                  let p = index.profiles.first(where: { $0.id == profileID }) else { throw CredentialError.notFound }
            return (c, p)
        }
        return .evaluate(certificate: cert, profile: profile, now: now())
    }

    // MARK: Importing

    /// Imports the first identity in the file (kept for single-identity callers).
    @discardableResult
    public func importCertificate(p12 data: Data, password: String) throws -> CertificateInfo {
        try importCertificates(p12: data, password: password)[0]
    }

    /// Imports every identity in the file. Identities that are already imported are skipped; if nothing new is
    /// left the error says so. An expired or not-yet-valid identity is skipped when another one imports, and
    /// reported when it is the only one.
    @discardableResult
    func importCertificates(p12 data: Data, password: String,
                            systemImport: PKCS12Reader.SystemImport) throws -> [CertificateInfo] {
        let parsed = try PKCS12Reader.readAll(data, password: password, systemImport: systemImport)
        var imported: [CertificateInfo] = []
        var firstError: Error?
        for identity in parsed {
            do { imported.append(try store(identity)) }
            catch { firstError = firstError ?? error }
        }
        if imported.isEmpty, let firstError { throw firstError }
        return imported
    }

    public func importCertificates(p12 data: Data, password: String) throws -> [CertificateInfo] {
        try importCertificates(p12: data, password: password, systemImport: PKCS12Reader.appleImport)
    }

    private func store(_ parsed: ParsedIdentity) throws -> CertificateInfo {
        let s = parsed.summary
        let current = Self.wholeSeconds(now())
        if current > s.notAfter { throw CredentialError.certificateExpired(s.notAfter) }
        if current < s.notBefore { throw CredentialError.certificateNotYetValid(s.notBefore) }

        let info = CertificateInfo(
            id: UUID(), commonName: s.commonName ?? "Unnamed certificate", organization: s.organization,
            teamID: s.organizationalUnit, country: s.country,
            serialNumberHex: s.serial.map { String(format: "%02X", $0) }.joined(),
            sha1Fingerprint: X509Summary.sha1Hex(parsed.certificateDER),
            notBefore: s.notBefore, notAfter: s.notAfter, importedAt: current)

        return try locked {
            if index.certificates.contains(where: { $0.sha1Fingerprint == info.sha1Fingerprint }) {
                throw CredentialError.alreadyImported
            }
            try keychain.store(identity: parsed.identity, id: info.id)
            var updated = index
            updated.certificates.append(info)
            do { try save(updated) } catch {
                try? keychain.remove(id: info.id) // keep Keychain and index in step
                throw error
            }
            index = updated
            return info
        }
    }

    /// A profile with a UUID that is already imported replaces the old one.
    @discardableResult
    public func importProfile(_ data: Data) throws -> ProfileInfo {
        let info = try ProfileReader.read(data, importedAt: Self.wholeSeconds(now()), now: now())
        return try locked {
            let url = profileURL(info.id)
            let previous = try? Data(contentsOf: url)
            do {
                try data.write(to: url, options: Self.writeOptions)
            } catch { throw CredentialError.storage("cannot write profile") }

            var updated = index
            updated.profiles.removeAll { $0.id == info.id }
            updated.profiles.append(info)
            do { try save(updated) } catch {
                if let previous { try? previous.write(to: url, options: Self.writeOptions) }
                else { try? FileManager.default.removeItem(at: url) }
                throw error
            }
            index = updated
            return info
        }
    }

    // MARK: Deleting

    /// Removes the index entry and Keychain key. If either step fails, the entry is retained when possible.
    public func deleteCertificate(id: UUID) throws {
        try locked {
            guard index.certificates.contains(where: { $0.id == id }) else { throw CredentialError.notFound }
            var updated = index
            updated.certificates.removeAll { $0.id == id }
            try save(updated)
            do { try keychain.remove(id: id) } catch {
                do { try save(index) }
                catch { throw CredentialError.storage("cannot restore index after keychain removal failed") }
                throw error
            }
            index = updated
        }
    }

    public func deleteProfile(id: UUID) throws {
        try locked {
            guard index.profiles.contains(where: { $0.id == id }) else { throw CredentialError.notFound }
            var updated = index
            updated.profiles.removeAll { $0.id == id }
            try save(updated)
            index = updated
            try? FileManager.default.removeItem(at: profileURL(id))
        }
    }

    // MARK: Internals

    private static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    /// The index stores ISO-8601 (whole seconds); truncate up front so values compare equal after a reload.
    private static func wholeSeconds(_ d: Date) -> Date {
        Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down))
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func save(_ index: Index) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try e.encode(index).write(to: indexURL, options: Self.writeOptions) }
        catch { throw CredentialError.storage("cannot write index") }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
}
