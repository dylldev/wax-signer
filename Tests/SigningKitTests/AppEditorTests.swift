import CoreGraphics
import ImageIO
import XCTest
@testable import SigningKit

final class AppEditorTests: XCTestCase {
    private func plist(_ url: URL) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: url.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
    }

    private func set(_ app: URL, _ values: [String: Any]) throws {
        var p = try plist(app)
        for (k, v) in values { p[k] = v }
        try PropertyListSerialization.data(fromPropertyList: p, format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
    }

    func testNoEditsLeavesTheAppByteForByteAlone() throws {
        let app = try makeWorkingApp()
        let before = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        let notes = try AppEditor.apply(AppEdits(), to: app)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Info.plist")), before)
        XCTAssertTrue(notes.isEmpty)
    }

    func testNameVersionAndBuildAreSet() throws {
        let app = try makeWorkingApp()
        var e = AppEdits(); e.displayName = "My App"; e.version = "9.1"; e.build = "42"
        _ = try AppEditor.apply(e, to: app)
        let p = try plist(app)
        XCTAssertEqual(p["CFBundleDisplayName"] as? String, "My App")
        XCTAssertEqual(p["CFBundleName"] as? String, "My App")
        XCTAssertEqual(p["CFBundleShortVersionString"] as? String, "9.1")
        XCTAssertEqual(p["CFBundleVersion"] as? String, "42")
    }

    func testBundleIDOverrideMovesTheAppAndItsExtensions() throws {
        let app = try makeWorkingApp()
        let old = try XCTUnwrap(try plist(app)["CFBundleIdentifier"] as? String)
        var e = AppEdits(); e.bundleIdentifier = "com.new.app"
        let notes = try AppEditor.apply(e, to: app)
        XCTAssertEqual(try plist(app)["CFBundleIdentifier"] as? String, "com.new.app")
        let ext = app.appendingPathComponent("PlugIns/TestExt.appex")
        let extID = try XCTUnwrap(try plist(ext)["CFBundleIdentifier"] as? String)
        XCTAssertTrue(extID.hasPrefix("com.new.app."), extID)
        XCTAssertFalse(extID.hasPrefix(old), extID)
        XCTAssertTrue(notes.contains { $0.contains("com.new.app") }, "\(notes)")
    }

    func testRandomSuffixIsAppendedToEveryBundleID() throws {
        let app = try makeWorkingApp()
        let old = try XCTUnwrap(try plist(app)["CFBundleIdentifier"] as? String)
        var e = AppEdits(); e.randomizeBundleID = true
        _ = try AppEditor.apply(e, to: app, randomSuffix: { "ab12cd" })
        XCTAssertEqual(try plist(app)["CFBundleIdentifier"] as? String, old + ".ab12cd")
        let ext = app.appendingPathComponent("PlugIns/TestExt.appex")
        XCTAssertTrue((try plist(ext)["CFBundleIdentifier"] as? String ?? "").hasPrefix(old + ".ab12cd."))
    }

    func testURLSchemesCanBeRemoved() throws {
        let app = try makeWorkingApp()
        try set(app, ["CFBundleURLTypes": [["CFBundleURLSchemes": ["tiktok"]]]])
        var e = AppEdits(); e.removeURLSchemes = true
        _ = try AppEditor.apply(e, to: app)
        XCTAssertNil(try plist(app)["CFBundleURLTypes"])
    }

    func testExtensionsAndWatchAppsCanBeRemoved() throws {
        let app = try makeWorkingApp()
        let watch = app.appendingPathComponent("Watch/Companion.app")
        try FileManager.default.createDirectory(at: watch, withIntermediateDirectories: true)
        var e = AppEdits(); e.removeExtensions = true; e.removeWatchApp = true
        let notes = try AppEditor.apply(e, to: app)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Watch").path))
        XCTAssertEqual(notes.count, 2, "\(notes)")
    }

    func testFileSharingMinimumOSAndProMotionKeys() throws {
        let app = try makeWorkingApp()
        var e = AppEdits(); e.enableFileSharing = true; e.minimumOSVersion = "15.0"; e.enableProMotion = true
        _ = try AppEditor.apply(e, to: app)
        let p = try plist(app)
        XCTAssertEqual(p["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(p["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
        XCTAssertEqual(p["MinimumOSVersion"] as? String, "15.0")
        XCTAssertEqual(p["CADisableMinimumFrameDurationOnPhone"] as? Bool, true)
    }

    func testBlankTextEditsAreIgnored() throws {
        let app = try makeWorkingApp()
        let before = try plist(app)["CFBundleIdentifier"] as? String
        var e = AppEdits(); e.displayName = "  "; e.bundleIdentifier = ""; e.version = nil
        XCTAssertTrue(e.isEmpty)
        _ = try AppEditor.apply(e, to: app)
        XCTAssertEqual(try plist(app)["CFBundleIdentifier"] as? String, before)
    }

    func testAnInvalidBundleIDIsRefusedBeforeAnythingChanges() throws {
        let app = try makeWorkingApp()
        var e = AppEdits(); e.bundleIdentifier = "not valid!"
        XCTAssertThrowsError(try AppEditor.apply(e, to: app))
    }

    func testSettingsRoundTripThroughJSON() throws {
        var e = AppEdits(); e.displayName = "X"; e.removeURLSchemes = true; e.enableProMotion = true
        let data = try JSONEncoder().encode(e)
        XCTAssertEqual(try JSONDecoder().decode(AppEdits.self, from: data), e)
    }

    // MARK: More plist options

    func testAppearanceSetsTheInterfaceStyle() throws {
        for (choice, expected) in [(AppEdits.Appearance.light, "Light"), (.dark, "Dark")] {
            let app = try makeWorkingApp()
            var e = AppEdits(); e.appearance = choice
            let notes = try AppEditor.apply(e, to: app)
            XCTAssertEqual(try plist(app)["UIUserInterfaceStyle"] as? String, expected)
            XCTAssertTrue(notes.contains { $0.lowercased().contains("appearance") }, "\(notes)")
        }
    }

    func testGameModeSetsTheSupportKey() throws {
        let app = try makeWorkingApp()
        var e = AppEdits(); e.gameMode = true
        _ = try AppEditor.apply(e, to: app)
        XCTAssertEqual(try plist(app)["GCSupportsGameMode"] as? Bool, true)
    }

    func testIPadFullScreenSetsRequiresFullScreen() throws {
        let app = try makeWorkingApp()
        var e = AppEdits(); e.iPadFullScreen = true
        _ = try AppEditor.apply(e, to: app)
        XCTAssertEqual(try plist(app)["UIRequiresFullScreen"] as? Bool, true)
    }

    func testRemoveDeviceRestrictionDeletesSupportedDevicesAndRequiredCapabilitiesLimits() throws {
        let app = try makeWorkingApp()
        try set(app, ["UISupportedDevices": ["iPhone15,2"], "UIDeviceFamily": [2]])
        var e = AppEdits(); e.removeDeviceRestriction = true
        _ = try AppEditor.apply(e, to: app)
        let p = try plist(app)
        XCTAssertNil(p["UISupportedDevices"])
        XCTAssertEqual((p["UIDeviceFamily"] as? [Int]).map(Set.init), Set([1, 2]), "iPhone is allowed too")
    }

    func testPlistEditAddsChangesAndDeletesKeys() throws {
        let app = try makeWorkingApp()
        try set(app, ["OldKey": "x", "KeepMe": true])
        var e = AppEdits()
        e.plistEdits = [
            PlistEdit(key: "NewString", value: .string("hello")),
            PlistEdit(key: "NewFlag", value: .bool(true)),
            PlistEdit(key: "NewNumber", value: .number(3)),
            PlistEdit(key: "OldKey", value: .string("changed")),
            PlistEdit(key: "KeepMe", value: nil),
        ]
        _ = try AppEditor.apply(e, to: app)
        let p = try plist(app)
        XCTAssertEqual(p["NewString"] as? String, "hello")
        XCTAssertEqual(p["NewFlag"] as? Bool, true)
        XCTAssertEqual(p["NewNumber"] as? Double, 3)
        XCTAssertEqual(p["OldKey"] as? String, "changed")
        XCTAssertNil(p["KeepMe"])
    }

    func testPlistEditsNeverTouchTheBundleIdentifierOrExecutable() throws {
        let app = try makeWorkingApp()
        let before = try plist(app)
        var e = AppEdits()
        e.plistEdits = [PlistEdit(key: "CFBundleIdentifier", value: .string("evil")), PlistEdit(key: "CFBundleExecutable", value: nil)]
        XCTAssertThrowsError(try AppEditor.apply(e, to: app))
        XCTAssertEqual(try plist(app)["CFBundleIdentifier"] as? String, before["CFBundleIdentifier"] as? String)
    }

    func testNewSwitchesCountAsEditsAndNewDefaultsAreKept() {
        var e = AppEdits(); e.gameMode = true
        XCTAssertFalse(e.isEmpty)
        e.appearance = .dark; e.iPadFullScreen = true; e.removeDeviceRestriction = true
        e.plistEdits = [PlistEdit(key: "K", value: .bool(true))]
        let d = e.defaultsOnly()
        XCTAssertEqual(d.appearance, .dark); XCTAssertTrue(d.gameMode); XCTAssertTrue(d.iPadFullScreen); XCTAssertTrue(d.removeDeviceRestriction)
        XCTAssertTrue(d.plistEdits.isEmpty, "plist edits are per app")
    }

    func testNoEditsStillLeavesTheAppByteForByteAlone() throws {
        let app = try makeWorkingApp()
        let before = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        _ = try AppEditor.apply(AppEdits(), to: app)
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Info.plist")), before)
    }

    // MARK: Icon

    private func pngData(side: Int) -> Data {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testIconIsReplacedAndThePlistPointsAtIt() throws {
        let app = try makeWorkingApp()
        try set(app, ["CFBundleIconName": "AppIcon", "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["Old"], "CFBundleIconName": "AppIcon"]]])
        var e = AppEdits(); e.iconPNG = pngData(side: 512)
        let notes = try AppEditor.apply(e, to: app)
        let p = try plist(app)
        let primary = ((p["CFBundleIcons"] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary?["CFBundleIconFiles"] as? [String], ["WaxIcon60x60"])
        XCTAssertNil(primary?["CFBundleIconName"], "the asset catalog icon would otherwise win")
        XCTAssertNil(p["CFBundleIconName"])
        let file = app.appendingPathComponent("WaxIcon60x60@2x.png")
        let src = try XCTUnwrap(CGImageSourceCreateWithURL(file as CFURL, nil))
        let img = try XCTUnwrap(CGImageSourceCreateImageAtIndex(src, 0, nil))
        XCTAssertEqual(img.width, 120); XCTAssertEqual(img.height, 120)
        XCTAssertTrue(notes.contains { $0.lowercased().contains("icon") }, "\(notes)")
    }

    func testAnUnreadableIconIsRefusedAndNothingIsChanged() throws {
        let app = try makeWorkingApp()
        let before = try Data(contentsOf: app.appendingPathComponent("Info.plist"))
        var e = AppEdits(); e.iconPNG = Data("not an image".utf8)
        XCTAssertThrowsError(try AppEditor.apply(e, to: app))
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Info.plist")), before)
    }
}
