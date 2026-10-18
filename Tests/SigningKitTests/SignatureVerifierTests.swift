import CredentialKit
import XCTest
@testable import SigningKit

/// The self-check must agree with Apple's `codesign` on good and tampered bundles.
final class SignatureVerifierTests: XCTestCase {
    private func signedApp() throws -> URL {
        let app = try makeWorkingApp()
        let creds = try TestCredentials()
        _ = try BundleSigner.sign(appDirectory: app, identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                                  profile: try ProvisioningProfile.parse(FixtureData.profileWildcardAll))
        return app
    }

    func testAcceptsAFreshlySignedBundle() throws {
        let report = SignatureVerifier.verifyBundle(at: try signedApp())
        XCTAssertTrue(report.passed, "\(report.failures)")
        XCTAssertGreaterThan(report.checks.count, 30, "all nested bundles are covered")
    }

    func testRejectsAnUnsignedBundle() throws {
        let report = SignatureVerifier.verifyBundle(at: try makeWorkingApp())
        XCTAssertFalse(report.passed)
    }

    func testDetectsEachKindOfTampering() throws {
        // modified resource
        var app = try signedApp()
        try Data("changed".utf8).write(to: app.appendingPathComponent("note.txt"))
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).failures.contains { $0.name.contains("resource seal") })

        // added file
        app = try signedApp()
        try Data("x".utf8).write(to: app.appendingPathComponent("extra.txt"))
        XCTAssertFalse(SignatureVerifier.verifyBundle(at: app).passed)

        // removed file
        app = try signedApp()
        try FileManager.default.removeItem(at: app.appendingPathComponent("note.txt"))
        XCTAssertFalse(SignatureVerifier.verifyBundle(at: app).passed)

        // modified executable page
        app = try signedApp()
        var exe = try Data(contentsOf: app.appendingPathComponent("SigningTestApp"))
        exe[200] ^= 0xFF
        try exe.write(to: app.appendingPathComponent("SigningTestApp"))
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).failures.contains { $0.name.contains("page hashes") })

        // modified nested framework
        app = try signedApp()
        let fw = app.appendingPathComponent("Frameworks/TestKit.framework/TestKit")
        var fbytes = try Data(contentsOf: fw)
        fbytes[300] ^= 0xFF
        try fbytes.write(to: fw)
        XCTAssertTrue(SignatureVerifier.verifyBundle(at: app).failures.contains { $0.name.contains("TestKit") })

        // modified Info.plist after signing
        app = try signedApp()
        var plist = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        plist.append(Data("\n".utf8))
        try plist.write(to: app.appendingPathComponent("Info.plist"))
        XCTAssertFalse(SignatureVerifier.verifyBundle(at: app).passed)
    }

    func testDetectsACorruptedCMSSignature() throws {
        let app = try signedApp()
        let exeURL = app.appendingPathComponent("SigningTestApp")
        var exe = try Data(contentsOf: exeURL)
        exe[exe.count - 5] ^= 0xFF          // inside the RSA signature bytes at the end of the CMS blob
        try exe.write(to: exeURL)
        let report = SignatureVerifier.verifyBundle(at: app)
        XCTAssertTrue(report.failures.contains { $0.name.contains("CMS signature is valid") }, "\(report.failures)")
    }

    #if os(macOS)
    func testAgreesWithCodesignOnEveryScenario() throws {
        let scenarios: [(String, (URL) throws -> Void)] = [
            ("untouched", { _ in }),
            ("resource", { try Data("c".utf8).write(to: $0.appendingPathComponent("note.txt")) }),
            ("added", { try Data("c".utf8).write(to: $0.appendingPathComponent("added.txt")) }),
            ("exe", { var d = try Data(contentsOf: $0.appendingPathComponent("SigningTestApp")); d[100] ^= 1
                       try d.write(to: $0.appendingPathComponent("SigningTestApp")) }),
        ]
        for (name, mutate) in scenarios {
            let app = try signedApp()
            try mutate(app)
            let apple = Process.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]).status == 0
            let ours = SignatureVerifier.verifyBundle(at: app).passed
            XCTAssertEqual(ours, apple, "scenario \(name): ours=\(ours) codesign=\(apple)")
        }
    }
    #endif
}
