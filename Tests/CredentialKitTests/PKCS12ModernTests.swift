import Security
import XCTest
@testable import CredentialKit

/// The modern-format fallback. Everything here is throwaway: keys generated for tests, public test passwords.
final class PKCS12ModernTests: XCTestCase {
    private func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
    private let smeg: [UInt8] = [0x00, 0x73, 0x00, 0x6d, 0x00, 0x65, 0x00, 0x67, 0x00, 0x00]   // BMPString "smeg" + NUL
    private let salt: [UInt8] = [0x0a, 0x58, 0xcf, 0x64, 0x53, 0x0d, 0x82, 0x3f]

    // Expected values were produced independently with `openssl kdf PKCS12KDF`.
    func testKeyDerivationMatchesOpenSSL() throws {
        func kdf(_ id: UInt8, _ n: Int, _ h: PKCS12Hash, _ it: Int) throws -> String {
            hex(try PKCS12KDF.derive(password: smeg, salt: salt, iterations: it, id: id, length: n, hash: h))
        }
        XCTAssertEqual(try kdf(1, 24, .sha1, 1), "8aaae6297b6cb04642ab5b077851284eb7128f1a2a7fbca3")
        XCTAssertEqual(try kdf(2, 8, .sha1, 1), "79993dfe048d3b76")
        XCTAssertEqual(try kdf(3, 20, .sha1, 1), "9ba6ef317b8cb9f4760ab2fa2e51c066f0dce645")
        XCTAssertEqual(try kdf(3, 32, .sha256, 1), "b26d0cad11e901ad0ba0ce08b18df8fc49d2eb271bf02a0cee1669e01251b18d")
        XCTAssertEqual(try kdf(3, 32, .sha256, 2048), "e4388cd88983083b1d1552867406cb3426e16cbcf4358c7bf5a97cdb2a11db46")
    }

    func testKeyDerivationRejectsInvalidIterationCounts() {
        for iterations in [0, PKCS12KDF.maxIterations + 1] {
            XCTAssertThrowsError(try PKCS12KDF.derive(password: smeg, salt: salt, iterations: iterations,
                                                      id: 1, length: 24, hash: .sha1))
        }
    }

    private func importCN(_ legacy: Data, _ pw: String) throws -> String {
        var items: CFArray?
        let st = SecPKCS12Import(legacy as CFData, [kSecImportExportPassphrase as String: pw] as CFDictionary, &items)
        XCTAssertEqual(st, errSecSuccess, "Apple's importer must accept the re-encoded file")
        let id = ((items as? [[String: Any]])?.first?[kSecImportItemIdentity as String]) as! SecIdentity
        var cert: SecCertificate?; SecIdentityCopyCertificate(id, &cert)
        return (SecCertificateCopySubjectSummary(cert!) as String?) ?? ""
    }

    func testReEncodesTheModernFixtureSoAppleAcceptsIt() throws {
        guard case .legacyEquivalent(let legacy) = ModernPKCS12.assess(FixtureData.p12ValidModern, password: FixtureData.password)
        else { return XCTFail("expected a re-encoded file") }
        XCTAssertTrue(try importCN(legacy, FixtureData.password).contains("Fixture Tester"))
    }

    func testReencodesModernPBES2FixtureWithEmptyPassword() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "empty-password-pbes2", withExtension: "p12", subdirectory: "Fixtures"))
        let fixture = try Data(contentsOf: url)
        guard case .legacyEquivalent(let legacy) = ModernPKCS12.assess(fixture, password: "") else {
            return XCTFail("expected the empty-password fixture to be re-encoded")
        }
        XCTAssertFalse(legacy.isEmpty)
    }

    // Shaped like a real-world file: OpenSSL 3 defaults and a MAC with no iteration field (the default of 1).
    private let macIter1 = Data(base64Encoded: "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")!

    func testReEncodesAFileWhoseMACHasNoIterationField() throws {
        guard case .legacyEquivalent(let legacy) = ModernPKCS12.assess(macIter1, password: "test-pass")
        else { return XCTFail("expected a re-encoded file") }
        XCTAssertEqual(try importCN(legacy, "test-pass"), "Wax Exp Test")
    }

    func testWrongPasswordIsDefinitive() {
        for pw in ["", "wrong", "test-pas", "test-pass "] {
            guard case .wrongPassword = ModernPKCS12.assess(macIter1, password: pw) else { return XCTFail("'\(pw)' must be rejected") }
        }
        guard case .wrongPassword = ModernPKCS12.assess(FixtureData.p12ValidModern, password: "nope") else { return XCTFail() }
    }

    func testGarbageIsLeftAlone() {
        for blob in [Data(repeating: 0xAB, count: 400), Data(), Data([0x30, 0x03, 0x02, 0x01, 0x03])] {
            guard case .unsupported = ModernPKCS12.assess(blob, password: FixtureData.password) else { return XCTFail("must not claim to handle this") }
        }
    }

    func testClassicFilesAreAlsoUnderstoodAndTheirWrongPasswordsCaught() {
        guard case .legacyEquivalent = ModernPKCS12.assess(FixtureData.p12ValidLegacy, password: FixtureData.password) else { return XCTFail() }
        guard case .wrongPassword = ModernPKCS12.assess(FixtureData.p12ValidLegacy, password: "nope") else { return XCTFail() }
    }

    func testTruncatedFileNeverCrashes() {
        for n in stride(from: 0, to: macIter1.count, by: 37) {
            _ = ModernPKCS12.assess(macIter1.prefix(n), password: "test-pass")
        }
    }

    // MARK: how the reader uses it

    func testReaderFallsBackWhenAppleRefusesButThePasswordIsRight() throws {
        var calls = 0
        let importer: PKCS12Reader.SystemImport = { data, pw in
            calls += 1
            if data == self.macIter1 { return (errSecDecode, nil) }            // pretend iOS cannot decode the original
            return PKCS12Reader.appleImport(data, pw)
        }
        let parsed = try PKCS12Reader.read(macIter1, password: "test-pass", systemImport: importer)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(parsed.summary.commonName, "Wax Exp Test")
    }

    func testReaderReportsWrongPasswordFromItsOwnCheckEvenWhenAppleSaysDecode() {
        let importer: PKCS12Reader.SystemImport = { _, _ in (errSecDecode, nil) }
        XCTAssertThrowsError(try PKCS12Reader.read(macIter1, password: "wrong", systemImport: importer)) {
            XCTAssertEqual($0 as? CredentialError, .incorrectPassword)
        }
    }

    func testReaderKeepsTheOriginalErrorForFilesItCannotHelpWith() {
        let importer: PKCS12Reader.SystemImport = { _, _ in (errSecDecode, nil) }
        XCTAssertThrowsError(try PKCS12Reader.read(Data(repeating: 1, count: 50), password: "x", systemImport: importer)) {
            XCTAssertEqual($0 as? CredentialError, .malformedPKCS12)
        }
    }
}
