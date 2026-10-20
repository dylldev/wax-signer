import Foundation
import Security

/// A certificate with its private key, held in memory only. Nothing here is persisted.
struct ParsedIdentity {
    let identity: SecIdentity
    let certificateDER: Data
    let summary: X509Summary
}

enum PKCS12Reader {
    static let maxBytes = 5 * 1024 * 1024

    typealias SystemImport = (Data, String) -> (OSStatus, [[String: Any]]?)

    /// Apple's importer. The key never leaves the Security framework.
    static func appleImport(_ data: Data, _ password: String) -> (OSStatus, [[String: Any]]?) {
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        if #available(iOS 18.0, macOS 15.0, *) {
            options[kSecImportToMemoryOnly as String] = true
        }
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        return (status, items as? [[String: Any]])
    }

    /// Opens a .p12. When Apple's importer refuses, the file's own integrity check decides whether the password is
    /// really wrong, and a file with a right password is re-encoded in the classic format and tried again.
    static func read(_ data: Data, password: String, systemImport: SystemImport = appleImport) throws -> ParsedIdentity {
        try readAll(data, password: password, systemImport: systemImport)[0]
    }

    /// Every identity in the file (a reseller's .p12 often holds both a Development and a Distribution identity).
    static func readAll(_ data: Data, password: String, systemImport: SystemImport = appleImport) throws -> [ParsedIdentity] {
        guard data.count <= maxBytes else { throw CredentialError.fileTooLarge }

        var (status, imported) = systemImport(data, password)
        if status != errSecSuccess {
            switch ModernPKCS12.assess(data, password: password) {
            case .wrongPassword: throw CredentialError.incorrectPassword
            case .legacyEquivalent(let classic): (status, imported) = systemImport(classic, password)
            case .unsupported: break
            }
        }

        switch status {
        case errSecSuccess: break
        case errSecAuthFailed, errSecPassphraseRequired: throw CredentialError.incorrectPassword
        case errSecDecode, errSecUnknownFormat, errSecInvalidData, errSecParam:
            throw CredentialError.malformedPKCS12
        default: throw CredentialError.unsupportedPKCS12(status: status)
        }

        let entries = imported ?? []
        let identities = entries.compactMap { $0[kSecImportItemIdentity as String] }
        guard !identities.isEmpty else { throw CredentialError.noPrivateKey }
        return try identities.map { try parse(identity: $0 as! SecIdentity) } // CF type; the dictionary key guarantees SecIdentity
    }

    private static func parse(identity: SecIdentity) throws -> ParsedIdentity {
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else {
            throw CredentialError.certificateUnreadable
        }
        var key: SecKey?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, key != nil else {
            throw CredentialError.noPrivateKey
        }

        let der = SecCertificateCopyData(cert) as Data
        guard let summary = try? X509Summary.parse(der: der) else { throw CredentialError.certificateUnreadable }
        return ParsedIdentity(identity: identity, certificateDER: der, summary: summary)
    }
}
