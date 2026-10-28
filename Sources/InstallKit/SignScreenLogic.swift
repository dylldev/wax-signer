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

/// The step Wax is on while it works. Ticked in order under the melting wax, so the wait says where it is.
public enum SignStage: String, Equatable, Sendable, CaseIterable {
    case reading, signing, uploading

    /// The step the screen is on right now, or nil when Wax is not working.
    public static func resolve(reading: Bool, signing: Bool, uploading: Bool) -> SignStage? {
        if uploading { return .uploading }
        if signing { return .signing }
        if reading { return .reading }
        return nil
    }

    public var title: String {
        switch self {
        case .reading: "Reading"
        case .signing: "Signing"
        case .uploading: "Uploading"
        }
    }

    /// A stage is done once a later one has started.
    public func isDone(current: SignStage) -> Bool {
        guard let mine = Self.allCases.firstIndex(of: self), let now = Self.allCases.firstIndex(of: current) else { return false }
        return mine < now
    }

    /// "Stage 2 of 3, Signing", for VoiceOver.
    public var spoken: String {
        let step = (Self.allCases.firstIndex(of: self) ?? 0) + 1
        return "Stage \(step) of \(Self.allCases.count), \(title)"
    }
}

/// One step of the Sign screen's setup card: what it needs, and what to do about it while it is missing.
/// Once the step is set, the row shows the value instead of these words.
public struct SignSetupStep: Equatable, Sendable {
    public let icon: String
    public let title: String
    public let detail: String

    public init(icon: String, title: String, detail: String) {
        self.icon = icon; self.title = title; self.detail = detail
    }
}

/// The three things signing needs. With nothing set up, the Sign screen's card reads as a checklist of these.
public enum SignSetupChecklist {
    public static let app = SignSetupStep(icon: "shippingbox", title: "No app chosen", detail: "Pick an IPA from Files")
    public static let identity = SignSetupStep(icon: "key", title: "Add your signing files", detail: "A .p12 certificate and .mobileprovision profile")
    public static let host = SignSetupStep(icon: "icloud.and.arrow.up", title: "Set up an install host", detail: "This iPhone or your own server")

    public static var steps: [SignSetupStep] { [app, identity, host] }

    /// First run: nothing is set up, so all three lines say what to do.
    public static func isFirstRun(hasApp: Bool, hasIdentity: Bool, hostReady: Bool) -> Bool {
        !(hasApp || hasIdentity || hostReady)
    }
}

/// Whether the install-server setup is shown, and how.
public enum InstallSetupPanel: Equatable, Sendable {
    /// Retained for API compatibility; a probe timeout alone must not hide delivery/retry setup.
    case hidden
    /// `collapsed`: setup is complete, show a one-line summary. `eligibilityUnknown`: this identity has not been
    /// independently verified for the current configuration, so say it may not install.
    case show(collapsed: Bool, eligibilityUnknown: Bool)

    public static func resolve(testResult: InstallTestResult?, setupComplete: Bool) -> InstallSetupPanel {
        // A legacy scheme observation has no profile/OS/time binding and cannot establish eligibility.
        .show(collapsed: setupComplete, eligibilityUnknown: true)
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
        case .needIdentity(let canImport): canImport ? "Import signing files" : "Choose an identity"
        case .needServer: "Set up installation"
        case .install: "Sign & Install"
        }
    }

    public var reason: String {
        switch self {
        case .needApp: "Pick an IPA to sign."
        case .needIdentity(let canImport):
            canImport ? "Bring your own .p12 certificate and .mobileprovision profile. Wax does not provide them." : "Pick the certificate to sign with."
        case .needServer: "Choose This iPhone, My server or Bucket in Settings."
        case .install: "Signs the app, uploads it, and asks iOS to install."
        }
    }

    /// The button does something useful in every state except while it only points at a missing step.
    public var isSigning: Bool { self == .install }
}
