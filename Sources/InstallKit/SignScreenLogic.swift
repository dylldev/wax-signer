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
    case reading, signing, preparing, uploading, handed

    /// The step the screen is on right now, or nil when Wax is not working.
    /// Reserving the host precedes signing; its preparing state must not hide active signing or reading.
    public static func resolve(reading: Bool, signing: Bool, uploading: Bool,
                               preparing: Bool = false, handed: Bool = false) -> SignStage? {
        if handed { return .handed }
        if uploading { return .uploading }
        if signing { return .signing }
        if reading { return .reading }
        if preparing { return .preparing }
        return nil
    }

    /// The stages one run passes through. A sign-only export never uploads or hands off, so it shows two.
    public static func sequence(exportOnly: Bool) -> [SignStage] {
        exportOnly ? [.reading, .signing] : allCases
    }

    public var title: String {
        switch self {
        case .reading: "Reading"
        case .signing: "Signing"
        case .uploading: "Uploading"
        case .preparing: "Preparing"
        case .handed: "Handed to iOS"
        }
    }

    /// A stage is done once a later one has started.
    public func isDone(current: SignStage) -> Bool {
        guard let mine = Self.allCases.firstIndex(of: self), let now = Self.allCases.firstIndex(of: current) else { return false }
        return mine < now
    }

    /// "Stage 2 of 3, Signing", for VoiceOver. `sequence` is the run's own list, so a sign-only run says two, not five.
    public func spoken(in sequence: [SignStage] = SignStage.allCases) -> String {
        let step = (sequence.firstIndex(of: self) ?? 0) + 1
        return "Stage \(step) of \(sequence.count), \(title)"
    }
}

/// How much of the melt to show. Only measured work counts: the run starts at 0, follows the signer's own
/// fraction, and reaches 1 only when the host really has the app. A reserved install session or an "installing"
/// flag is not progress, so neither may pin the melt at the end before signing has even started.
public enum SignProgress {
    public static func fraction(signFraction: Double, signed: Bool, uploading: Bool, uploadFraction: Double?,
                                handedToHost: Bool, exportOnly: Bool, remoteHost: Bool) -> Double {
        let sign = signed || uploading || handedToHost ? 1 : clamp(signFraction)
        if exportOnly { return sign }
        if remoteHost {
            let upload = uploading ? clamp(uploadFraction ?? 0) : (handedToHost ? 1 : 0)
            return (sign + upload) / 2
        }
        // On this iPhone the last stretch is the handoff, so signing alone stops just short of the end.
        return handedToHost ? 1 : sign * 0.92
    }

    private static func clamp(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        return min(1, max(0, value))
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
    case needProfile
    case needServer
    case install

    public static func resolve(hasApp: Bool, hasCertificates: Bool, certificateChosen: Bool,
                               inputIsInstallable: Bool, serverReady: Bool, hasProfiles: Bool = true) -> SignPrimary {
        guard hasApp else { return .needApp }
        if certificateChosen && !hasProfiles { return .needProfile }
        if !certificateChosen && !inputIsInstallable { return .needIdentity(canImport: !hasCertificates) }
        return serverReady ? .install : .needServer
    }

    public var title: String {
        switch self {
        case .needApp: "Choose an app"
        case .needIdentity(let canImport): canImport ? "Import signing files" : "Choose an identity"
        case .needProfile: "Import a profile"
        case .needServer: "Set up installation"
        case .install: "Sign & Install"
        }
    }

    public var reason: String {
        switch self {
        case .needApp: "Pick an IPA to sign."
        case .needIdentity(let canImport):
            canImport ? "Bring your own .p12 certificate and .mobileprovision profile. Wax does not provide them." : "Pick the certificate to sign with."
        case .needProfile: "Choose the matching .mobileprovision file."
        case .needServer: "Choose This iPhone, My server or Bucket in Settings."
        case .install: "Signs the app, uploads it, and asks iOS to install."
        }
    }

    /// The button does something useful in every state except while it only points at a missing step.
    public var isSigning: Bool { self == .install }
}
