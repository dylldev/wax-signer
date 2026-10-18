import XCTest
@testable import CredentialKit

final class CredentialStoreTests: XCTestCase {
    private var dir: URL!
    private var keychain: FakeKeychain!

    override func setUpWithError() throws {
        dir = try makeTempDirectory()
        keychain = FakeKeychain()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeStore(now: @escaping @Sendable () -> Date = { Date() }) throws -> CredentialStore {
        try CredentialStore(directory: dir, keychain: keychain, now: now)
    }

    // MARK: Several identities in one .p12

    /// A system import that answers as if one .p12 held both fixture identities.
    private func twoIdentityImport() -> PKCS12Reader.SystemImport {
        let (sa, ia) = PKCS12Reader.appleImport(FixtureData.p12ValidLegacy, FixtureData.password)
        let (sb, ib) = PKCS12Reader.appleImport(FixtureData.p12SecondIdentity, FixtureData.password)
        precondition(sa == errSecSuccess && sb == errSecSuccess)
        return { _, _ in (errSecSuccess, (ia ?? []) + (ib ?? [])) }
    }

    func testReadAllReturnsEveryIdentityInTheFile() throws {
        let all = try PKCS12Reader.readAll(Data([0]), password: "x", systemImport: twoIdentityImport())
        XCTAssertEqual(all.count, 2)
        XCTAssertNotEqual(all[0].certificateDER, all[1].certificateDER)
    }

    func testImportCertificatesImportsBothIdentities() throws {
        let store = try makeStore()
        let infos = try store.importCertificates(p12: Data([0]), password: "x", systemImport: twoIdentityImport())
        XCTAssertEqual(infos.count, 2)
        XCTAssertEqual(Set(store.certificates().map(\.sha1Fingerprint)).count, 2)
        XCTAssertEqual(keychain.count, 2)
    }

    func testIdentitiesAlreadyImportedAreSkippedAndTheNewOneIsKept() throws {
        let store = try makeStore()
        try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        let infos = try store.importCertificates(p12: Data([0]), password: "x", systemImport: twoIdentityImport())
        XCTAssertEqual(infos.count, 1)
        XCTAssertEqual(store.certificates().count, 2)
    }

    func testImportingTheSameFileAgainSaysAlreadyImported() throws {
        let store = try makeStore()
        _ = try store.importCertificates(p12: Data([0]), password: "x", systemImport: twoIdentityImport())
        XCTAssertThrowsError(try store.importCertificates(p12: Data([0]), password: "x", systemImport: twoIdentityImport())) {
            XCTAssertEqual($0 as? CredentialError, .alreadyImported)
        }
    }

    func testSingleIdentityFileBehavesAsBefore() throws {
        let store = try makeStore()
        let infos = try store.importCertificates(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        XCTAssertEqual(infos.map(\.commonName), ["Apple Development: Fixture Tester (AAAA111111)"])
    }

    // MARK: Certificates

    func testImportCertificateStoresMetadataAndKey() throws {
        let store = try makeStore()
        let info = try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        XCTAssertEqual(info.commonName, "Apple Development: Fixture Tester (AAAA111111)")
        XCTAssertEqual(info.teamID, FixtureData.teamID)
        XCTAssertEqual(info.sha1Fingerprint, X509Summary.sha1Hex(FixtureData.certADER))
        XCTAssertEqual(info.validity(at: Date()), .valid)
        XCTAssertEqual(store.certificates(), [info])
        XCTAssertEqual(keychain.count, 1)

        // A signer can obtain a usable private key.
        var key: SecKey?
        XCTAssertEqual(SecIdentityCopyPrivateKey(try store.identity(for: info.id), &key), errSecSuccess)
        XCTAssertTrue(SecKeyIsAlgorithmSupported(try XCTUnwrap(key), .sign, .rsaSignatureMessagePKCS1v15SHA256))
    }

    func testFailedImportsWriteNothing() throws {
        let store = try makeStore()
        let cases: [(Data, String, CredentialError)] = [
            (FixtureData.p12ValidModern, "wrong", .incorrectPassword),
            (FixtureData.p12Malformed, FixtureData.password, .malformedPKCS12),
            (FixtureData.p12CertOnly, FixtureData.password, .noPrivateKey),
        ]
        for (data, pw, expected) in cases {
            XCTAssertThrowsError(try store.importCertificate(p12: data, password: pw)) {
                XCTAssertEqual($0 as? CredentialError, expected)
            }
        }
        XCTAssertEqual(keychain.storeCalls, 0)
        XCTAssertTrue(store.certificates().isEmpty)
    }

    func testRejectsExpiredAndNotYetValidCertificates() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.importCertificate(p12: FixtureData.p12Expired, password: FixtureData.password)) {
            guard case .certificateExpired = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
        XCTAssertThrowsError(try store.importCertificate(p12: FixtureData.p12NotYetValid, password: FixtureData.password)) {
            guard case .certificateNotYetValid = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(keychain.storeCalls, 0)
    }

    func testDuplicateCertificateIsRejectedWithoutSecondKeychainItem() throws {
        let store = try makeStore()
        try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        XCTAssertThrowsError(try store.importCertificate(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)) {
            XCTAssertEqual($0 as? CredentialError, .alreadyImported)
        }
        XCTAssertEqual(keychain.count, 1)
        XCTAssertEqual(store.certificates().count, 1)
    }

    func testKeychainStoreFailureLeavesNoMetadata() throws {
        let store = try makeStore()
        keychain.failStore = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)) {
            XCTAssertEqual($0 as? CredentialError, .keychain(operation: "store key", status: errSecInteractionNotAllowed))
        }
        XCTAssertTrue(store.certificates().isEmpty)
        XCTAssertEqual(keychain.count, 0)
        XCTAssertTrue(try makeStore().certificates().isEmpty)
    }

    func testIndexWriteFailureRollsBackKeychain() throws {
        let store = try makeStore()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        XCTAssertThrowsError(try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)) {
            guard case .storage = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(keychain.count, 0, "key must not be orphaned in the keychain")
        XCTAssertTrue(store.certificates().isEmpty)
    }

    func testDeleteCertificateRemovesKeychainItemsAndMetadata() throws {
        let store = try makeStore()
        let info = try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        try store.deleteCertificate(id: info.id)
        XCTAssertTrue(store.certificates().isEmpty)
        XCTAssertEqual(keychain.count, 0)
        XCTAssertThrowsError(try store.identity(for: info.id)) { XCTAssertEqual($0 as? CredentialError, .notFound) }
        XCTAssertThrowsError(try store.deleteCertificate(id: info.id)) { XCTAssertEqual($0 as? CredentialError, .notFound) }
    }

    func testDeleteKeepsMetadataWhenKeychainRemovalFails() throws {
        let store = try makeStore()
        let info = try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        keychain.failRemove = errSecInteractionNotAllowed
        XCTAssertThrowsError(try store.deleteCertificate(id: info.id))
        XCTAssertEqual(store.certificates(), [info], "entry stays so the user can retry")
        keychain.failRemove = nil
        try store.deleteCertificate(id: info.id)
        XCTAssertTrue(store.certificates().isEmpty)
    }

    func testDeleteIndexWriteFailureLeavesKeychainIdentityAndMetadataIntact() throws {
        let store = try makeStore()
        let info = try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        let indexURL = dir.appendingPathComponent("index.json")
        let indexData = try Data(contentsOf: indexURL)
        try FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: false)
        defer {
            try? FileManager.default.removeItem(at: indexURL)
            try? indexData.write(to: indexURL)
        }

        XCTAssertThrowsError(try store.deleteCertificate(id: info.id)) {
            guard case .storage = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(store.certificates(), [info])
        XCTAssertEqual(keychain.count, 1)
    }

    // MARK: Profiles

    func testImportProfileKeepsOriginalBytes() throws {
        let store = try makeStore()
        let info = try store.importProfile(FixtureData.profileValidBER)
        XCTAssertEqual(store.profiles(), [info])
        XCTAssertEqual(try store.profileData(for: info.id), FixtureData.profileValidBER)
    }

    func testInvalidProfilesAreNotStored() throws {
        let store = try makeStore()
        for bad in [FixtureData.profileNotCMS, FixtureData.profileMissingUUID, FixtureData.profileExpired] {
            XCTAssertThrowsError(try store.importProfile(bad))
        }
        XCTAssertTrue(store.profiles().isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("profiles").path)
        XCTAssertTrue(files.isEmpty)
    }

    func testReimportingSameProfileReplacesIt() throws {
        let store = try makeStore()
        try store.importProfile(FixtureData.profileValidBER)
        try store.importProfile(FixtureData.profileValidBER)
        XCTAssertEqual(store.profiles().count, 1)
    }

    func testDeleteProfileRemovesFileAndMetadata() throws {
        let store = try makeStore()
        let info = try store.importProfile(FixtureData.profileValidBER)
        try store.deleteProfile(id: info.id)
        XCTAssertTrue(store.profiles().isEmpty)
        XCTAssertThrowsError(try store.profileData(for: info.id))
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("profiles").path)
        XCTAssertTrue(files.isEmpty)
    }

    // MARK: Compatibility

    private func report(cert: Data, profile: Data) throws -> CompatibilityReport {
        let store = try makeStore()
        let c = try store.importCertificate(p12: cert, password: FixtureData.password)
        let p = try store.importProfile(profile)
        return try store.compatibility(certificateID: c.id, profileID: p.id)
    }

    func testMatchingPairHasNoFailuresAndStillDisclaimsDeviceEligibility() throws {
        let r = try report(cert: FixtureData.p12ValidModern, profile: FixtureData.profileValidBER)
        XCTAssertFalse(r.hasFailures)
        XCTAssertEqual(r.checks.first { $0.title == "Device eligibility" }?.status, .unknown)
        XCTAssertTrue(CompatibilityReport.disclaimer.contains("does not guarantee"))
    }

    func testCertificateNotListedInProfileFails() throws {
        let r = try report(cert: FixtureData.p12ValidModern, profile: FixtureData.profileListsOtherCert)
        XCTAssertEqual(r.checks.first { $0.title == "Profile includes this certificate" }?.status, .fail)
        XCTAssertTrue(r.hasFailures)
    }

    func testTeamMismatchFails() throws {
        let r = try report(cert: FixtureData.p12ValidModern, profile: FixtureData.profileTeamMismatch)
        XCTAssertEqual(r.checks.first { $0.title == "Team ID matches" }?.status, .fail)
    }

    func testOtherTeamCertificateAgainstProfileFailsBothChecks() throws {
        let r = try report(cert: FixtureData.p12OtherTeam, profile: FixtureData.profileValidBER)
        XCTAssertEqual(r.checks.first { $0.title == "Team ID matches" }?.status, .fail)
        XCTAssertEqual(r.checks.first { $0.title == "Profile includes this certificate" }?.status, .fail)
    }

    func testAppStoreProfileIsFlaggedNotInstallable() throws {
        let r = try report(cert: FixtureData.p12ValidModern, profile: FixtureData.profileAppStore)
        XCTAssertEqual(r.checks.first { $0.title == "Device eligibility" }?.status, .fail)
    }

    func testExpiryIsEvaluatedAgainstTheClock() throws {
        let store = try makeStore()
        let c = try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        let p = try store.importProfile(FixtureData.profileValidBER)
        let future = Date().addingTimeInterval(86400 * 365 * 11)
        let r = CompatibilityReport.evaluate(certificate: c, profile: p, now: future)
        XCTAssertEqual(r.checks.first { $0.title == "Certificate currently valid" }?.status, .fail)
        XCTAssertEqual(r.checks.first { $0.title == "Profile not expired" }?.status, .fail)
    }

    func testCompatibilityForUnknownIDsThrows() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.compatibility(certificateID: UUID(), profileID: UUID())) {
            XCTAssertEqual($0 as? CredentialError, .notFound)
        }
    }

    // MARK: Persistence and secrecy

    func testStateSurvivesRestart() throws {
        let first = try makeStore()
        let c = try first.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        let p = try first.importProfile(FixtureData.profileValidBER)
        let second = try makeStore()
        XCTAssertEqual(second.certificates(), [c])
        XCTAssertEqual(second.profiles(), [p])
    }

    func testCorruptIndexIsReportedNotReset() throws {
        try Data("{not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        XCTAssertThrowsError(try makeStore()) {
            guard case .storage = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("index.json"), encoding: .utf8), "{not json")
    }

    func testNoSecretsOnDiskOrInErrors() throws {
        let store = try makeStore()
        let typed = "typed-secret-\(UUID().uuidString)"
        var errorText = ""
        do { _ = try store.importCertificate(p12: FixtureData.p12ValidModern, password: typed) }
        catch { errorText = "\(error) \(error.localizedDescription) \(String(reflecting: error))" }
        XCTAssertFalse(errorText.isEmpty)
        XCTAssertFalse(errorText.contains(typed))

        try store.importCertificate(p12: FixtureData.p12ValidModern, password: FixtureData.password)
        try store.importProfile(FixtureData.profileValidBER)

        let p12Window = FixtureData.p12ValidModern.subdata(in: 100..<164)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in enumerator where !url.hasDirectoryPath {
            let bytes = try Data(contentsOf: url)
            scanned += 1
            XCTAssertNil(bytes.range(of: Data(FixtureData.password.utf8)), "password found in \(url.lastPathComponent)")
            XCTAssertNil(bytes.range(of: p12Window), "p12 bytes found in \(url.lastPathComponent)")
        }
        XCTAssertEqual(scanned, 2) // index.json + one profile
    }

    func testStorageDirectoryIsExcludedFromBackup() throws {
        _ = try makeStore()
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }
}
