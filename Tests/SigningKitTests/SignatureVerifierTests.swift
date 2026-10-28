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

/// Exercises the complete verifier on hostile bytes without importing a signing identity.
final class SignatureVerifierMalformedTests: XCTestCase {
    private func verify(_ build: (MachO) -> Data) throws -> VerificationReport {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Hostile")
        let original = try MachO(Data(contentsOf: Fixtures.appDirectory.appendingPathComponent("SigningTestApp")))
        var probe = original; try probe.prepareForSignature(size: 0)
        let size = build(probe).count
        var image = original; try image.prepareForSignature(size: size)
        let signature = build(image)
        XCTAssertEqual(size, signature.count)
        try image.attach(signature: signature); try image.data.write(to: url)
        var report = VerificationReport()
        SignatureVerifier.verifyExecutable(url, label: "malformed", infoPlist: nil, codeResources: nil, into: &report)
        XCTAssertFalse(report.passed, "hostile signature must produce a failed report")
        XCTAssertEqual(try Data(contentsOf: url), image.data, "verification must never mutate input")
        return report
    }

    private func cd(_ image: MachO) -> Data {
        CodeDirectory(identifier: "test", teamIdentifier: nil, codeLimit: image.signedLength,
                      execSegmentBase: image.textFileOffset, execSegmentLimit: image.textFileSize,
                      execSegmentFlags: 1, specialHashes: [:]).build(image: image.data)
    }

    private func patch(_ bytes: inout Data, _ field: Int, _ value: UInt32) {
        bytes.replaceSubrange(field..<(field + 4), with: Blob.be32(value))
    }

    func testInvalidCodeDirectoryTablesProduceFailedReports() throws {
        for (field, value): (Int, UInt32) in [(16, .max), (16, 0), (24, .max), (24, 7), (28, .max), (32, .max)] {
            let report = try verify { image in
                var directory = self.cd(image); self.patch(&directory, field, value)
                return Blob.superBlob(magic: Blob.embeddedSignature, entries: [(0, directory)])
            }
            XCTAssertTrue(report.failures.contains { $0.name.contains("CodeDirectory geometry") }, "\(report.failures)")
        }
    }

    func testMalformedContainerIndicesAndBlobLengthsProduceFailedReports() throws {
        for (field, value): (Int, UInt32) in [(4, 0), (4, 12), (8, .max), (16, .max), (24, .max), (24, 0)] {
            let report = try verify { image in
                var blob = Blob.superBlob(magic: Blob.embeddedSignature, entries: [(0, self.cd(image))])
                self.patch(&blob, field, value)
                return blob
            }
            XCTAssertTrue(report.failures.contains { $0.name.contains("blob index") }, "\(report.failures)")
        }
    }

    func testTruncatedAndInconsistentCMSProduceFailedReports() throws {
        let bodies = [Data(), Data([0x30, 0]), Data([0x30, 0x84, 0xff, 0xff, 0xff, 0xff]),
                      Data([0x30, 0x80, 0x30, 0x80]), Data(repeating: 0xff, count: 32)]
        for body in bodies {
            let report = try verify { image in
                Blob.superBlob(magic: Blob.embeddedSignature, entries: [
                    (0, self.cd(image)), (0x10000, Blob.wrap(Blob.cmsWrapper, body))])
            }
            XCTAssertTrue(report.failures.contains { $0.name.contains("CMS signature present and parseable") }, "\(report.failures)")
        }
    }
}
