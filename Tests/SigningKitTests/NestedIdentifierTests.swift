import XCTest
@testable import SigningKit

final class NestedIdentifierTests: XCTestCase {
    func testPrefixedExtensionKeepsItsFullSuffixFirst() {
        let c = NestedIdentifier.candidates(original: "com.foo.app.share.ext", mainOriginal: "com.foo.app", newMain: "T.vendor.app")
        XCTAssertEqual(c.first, "T.vendor.app.share.ext")
        XCTAssertTrue(c.contains("T.vendor.app.ext"), "then the last component")
        XCTAssertEqual(c.last, "com.foo.app.share.ext", "and finally the original")
    }

    func testUnrelatedExtensionTriesLastComponentThenOriginal() {
        let c = NestedIdentifier.candidates(original: "com.bare.share", mainOriginal: "com.foo.app", newMain: "T.vendor.app")
        XCTAssertEqual(c, ["T.vendor.app.share", "com.bare.share"])
    }

    func testCandidatesAreUnique() {
        let c = NestedIdentifier.candidates(original: "com.foo.app.ext", mainOriginal: "com.foo.app", newMain: "T.vendor.app")
        XCTAssertEqual(c.count, Set(c).count)
        XCTAssertEqual(c.first, "T.vendor.app.ext")
    }
}
