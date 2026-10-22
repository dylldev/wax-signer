import XCTest
@testable import IPAKit

final class ImportLogTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("implog-\(UUID().uuidString)/import.log")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testAppendsLinesInOrder() {
        let log = ImportLog(fileURL: url)
        log.log("one"); log.log("two")
        let lines = log.recentLines()
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix("one"))
        XCTAssertTrue(lines[1].hasSuffix("two"))
    }

    func testNewlinesCannotForgeLogLines() {
        let log = ImportLog(fileURL: url)
        log.log("file named a\nFAKE 2026 forged entry")
        XCTAssertEqual(log.recentLines().count, 1)
    }

    func testStaysWithinItsSizeBudgetAndKeepsTheNewest() {
        let log = ImportLog(fileURL: url, maxBytes: 2000)
        for i in 0..<200 { log.log("entry \(i) " + String(repeating: "x", count: 40)) }
        let size = (try? Data(contentsOf: url).count) ?? 0
        XCTAssertLessThanOrEqual(size, 2100)
        XCTAssertTrue(log.recentLines(1).first?.contains("entry 199") == true)
    }

    func testDescribeFileNamesNoDirectoryAndErrorsCarryDomainAndCode() throws {
        let f = url.deletingLastPathComponent().appendingPathComponent("cert.p12")
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 12).write(to: f)
        let text = ImportLog.describe(f)
        XCTAssertEqual(text, "cert.p12 (12 bytes)")
        XCTAssertFalse(text.contains("/"))
        let e = ImportLog.describe(NSError(domain: "D", code: 7, userInfo: [NSLocalizedDescriptionKey: "bad"]))
        XCTAssertEqual(e, "D 7: bad")
    }

    func testClearRemovesTheFile() {
        let log = ImportLog(fileURL: url)
        log.log("x"); log.clear()
        XCTAssertTrue(log.recentLines().isEmpty)
    }
}
