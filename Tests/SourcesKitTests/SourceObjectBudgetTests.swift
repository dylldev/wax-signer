import XCTest
@testable import SourcesKit

final class SourceObjectBudgetTests: XCTestCase {
    private let valid = Data(#"{"name":"Fixture","apps":[{"bundleIdentifier":"com.fixture","version":"1","downloadURL":"https://fixture.invalid/app.ipa"}]}"#.utf8)
    private func expectLimit(_ json: Data, limits: SourceParser.Limits, _ reason: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try SourceParser.parse(json, limits: limits), file: file, line: line) {
            XCTAssertEqual($0 as? SourceError, .resourceLimit(reason), file: file, line: line)
        }
    }
    func testByteBudgetRejectsBeforeFoundationAndAcceptsExactBoundary() throws {
        var limits = SourceParser.Limits(); limits.maxBytes = valid.count - 1
        expectLimit(valid, limits: limits, "JSON byte limit")
        limits.maxBytes = valid.count; XCTAssertEqual(try SourceParser.parse(valid, limits: limits).apps.count, 1)
    }
    func testIgnoredContainersCountAndCannotBeSkippedByLenientSchema() throws {
        let json = Data(#"{"apps":[],"ignored":[{},{}]}"#.utf8)
        var limits = SourceParser.Limits(); limits.maxContainers = 4
        expectLimit(json, limits: limits, "JSON container limit")
        limits.maxContainers = 5; XCTAssertEqual(try SourceParser.parse(json, limits: limits).apps.count, 0)
    }
    func testFlatIgnoredScalarsAreBudgetedWithoutContainers() throws {
        let json = Data(#"{"apps":[],"ignored":[0,true,null,false]}"#.utf8)
        var limits = SourceParser.Limits(); limits.maxTokens = 8
        expectLimit(json, limits: limits, "JSON token limit")
        limits.maxTokens = 9; XCTAssertTrue(try SourceParser.parse(json, limits: limits).apps.isEmpty)
    }
    func testNestingIsBoundedBeforeFoundationDecodesIt() throws {
        var limits = SourceParser.Limits(); limits.maxDepth = 4
        expectLimit(Data(#"{"apps":[],"ignored":[[[[]]]]}"#.utf8), limits: limits, "JSON nesting limit")
        XCTAssertTrue(try SourceParser.parse(Data(#"{"apps":[],"ignored":[[[]]]}"#.utf8), limits: limits).apps.isEmpty)
    }
    func testStringBudgetUsesUTF8BytesAndIncludesIgnoredFields() throws {
        var limits = SourceParser.Limits(); limits.maxStringBytes = 7
        let json = Data(#"{"apps":[],"ignored":"éééé"}"#.utf8)
        expectLimit(json, limits: limits, "JSON string byte limit")
        limits.maxStringBytes = 8; XCTAssertTrue(try SourceParser.parse(json, limits: limits).apps.isEmpty)
    }
    func testEscapedQuotesBackslashesAndBracketsDoNotCountAsContainers() throws {
        var limits = SourceParser.Limits(); limits.maxDepth = 2; limits.maxContainers = 2
        let json = Data(#"{"apps":[],"name":"[{}] \"quoted\" \\ end"}"#.utf8)
        XCTAssertEqual(try SourceParser.parse(json, limits: limits).name, "[{}] \"quoted\" \\ end")
    }
    func testBudgetErrorsCannotBeTurnedIntoAnIgnoredBadApp() {
        var limits = SourceParser.Limits(); limits.maxContainers = 5
        expectLimit(Data(#"{"apps":[{"versions":[{},{}]}]}"#.utf8), limits: limits, "JSON container limit")
    }
    func testMalformedJSONStillReturnsNotJSONAndUTF8BOMIsSupported() throws {
        for json in [#"{"apps":[]"#, #"{"apps":[],"name":"unterminated}"#, #"{"apps":[]}]}"#, #"{"apps":[],"x":[}}"#] {
            XCTAssertThrowsError(try SourceParser.parse(Data(json.utf8))) { XCTAssertEqual($0 as? SourceError, .notJSON) }
        }
        XCTAssertEqual(try SourceParser.parse(Data([0xef, 0xbb, 0xbf]) + valid).apps.count, 1)
        XCTAssertThrowsError(try SourceParser.parse(try XCTUnwrap(String(decoding: valid, as: UTF8.self).data(using: .utf16)))) {
            XCTAssertEqual($0 as? SourceError, .notJSON)
        }
    }
    func testInvalidAndOverflowBoundaryBudgetsAreControlledErrors() {
        for value in [0, -1, Int.max] {
            var limits = SourceParser.Limits(); limits.maxDepth = value
            expectLimit(valid, limits: limits, "invalid parser budget")
        }
        var limits = SourceParser.Limits(); limits.deadline = .nan
        expectLimit(valid, limits: limits, "invalid parser budget")
    }
    func testCancellationIsObservedWhileScanningBeforeDecode() async {
        let data = valid
        let task = Task<Bool, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try SourceParser.parse(data); return false }
            catch { return error is CancellationError }
        }
        let canceled = await task.value; XCTAssertTrue(canceled)
    }
    func testMonotonicDeadlineIncludesVersionReductionAndIsNotAByteArrivalTimer() {
        var ticks = 0
        XCTAssertThrowsError(try SourceParser.parse(valid, limits: .init(), now: {
            ticks += 1; return ticks < 7 ? 0 : 16
        })) { XCTAssertEqual($0 as? SourceError, .resourceLimit("JSON processing deadline")) }
        XCTAssertEqual(ticks, 7)
    }
    func testScannerChecksDuringLongStringsAndDoesNotAllocateDecodedValues() {
        let data = Data((#"{"apps":[],"ignored":""# + String(repeating: "a", count: 140_000) + #""}"#).utf8)
        var calls = 0
        struct Interrupted: Error {}
        XCTAssertThrowsError(try SourceJSONBudget.validate(data, limits: .init(), checkpoint: {
            calls += 1; if calls == 3 { throw Interrupted() }
        })) { XCTAssertTrue($0 is Interrupted) }
        XCTAssertEqual(calls, 3)
    }
}
