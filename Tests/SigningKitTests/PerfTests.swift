import CredentialKit
import XCTest
@testable import SigningKit

/// Stage timings for a real IPA. Skipped unless WAX_PERF_IPA points at one. Uses fixture credentials only.
final class PerfTests: XCTestCase {
    func testStageTimings() throws {
        guard let path = ProcessInfo.processInfo.environment["WAX_PERF_IPA"] else { throw XCTSkip("set WAX_PERF_IPA") }
        let creds = try TestCredentials()
        var options = SigningOptions()
        options.keepBundleIdentifier = true
        var last = Date(), lastLabel = "start"
        var marks: [(String, Double)] = []
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("perf-out.ipa")
        let t0 = Date()
        _ = try IPASigner.sign(ipa: URL(fileURLWithPath: path), identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                               profiles: ProfileSet(pool: [try ProvisioningProfile.parse(FixtureData.profileWildcardAll)]),
                               options: options, output: out, workDirectory: FileManager.default.temporaryDirectory) { p in
            let label = p.message
            let now = Date(); marks.append((lastLabel, now.timeIntervalSince(last))); last = now; lastLabel = label
        }
        marks.append((lastLabel, Date().timeIntervalSince(last)))
        let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        print("PERF total \(String(format: "%.1f", Date().timeIntervalSince(t0)))s, output \(size / 1_000_000) MB")
        var sums: [String: Double] = [:], order: [String] = []
        for (l, s) in marks { if sums[l] == nil { order.append(l) }; sums[l, default: 0] += s }
        for l in order { print("PERF \(String(format: "%6.1f", sums[l]!))s  \(l)") }
        try? FileManager.default.removeItem(at: out)
    }
}
