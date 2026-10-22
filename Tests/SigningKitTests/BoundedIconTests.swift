import CoreGraphics
import ImageIO
import IPAKit
import XCTest
@testable import SigningKit

final class BoundedIconTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("icon-budget-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func png(width: Int = 300, height: Int = 200) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage()), output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
    func testValidImageIsDownsampledBeforePreview() throws {
        let data = try BoundedIcon.prepare(data: png())
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 152); XCTAssertLessThanOrEqual(image.height, 152); XCTAssertLessThan(data.count, 128 * 1024)
    }
    func testActualFileReadBudgetRejectsAndPreservesSource() throws {
        let file = root.appendingPathComponent("photo"), bytes = Data(repeating: 1, count: 65); try bytes.write(to: file)
        XCTAssertThrowsError(try BoundedIcon.prepare(file: file, limits: .init(maxBytes: 64))) { XCTAssertEqual($0 as? BoundedIcon.Failure, .tooLarge) }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testDataBudgetRunsBeforeImageDecode() {
        XCTAssertThrowsError(try BoundedIcon.prepare(data: Data(repeating: 0, count: 65), limits: .init(maxBytes: 64))) {
            XCTAssertEqual($0 as? BoundedIcon.Failure, .tooLarge)
        }
    }
    func testPixelBudgetIsCheckedBeforeDecode() throws {
        let data = try png(width: 4, height: 4)
        XCTAssertThrowsError(try BoundedIcon.prepare(data: data, limits: .init(maxPixels: 15))) { XCTAssertEqual($0 as? BoundedIcon.Failure, .dimensions) }
        XCTAssertNoThrow(try BoundedIcon.prepare(data: data, limits: .init(maxPixels: 16)))
    }
    func testDimensionBoundaryAndOverflowAreControlled() throws {
        for (width, height) in [(Int64.max, Int64.max), (0, 1), (-1, 1), (32_769, 1), (16_384, 16_384)] {
            XCTAssertThrowsError(try BoundedIcon.validateDimensions(width: width, height: height, limits: .init())) {
                XCTAssertEqual($0 as? BoundedIcon.Failure, .dimensions)
            }
        }
        XCTAssertNoThrow(try BoundedIcon.validateDimensions(width: 8192, height: 8192, limits: .init()))
    }
    func testInvalidLimitsAndUnreadableDataAreControlled() {
        XCTAssertThrowsError(try BoundedIcon.prepare(data: Data(), limits: .init(maxBytes: .max))) { XCTAssertEqual($0 as? BoundedIcon.Failure, .invalidLimits) }
        XCTAssertThrowsError(try BoundedIcon.prepare(data: Data([1,2,3]))) { XCTAssertEqual($0 as? BoundedIcon.Failure, .unreadable) }
    }
    func testCancellationBeforeReadDoesNotDeleteSource() async throws {
        let file = root.appendingPathComponent("icon.png"), bytes = try png(); try bytes.write(to: file)
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try BoundedIcon.prepare(file: file)
        }
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    func testEditorPixelRefusalLeavesAppUnchanged() throws {
        let app = try makeWorkingApp(); defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        let plist = app.appendingPathComponent("Info.plist"), before = try Data(contentsOf: plist)
        var edits = AppEdits(); edits.iconPNG = Data([1,2,3])
        XCTAssertThrowsError(try AppEditor.apply(edits, to: app))
        XCTAssertEqual(try Data(contentsOf: plist), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("WaxIcon60x60@2x.png").path))
    }
}
