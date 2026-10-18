import XCTest
@testable import InstallKit

/// Talks to a real server. Skipped unless WAX_OTA_URL and WAX_OTA_TOKEN_FILE are set.
final class OTALiveTests: XCTestCase {
    func testUploadsLargeFileThroughRealServerAndItIsServedBack() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let url = env["WAX_OTA_URL"], let tokenFile = env["WAX_OTA_TOKEN_FILE"] else { throw XCTSkip("no live server configured") }
        let token = try String(contentsOfFile: tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let ipa = FileManager.default.temporaryDirectory.appendingPathComponent("live-\(UUID().uuidString).ipa")
        var bytes = [UInt8](repeating: 0, count: 25 << 20)
        for i in 0..<bytes.count { bytes[i] = UInt8(truncatingIfNeeded: i &* 31) }
        try Data(bytes).write(to: ipa); defer { try? FileManager.default.removeItem(at: ipa) }

        final class Box: @unchecked Sendable { var last = 0.0 }
        let box = Box()
        let link = try await OTAUploader(endpoint: try OTAEndpoint(url), token: token)
            .upload(ipa: ipa, bundleIdentifier: "dev.localsigner.livetest", version: "1.0", title: "Live") { box.last = $0 }
        XCTAssertGreaterThan(box.last, 0.99)

        let manifestURL = URL(string: String(link.absoluteString.dropFirst("itms-services://?action=download-manifest&url=".count)))!
        let (mdata, mresp) = try await URLSession.shared.data(from: manifestURL)
        XCTAssertEqual((mresp as? HTTPURLResponse)?.statusCode, 200)
        let plist = try PropertyListSerialization.propertyList(from: mdata, format: nil) as! [String: Any]
        let ipaURL = URL(string: ((((plist["items"] as! [[String: Any]])[0]["assets"]) as! [[String: Any]])[0]["url"]) as! String)!
        let (idata, iresp) = try await URLSession.shared.data(from: ipaURL)
        XCTAssertEqual((iresp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(idata.count, 25 << 20)
        XCTAssertEqual(Array(idata.prefix(64)), Array(bytes.prefix(64)))
        // clean up what we created
        let id = ipaURL.deletingLastPathComponent().lastPathComponent
        var del = URLRequest(url: URL(string: "\(url)/ota-up/u/\(id)")!); del.httpMethod = "DELETE"
        del.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: del)
    }
}
