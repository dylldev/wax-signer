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
        let recorder = PerformanceRecorder()
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("wax-perf-\(UUID())")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let out = scratch.appendingPathComponent("output.ipa")
        _ = try IPASigner.sign(ipa: URL(fileURLWithPath: path), identity: creds.signer, certificateTeamID: creds.loaded.teamID,
                               profiles: ProfileSet(pool: [try ProvisioningProfile.parse(FixtureData.profileWildcardAll)]),
                               options: options, output: out, workDirectory: scratch,
                               compressChangedFiles: ProcessInfo.processInfo.environment["WAX_PERF_STORE"] == nil) { p in
            recorder.record(p.message)
        }
        let timing = recorder.finish()
        let size = (try? FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        print("PERF total \(String(format: "%.1f", timing.seconds))s, output \(size / 1_000_000) MB")
        var sums: [String: Double] = [:], order: [String] = []
        for mark in timing.marks {
            let l = mark.label, s = mark.seconds
            if sums[l] == nil { order.append(l) }
            sums[l, default: 0] += s
        }
        for l in order { print("PERF \(String(format: "%6.1f", sums[l]!))s  \(l)") }
        if let directory = ProcessInfo.processInfo.environment["WAX_PERF_OUT"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // New unique sample file: never overwrite earlier measurements or another concurrent run.
            try JSONEncoder().encode(timing).write(to: folder.appendingPathComponent("sample-\(UUID()).json"), options: .atomic)
        }
    }
}

final class PerformanceRecorderTests: XCTestCase {
    func testConcurrentCallbacksProduceFiniteMonotonicSamples() {
        let recorder = PerformanceRecorder()
        DispatchQueue.concurrentPerform(iterations: 1000) { i in recorder.record("stage-\(i)") }
        let snapshot = recorder.finish()
        XCTAssertEqual(snapshot.marks.count, 1001)
        XCTAssertTrue(snapshot.marks.allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 })
        XCTAssertTrue(snapshot.seconds.isFinite)
        XCTAssertEqual(snapshot.marks.reduce(0) { $0 + $1.seconds }, snapshot.seconds, accuracy: 0.000001)
    }
    func testFinalizedSamplesIgnoreLateCallbacks() {
        let recorder = PerformanceRecorder(); recorder.record("sign")
        let first = recorder.finish(); recorder.record("late completion")
        let second = recorder.finish()
        XCTAssertEqual(first.seconds, second.seconds)
        XCTAssertEqual(first.marks.count, second.marks.count)
    }
    func testRawTimingSamplesRoundTrip() throws {
        let recorder = PerformanceRecorder(); recorder.record("extract"); recorder.record("sign")
        let sample = recorder.finish()
        let decoded = try JSONDecoder().decode(PerformanceRecorder.Snapshot.self, from: JSONEncoder().encode(sample))
        XCTAssertEqual(decoded.seconds, sample.seconds)
        XCTAssertEqual(decoded.marks.map(\.label), ["start", "extract", "sign"])
    }
}
