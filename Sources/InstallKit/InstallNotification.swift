import Foundation

/// The local notification Wax sends when a signed app is ready, and the identifiers the background task uses.
public enum InstallNotification {
    public struct Content: Equatable {
        public let title: String
        public let body: String
        public let userInfo: [String: String]
    }

    private static let linkKey = "waxInstallLink"

    public static func readyToInstall(appTitle: String, link: URL) -> Content {
        Content(title: "Ready to install", body: "\(name(appTitle)) is signed and uploaded. Tap to install.",
                userInfo: [linkKey: link.absoluteString])
    }

    public static func halfway(appTitle: String) -> Content {
        Content(title: "50% done", body: "\(name(appTitle)) is halfway signed.", userInfo: [:])
    }

    public static func signed(appTitle: String) -> Content {
        Content(title: "Signed", body: "\(name(appTitle)) is signed. Tap to export it.", userInfo: [:])
    }

    /// The link from a tapped notification, only if it is an `itms-services` link to an https manifest.
    /// Anything else in a notification's data is ignored.
    public static func link(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let text = userInfo[linkKey] as? String, let url = URL(string: text), url.scheme == "itms-services",
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.queryItems?.first(where: { $0.name == "action" })?.value == "download-manifest",
              let manifest = c.queryItems?.first(where: { $0.name == "url" })?.value,
              URL(string: manifest)?.scheme == "https" else { return nil }
        return url
    }

    /// One fixed identifier: it is registered at launch and listed in Info.plist, and iOS only accepts a task
    /// request whose identifier matches a registered one exactly. Wax signs one app at a time.
    public static func taskIdentifier(bundleID: String) -> String { "\(bundleID).signing" }

    private static func name(_ title: String) -> String { title.isEmpty ? "Your app" : title }
}
