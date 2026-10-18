import Foundation

/// What the Sign screen shows next to the action buttons. Busy wins over an error, an error over a result.
public enum SignPhase: Equatable, Sendable {
    case idle, signing, failed, done

    public static func resolve(busy: Bool, hasError: Bool, hasReport: Bool) -> SignPhase {
        if busy { return .signing }
        if hasError { return .failed }
        return hasReport ? .done : .idle
    }
}

/// Whether the install-server setup is shown, and how.
public enum InstallSetupPanel: Equatable, Sendable {
    /// A test install with this identity did not complete, so uploading would only mislead.
    case hidden
    /// `collapsed`: setup is complete, show a one-line summary. `eligibilityUnknown`: this identity has not been
    /// test-installed on this phone yet, so say it may not install.
    case show(collapsed: Bool, eligibilityUnknown: Bool)

    public static func resolve(testResult: InstallTestResult?, setupComplete: Bool) -> InstallSetupPanel {
        testResult == .failed ? .hidden : .show(collapsed: setupComplete, eligibilityUnknown: testResult == nil)
    }
}

/// What the main button on the Sign screen does and says, and the one-line reason shown under it.
public enum SignPrimary: Equatable, Sendable {
    case needApp
    case needIdentity(canImport: Bool)
    case needServer
    case install

    public static func resolve(hasApp: Bool, hasCertificates: Bool, certificateChosen: Bool,
                               inputIsInstallable: Bool, serverReady: Bool) -> SignPrimary {
        guard hasApp else { return .needApp }
        if !certificateChosen && !inputIsInstallable { return .needIdentity(canImport: !hasCertificates) }
        return serverReady ? .install : .needServer
    }

    public var title: String {
        switch self {
        case .needApp: "Choose an app"
        case .needIdentity(let canImport): canImport ? "Import credentials" : "Choose an identity"
        case .needServer: "Set up install server"
        case .install: "Sign & Install"
        }
    }

    public var reason: String {
        switch self {
        case .needApp: "Pick an IPA to sign."
        case .needIdentity(let canImport):
            canImport ? "Import a certificate and provisioning profile first." : "Pick the certificate to sign with."
        case .needServer: "Wax uploads to your own HTTPS server, then asks iOS to install."
        case .install: "Signs the app, uploads it, and asks iOS to install."
        }
    }

    /// The button does something useful in every state except while it only points at a missing step.
    public var isSigning: Bool { self == .install }
}
