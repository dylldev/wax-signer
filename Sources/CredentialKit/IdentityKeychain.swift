import Foundation
import Security

/// Where certificate private keys live. The real implementation is the system Keychain; tests can
/// substitute one to inject failures.
public protocol IdentityKeychain: Sendable {
    func store(identity: SecIdentity, id: UUID) throws
    func identity(id: UUID) throws -> SecIdentity
    /// Idempotent: removing something that is not there is not an error.
    func remove(id: UUID) throws
}

/// Stores the private key and certificate as separate Keychain items, tagged by `service` + id.
/// Items are `AfterFirstUnlockThisDeviceOnly`: not in backups, not synced, and readable after the first unlock
/// since boot, so signing that carries on in the background after the screen locks can still use the key.
public struct SystemIdentityKeychain: IdentityKeychain {
    public let service: String
    public static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    public init(service: String = "dev.localsigner.credentials") {
        self.service = service
    }

    private func label(_ id: UUID) -> String { "\(service).\(id.uuidString)" }
    private func tag(_ id: UUID) -> Data { Data(label(id).utf8) }

    public func store(identity: SecIdentity, id: UUID) throws {
        var key: SecKey?
        var cert: SecCertificate?
        guard SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess, let key else {
            throw CredentialError.noPrivateKey
        }
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else {
            throw CredentialError.certificateUnreadable
        }

        let keyStatus = SecItemAdd([
            kSecClass: kSecClassKey, kSecValueRef: key,
            kSecAttrApplicationTag: tag(id), kSecAttrLabel: label(id),
            kSecAttrAccessible: Self.accessibility,
        ] as CFDictionary, nil)
        guard keyStatus == errSecSuccess else {
            throw CredentialError.keychain(operation: "store key", status: keyStatus)
        }

        let addCertificate = {
            SecItemAdd([
                kSecClass: kSecClassCertificate, kSecValueRef: cert, kSecAttrLabel: label(id),
                kSecAttrAccessible: Self.accessibility,
            ] as CFDictionary, nil)
        }
        var certStatus = addCertificate()
        if certStatus == errSecDuplicateItem {
            // The Keychain keeps one item per certificate, and items outlive app deletion. A copy
            // left behind by an earlier install (its index is gone) would block this import
            // forever, so replace that stale item and retry once.
            SecItemDelete([kSecClass: kSecClassCertificate, kSecValueRef: cert] as CFDictionary)
            certStatus = addCertificate()
        }
        guard certStatus == errSecSuccess else {
            try? remove(id: id) // do not leave a key without its certificate
            throw CredentialError.keychain(operation: "store certificate", status: certStatus)
        }
    }

    public func identity(id: UUID) throws -> SecIdentity {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassIdentity, kSecAttrLabel: label(id),
            kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { throw CredentialError.notFound }
        guard status == errSecSuccess, let result else {
            throw CredentialError.keychain(operation: "read identity", status: status)
        }
        return result as! SecIdentity // kSecClassIdentity query returns a SecIdentity
    }

    /// Moves items stored by an older build to the current accessibility. Best effort (errors ignored),
    /// safe to run on every launch.
    public func migrateAccessibility() {
        for cls in [kSecClassKey, kSecClassCertificate] {
            var found: CFTypeRef?
            guard SecItemCopyMatching([kSecClass: cls, kSecReturnAttributes: true, kSecMatchLimit: kSecMatchLimitAll] as CFDictionary, &found) == errSecSuccess,
                  let items = found as? [[String: Any]] else { continue }
            for item in items {
                let label = item[kSecAttrLabel as String] as? String ?? ""
                guard label.hasPrefix(service + ".") else { continue }
                SecItemUpdate([kSecClass: cls, kSecAttrLabel: label] as CFDictionary,
                              [kSecAttrAccessible: Self.accessibility] as CFDictionary)
            }
        }
    }

    public func remove(id: UUID) throws {
        let keyStatus = SecItemDelete([
            kSecClass: kSecClassKey, kSecAttrApplicationTag: tag(id),
        ] as CFDictionary)
        let certStatus = SecItemDelete([
            kSecClass: kSecClassCertificate, kSecAttrLabel: label(id),
        ] as CFDictionary)
        for (op, status) in [("remove key", keyStatus), ("remove certificate", certStatus)]
        where status != errSecSuccess && status != errSecItemNotFound {
            throw CredentialError.keychain(operation: op, status: status)
        }
    }
}
