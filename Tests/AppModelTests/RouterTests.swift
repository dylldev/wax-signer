import XCTest
@testable import LocalIPASigner

@MainActor
final class RouterTests: XCTestCase {
    func testInstallSetupOpensItsScreenDirectly() {
        let router = Router()
        router.openInstallHost()
        XCTAssertEqual(router.tab, .settings)
        XCTAssertEqual(router.settingsPath, [.installHost])
        router.reselect(.settings)
        XCTAssertTrue(router.settingsPath.isEmpty)
    }

    func testCredentialsSetupReplacesThePreviousDestination() {
        let router = Router()
        router.openInstallHost()
        router.openCredentials()
        XCTAssertEqual(router.settingsPath, [.credentials])
        XCTAssertEqual(router.tab, .settings)
    }
}
