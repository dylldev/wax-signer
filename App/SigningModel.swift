import CredentialKit
import Foundation
import InstallKit
import IPAKit
import SigningKit
import UIKit

/// Drives the Sign screen. All heavy work runs off the main thread; every failure ends in `errorText`.
@MainActor
final class SigningModel: ObservableObject {
    struct Report {
        var archiveLines: [String]
        var checkSummary: String
        var checkFailures: [String]
        var profileLines: [String]
        var warnings: [String]
        var output: URL
        var outputSize: Int
        var installTarget: InstallTarget
    }

    @Published private(set) var ipaName: String?
    @Published private(set) var ipaInfo: IPAMetadata?
    /// A result belongs to the settings it was made with; changing them clears it so a stale file cannot be exported.
    @Published var certificateID: UUID? { didSet { if certificateID != oldValue { clearResult() } } }
    /// UI preference only; does not affect how signing works.
    /// On by default: profiles with a fixed app ID are common, and other signers re-label the app for you too.
    @Published var rewriteBundleID = UserDefaults.standard.object(forKey: "rewriteBundleID") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rewriteBundleID, forKey: "rewriteBundleID"); if rewriteBundleID != oldValue { clearResult() } }
    }
    /// Keep the app's own bundle ID and sign under the profile's application ID, as other signers do.
    /// On by default: verified on iOS 27.2 that a Distribution profile with a fixed app ID installs and launches
    /// an app under its own bundle ID. iOS has the final say for other profiles.
    @Published var keepBundleID = UserDefaults.standard.object(forKey: "keepBundleID") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepBundleID, forKey: "keepBundleID"); if keepBundleID != oldValue { clearResult() } }
    }
    /// Extra changes made to the app before signing. The switches start from the saved defaults.
    @Published var edits: AppEdits = SigningModel.loadDefaultEdits()
    private static let editsKey = "signing.defaultEdits"
    private static func loadDefaultEdits() -> AppEdits {
        UserDefaults.standard.data(forKey: editsKey).flatMap { try? JSONDecoder().decode(AppEdits.self, from: $0) } ?? AppEdits()
    }
    func saveEditsAsDefaults() {
        if let data = try? JSONEncoder().encode(edits.defaultsOnly()) { UserDefaults.standard.set(data, forKey: Self.editsKey) }
    }
    func resetEditsToDefaults() { edits = Self.loadDefaultEdits() }

    /// The profile to sign the app with, or nil for "automatic" (Wax picks the best fit).
    @Published var profileChoice: UUID?
    /// A chosen entitlements file (a property list) that replaces the app's own; per app, never kept.
    @Published private(set) var customEntitlements: [String: Any]?
    @Published private(set) var customEntitlementsName: String?

    /// Reads a chosen entitlements file. Throws a plain message when it is not a property list of entitlements.
    func setEntitlements(from url: URL?) throws {
        guard let url else { customEntitlements = nil; customEntitlementsName = nil; return }
        defer { discardPickerCopy(url) }
        let data = try Data(contentsOf: url)
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any], !dict.isEmpty else {
            throw EntitlementsFileError.notEntitlements
        }
        customEntitlements = dict
        customEntitlementsName = url.lastPathComponent
    }

    struct EntitlementsFileError: LocalizedError {
        static let notEntitlements = EntitlementsFileError()
        var errorDescription: String? { "That file is not an entitlements property list (a .plist or .entitlements file with keys and values)." }
    }

    @Published private(set) var busyMessage: String?
    /// How far through signing the app really is (0...1), from the engine's own stages.
    @Published private(set) var signFraction: Double = 0
    @Published private(set) var report: Report?
    @Published private(set) var errorText: String?

    private var ipaURL: URL?
    private var signStarted: Date?
    /// How long the last signing run took, for the progress estimate.
    private(set) var lastSignSeconds: Double = 0
    private let credentials: CredentialsModel

    init(credentials: CredentialsModel) { self.credentials = credentials }

    /// Weights signing against uploading by how long each took on earlier runs (or sensible defaults).
    func jobProgress(uploadFraction: Double, exportOnly: Bool) -> JobProgress {
        let mb = Double((try? ipaURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
        let e = JobEstimator(store: UserDefaults.standard).estimate(megabytes: max(mb, 1))
        return JobProgress(signSeconds: e.sign, uploadSeconds: exportOnly ? 0 : e.upload)
    }

    func clearResult() { report = nil; errorText = nil; readyLink = nil }

    enum BundleIDMode: String, CaseIterable { case keep, rename }

    /// One choice in place of two switches: keep the app's own bundle ID, or rename it to fit a fixed-ID profile.
    var bundleIDMode: BundleIDMode {
        get { keepBundleID ? .keep : .rename }
        set { keepBundleID = newValue == .keep; if newValue == .rename { rewriteBundleID = true } }
    }

    /// The chosen IPA itself, when it is already signed and carries a profile (installed exactly as it is).
    var signedInputTarget: InstallTarget? {
        guard let info = ipaInfo, info.hasCodeSignature, info.hasEmbeddedProfile, let ipaURL else { return nil }
        return InstallTarget(ipa: ipaURL, bundleIdentifier: info.bundleIdentifier, version: info.version, build: info.build,
                             title: info.displayName)
    }

    /// The install link of the last upload, kept so the Install button still works after a cancelled prompt.
    @Published private(set) var readyLink: URL?
    /// True from the tap on Sign & Install until the app has been handed over (or failed), so a second install cannot start.
    @Published private(set) var installing = false

    /// One tap: sign with the chosen certificate (when there is one), then upload and hand the app to iOS.
    /// Nothing is uploaded unless signing succeeded and its self-check passed. Keeps going if Wax is sent to the
    /// background, and posts a notification when the app is ready to install.
    func signAndInstall(ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard !installing else { return }
        installing = true
        let job = BackgroundJob.shared
        job.askForNotificationPermission()
        job.begin(title: ipaInfo?.displayName ?? "Wax")
        var succeeded = false
        defer { job.end(success: succeeded); installing = false }
        readyLink = nil

        let target: InstallTarget?
        if certificateID != nil {
            guard let task = sign(standalone: false, storeBigFiles: ota.hostKind == .phone) else { return }
            await task.value
            guard let r = report, r.checkFailures.isEmpty else { return }
            if BundleIDGuard.replacesRunningWax(originalID: ipaInfo?.bundleIdentifier ?? "",
                                                finalID: r.installTarget.bundleIdentifier,
                                                runningID: Bundle.main.bundleIdentifier) {
                ota.block(BundleIDGuard.explanation)
                return
            }
            target = r.installTarget
        } else {
            target = signedInputTarget
            // Installing an already-signed app under Wax's own ID would replace the running Wax, same as a re-label
            // would. A signed copy of Wax itself (same executable) is an update, not a clash; a different app that
            // merely carries one of Wax's IDs is not.
            let isWaxItself = ipaInfo?.executable == Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            if let t = target, !isWaxItself,
               t.bundleIdentifier == Bundle.main.bundleIdentifier {
                ota.block(BundleIDGuard.explanation)
                return
            }
        }
        guard let target else { return }

        // Mirror the upload's real progress into the system's background progress.
        let weights = jobProgress(uploadFraction: 0, exportOnly: false)
        let watcher = ota.$state.sink { state in
            if case .uploading(let f) = state { job.update(fraction: weights.overall(sign: 1, upload: f), subtitle: "Sending to your server") }
        }
        defer { watcher.cancel() }

        let uploadStart = Date()
        guard let link = await ota.upload(ipa: target.ipa, bundleIdentifier: target.bundleIdentifier,
                                          version: target.version, build: target.build, title: target.title) else { return }
        let megabytes = Double((try? target.ipa.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
        var estimator = JobEstimator(store: UserDefaults.standard)
        estimator.record(megabytes: megabytes, signSeconds: certificateID != nil ? lastSignSeconds : 0,
                         uploadSeconds: Date().timeIntervalSince(uploadStart))
        readyLink = link
        if UIApplication.shared.applicationState == .active {
            open(link)
        } else {
            job.notifyIfInBackground(InstallNotification.readyToInstall(appTitle: target.title, link: link))
        }
        // The phone serves the file itself, so it must stay alive (also in the background) until iOS has it all.
        job.update(fraction: 1, subtitle: "Waiting for iOS to take the app")
        succeeded = await ota.finishPhoneTransfer()
        if ota.hostKind == .phone { readyLink = nil }      // the listener is closed now; the link no longer works
    }

    var canSignAndInstall: Bool {
        busyMessage == nil && !installing && ipaInfo != nil && (certificateID != nil || signedInputTarget != nil)
    }

    var canSign: Bool { ipaInfo != nil && certificateID != nil && busyMessage == nil }

    // MARK: Choosing the IPA

    /// Chooses an IPA already on the shelf.
    func use(_ entry: LibraryEntry) {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Pick-\(UUID().uuidString).ipa")
        guard (try? FileManager.default.copyItem(at: LibraryModel.shared.url(for: entry), to: copy)) != nil else {
            errorText = "That file is no longer in Wax's library."
            LibraryModel.shared.refresh()
            return
        }
        picked(ipa: copy, fromLibrary: entry)
    }

    func picked(ipa url: URL, fromLibrary: LibraryEntry? = nil) {
        report = nil
        errorText = nil
        ipaInfo = nil
        edits = edits.defaultsOnly()          // name, version and ID belong to the last app
        profileChoice = nil; customEntitlements = nil; customEntitlementsName = nil
        ipaName = url.lastPathComponent
        busyMessage = "Reading “\(url.lastPathComponent)”…"
        ImportLogs.shared.log("sign: picked \(ImportLog.describe(url))")
        // Keep our own copy: the picker's copy is removed when this call returns.
        let model = self
        Task.detached {
            do {
                // A folder of its own per pick, so two quick picks cannot delete each other's file.
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Input-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
                let dest = kept.appendingPathComponent("input.ipa")
                try FileManager.default.moveItem(at: url, to: dest)
                let info = try IPAInspector.inspect(url: dest)
                await MainActor.run {
                    if let old = model.ipaURL { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()) }
                    model.ipaURL = dest
                    model.ipaInfo = info
                    model.busyMessage = nil
                    if fromLibrary == nil { LibraryModel.shared.file(dest, info: info) }
                }
            } catch {
                ImportLogs.shared.log("sign: ipa rejected \(ImportLog.describe(error))")
                await MainActor.run {
                    model.busyMessage = nil
                    model.errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    // MARK: Signing

    @discardableResult
    /// `storeBigFiles` writes changed big files uncompressed: right for an install that stays on this phone, wrong for
    /// anything uploaded or exported.
    func sign(standalone: Bool = true, storeBigFiles: Bool = false) -> Task<Void, Never>? {
        guard let ipaURL, let info = ipaInfo, let certificateID, let store = credentials.store,
              let cert = credentials.certificates.first(where: { $0.id == certificateID }) else { return nil }
        report = nil
        errorText = nil
        busyMessage = "Preparing…"
        let title = info.displayName.isEmpty ? "Wax" : info.displayName
        if standalone {
            BackgroundJob.shared.askForNotificationPermission()
            BackgroundJob.shared.begin(title: title)
        }
        let weights = jobProgress(uploadFraction: 0, exportOnly: standalone)
        let rewrite = rewriteBundleID
        let appEdits = edits
        let chosenProfile = profileChoice
        let entitlementsOverride = customEntitlements
        let keep = keepBundleID
        let model = self
        ImportLogs.shared.log("sign: start id=\(ipaInfo?.bundleIdentifier ?? "?") rewrite=\(rewrite)")

        signFraction = 0
        signStarted = Date()
        let throttle = ProgressThrottle()
        return Task.detached(priority: .userInitiated) {
            do {
                let identity = try SecurityFrameworkIdentity(identity: store.identity(for: certificateID))

                // Every imported, still-valid profile is a candidate; the engine picks per bundle and says why.
                var pool: [ProvisioningProfile] = []
                var skipped: [String] = []
                for info in store.profiles() {
                    do { pool.append(try ProvisioningProfile.parse(try store.profileData(for: info.id))) }
                    catch { skipped.append("\(info.name): \((error as? LocalizedError)?.errorDescription ?? "unreadable")") }
                }

                var options = SigningOptions()
                options.rewriteBundleIdentifier = rewrite
        options.keepBundleIdentifier = keep
        options.overrideEntitlements = entitlementsOverride

                let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Signed", isDirectory: true)
                try? FileManager.default.removeItem(at: outDir)
                let stem = (info.displayName.isEmpty ? "App" : info.displayName)
                    .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                let output = outDir.appendingPathComponent("\(stem.isEmpty ? "App" : stem)-signed.ipa")

                let outcome = try IPASigner.sign(
                    ipa: ipaURL, identity: identity, certificateTeamID: cert.teamID,
                    profiles: try ProfileSet(pool: pool, overrides: Self.overrides(chosen: chosenProfile, store: store)),
                    options: options, edits: appEdits, output: output,
                    workDirectory: FileManager.default.temporaryDirectory,
                    compressChangedFiles: !storeBigFiles      // only an install that stays on this phone skips compressing; uploads and exports stay small
                ) { p in
                    // The engine reports often; only pass on a visible change.
                    guard throttle.shouldPublish(p) else { return }
                    Task { @MainActor in
                        model.busyMessage = p.message; model.signFraction = p.fraction
                        BackgroundJob.shared.update(fraction: weights.overall(sign: p.fraction, upload: 0), subtitle: p.message)
                    }
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: outcome.output.path)[.size] as? Int) ?? 0
                var profileLines = outcome.signing.profileSelections.map { sel -> String in
                    "\(sel.bundlePath == "." ? "App" : sel.bundlePath) → “\(sel.profileName)” · \(Self.describe(sel.signatureStatus))"
                }
                profileLines += skipped.map { "Skipped \($0)" }
                var archive = [
                    "Input: \(outcome.inputArchive.displayName) \(outcome.inputArchive.version) (\(outcome.inputArchive.build)), \(outcome.inputArchive.entryCount) files",
                    "Output: \(outcome.outputArchive.entryCount) files, signature files present: \(outcome.outputArchive.hasCodeSignature ? "yes" : "no")",
                ]
                archive += outcome.editNotes
                if keep, let first = outcome.signing.profileSelections.first {
                    archive.append("Bundle IDs kept. Signed under the profile “\(first.profileName)”; iOS decides whether it accepts the app.")
                }
                for (old, new) in outcome.signing.bundleIdentifierChanges.sorted(by: { $0.key < $1.key }) {
                    archive.append("Bundle ID changed: \(old) → \(new)")
                }
                let r = Report(
                    archiveLines: archive,
                    checkSummary: outcome.selfCheck.passed
                        ? "Passed \(outcome.selfCheck.checks.count) consistency checks"
                        : "FAILED \(outcome.selfCheck.failures.count) of \(outcome.selfCheck.checks.count)",
                    checkFailures: outcome.selfCheck.failures.map { "\($0.name) \($0.detail)" },
                    profileLines: profileLines, warnings: outcome.signing.warnings,
                    output: outcome.output, outputSize: size,
                    installTarget: InstallTarget(
                        ipa: outcome.output, bundleIdentifier: outcome.outputArchive.bundleIdentifier,
                        version: outcome.outputArchive.version, build: outcome.outputArchive.build, title: outcome.outputArchive.displayName))
                ImportLogs.shared.log("sign: ok items=\(outcome.signing.items.count) bytes=\(size)")
                await MainActor.run {
                    model.lastSignSeconds = Date().timeIntervalSince(model.signStarted ?? Date())
                    model.report = r; model.busyMessage = nil
                    LibraryModel.shared.file(outcome.output, info: outcome.outputArchive, signed: true)
                    if standalone {
                        BackgroundJob.shared.end(success: true)
                        BackgroundJob.shared.notifyIfInBackground(InstallNotification.signed(appTitle: title))
                    }
                }
            } catch {
                let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ImportLogs.shared.log("sign: failed \(ImportLog.describe(error))")
                await MainActor.run {
                    model.errorText = text; model.busyMessage = nil
                    if standalone { BackgroundJob.shared.end(success: false) }
                }
            }
        }
    }

    /// Pins the main app to the profile the user chose; empty (automatic) when none was chosen.
    nonisolated static func overrides(chosen: UUID?, store: CredentialStore) throws -> [String: ProvisioningProfile] {
        guard let chosen else { return [:] }
        return ["." : try ProvisioningProfile.parse(try store.profileData(for: chosen))]
    }

    nonisolated static func describe(_ status: ProfileSignatureStatus) -> String {
        switch status {
        case .appleChainVerified: return "signed by an Apple chain"
        case .signatureValidButUntrusted: return "profile signature intact but not shown to be Apple's"
        case .invalid(let why): return "profile signature invalid (\(why))"
        }
    }
}

/// Lets a progress report through when the message changes or it moved by at least one percent.
/// Called from several worker threads at once while unpacking, so the state is guarded.
private final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last: SigningProgress?
    func shouldPublish(_ p: SigningProgress) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let publish = shouldStore(p)
        if publish { last = p }
        return publish
    }
    private func shouldStore(_ p: SigningProgress) -> Bool {
        guard let last else { return true }
        return last.message != p.message || p.fraction - last.fraction >= 0.01
    }
}
