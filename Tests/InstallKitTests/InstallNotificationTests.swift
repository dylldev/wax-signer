import XCTest
@testable import InstallKit

final class InstallNotificationTests: XCTestCase {
    private let link = URL(string: "itms-services://?action=download-manifest&url=https://example.test/ota/abc/manifest.plist")!

    func testReadyToInstallCarriesTheLinkAndNamesTheApp() throws {
        let n = InstallNotification.readyToInstall(appTitle: "Sample App", link: link)
        XCTAssertEqual(n.title, "Ready to install")
        XCTAssertTrue(n.body.contains("Sample App"), n.body)
        XCTAssertEqual(InstallNotification.link(from: n.userInfo), link)
    }

    func testSignedForExportHasNoLink() {
        let n = InstallNotification.signed(appTitle: "Sample App")
        XCTAssertEqual(n.title, "Signed")
        XCTAssertNil(InstallNotification.link(from: n.userInfo))
    }

    func testOnlyItmsServicesLinksAreAcceptedFromANotification() {
        XCTAssertNil(InstallNotification.link(from: ["waxInstallLink": "https://evil.test/x"]))
        XCTAssertNil(InstallNotification.link(from: ["waxInstallLink": "itms-services://?action=download-manifest&url=http://insecure.test/m.plist"]))
        XCTAssertNil(InstallNotification.link(from: [:]))
        XCTAssertNil(InstallNotification.link(from: ["waxInstallLink": 5]))
    }

    func testAnEmptyTitleStillReadsWell() {
        XCTAssertTrue(InstallNotification.readyToInstall(appTitle: "", link: link).body.contains("Your app"))
    }

    func testTheBackgroundTaskIdentifierIsOneFixedIDPrefixedWithTheBundleID() {
        XCTAssertEqual(InstallNotification.taskIdentifier(bundleID: "io.github.dylldev.wax"),
                       "io.github.dylldev.wax.signing")
    }

    func testHalfwayNotificationNamesTheApp() {
        let c = InstallNotification.halfway(appTitle: "Sample")
        XCTAssertEqual(c.title, "50% done")
        XCTAssertTrue(c.body.contains("Sample"))
        XCTAssertTrue(c.userInfo.isEmpty)
    }

    func testInstallLinkKeepsTheWholeManifestURLInItsQuery() throws {
        let manifest = URL(string: "https://example.com/a&b=c/ota/x/manifest.plist")!
        let link = OTALink.installURL(manifest: manifest)
        let items = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(items?.first(where: { $0.name == "url" })?.value, manifest.absoluteString)
    }
}
