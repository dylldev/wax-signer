import CoreGraphics
import Foundation
import ImageIO

/// Changes to make to an app before it is signed. Everything is optional; an empty value changes nothing.
public struct AppEdits: Equatable, Codable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case displayName, version, build, bundleIdentifier, randomizeBundleID, removeURLSchemes, removeExtensions, removeWatchApp,
             enableFileSharing, minimumOSVersion, enableProMotion, appearance, gameMode, iPadFullScreen, removeDeviceRestriction, plistEdits
    }
    public var displayName: String?
    public var version: String?
    public var build: String?
    /// The app's new bundle ID. Its extensions and Watch app follow.
    public var bundleIdentifier: String?
    /// Adds a random string to every bundle ID (some signers do this to avoid Apple's profile-quality checks).
    public var randomizeBundleID = false
    public var removeURLSchemes = false
    public var removeExtensions = false
    public var removeWatchApp = false
    public var enableFileSharing = false
    public var minimumOSVersion: String?
    public var enableProMotion = false
    public var appearance: Appearance?
    public var gameMode = false
    public var iPadFullScreen = false
    /// Lets an app limited to certain devices (or to iPad) run on this iPhone.
    public var removeDeviceRestriction = false
    /// Libraries to add to the app (.dylib, .framework, .deb). Chosen files, so per app: never kept as a default.
    public var injectLibraries: [URL] = []
    /// A new icon (any image iOS can read). Replaces the app's icon at both iPhone sizes.
    public var iconPNG: Data?
    /// Any Info.plist key to add, change or delete. Per app: never kept as a default.
    public var plistEdits: [PlistEdit] = []

    /// `nil` is "leave whatever this app already asks for". `system` is a real choice: it removes a developer's pin
    /// so the app tracks the phone's setting, which UIUserInterfaceStyle has no string value for.
    public enum Appearance: String, Codable, Sendable { case light, dark, system }

    public init() {}

    /// Older saved defaults lack the newer keys: missing keys mean "off".
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        build = try c.decodeIfPresent(String.self, forKey: .build)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        randomizeBundleID = try c.decodeIfPresent(Bool.self, forKey: .randomizeBundleID) ?? false
        removeURLSchemes = try c.decodeIfPresent(Bool.self, forKey: .removeURLSchemes) ?? false
        removeExtensions = try c.decodeIfPresent(Bool.self, forKey: .removeExtensions) ?? false
        removeWatchApp = try c.decodeIfPresent(Bool.self, forKey: .removeWatchApp) ?? false
        enableFileSharing = try c.decodeIfPresent(Bool.self, forKey: .enableFileSharing) ?? false
        minimumOSVersion = try c.decodeIfPresent(String.self, forKey: .minimumOSVersion)
        enableProMotion = try c.decodeIfPresent(Bool.self, forKey: .enableProMotion) ?? false
        appearance = try c.decodeIfPresent(Appearance.self, forKey: .appearance)
        gameMode = try c.decodeIfPresent(Bool.self, forKey: .gameMode) ?? false
        iPadFullScreen = try c.decodeIfPresent(Bool.self, forKey: .iPadFullScreen) ?? false
        removeDeviceRestriction = try c.decodeIfPresent(Bool.self, forKey: .removeDeviceRestriction) ?? false
        plistEdits = try c.decodeIfPresent([PlistEdit].self, forKey: .plistEdits) ?? []
        iconPNG = nil; injectLibraries = []   // per app, never kept as a default
    }

    /// The part worth keeping as a default: switches that suit every app. Name, version, ID and minimum iOS are per app.
    public func defaultsOnly() -> AppEdits {
        var d = AppEdits()
        d.randomizeBundleID = randomizeBundleID; d.removeURLSchemes = removeURLSchemes; d.removeExtensions = removeExtensions
        d.removeWatchApp = removeWatchApp; d.enableFileSharing = enableFileSharing; d.enableProMotion = enableProMotion
        d.appearance = appearance; d.gameMode = gameMode; d.iPadFullScreen = iPadFullScreen; d.removeDeviceRestriction = removeDeviceRestriction
        return d
    }

    private static func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    public var isEmpty: Bool {
        Self.blank(displayName) && Self.blank(version) && Self.blank(build) && Self.blank(bundleIdentifier) && !randomizeBundleID
            && !removeURLSchemes && !removeExtensions && !removeWatchApp && !enableFileSharing && Self.blank(minimumOSVersion)
            && !enableProMotion && appearance == nil && !gameMode && !iPadFullScreen && !removeDeviceRestriction && plistEdits.isEmpty
            && iconPNG == nil && injectLibraries.isEmpty
    }
}

/// One Info.plist change: set `key` to `value`, or delete it when `value` is nil.
public struct PlistEdit: Equatable, Codable, Sendable, Identifiable {
    public var key: String
    public var value: PlistValue?
    /// Identity for lists in the UI only; not part of the saved data and not compared.
    public var id = UUID()
    public init(key: String, value: PlistValue?) { self.key = key; self.value = value }
    enum CodingKeys: String, CodingKey { case key, value }
    public static func == (a: PlistEdit, b: PlistEdit) -> Bool { a.key == b.key && a.value == b.value }
}

public enum PlistValue: Equatable, Codable, Sendable {
    case string(String), bool(Bool), number(Double)
    var any: Any {
        switch self { case .string(let s): s; case .bool(let b): b; case .number(let n): n }
    }
}

/// Applies `AppEdits` to an unpacked app (the `.app` folder). Runs before signing, so the signature covers the result.
public enum AppEditor {
    /// Keys the signer depends on; editing them would break the signature, the install or the bundle ID handling.
    static let protectedKeys: Set<String> = ["CFBundleIdentifier", "CFBundleExecutable", "CFBundlePackageType"]
    /// Writes the icon at 60pt@2x (iPhone) and 76pt@2x (iPad) and points the plist at them, dropping the
    /// asset-catalog icon name that would otherwise take priority. Throws before touching anything if the image is unreadable.
    private static func writeIcon(_ data: Data, into app: URL, plist: inout [String: Any]) throws {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw SigningError.bundle("The chosen icon could not be read as an image.")
        }
        for (name, side) in [("WaxIcon60x60@2x.png", 120), ("WaxIcon76x76@2x~ipad.png", 152)] {
            guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw SigningError.bundle("The icon could not be resized.")
            }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            let out = NSMutableData()
            guard let scaled = ctx.makeImage(), let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else {
                throw SigningError.bundle("The icon could not be resized.")
            }
            CGImageDestinationAddImage(dest, scaled, nil)
            guard CGImageDestinationFinalize(dest) else { throw SigningError.bundle("The icon could not be saved.") }
            try (out as Data).write(to: app.appendingPathComponent(name))
        }
        plist.removeValue(forKey: "CFBundleIconName")
        plist.removeValue(forKey: "CFBundleIconFiles")
        plist["CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["WaxIcon60x60"]]]
        plist["CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["WaxIcon60x60", "WaxIcon76x76"]]]
    }

    private static let bundleIDPattern = #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#

    /// Returns one short note for each change that was made.
    @discardableResult
    public static func apply(_ edits: AppEdits, to app: URL, randomSuffix: () -> String = defaultSuffix) throws -> [String] {
        try applyDetailed(edits, to: app, randomSuffix: randomSuffix).notes
    }

    /// Notes for each change, and every bundle ID that was changed (old to new), so entitlements named after
    /// those IDs can follow the rename when the app is signed.
    public static func applyDetailed(_ edits: AppEdits, to app: URL, randomSuffix: () -> String = defaultSuffix) throws -> (notes: [String], renames: [String: String]) {
        var renamed: [String: String] = [:]
        func text(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        guard !edits.isEmpty else { return ([], [:]) }
        defer {
            lock.lock()
            formats = formats.filter { $0.key != app.appendingPathComponent("Info.plist").path && !$0.key.hasPrefix(app.path + "/") }
            lock.unlock()
        }
        if let id = text(edits.bundleIdentifier), id.range(of: bundleIDPattern, options: .regularExpression) == nil {
            throw SigningError.bundle("“\(id)” is not a valid bundle ID. Use letters, digits and hyphens separated by dots.")
        }

        var notes: [String] = []
        let fm = FileManager.default

        // Removals first, so renaming does not touch bundles that are about to disappear.
        if edits.removeExtensions {
            let plugins = app.appendingPathComponent("PlugIns")
            if fm.fileExists(atPath: plugins.path) { try fm.removeItem(at: plugins); notes.append("Removed app extensions") }
        }
        if edits.removeWatchApp {
            let watch = app.appendingPathComponent("Watch")
            if fm.fileExists(atPath: watch.path) { try fm.removeItem(at: watch); notes.append("Removed the Watch app") }
        }

        var main = try readPlist(app)
        let oldID = main["CFBundleIdentifier"] as? String ?? ""

        if let v = text(edits.displayName) { main["CFBundleDisplayName"] = v; main["CFBundleName"] = v; notes.append("Name set to \(v)") }
        if let v = text(edits.version) { main["CFBundleShortVersionString"] = v; notes.append("Version set to \(v)") }
        if let v = text(edits.build) { main["CFBundleVersion"] = v; notes.append("Build set to \(v)") }
        if let v = text(edits.minimumOSVersion) { main["MinimumOSVersion"] = v; notes.append("Minimum iOS set to \(v)") }
        if edits.removeURLSchemes, main["CFBundleURLTypes"] != nil { main.removeValue(forKey: "CFBundleURLTypes"); notes.append("Removed URL schemes") }
        if edits.enableFileSharing {
            main["UIFileSharingEnabled"] = true; main["LSSupportsOpeningDocumentsInPlace"] = true
            notes.append("File sharing turned on")
        }
        if edits.enableProMotion { main["CADisableMinimumFrameDurationOnPhone"] = true; notes.append("High frame rate turned on") }
        if let a = edits.appearance {
            switch a {
            case .light: main["UIUserInterfaceStyle"] = "Light"; notes.append("Appearance fixed to light")
            case .dark: main["UIUserInterfaceStyle"] = "Dark"; notes.append("Appearance fixed to dark")
            case .system: main.removeValue(forKey: "UIUserInterfaceStyle"); notes.append("Appearance left to follow the phone")
            }
        }
        if edits.gameMode { main["GCSupportsGameMode"] = true; notes.append("Game mode turned on") }
        if edits.iPadFullScreen { main["UIRequiresFullScreen"] = true; notes.append("iPad full screen turned on") }
        if edits.removeDeviceRestriction {
            main.removeValue(forKey: "UISupportedDevices")
            let family = (main["UIDeviceFamily"] as? [Int]) ?? []
            if !family.contains(1) { main["UIDeviceFamily"] = family + [1] }
            notes.append("Device restriction removed")
        }
        if !edits.injectLibraries.isEmpty {
            notes.append(contentsOf: try LibraryInjector.inject(edits.injectLibraries, into: app))
        }
        if let png = edits.iconPNG {
            try writeIcon(png, into: app, plist: &main)
            notes.append("Icon replaced")
        }
        for edit in edits.plistEdits {
            let key = edit.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            guard !AppEditor.protectedKeys.contains(key) else {
                throw SigningError.bundle("“\(key)” cannot be edited here. Use the bundle ID option for the identifier.")
            }
            if let v = edit.value { main[key] = v.any; notes.append("Set \(key)") }
            else if main.removeValue(forKey: key) != nil { notes.append("Removed \(key)") }
        }
        try writePlist(main, to: app)

        // Bundle IDs.
        var newID: String? = text(edits.bundleIdentifier)
        if edits.randomizeBundleID {
            let base = newID ?? oldID
            if !base.isEmpty { newID = base + "." + randomSuffix() }
        }
        if let newID, !oldID.isEmpty, newID != oldID {
            var renames: [String: String] = [oldID: newID]
            var bundles = nestedBundles(in: app)
            for b in bundles {
                var p = try readPlist(b)
                guard let id = p["CFBundleIdentifier"] as? String else { continue }
                let renamed = NestedIdentifier.candidates(original: id, mainOriginal: oldID, newMain: newID)[0]
                renames[id] = renamed
                p["CFBundleIdentifier"] = renamed
                try writePlist(p, to: b)
            }
            // Cross references between the app, its Watch app and the extensions.
            bundles.append(app)
            for b in bundles {
                var p = try readPlist(b)
                var changed = false
                do {
                    if let c = p["WKCompanionAppBundleIdentifier"] as? String, let n = renames[c] { p["WKCompanionAppBundleIdentifier"] = n; changed = true }
                    if var ext = p["NSExtension"] as? [String: Any], var attrs = ext["NSExtensionAttributes"] as? [String: Any],
                       let t = attrs["WKAppBundleIdentifier"] as? String, let n = renames[t] {
                        attrs["WKAppBundleIdentifier"] = n; ext["NSExtensionAttributes"] = attrs; p["NSExtension"] = ext; changed = true
                    }
                }
                if b == app { p["CFBundleIdentifier"] = newID; changed = true }
                if changed { try writePlist(p, to: b) }
            }
            renamed = renames
            notes.append("Bundle ID changed to \(newID)")
        }
        return (notes, renamed)
    }

    public static func defaultSuffix() -> String {
        String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
    }

    // MARK: files

    static func nestedBundles(in app: URL) -> [URL] {
        BundleLayout.nestedBundles(in: app)
    }

    private static var formats: [String: PropertyListSerialization.PropertyListFormat] = [:]
    private static let lock = NSLock()

    private static func readPlist(_ bundle: URL) throws -> [String: Any] {
        let url = bundle.appendingPathComponent("Info.plist")
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let data = try? Data(contentsOf: url),
              let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw SigningError.bundle("\(bundle.lastPathComponent): Info.plist is missing or unreadable")
        }
        lock.lock(); formats[url.path] = format; lock.unlock()
        return dict
    }

    private static func writePlist(_ dict: [String: Any], to bundle: URL) throws {
        let url = bundle.appendingPathComponent("Info.plist")
        lock.lock(); let format = formats[url.path] ?? .xml; lock.unlock()
        try PropertyListSerialization.data(fromPropertyList: dict, format: format, options: 0).write(to: url)
    }
}
