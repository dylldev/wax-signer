import CredentialKit
import Foundation
import XCTest
@testable import SigningKit

enum Fixtures {
    static var directory: URL {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        #else
        return Bundle(for: BundleToken.self).resourceURL!
        #endif
    }
    static var appDirectory: URL { directory.appendingPathComponent("TestApp.app") }
    static var ipa: URL { directory.appendingPathComponent("TestApp.ipa") }

    /// Apple's own DER entitlements blobs (slot 7) for the plists below, captured from `codesign`.
    static let appleDER1 = "fade7172000000d77081cc020101b081c6303c0c166170706c69636174696f6e2d6964656e7469666965720c22464958543132333435362e6465762e6c6f63616c7369676e65722e7465737461707030310c23636f6d2e6170706c652e646576656c6f7065722e7465616d2d6964656e7469666965720c0a4649585431323334353630130c0e6765742d7461736b2d616c6c6f770101ff303e0c166b6579636861696e2d6163636573732d67726f75707330240c22464958543132333435362e6465762e6c6f63616c7369676e65722e74657374617070"
    static let appleDER2 = "fade717200000056704c020101b04730170c036172723010b00830060c016b0c01760201070c017330090c04666c616701010030070c016e0202012c30180c047a657461b01030060c01620c017830060c01630101ff"

    static let entitlements1: [String: Any] = [
        "application-identifier": "FIXT123456.dev.localsigner.testapp",
        "com.apple.developer.team-identifier": "FIXT123456",
        "get-task-allow": true,
        "keychain-access-groups": ["FIXT123456.dev.localsigner.testapp"],
    ]
    static let entitlements2: [String: Any] = [
        "zeta": ["b": "x", "c": true],
        "arr": [["k": "v"], 7, "s"] as [Any],
        "n": 300,
        "flag": false,
    ]
}

private final class BundleToken {}

/// Copies the unsigned test app to a fresh directory.
func makeWorkingApp() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("signkit-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let app = dir.appendingPathComponent("SigningTestApp.app")
    try FileManager.default.copyItem(at: Fixtures.appDirectory, to: app)
    return app
}

struct TestCredentials {
    let loaded: LoadedIdentity
    let signer: SecurityFrameworkIdentity

    init(p12: Data = FixtureData.p12ValidLegacy) throws {
        loaded = try LoadedIdentity.load(p12: p12, password: FixtureData.password)
        signer = try SecurityFrameworkIdentity(identity: loaded.identity)
    }
}

func hex(_ s: String) -> Data {
    var d = Data(); var i = s.startIndex
    while i < s.endIndex { let j = s.index(i, offsetBy: 2); d.append(UInt8(s[i..<j], radix: 16)!); i = j }
    return d
}

/// Pulls the CodeDirectory and CMS blobs out of a signed Mach-O.
func signatureBlobs(ofExecutable url: URL) throws -> (codeDirectory: Data, cms: Data) {
    let exe = try Data(contentsOf: url)
    let sig = try XCTUnwrap(try MachO(exe).existingSignature, "no signature")
    let blob = exe[sig.offset..<(sig.offset + sig.size)]
    func be32(_ o: Int) -> Int { (0..<4).reduce(0) { $0 << 8 | Int(blob[blob.startIndex + o + $1]) } }
    var cd = Data(), cms = Data()
    for i in 0..<be32(8) {
        let type = be32(12 + 8 * i), off = be32(16 + 8 * i), len = be32(off + 4)
        let body = blob[(blob.startIndex + off)..<(blob.startIndex + off + len)]
        if type == 0 { cd = Data(body) }
        if type == 0x10000 { cms = Data(body.dropFirst(8)) }
    }
    return (cd, cms)
}
