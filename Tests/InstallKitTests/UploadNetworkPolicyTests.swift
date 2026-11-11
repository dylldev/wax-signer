import XCTest
@testable import InstallKit

/// Uploading a signed app can be hundreds of megabytes. A phone on cellular should not spend that by surprise,
/// and the phone host never touches the network at all.
final class UploadNetworkPolicyTests: XCTestCase {
    func testCellularIsBlockedByDefault() {
        XCTAssertTrue(UploadNetworkPolicy.blocksUpload(remote: true, expensive: true, allowCellular: false))
    }

    func testWiFiIsAlwaysAllowed() {
        XCTAssertFalse(UploadNetworkPolicy.blocksUpload(remote: true, expensive: false, allowCellular: false))
    }

    func testTheOverrideAllowsCellular() {
        XCTAssertFalse(UploadNetworkPolicy.blocksUpload(remote: true, expensive: true, allowCellular: true))
    }

    func testThePhoneHostNeverAsks() {
        XCTAssertFalse(UploadNetworkPolicy.blocksUpload(remote: false, expensive: true, allowCellular: false))
    }

    func testTheMessageSaysWhatToChange() {
        let text = UploadNetworkPolicy.message
        XCTAssertTrue(text.contains("Wi-Fi"), text)
        XCTAssertTrue(text.contains("Upload over cellular"), text)
    }
}
