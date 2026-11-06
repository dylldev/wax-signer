import CredentialKit
import InstallKit
import Security
import SigningKit
import XCTest
@testable import LocalIPASigner

@MainActor
final class IdentityReadinessOutcomeTests: XCTestCase {
    private var directory: URL!
    private var keychain: ReadinessKeychain!
    private var store: CredentialStore!
    private var certificate: CertificateInfo!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("readiness-\(UUID())")
        keychain = ReadinessKeychain()
        store = try CredentialStore(directory: directory, keychain: keychain)
        certificate = try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        try store.importProfile(FixtureData.profileWildcardAll)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testUncheckedIdentityIsNotReadyFromMetadataAlone() {
        XCTAssertEqual(IdentityReadiness.status(for: certificate, profiles: store.profiles()),
                       .needsAttention("Checking the stored signing certificate…"))
    }

    func testReadinessUsesSharedLookupAndKeepsSavedRecordsOnMismatch() async throws {
        let model = CredentialsModel(store: store)
        await model.refreshIdentityChecks()
        XCTAssertEqual(model.identityStatus(for: certificate), .ready)
        let other = try LoadedIdentity.load(p12: FixtureData.p12SecondIdentity, password: FixtureData.password)
        try keychain.store(identity: other.identity, id: certificate.id)
        let before = try Data(contentsOf: directory.appendingPathComponent("index.json"))
        await model.refreshIdentityChecks()
        guard case .needsAttention(let detail) = model.identityStatus(for: certificate) else {
            return XCTFail("A mismatched runtime leaf must not be ready")
        }
        XCTAssertTrue(detail.contains("does not match"))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("index.json")), before)
        XCTAssertEqual(store.certificates(), [certificate])
        try keychain.remove(id: certificate.id)
        await model.refreshIdentityChecks()
        guard case .needsAttention(let missing) = model.identityStatus(for: certificate) else {
            return XCTFail("A missing runtime identity must not be ready")
        }
        XCTAssertTrue(missing.contains("unavailable"))
    }

    func testObsoleteRefreshCannotOverwriteNewerMismatch() async throws {
        let model = CredentialsModel(store: store)
        let entered = expectation(description: "first read captured matching identity")
        let release = DispatchSemaphore(value: 0)
        keychain.blockNextRead { entered.fulfill(); _ = release.wait(timeout: .now() + 10) }
        let old = Task { await model.refreshIdentityChecks() }
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 5)
        let other = try LoadedIdentity.load(p12: FixtureData.p12SecondIdentity, password: FixtureData.password)
        try keychain.store(identity: other.identity, id: certificate.id)
        await model.refreshIdentityChecks()
        let latest = model.identityStatus(for: certificate)
        guard case .needsAttention(let detail) = latest else { return XCTFail("Latest lookup should reject mismatch") }
        XCTAssertTrue(detail.contains("does not match"))
        release.signal(); await old.value
        XCTAssertEqual(model.identityStatus(for: certificate), latest)
    }

    func testRemovedCertificateCannotReceiveAnInflightSuccess() async throws {
        let model = CredentialsModel(store: store)
        await model.refreshIdentityChecks()
        XCTAssertEqual(model.identityStatus(for: certificate), .ready)
        let entered = expectation(description: "read captured identity before deletion")
        let removed = expectation(description: "model published deletion")
        let subscription = model.$certificates.dropFirst().sink { if $0.isEmpty { removed.fulfill() } }
        defer { subscription.cancel() }
        let release = DispatchSemaphore(value: 0)
        keychain.blockNextRead { entered.fulfill(); _ = release.wait(timeout: .now() + 10) }
        let old = Task { await model.refreshIdentityChecks() }
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 5)
        model.delete(certificate: certificate)
        await fulfillment(of: [removed], timeout: 5)
        release.signal(); await old.value
        XCTAssertEqual(model.identityStatus(for: certificate), .needsAttention("Checking the stored signing certificate…"))
        XCTAssertTrue(model.identityChecks.isEmpty)
        XCTAssertTrue(store.certificates().isEmpty)
    }

    func testCancelledRefreshDoesNotPublishSuccess() async throws {
        let model = CredentialsModel(store: store)
        let entered = expectation(description: "read started")
        let release = DispatchSemaphore(value: 0)
        keychain.blockNextRead { entered.fulfill(); _ = release.wait(timeout: .now() + 10) }
        let task = Task { await model.refreshIdentityChecks() }
        defer { release.signal() }
        await fulfillment(of: [entered], timeout: 5)
        task.cancel(); release.signal(); await task.value
        XCTAssertEqual(model.identityStatus(for: certificate), .needsAttention("Checking the stored signing certificate…"))
        await model.refreshIdentityChecks()
        XCTAssertEqual(model.identityStatus(for: certificate), .ready)
    }
}

private final class ReadinessKeychain: IdentityKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: SecIdentity] = [:]
    private var nextRead: (@Sendable () -> Void)?
    func blockNextRead(_ action: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }; nextRead = action
    }
    func store(identity: SecIdentity, id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; items[id] = identity
    }
    func identity(id: UUID) throws -> SecIdentity {
        lock.lock(); let result = items[id]; let action = nextRead; nextRead = nil; lock.unlock()
        action?()
        guard let result else { throw CredentialError.notFound }
        return result
    }
    func remove(id: UUID) throws { lock.lock(); defer { lock.unlock() }; items[id] = nil }
}
