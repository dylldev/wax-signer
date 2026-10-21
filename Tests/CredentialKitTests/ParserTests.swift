import XCTest
@testable import CredentialKit

final class ParserTests: XCTestCase {
    private let now = Date()

    // MARK: ASN.1 / X.509

    func testParsesIndefiniteLengthSequence() throws {
        // SEQUENCE (indefinite) { INTEGER 5 } EOC
        let node = try ASN1.parse(Data([0x30, 0x80, 0x02, 0x01, 0x05, 0x00, 0x00]))
        let kids = try node.children()
        XCTAssertEqual(kids.count, 1)
        XCTAssertEqual(kids[0].content, [5])
    }

    func testRejectsTruncatedLength() {
        XCTAssertThrowsError(try ASN1.parse(Data([0x30, 0x05, 0x02, 0x01])))
    }

    func testRejectsExcessiveNesting() {
        var bytes: [UInt8] = [0x05, 0x00]
        for _ in 0..<40 { bytes = [0x30, UInt8(bytes.count)] + bytes } // each wrapper adds 2 bytes; stays < 128
        // Deep tree must fail on traversal, not crash.
        func walk(_ n: ASN1) throws { for c in try n.children() where c.isConstructed { try walk(c) } }
        XCTAssertThrowsError(try walk(ASN1.parse(Data(bytes))))
    }

    func testRejectsHugeDeclaredLength() {
        XCTAssertThrowsError(try ASN1.parse(Data([0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])))
    }

    func testX509FixtureFields() throws {
        let s = try X509Summary.parse(der: FixtureData.certADER)
        XCTAssertEqual(s.commonName, "Apple Development: Fixture Tester (AAAA111111)")
        XCTAssertEqual(s.organizationalUnit, FixtureData.teamID)
        XCTAssertEqual(s.organization, "Fixture Team FIXT123456")
        XCTAssertEqual(s.country, "US")
        XCTAssertFalse(s.serial.isEmpty)
        XCTAssertLessThan(s.notBefore, now)
        XCTAssertGreaterThan(s.notAfter, now.addingTimeInterval(86400 * 365 * 9))
    }

    func testX509RejectsGarbage() {
        XCTAssertThrowsError(try X509Summary.parse(der: Data([1, 2, 3])))
    }

    // MARK: Profiles

    private func read(_ data: Data) throws -> ProfileInfo {
        try ProfileReader.read(data, importedAt: now, now: now)
    }

    private func assertProfileError(_ data: Data, _ expected: CredentialError,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try read(data), file: file, line: line) {
            XCTAssertEqual($0 as? CredentialError, expected, file: file, line: line)
        }
    }

    func testReadsBERIndefiniteProfile() throws {
        let p = try read(FixtureData.profileValidBER)
        XCTAssertEqual(p.name, "Fixture Dev Profile")
        XCTAssertEqual(p.teamID, FixtureData.teamID)
        XCTAssertEqual(p.applicationIdentifier, "FIXT123456.com.example.fixture")
        XCTAssertEqual(p.bundleIdentifierPattern, "com.example.fixture")
        XCTAssertEqual(p.kind, .development)
        XCTAssertEqual(p.provisionedDeviceCount, 2)
        XCTAssertTrue(p.getTaskAllow)
        XCTAssertEqual(p.certificateSHA1s, [X509Summary.sha1Hex(FixtureData.certADER)])
        XCTAssertEqual(p.id, UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        XCTAssertEqual(p.platforms, ["iOS"])
    }

    func testReadsDERProfile() throws {
        XCTAssertEqual(try read(FixtureData.profileValidDER).kind, .development)
    }

    func testProfileKinds() throws {
        XCTAssertEqual(try read(FixtureData.profileAdHoc).kind, .adHoc)
        let ent = try read(FixtureData.profileEnterprise)
        XCTAssertEqual(ent.kind, .enterprise)
        XCTAssertTrue(ent.provisionsAllDevices)
        XCTAssertNil(ent.provisionedDeviceCount)
        XCTAssertEqual(try read(FixtureData.profileAppStore).kind, .appStore)
    }

    func testRejectsExpiredProfile() throws {
        XCTAssertThrowsError(try read(FixtureData.profileExpired)) {
            guard case .profileExpired = $0 as? CredentialError else { return XCTFail("\($0)") }
        }
    }

    func testRejectsNonCMS() {
        assertProfileError(FixtureData.profileNotCMS, .profileNotCMS)
        assertProfileError(FixtureData.profileUnsignedPlist, .profileNotCMS)
        assertProfileError(Data(), .profileNotCMS)
        assertProfileError(FixtureData.profileValidBER.prefix(500), .profileNotCMS)
    }

    func testRejectsCMSWithoutPlist() {
        assertProfileError(FixtureData.profileCMSNotPlist, .profileInvalidPlist)
    }

    func testRejectsMissingRequiredKey() {
        assertProfileError(FixtureData.profileMissingUUID, .profileMissingKey("UUID"))
    }

    func testRejectsOversizedProfile() {
        assertProfileError(Data(count: ProfileReader.maxBytes + 1), .fileTooLarge)
    }

    // MARK: PKCS#12

    private func importP12(_ data: Data, _ pw: String = FixtureData.password) throws -> ParsedIdentity {
        try PKCS12Reader.read(data, password: pw)
    }

    private func assertP12Error(_ data: Data, pw: String = FixtureData.password, _ expected: CredentialError,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try importP12(data, pw), file: file, line: line) {
            XCTAssertEqual($0 as? CredentialError, expected, file: file, line: line)
        }
    }

    func testReadsModernAndLegacyEncryptedP12() throws {
        let a = try importP12(FixtureData.p12ValidModern)
        let b = try importP12(FixtureData.p12ValidLegacy)
        XCTAssertEqual(a.certificateDER, FixtureData.certADER)
        XCTAssertEqual(b.certificateDER, FixtureData.certADER)
    }

    func testIncorrectPassword() {
        assertP12Error(FixtureData.p12ValidModern, pw: "not-the-password", .incorrectPassword)
        assertP12Error(FixtureData.p12ValidLegacy, pw: "", .incorrectPassword)
    }

    func testMalformedP12() {
        assertP12Error(FixtureData.p12Malformed, .malformedPKCS12)
        assertP12Error(FixtureData.p12Truncated, .malformedPKCS12)
        assertP12Error(Data(), .malformedPKCS12)
    }

    func testCertificateOnlyP12HasNoPrivateKey() {
        assertP12Error(FixtureData.p12CertOnly, .noPrivateKey)
    }

    func testOversizedP12() {
        assertP12Error(Data(count: PKCS12Reader.maxBytes + 1), .fileTooLarge)
    }

    /// Opt-in: PROFILE_PATH=/path/to.mobileprovision swift test --filter testRealProfile
    /// Writes only non-identifying summary fields (no UDIDs, no names) to REAL_PROFILE_OUT.
    func testRealProfile() throws {
        guard let path = ProcessInfo.processInfo.environment["PROFILE_PATH"] else { throw XCTSkip("PROFILE_PATH not set") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        var line: String
        do {
            let p = try read(data)
            line = "parsed kind=\(p.kind.rawValue) devices=\(p.provisionedDeviceCount.map(String.init) ?? "nil") "
                + "allDevices=\(p.provisionsAllDevices) taskAllow=\(p.getTaskAllow) certs=\(p.certificateSHA1s.count) "
                + "platforms=\(p.platforms)"
        } catch CredentialError.profileExpired {
            line = "valid structure, expired"
        }
        if let out = ProcessInfo.processInfo.environment["REAL_PROFILE_OUT"] {
            try line.write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    // MARK: CMS / profile signature

    func testFixtureProfileSignatureIsIntactButNotAppleTrusted() throws {
        for data in [FixtureData.profileValidBER, FixtureData.profileValidDER] {
            let cms = try CMSSignedData.parse(data)
            XCTAssertEqual(cms.signers.count, 1)
            XCTAssertEqual(cms.checkSignature(), .valid)
            guard case .signatureValidButUntrusted(_, let chain) = ProfileTrust.evaluate(data) else {
                return XCTFail("self-signed profile must not be reported as Apple-verified")
            }
            XCTAssertEqual(chain.count, 1)
        }
    }

    func testStructurallyValidProfileIsNotTreatedAsTrusted() throws {
        // Parses and imports as a profile, yet is not Apple-signed.
        XCTAssertNoThrow(try read(FixtureData.profileValidBER))
        if case .appleChainVerified = ProfileTrust.evaluate(FixtureData.profileValidBER) { XCTFail("must not be trusted") }
    }

    func testTamperedProfileContentFailsSignature() throws {
        var bytes = [UInt8](FixtureData.profileValidDER)
        // flip a byte inside the embedded plist (DER, so the content is contiguous): find "Fixture Dev Profile"
        let needle = Array("Fixture Dev Profile".utf8)
        let at = try XCTUnwrap(bytes.indices.first { i in i + needle.count <= bytes.count && Array(bytes[i..<(i + needle.count)]) == needle })
        bytes[at] ^= 0x01
        guard case .invalid(let why) = ProfileTrust.evaluate(Data(bytes)) else { return XCTFail("tampered profile must be invalid") }
        XCTAssertTrue(why.contains("digest"), why)
    }

    func testGarbageIsInvalidNotTrusted() {
        guard case .invalid = ProfileTrust.evaluate(FixtureData.profileNotCMS) else { return XCTFail() }
        guard case .invalid = ProfileTrust.evaluate(Data()) else { return XCTFail() }
    }

    /// Opt-in, real Apple-issued profiles: PROFILE_PATH=... REAL_PROFILE_OUT=...
    func testRealProfileSignatureStatus() throws {
        guard let path = ProcessInfo.processInfo.environment["PROFILE_PATH"] else { throw XCTSkip("PROFILE_PATH not set") }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let atSigning = ProfileTrust.evaluate(data)
        let atNow = ProfileTrust.evaluate(data, usingSigningTime: false)
        if let out = ProcessInfo.processInfo.environment["REAL_PROFILE_OUT"] {
            try "signingTime: \(atSigning)\nnow: \(atNow)".write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    func testMissingKeychainEntitlementIsExplainedNotJustANumber() {
        let text = CredentialError.keychain(operation: "store key", status: errSecMissingEntitlement).errorDescription ?? ""
        XCTAssertTrue(text.contains("signed without keychain access"), text)
        XCTAssertTrue(text.contains("-34018"), text)
        let other = CredentialError.keychain(operation: "store key", status: errSecInteractionNotAllowed).errorDescription ?? ""
        XCTAssertFalse(other.contains("signed without keychain access"), other)
    }
}
