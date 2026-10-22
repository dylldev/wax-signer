import Foundation
import Security

/// Keeps one small secret (the install-server token) in the Keychain only: this device, not synced.
public protocol SecretStore {
    func load() -> Data?
    func save(_ data: Data) throws
    func delete()
}

public struct KeychainSecretStore: SecretStore {
    public struct Failure: Error, LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? { "Keychain refused the secret (OSStatus \(status))." }
    }

    /// Readable once the phone has been unlocked since boot, so an upload that carries on in the background
    /// after the screen locks can still read the token. Still this device only: not in backups, not synced.
    public static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// The Keychain service name. DO NOT RENAME: Wax has shipped under this string, and changing it would orphan
    /// every install token already stored on people's phones, making them re-enter it.
    public static let defaultService = "dev.localsigner.wax.install-token"

    private let service: String
    public init(service: String = KeychainSecretStore.defaultService) { self.service = service }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "record"]
    }

    public func load() -> Data? {
        var q = base
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    public func save(_ data: Data) throws {
        // Update in place first: delete-then-add would lose the token if the app were stopped between the two calls.
        let updated = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw Failure(status: updated) }
        var q = base
        q[kSecValueData as String] = data
        q[kSecAttrSynchronizable as String] = false
        #if os(iOS)
        q[kSecAttrAccessible as String] = KeychainSecretStore.accessibility
        #endif
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    /// Moves a token saved by an older build to the current accessibility. Best effort, safe to repeat.
    public func migrateAccessibility() {
        SecItemUpdate(base as CFDictionary, [kSecAttrAccessible as String: Self.accessibility] as CFDictionary)
    }

    public func delete() { SecItemDelete(base as CFDictionary) }
}
