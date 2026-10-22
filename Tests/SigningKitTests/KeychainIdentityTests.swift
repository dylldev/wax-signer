import CredentialKit
import CryptoKit
import Security
import XCTest
@testable import SigningKit

/// Answers: can a Keychain-resident identity supply the signer's operations without the app
/// exporting private-key material? Runs for real in the app-hosted iOS simulator bundle; the
/// unsigned macOS test host has no keychain entitlement and skips.
final class KeychainIdentityTests: XCTestCase {
    private var keychain: SystemIdentityKeychain!
    private var id = UUID()

    override func setUp() {
        keychain = SystemIdentityKeychain(service: "dev.localsigner.signtests.\(UUID().uuidString)")
    }

    override func tearDown() {
        try? keychain.remove(id: id)
    }

    private func storedIdentity() throws -> SecIdentity {
        let loaded = try LoadedIdentity.load(p12: FixtureData.p12ValidLegacy, password: FixtureData.password)
        do { try keychain.store(identity: loaded.identity, id: id) }
        catch CredentialError.keychain(_, let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain unavailable in this test host (errSecMissingEntitlement)")
        }
        return try keychain.identity(id: id)
    }

    func testSignAppUsingKeychainResidentKey() throws {
        let identity = try storedIdentity()
        let signer = try SecurityFrameworkIdentity(identity: identity)

        let app = try makeWorkingApp()
        let profile = try ProvisioningProfile.parse(FixtureData.profileWildcardAll)
        let result = try BundleSigner.sign(appDirectory: app, identity: signer, certificateTeamID: FixtureData.teamID,
                                           profile: profile)
        XCTAssertEqual(result.items.count, 3)

        // Internal consistency check (NOT Apple's verification, which needs macOS `codesign`):
        // the CMS must be a valid signature, by the Keychain key's certificate, over the CodeDirectory.
        for rel in ["SigningTestApp", "Frameworks/TestKit.framework/TestKit", "PlugIns/TestExt.appex/TestExt"] {
            let (cd, cmsData) = try signatureBlobs(ofExecutable: app.appendingPathComponent(rel))
            let cms = try CMSSignedData.parse(cmsData)
            XCTAssertEqual(cms.signers.count, 1, rel)
            XCTAssertEqual(cms.checkSignature(content: cd), .valid, rel)
            XCTAssertEqual(cms.signers[0].messageDigest, Data(SHA256.hash(data: cd)), rel)
            XCTAssertEqual(cms.signerCertificateDER(cms.signers[0]), signer.certificateChainDER[0], rel)
        }
        let appCD = try signatureBlobs(ofExecutable: app.appendingPathComponent("SigningTestApp")).codeDirectory
        XCTAssertEqual(result.items.last?.cdHash, SHA256.hash(data: appCD).prefix(20).map { String(format: "%02x", $0) }.joined())
    }

    func testKeyCustodyFindings() throws {
        let identity = try storedIdentity()
        var key: SecKey?
        XCTAssertEqual(SecIdentityCopyPrivateKey(identity, &key), errSecSuccess)
        let privateKey = try XCTUnwrap(key)

        // Signing needs no export:
        var error: Unmanaged<CFError>?
        XCTAssertNotNil(SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, Data("m".utf8) as CFData, &error))

        // What the OS would let any code in this app do with the same key:
        let attrs = SecKeyCopyAttributes(privateKey) as? [String: Any] ?? [:]
        let extractable = attrs[kSecAttrIsExtractable as String]
        let token = attrs[kSecAttrTokenID as String]
        var exportError: Unmanaged<CFError>?
        let exported = SecKeyCopyExternalRepresentation(privateKey, &exportError)
        let line = "platform=\(platformName) isExtractable=\(String(describing: extractable)) tokenID=\(String(describing: token)) "
            + "exportable=\(exported != nil) keyBits=\(attrs[kSecAttrKeySizeInBits as String] ?? "?")"
        try? line.write(toFile: "/private/tmp/key-custody-\(platformName).txt", atomically: true, encoding: .utf8)
        add(XCTAttachment(string: line))
        print("KEY-CUSTODY \(line)")
    }

    private var platformName: String {
        #if os(iOS)
        "ios-simulator"
        #else
        "macos"
        #endif
    }
}
