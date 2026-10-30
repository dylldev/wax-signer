import Foundation

/// A local report contains user-entered text and version information only.
public enum BugReport {
    public struct About: Equatable, Sendable {
        public var appVersion: String
        public var build: String
        public var osVersion: String

        public init(appVersion: String, build: String, osVersion: String) {
            self.appVersion = appVersion; self.build = build; self.osVersion = osVersion
        }

        /// Reads only the two version keys from the app's Info.plist.
        public init(infoDictionary: [String: Any], osVersion: String) {
            self.init(appVersion: infoDictionary["CFBundleShortVersionString"] as? String ?? "unknown",
                      build: infoDictionary["CFBundleVersion"] as? String ?? "unknown", osVersion: osVersion)
        }
    }

    public struct Draft: Equatable, Sendable {
        public let about: About
        public var whatHappened = ""
        public var expectedBehavior = ""

        public init(about: About) { self.about = about }

        public var text: String {
            """
            **What happened**
            \(whatHappened)

            **What you expected**
            \(expectedBehavior)

            **Your setup**
            Wax \(about.appVersion) (\(about.build)) · \(about.osVersion)
            """
        }

        public mutating func reset() { whatHappened = ""; expectedBehavior = "" }
    }

    public static func issueURL(about: About) -> URL { issueURL(report: Draft(about: about).text) }

    public static func issueURL(report body: String) -> URL {
        var parts = URLComponents(string: "https://github.com/dylldev/wax-signer/issues/new")!
        parts.queryItems = [URLQueryItem(name: "labels", value: "bug"), URLQueryItem(name: "body", value: body)]
        return parts.url!
    }
}

/// When a shake may ask to report a problem. Anything else on screen wins; the shake then does nothing.
public enum ShakeGate {
    public struct Context: Equatable, Sendable {
        /// The report prompt is already showing.
        public var presenting: Bool
        /// A sheet, picker, alert or the first-run guide is showing.
        public var somethingOnTop: Bool
        /// A text field (a password, say) has the keyboard.
        public var editingText: Bool
        /// Signing or installing is under way.
        public var busy: Bool

        public init(presenting: Bool, somethingOnTop: Bool, editingText: Bool, busy: Bool) {
            self.presenting = presenting; self.somethingOnTop = somethingOnTop; self.editingText = editingText; self.busy = busy
        }
    }

    public static func shouldOpen(_ c: Context) -> Bool { !c.presenting && !c.somethingOnTop && !c.editingText && !c.busy }
}
