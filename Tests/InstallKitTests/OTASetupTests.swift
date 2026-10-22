import XCTest
@testable import InstallKit

final class OTASetupTests: XCTestCase {
    func testRoundTrip() throws {
        let line = OTASetup.make(server: "https://h.example", token: "abcDEF0123456789abcdefABCDEF0123")
        let p = try OTASetup.parse(line)
        XCTAssertEqual(p.server, "https://h.example")
        XCTAssertEqual(p.token, "abcDEF0123456789abcdefABCDEF0123")
    }

    func testToleratesWhitespaceAndNewlines() throws {
        let p = try OTASetup.parse("  WAXINSTALL1   https://h.example/ \n 0123456789abcdef0123456789abcdef \n")
        XCTAssertEqual(p.server, "https://h.example")
        XCTAssertEqual(p.token.count, 32)
    }

    func testRejectsBadInput() {
        for bad in ["", "hello", "WAXINSTALL1", "WAXINSTALL1 https://h.example", "WAXINSTALL2 https://h.example 0123456789abcdef0123456789abcdef",
                    "WAXINSTALL1 http://h.example 0123456789abcdef0123456789abcdef",
                    "WAXINSTALL1 https://h.example short",
                    "WAXINSTALL1 https://h.example 0123456789abcdef0123456789abcdef extra",
                    "WAXINSTALL1 https://h.example 0123456789abcdef0123456789abc<ef"] {
            XCTAssertThrowsError(try OTASetup.parse(bad), bad)
        }
    }

    func testErrorsNeverEchoTheToken() {
        let secret = "SECRETSECRETSECRETSECRETSECRET00"
        do { _ = try OTASetup.parse("WAXINSTALL1 http://h.example \(secret)") } catch {
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }
    }

    func testMinimumTokenLengthIs32() { XCTAssertEqual(OTASetup.minimumTokenLength, 32) }

    func testTokenOf31CharactersIsRejected() {
        let t = String(repeating: "a", count: 31)
        XCTAssertThrowsError(try OTASetup.parse("WAXINSTALL1 https://h.example \(t)"))
    }

    func testTokenOf32CharactersIsAccepted() throws {
        let t = String(repeating: "a", count: 32)
        XCTAssertEqual(try OTASetup.parse("WAXINSTALL1 https://h.example \(t)").token, t)
    }
}
