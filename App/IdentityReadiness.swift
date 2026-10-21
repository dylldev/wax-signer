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
/// Scheme detection is an observation of the probe, not proof of launch or general installation eligibility.
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
    private var operationID: UUID?
    private var operation: Task<Void, Never>?
    private var reservation: (OTAInstallModel, OTAInstallModel.Session)?
    /// Failed/canceled probe outputs are retained in app-owned storage, not deleted while a host may read them.
    /// They contain only the synthetic probe, never an imported user's IPA.
    @Published private(set) var retainedArtifacts: [URL] = []

    var isRunning: Bool { testing != nil }

    func test(_ cert: CertificateInfo, credentials: CredentialsModel, ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard let probe = Bundle.main.url(forResource: "WaxProbe", withExtension: "ipa"), let store = credentials.store else {
            if !isRunning { state = .problem("The test app is missing from this copy of Wax.") }; return
        }
        let cancellation = SigningCancellation()
        await run(identityID: cert.id, fingerprint: cert.sha1Fingerprint, ota: ota, sign: {
            // This worker is retained until completion. Cancellation never deletes a partially committed R2 output.
            let worker = Task.detached { () throws -> URL in
                try Task.checkCancellation()
                let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Install/Probes/\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                var directory = dir; var values = URLResourceValues(); values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                let out = dir.appendingPathComponent("probe-signed.ipa")
                try Self.signProbe(probe, store: store, certificateID: cert.id, certificateTeamID: cert.teamID,
                                   output: out, workDirectory: dir, cancellation: cancellation)
                return out
            }
            return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel(); cancellation.cancel() })
        }, detected: { UIApplication.shared.canOpenURL(self.probeScheme) }, cancelSigning: { cancellation.cancel() }, open: open)
    }

    /// Explicit Test consent signs the fixed source-built probe without a user-edit preview. It still uses
    /// the same production CMS policy and frozen transaction as normal signing, with the R8 owner token.
    nonisolated static func signProbe(_ probe: URL, store: CredentialStore, certificateID: UUID, certificateTeamID: String?,
                                     output: URL, workDirectory: URL, cancellation: SigningCancellation) throws {
        try cancellation.check()
        let profiles = try store.profiles().map { try ProvisioningProfile.parse(store.profileData(for: $0.id)) }
        let identity = try SecurityFrameworkIdentity(identity: store.identity(for: certificateID))
        var options = SigningOptions(); options.keepBundleIdentifier = true; options.cancellation = cancellation
        let prepared = try PreparedIPA.prepare(ipa: probe, certificateChainDER: identity.certificateChainDER,
            certificateTeamID: certificateTeamID, profiles: ProfileSet(pool: profiles), options: options, workDirectory: workDirectory)
        defer { prepared.discard() }
        _ = try prepared.execute(identity: identity, output: output)
    }

    /// Deterministic lifecycle seam: production signs a frozen probe and checks the system's probe scheme.
    func run(identityID: UUID, fingerprint: String, ota: OTAInstallModel,
             sign: @escaping @Sendable () async throws -> URL,
             detected: @escaping () -> Bool,
             cancelSigning: @escaping () -> Void = {},
             background: BackgroundJob? = nil,
             record: @escaping (InstallTestResult, String) -> Void = { InstallTestStore().set($0, for: $1) },
             pause: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(2)) },
             seconds: Int = 90, open: @escaping (URL) -> Void) async {
        guard !isRunning, !Task.isCancelled else { return }
        let session: OTAInstallModel.Session
        do { session = try ota.reserve() }
        catch { state = .problem(error.localizedDescription); return }
        ota.onRelease(of: session, perform: cancelSigning)
        guard !detected() else {
            ota.release(session)
            state = .problem("Wax Probe is already on this phone. Delete it from the home screen, then test again."); return
        }
        let generation = UUID(); operationID = generation
        testing = identityID; lastTested = identityID; reservation = (ota, session); state = .signing
        let background = background ?? .shared
        let backgroundID = background.begin(title: "Wax Probe", onExpiration: { [weak self] in self?.cancel(generation) })
        guard operationID == generation else { background.end(backgroundID, success: false); return }
        let task = Task {
            var observed = false
            defer {
                background.end(backgroundID, success: observed)
                ota.release(session)
                if operationID == generation { testing = nil; reservation = nil; operation = nil; operationID = nil }
            }
            do {
                let signed = try await sign()
                // Always keep a finished output even if a canceled worker was slow to return.
                retainedArtifacts.append(signed)
                try Task.checkCancellation()
                guard operationID == generation, ota.owns(session) else { return }
                let watcher = ota.$state.sink { [weak self] state in
                    guard let self, self.operationID == generation, ota.owns(session) else { return }
                    if case .uploading(let fraction) = state { self.state = .uploading(fraction) }
                }
                defer { watcher.cancel() }
                guard let link = await ota.upload(ipa: signed, bundleIdentifier: "io.github.dylldev.wax.probe", version: "1.0", build: "1", title: "Wax Probe", session: session),
                      operationID == generation, ota.owns(session), !Task.isCancelled else {
                    if operationID == generation {
                        if case .failed(let reason) = ota.state { state = .problem(reason) }
                        else { state = .problem("The upload did not finish. The signed probe is retained.") }
                    }
                    return
                }
                open(link)
                let delivery = Task { await ota.finishPhoneTransfer(session: session, releaseWhenFinished: false) }
                defer { delivery.cancel() }
                for left in stride(from: max(0, seconds), to: 0, by: -2) {
                    try Task.checkCancellation()
                    guard operationID == generation, ota.owns(session) else {
                        if operationID == generation { state = .problem("The test delivery ended. No installation result was recorded.") }; return
                    }
                    state = .waiting(secondsLeft: left)
                    if detected() {
                        observed = true
                        record(.installed, fingerprint)
                        state = .finished(.installed, InstallProbeMessaging.detected)
                        return
                    }
                    try await pause()
                }
                try Task.checkCancellation()
                guard operationID == generation, ota.owns(session) else { return }
                record(.failed, fingerprint)
                state = .finished(.failed, InstallProbeMessaging.notDetected)
            } catch {
                guard operationID == generation else { return }
                state = .problem(Task.isCancelled || error is CancellationError
                    ? "Test canceled. Signed IPA files are kept."
                    : ((error as? LocalizedError)?.errorDescription ?? "The test could not finish. Retry with the retained signed probe."))
            }
        }
        operation = task
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: {
            task.cancel()
            Task { @MainActor [weak self] in self?.cancel(generation) }
        })
    }

    private func cancel(_ generation: UUID) {
        guard operationID == generation else { return }
        operationID = nil; operation?.cancel(); operation = nil
        if let (ota, session) = reservation { ota.cancel(session) }
        reservation = nil; testing = nil; state = .problem("Test canceled. Signed IPA files are kept.")
    }
    func cancel() { if let generation = operationID { cancel(generation) } }
    func forget(_ cert: CertificateInfo) {
        guard !isRunning else { return }
        InstallTestStore().set(nil, for: cert.sha1Fingerprint); state = .idle
    }
    func dismiss() { if !isRunning { state = .idle } }
}
