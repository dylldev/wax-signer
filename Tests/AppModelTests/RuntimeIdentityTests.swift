import CredentialKit
import InstallKit
import Security
import XCTest
@testable import LocalIPASigner

@MainActor
final class RuntimeIdentityTests: XCTestCase {
    private func fixture() throws -> (URL, RuntimeKeychain, CredentialStore, CertificateInfo) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let keychain = RuntimeKeychain()
        let store = try CredentialStore(directory: directory, keychain: keychain)
        let cert = try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        _ = try store.importProfile(FixtureData.profileValidDER)
        return (directory, keychain, store, cert)
    }

    func testMetadataAloneCannotReportReady() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CredentialStore(directory: directory, keychain: RuntimeKeychain())
        let cert = try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        _ = try store.importProfile(FixtureData.profileValidDER)
        let status = IdentityReadiness.status(for: cert, profiles: store.profiles())
        guard case .needsAttention = status else { return XCTFail("Metadata alone reported \(status)") }
    }

    func testReadinessChecksActualIdentityInBackgroundAndRefreshesAfterItDisappears() async throws {
        let (directory, keychain, store, cert) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = CredentialsModel(store: store)
        XCTAssertNotEqual(model.identityStatus(for: cert), .ready)
        await model.refreshIdentityChecks()
        XCTAssertEqual(model.identityStatus(for: cert), .ready)
        try keychain.remove(id: cert.id)
        await model.refreshIdentityChecks()
        guard case .needsAttention(let detail) = model.identityStatus(for: cert) else { return XCTFail("Missing identity reported ready") }
        XCTAssertTrue(detail.contains("unavailable"))
    }

    func testOlderSuccessfulCheckCannotOverwriteNewMismatch() async throws {
        let (directory, keychain, store, cert) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = CredentialsModel(store: store)
        let entered = expectation(description: "old lookup captured identity")
        let release = DispatchSemaphore(value: 0)
        keychain.pauseNextRead(entered: entered, release: release)
        let old = Task { await model.refreshIdentityChecks() }
        await fulfillment(of: [entered], timeout: 5)
        let other = try LoadedIdentity.load(p12: FixtureData.p12SecondIdentity, password: FixtureData.password)
        try keychain.store(identity: other.identity, id: cert.id)
        await model.refreshIdentityChecks()
        release.signal()
        await old.value
        guard case .needsAttention(let detail) = model.identityStatus(for: cert) else { return XCTFail("Old success overwrote mismatch") }
        XCTAssertEqual(detail, CredentialError.identityMismatch.errorDescription)
        XCTAssertEqual(store.certificates(), [cert])
    }

    func testCancelledLookupCannotPublishReady() async throws {
        let (directory, keychain, store, cert) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = CredentialsModel(store: store)
        let entered = expectation(description: "lookup entered")
        let release = DispatchSemaphore(value: 0)
        keychain.pauseNextRead(entered: entered, release: release)
        let work = Task { await model.refreshIdentityChecks() }
        await fulfillment(of: [entered], timeout: 5)
        work.cancel(); release.signal(); await work.value
        XCTAssertNotEqual(model.identityStatus(for: cert), .ready)
    }
}

private final class RuntimeKeychain: IdentityKeychain, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [UUID: SecIdentity] = [:]
    private var pause: (XCTestExpectation, DispatchSemaphore)?
    func pauseNextRead(entered: XCTestExpectation, release: DispatchSemaphore) {
        lock.lock(); defer { lock.unlock() }; pause = (entered, release)
    }
    func store(identity: SecIdentity, id: UUID) throws {
        lock.lock(); defer { lock.unlock() }; items[id] = identity
    }
    func identity(id: UUID) throws -> SecIdentity {
        XCTAssertFalse(Thread.isMainThread, "Keychain readiness checks must not block rendering")
        lock.lock()
        let value = items[id]; let blocked = pause; pause = nil
        lock.unlock()
        blocked?.0.fulfill()
        if let blocked { _ = blocked.1.wait(timeout: .now() + 10) }
        guard let value else { throw CredentialError.notFound }; return value
    }
    func remove(id: UUID) throws { lock.lock(); defer { lock.unlock() }; items[id] = nil }
}
