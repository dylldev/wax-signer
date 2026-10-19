import CredentialKit
import InstallKit
import SigningKit
import SwiftUI
import UIKit

/// What Wax can say about one certificate, from the imported profiles and any earlier test install.
@MainActor
enum IdentityReadiness {
    /// The kind of the first imported profile that fits this certificate, read from the profile itself. Nil when none fits.
    static func kindLabel(for cert: CertificateInfo, profiles: [ProfileInfo]) -> String? {
        let now = Date()
        let compatible = profiles.first { !CompatibilityReport.evaluate(certificate: cert, profile: $0, now: now).hasFailures }
        return compatible?.kind.title
    }

    static func status(for cert: CertificateInfo, profiles: [ProfileInfo], store: InstallTestStore = InstallTestStore()) -> IdentityStatus {
        let now = Date()
        let compatible = profiles.first { !CompatibilityReport.evaluate(certificate: cert, profile: $0, now: now).hasFailures }
        let kind: IdentityFacts.ProfileKind = switch compatible?.kind {
        case .development?: .development
        case .enterprise?: .enterprise
        case .appStore?: .appStore
        default: .adHoc
        }
        return IdentityStatus.evaluate(IdentityFacts(
            certificateValid: cert.validity(at: now) == .valid, hasCompatibleProfile: compatible != nil,
            profileExpired: compatible?.isExpired(at: now) ?? false, profileKind: kind,
            installTest: store.result(for: cert.sha1Fingerprint)))
    }
}

extension IdentityStatus {
    var pill: WaxPill {
        switch self {
        case .ready, .verified: WaxPill(text: label, tone: .ok)
        case .installFailed: WaxPill(text: label, tone: .warn)
        case .needsAttention: WaxPill(text: label, tone: .bad)
        }
    }
}

/// Signs and installs the tiny built-in Wax Probe app with one identity, then watches for it to appear.
/// Whether it installed is the real answer to "does this identity work on this phone".
@MainActor
final class IdentityTester: ObservableObject {
    enum State: Equatable {
        case idle
        case signing
        case uploading(Double)
        case waiting(secondsLeft: Int)
        case finished(InstallTestResult, String)
        case problem(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var testing: UUID?
    /// The identity the progress or result on screen belongs to.
    @Published private(set) var lastTested: UUID?

    private let probeScheme = URL(string: "waxprobe://")!
    private let waitSeconds = 90

    var isRunning: Bool { testing != nil }

    func test(_ cert: CertificateInfo, credentials: CredentialsModel, ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard testing == nil else { return }
        guard ota.isConfigured else { state = .problem("Set up the install server in Settings first."); return }
        guard !UIApplication.shared.canOpenURL(probeScheme) else {
            state = .problem("Wax Probe is already on this phone. Delete it from the home screen, then test again.")
            return
        }
        guard let probe = Bundle.main.url(forResource: "WaxProbe", withExtension: "ipa"), let store = credentials.store else {
            state = .problem("The test app is missing from this copy of Wax."); return
        }
        testing = cert.id
        lastTested = cert.id
        defer { testing = nil }
        state = .signing

        // Sign off the main thread, the same way a normal signing does.
        let profiles: [ProvisioningProfile] = store.profiles().compactMap { try? ProvisioningProfile.parse(try store.profileData(for: $0.id)) }
        let signed: URL
        do {
            signed = try await Task.detached { () throws -> URL in
                let identity = try SecurityFrameworkIdentity(identity: store.identity(for: cert.id))
                var options = SigningOptions(); options.keepBundleIdentifier = true
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Probe-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let out = dir.appendingPathComponent("probe-signed.ipa")
                do {
                    _ = try IPASigner.sign(ipa: probe, identity: identity, certificateTeamID: cert.teamID, profiles: ProfileSet(pool: profiles),
                                           options: options, output: out, workDirectory: dir)
                    return out
                } catch {
                    try? FileManager.default.removeItem(at: dir)
                    throw error
                }
            }.value
        } catch {
            state = .problem((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return
        }

        defer { try? FileManager.default.removeItem(at: signed.deletingLastPathComponent()) }   // the probe's signed copy is only needed for the upload
        let watcher = ota.$state.sink { [weak self] s in if case .uploading(let f) = s { self?.state = .uploading(f) } }
        defer { watcher.cancel() }
        guard let link = await ota.upload(ipa: signed, bundleIdentifier: "io.github.dylldev.wax.probe", version: "1.0", build: "1", title: "Wax Probe") else {
            if case .failed(let why) = ota.state { state = .problem(why) } else { state = .problem("The upload did not finish.") }
            return
        }
        open(link)

        // The test app registers its own link scheme, so it shows up here once iOS has installed it.
        for left in stride(from: waitSeconds, to: 0, by: -2) {
            state = .waiting(secondsLeft: left)
            if UIApplication.shared.canOpenURL(probeScheme) {
                InstallTestStore().set(.installed, for: cert.sha1Fingerprint)
                state = .finished(.installed, "It installed. Delete Wax Probe from your home screen when you like.")
                return
            }
            try? await Task.sleep(for: .seconds(2))
        }
        InstallTestStore().set(.failed, for: cert.sha1Fingerprint)
        state = .finished(.failed, "It didn't install. If you cancelled the prompt, test again.")
    }

    func forget(_ cert: CertificateInfo) { InstallTestStore().set(nil, for: cert.sha1Fingerprint); state = .idle }
    func dismiss() { if !isRunning { state = .idle } }
}
