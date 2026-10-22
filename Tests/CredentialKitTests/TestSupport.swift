import Foundation
import Security
@testable import CredentialKit

/// In-memory keychain with failure injection.
final class FakeKeychain: IdentityKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: SecIdentity] = [:]
    var failStore: Int32?
    var failRemove: Int32?
    private(set) var storeCalls = 0

    var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }

    func store(identity: SecIdentity, id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        storeCalls += 1
        if let s = failStore { throw CredentialError.keychain(operation: "store key", status: s) }
        items[id] = identity
    }

    func identity(id: UUID) throws -> SecIdentity {
        lock.lock(); defer { lock.unlock() }
        guard let i = items[id] else { throw CredentialError.notFound }
        return i
    }

    func remove(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        if let s = failRemove { throw CredentialError.keychain(operation: "remove key", status: s) }
        items[id] = nil
    }
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("credkit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
