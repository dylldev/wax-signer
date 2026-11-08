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
    @Published var edits: AppEdits = SigningModel.loadDefaultEdits() { didSet { if edits != oldValue { clearResult() } } }
    private static let editsKey = "signing.defaultEdits"
    private static func loadDefaultEdits() -> AppEdits {
        UserDefaults.standard.data(forKey: editsKey).flatMap { try? JSONDecoder().decode(AppEdits.self, from: $0) } ?? AppEdits()
    }
    func saveEditsAsDefaults() {
        if let data = try? JSONEncoder().encode(edits.defaultsOnly()) { UserDefaults.standard.set(data, forKey: Self.editsKey) }
    }
    func resetEditsToDefaults() { edits = Self.loadDefaultEdits() }

    /// The profile to sign the app with, or nil for "automatic" (Wax picks the best fit).
    @Published var profileChoice: UUID? { didSet { if profileChoice != oldValue { clearResult() } } }
    /// A chosen entitlements file (a property list) that replaces the app's own; per app, never kept.
    @Published private(set) var customEntitlements: [String: Any]?
    @Published private(set) var customEntitlementsName: String?
    @Published private(set) var passportReport: SigningPreflightReport?

    /// Reads a chosen entitlements file. Throws a plain message when it is not a property list of entitlements.
    func setEntitlements(from url: URL?) throws {
        guard let url else { customEntitlements = nil; customEntitlementsName = nil; clearResult(); return }
        defer { discardPickerCopy(url) }
        let data = try Data(contentsOf: url)
        guard let dict = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any], !dict.isEmpty else {
            throw EntitlementsFileError.notEntitlements
        }
        customEntitlements = dict
        customEntitlementsName = url.lastPathComponent
        clearResult()
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
    private var preparedSigning: PreparedIPASigning?
    private var inputRevision = UUID()
    private var activeSigningRun: UUID?
    private var signStarted: Date?
    /// How long the last signing run took, for the progress estimate.
    private(set) var lastSignSeconds: Double = 0
    private let credentials: CredentialsModel
    private let library: LibraryModel
    let background: BackgroundJob

    init(credentials: CredentialsModel, library: LibraryModel? = nil, background: BackgroundJob? = nil) {
        self.credentials = credentials; self.library = library ?? .shared; self.background = background ?? .shared
        IPASigner.removeStalePreparations()
    }

    /// Where the last signed IPA stands on the shelf. A failed save never loses the signed file (see `retrySignedSave`).
    @Published private(set) var shelfSaveState: LibraryModel.SaveState = .idle
    private var signedPendingID: UUID?
    @Published private(set) var runningSign = false

    /// Called once signing has passed its self-check: keeps the report and commits the retained artifact to the shelf.
    func acceptSignedResult(_ result: Report, pendingID: UUID, generation: UUID? = nil, revision: UUID? = nil) async {
        // A result belongs to the input it was made from. If that changed while the file was being saved, drop it:
        // the retained artifact stays in the library's recovery list instead of replacing the current operation.
        if let revision, revision != inputRevision { return }
        report = result; signedPendingID = pendingID
        await retrySignedSave()
    }

    func retrySignedSave() async {
        guard let id = signedPendingID, report != nil, !shelfSaveState.isSaving else { return }
        shelfSaveState = .saving
        do {
            let saved = try await library.finishPending(id)
            guard signedPendingID == id else { return }
            relocateReport(to: library.url(for: saved.entry))
            shelfSaveState = .saved(saved)
        } catch {
            guard signedPendingID == id, let report else { return }
            let file = (error as? ShelfSaveFailure)?.artifact ?? report.output
            relocateReport(to: file)
            shelfSaveState = .failed((error as? ShelfSaveFailure) ?? ShelfSaveFailure(reason: error.localizedDescription, artifact: file, pendingID: id))
        }
    }

    private func relocateReport(to file: URL) {
        guard var result = report else { return }
        let old = result.installTarget
        result.output = file
        result.installTarget = InstallTarget(ipa: file, bundleIdentifier: old.bundleIdentifier, version: old.version, build: old.build, title: old.title)
        report = result
    }

    func ownsInstallation(_ ota: OTAInstallModel) -> Bool { installSession.map { ota.owns($0) } ?? false }
    func startOver(ota: OTAInstallModel) { cancelInstallation(ota: ota); clearResult(); ota.resetIfIdle() }
    func canOpenInstallLink(_ link: URL, ota: OTAInstallModel) -> Bool {
        ota.activeSession == nil || (ownsInstallation(ota) && readyLink == link)
    }
    /// Notification activation can be delayed by foregrounding. It must not open over a replacement operation.
    func openInstallLink(_ link: URL, ota: OTAInstallModel, prepare: () async throws -> Void, open: (URL) -> Void) async -> Bool {
        guard canOpenInstallLink(link, ota: ota), !Task.isCancelled else { return false }
        let owner = ota.activeSession?.id
        do { try await prepare() } catch { return false }
        guard !Task.isCancelled, owner == ota.activeSession?.id, canOpenInstallLink(link, ota: ota) else { return false }
        open(link); return true
    }

    /// Weights signing against uploading by how long each took on earlier runs (or sensible defaults).
    func jobProgress(uploadFraction: Double, exportOnly: Bool) -> JobProgress {
        let mb = Double((try? ipaURL?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
        let e = JobEstimator(store: UserDefaults.standard).estimate(megabytes: max(mb, 1))
        return JobProgress(signSeconds: e.sign, uploadSeconds: exportOnly ? 0 : e.upload)
    }

    func clearResult() {
        inputRevision = UUID()
        preparedSigning?.discard()
        preparedSigning = nil
        passportReport = nil
        skippedProfiles = []
        report = nil; errorText = nil; savedInstallError = nil; signedPendingID = nil; shelfSaveState = .idle
        if installSession == nil { readyLink = nil }
    }

    func discardPreflight() { clearResult() }

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
    /// Refuse signing when a profile cannot grant requested entitlements (instead of dropping them with a warning).
    @Published var strictEntitlements = false { didSet { if strictEntitlements != oldValue { clearResult() } } }
    private var installSession: OTAInstallModel.Session?
    @Published private(set) var savedInstallError: String?
    /// The shelf row whose saved app is being installed right now, so that row can show progress.
    @Published private(set) var savedInstallID: LibraryEntry.ID?

    /// Signs with the chosen certificate (when there is one), then uploads and hands the app to iOS.
    /// When signing still has to run, this starts it and returns; the Install button appears once the report is ready.
    /// Nothing is uploaded unless signing succeeded and its self-check passed. Keeps going if Wax is sent to the
    /// background, and posts a notification when the app is ready to install.
    func signAndInstall(ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard !installing, !Task.isCancelled else { return }
        if certificateID != nil, preparedSigning == nil {
            if let task = sign(standalone: false, compression: SigningCompression.Preference().flags(phoneInstall: ota.hostKind == .phone)) { await task.value }
            return
        }
        if let preparedSigning, !preparedSigning.preflight.canContinue { return }
        await install(saved: nil, ota: ota, open: open)
    }

    /// Installs the retained signed bytes, regardless of the certificate selected on the Sign screen.
    func installSaved(_ entry: LibraryEntry, ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard busyMessage == nil, !installing, !shelfSaveState.isSaving else {
            savedInstallError = "Another job is active. Wait for it to finish before installing a saved app."
            return
        }
        savedInstallError = nil
        savedInstallID = entry.id
        defer { savedInstallID = nil }
        await install(saved: entry, ota: ota, open: open)
    }

    private func install(saved: LibraryEntry?, ota: OTAInstallModel, open: @escaping (URL) -> Void) async {
        guard !installing, !Task.isCancelled else { return }
        let fail: (String) -> Void = { message in
            if saved != nil { self.savedInstallError = message } else { self.errorText = message }
        }
        let session: OTAInstallModel.Session
        do { session = try ota.reserve() }
        catch { fail(error.localizedDescription); return }
        installing = true; installSession = session
        defer { ota.release(session); if installSession === session { installSession = nil } }
        let job = background
        var signingTask: Task<Void, Never>?
        var snapshotTask: Task<(LibraryEntry, IPAMetadata), Error>?
        let backgroundID = job.begin(title: saved?.name ?? ipaInfo?.displayName ?? "Wax", onExpiration: {
            ota.cancel(session)
            signingTask?.cancel(); snapshotTask?.cancel()
        })
        ota.onRelease(of: session) { signingTask?.cancel(); snapshotTask?.cancel() }
        var succeeded = false
        defer { job.end(backgroundID, success: succeeded); installing = false }
        guard ota.owns(session), !Task.isCancelled else { return }
        readyLink = nil

        var snapshotDirectory: URL?
        defer { if let snapshotDirectory { try? FileManager.default.removeItem(at: snapshotDirectory) } }
        let target: InstallTarget?
        if let saved {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Install-" + UUID().uuidString, isDirectory: true)
            snapshotDirectory = directory
            let snapshot = directory.appendingPathComponent("signed.ipa"), storage = library.storage
            let task = Task.detached(priority: .userInitiated) { () throws -> (LibraryEntry, IPAMetadata) in
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let current = try storage.copySignedForInstallation(saved.id, to: snapshot, checkCancellation: { try Task.checkCancellation() })
                try Task.checkCancellation()
                let info = try IPAInspector.inspect(url: snapshot)
                guard info.hasCodeSignature, info.hasEmbeddedProfile else {
                    throw LibraryError.installation("The file has no embedded signature or profile. Re-sign it first.")
                }
                guard (current.bundleID.isEmpty || current.bundleID == info.bundleIdentifier),
                      (current.version.isEmpty || current.version == info.version),
                      (current.build == nil || current.build == info.build),
                      (current.record == nil || current.record?.finalBundleID == info.bundleIdentifier) else {
                    throw LibraryError.installation("The file does not match its saved app details. Re-sign the original.")
                }
                return (current, info)
            }
            snapshotTask = task
            do {
                let (_, info) = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
                guard !Task.isCancelled, ota.owns(session) else { return }
                let isWaxItself = info.executable == Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
                if !isWaxItself, info.bundleIdentifier == Bundle.main.bundleIdentifier {
                    throw LibraryError.installation(BundleIDGuard.explanation)
                }
                target = InstallTarget(ipa: snapshot, bundleIdentifier: info.bundleIdentifier, version: info.version, build: info.build, title: info.displayName)
            } catch {
                if ota.owns(session), !Task.isCancelled { fail(error.localizedDescription) }
                return
            }
        } else if certificateID != nil {
            guard let task = sign(standalone: false, compression: SigningCompression.Preference().flags(phoneInstall: session.kind == .phone), backgroundID: backgroundID) else { return }
            signingTask = task
            await task.value
            guard !Task.isCancelled, ota.owns(session), let r = report, r.checkFailures.isEmpty else { return }
            if BundleIDGuard.replacesRunningWax(originalID: ipaInfo?.bundleIdentifier ?? "",
                                                finalID: r.installTarget.bundleIdentifier,
                                                runningID: Bundle.main.bundleIdentifier) {
                ota.fail(session, reason: BundleIDGuard.explanation)
                return
            }
            target = r.installTarget
        } else {
            target = signedInputTarget
            // A signed copy of Wax itself (same executable) is an update, not a clash; a different app that merely
            // carries one of Wax's IDs is not.
            let isWaxItself = ipaInfo?.executable == Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
            if let t = target, !isWaxItself, t.bundleIdentifier == Bundle.main.bundleIdentifier {
                ota.fail(session, reason: BundleIDGuard.explanation)
                return
            }
        }
        guard let target, !Task.isCancelled, ota.owns(session) else { return }

        let megabytes = Double((try? target.ipa.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) / 1_000_000
        let weights = saved == nil ? jobProgress(uploadFraction: 0, exportOnly: false)
            : JobProgress(signSeconds: 0, uploadSeconds: JobEstimator(store: UserDefaults.standard).estimate(megabytes: max(1, megabytes)).upload)
        let watcher = ota.$state.sink { state in
            if ota.owns(session), case .uploading(let f) = state { job.update(backgroundID, fraction: weights.overall(sign: 1, upload: f), subtitle: "Sending to your server") }
        }
        defer { watcher.cancel() }

        let uploadStart = Date()
        guard let link = await ota.upload(ipa: target.ipa, bundleIdentifier: target.bundleIdentifier,
                                          version: target.version, build: target.build, title: target.title, session: session),
              !Task.isCancelled, ota.owns(session) else {
            if saved != nil, case .failed(let message) = ota.state { fail(message) }
            return
        }
        var estimator = JobEstimator(store: UserDefaults.standard)
        estimator.record(megabytes: megabytes, signSeconds: saved == nil && certificateID != nil ? lastSignSeconds : 0,
                         uploadSeconds: Date().timeIntervalSince(uploadStart))
        readyLink = link
        if UIApplication.shared.applicationState == .active {
            open(link)
        } else {
            job.notifyIfInBackground(InstallNotification.readyToInstall(appTitle: target.title, link: link))
        }
        // The phone serves the file itself, so it must stay alive (also in the background) until iOS has it all.
        job.update(backgroundID, fraction: 1, subtitle: "Waiting for iOS to take the app")
        succeeded = await ota.finishPhoneTransfer(session: session)
        if saved != nil, !succeeded, ota.activeSession == nil, case .failed(let message) = ota.state { fail(message) }
        if session.kind == .phone || !succeeded { readyLink = nil }      // the listener is closed now; the link no longer works
    }

    func cancelInstallation(ota: OTAInstallModel) { if let installSession { ota.cancel(installSession) } }

    var canSignAndInstall: Bool {
        busyMessage == nil && !installing && ipaInfo != nil && (certificateID != nil || signedInputTarget != nil)
    }

    var canSign: Bool { !installing && ipaInfo != nil && certificateID != nil && busyMessage == nil }

    // MARK: Choosing the IPA

    /// Chooses an IPA already on the shelf.
    func use(_ entry: LibraryEntry) {
        guard activeSigningRun == nil else { return }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("Wax-Pick-\(UUID().uuidString).ipa")
        guard (try? FileManager.default.copyItem(at: library.url(for: entry), to: copy)) != nil else {
            errorText = "That file is no longer in Wax's library."
            Task { await library.refresh() }
            return
        }
        picked(ipa: copy, fromLibrary: entry)
    }

    func picked(ipa url: URL, fromLibrary: LibraryEntry? = nil) {
        guard activeSigningRun == nil else { discardPickerCopy(url); return }
        clearResult()
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
                    if fromLibrary == nil { let saved = dest; Task { _ = try? await model.library.fileNow(saved, info: info) } }
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
    /// `compression` is read once, here, so changing Signing options ▸ File compression cannot alter a run under way.
    /// Left out, it is the saved choice for an export (Signing options ▸ File compression).
    func sign(standalone: Bool = true, compression: SigningCompression.Flags? = nil, backgroundID: UUID? = nil, cancellation: SigningCancellation? = nil) -> Task<Void, Never>? {
        guard busyMessage == nil, !runningSign, !shelfSaveState.isSaving, let ipaURL, let info = ipaInfo, let certificateID, let store = credentials.store,
              let cert = credentials.certificates.first(where: { $0.id == certificateID }) else { return nil }
        let revision = inputRevision
        let packing = compression ?? SigningCompression.Preference().flags(phoneInstall: false)
        let strictForRun = strictEntitlements
        let profileInfos = credentials.profiles
        let run = UUID()
        let preparedToSign = preparedSigning
        if let preparedToSign, !preparedToSign.preflight.canContinue {
            errorText = preparedToSign.preflight.findings.first(where: { $0.status == .blocked })?.detail
            return nil
        }
        activeSigningRun = run
        runningSign = true
        report = nil
        errorText = nil
        passportReport = nil
        if preparedToSign != nil { preparedSigning = nil }
        busyMessage = preparedToSign == nil ? "Preparing…" : "Signing…"
        let title = info.displayName.isEmpty ? "Wax" : info.displayName
        let backgroundJob = standalone && preparedToSign != nil
        // This run's own job: never read from shared state later, so a replacement run's job cannot be ended by mistake.
        var ownedJobID: UUID? = backgroundID
        if backgroundJob {
            ownedJobID = background.begin(title: title)
        }
        let jobForRun = ownedJobID
        let weights = jobProgress(uploadFraction: 0, exportOnly: standalone)
        let rewrite = rewriteBundleID
        let appEdits = edits
        let chosenProfile = profileChoice
        let entitlementsOverride = customEntitlements
        let keep = keepBundleID
        let skippedProfilesForRun = skippedProfiles
        let model = self
        ImportLogs.shared.log("sign: start id=\(ipaInfo?.bundleIdentifier ?? "?") rewrite=\(rewrite)")

        signFraction = 0
        signStarted = Date()
        let throttle = ProgressThrottle()
        let worker = Task.detached(priority: .userInitiated) {
            do {
                let prepared: PreparedIPASigning
                if let preparedToSign {
                    prepared = preparedToSign
                } else {
                    let identity = try SecurityFrameworkIdentity(identity: store.identity(for: certificateID))
                    var pool: [ProvisioningProfile] = []
                    var skipped: [String] = []
                    for profileInfo in store.profiles() {
                        do { pool.append(try ProvisioningProfile.parse(try store.profileData(for: profileInfo.id))) }
                        catch { skipped.append("\(profileInfo.name): \((error as? LocalizedError)?.errorDescription ?? "unreadable")") }
                    }
                    var options = SigningOptions()
                    options.cancellation = cancellation
                    options.rewriteBundleIdentifier = rewrite
                    options.keepBundleIdentifier = keep
                    options.overrideEntitlements = entitlementsOverride
                    options.entitlementPolicy = strictForRun ? .reject : .dropAndWarn
                    let profiles = try ProfileSet(pool: pool, overrides: Self.overrides(chosen: chosenProfile, store: store))
                    let prepared = try IPASigner.prepare(ipa: ipaURL, identity: identity, certificateTeamID: cert.teamID,
                                                         profiles: profiles, options: options, edits: appEdits,
                                                         workDirectory: FileManager.default.temporaryDirectory) { p in
                        guard throttle.shouldPublish(p) else { return }
                        Task { @MainActor in
                            guard model.activeSigningRun == run, model.inputRevision == revision else { return }
                            model.busyMessage = p.message; model.signFraction = p.fraction
                        }
                    }
                    var findings = prepared.preflight.findings
                    findings.append(Self.minimumOSFinding(prepared.minimumOSVersion))
                    let passport = SigningPreflightReport(findings: findings, blockingError: prepared.preflight.blockingError,
                                                          selections: prepared.preflight.selections)
                    let skippedProfilesForPreparation = skipped
                    await MainActor.run {
                        model.runningSign = false
                        guard model.activeSigningRun == run else { prepared.discard(); return }
                        model.activeSigningRun = nil
                        model.busyMessage = nil
                        guard model.inputRevision == revision else { prepared.discard(); return }
                        model.preparedSigning = prepared
                        let continuity = Self.continuityFinding(original: info.bundleIdentifier, selections: passport.selections,
                                                                certificate: cert, profiles: profileInfos, entries: model.library.signed)
                        model.passportReport = continuity.map {
                            SigningPreflightReport(findings: passport.findings + [$0], blockingError: passport.blockingError, selections: passport.selections)
                        } ?? passport
                        model.skippedProfiles = skippedProfilesForPreparation
                        model.busyMessage = nil
                    }
                    return
                }

                let shelf = model.library.storage
                let pending = try shelf.reserve(kind: .signed, name: title, provenance: .waxSigned)
                let output = try shelf.pendingURL(pending.id)
                let outcome = try IPASigner.sign(prepared: prepared, output: output, compressChangedFiles: packing.compressChangedFiles, fastDeflate: packing.fastDeflate) { p in
                    // The engine reports often; only pass on a visible change.
                    guard throttle.shouldPublish(p) else { return }
                    Task { @MainActor in
                        guard model.activeSigningRun == run, model.inputRevision == revision else { return }
                        model.busyMessage = p.message; model.signFraction = p.fraction
                        if let id = jobForRun { model.background.update(id, fraction: weights.overall(sign: p.fraction, upload: 0), subtitle: p.message) }
                    }
                }

                let size = (try? FileManager.default.attributesOfItem(atPath: outcome.output.path)[.size] as? Int) ?? 0
                // What this copy was signed with, kept beside it on the shelf. Losing it only loses later comparisons.
                try? shelf.setRecord(Self.signingRecord(original: outcome.inputArchive.bundleIdentifier, final: outcome.outputArchive.bundleIdentifier,
                                                        certificate: cert, selections: outcome.signing.profileSelections, profiles: profileInfos),
                                     for: pending.id)
                var profileLines = outcome.signing.profileSelections.map { sel -> String in
                    "\(sel.bundlePath == "." ? "App" : sel.bundlePath) → “\(sel.profileName)” · \(Self.describe(sel.signatureStatus))"
                }
                profileLines += skippedProfilesForRun.map { "Skipped \($0)" }
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
                let accepted: Bool = await MainActor.run {
                    guard model.activeSigningRun == run else { return false }
                    model.activeSigningRun = nil
                    model.busyMessage = nil
                    model.runningSign = false
                    guard model.inputRevision == revision else {
                        if backgroundJob, let id = jobForRun { model.background.end(id, success: false) }
                        return false
                    }
                    model.lastSignSeconds = Date().timeIntervalSince(model.signStarted ?? Date())
                    model.skippedProfiles = []
                    return true
                }
                guard accepted else { return }
                await model.acceptSignedResult(r, pendingID: pending.id, revision: revision)
                await MainActor.run {
                    if standalone {
                        let saved = model.shelfSaveState.confirmedSaved
                        if backgroundJob, let id = jobForRun { model.background.end(id, success: saved) }
                        if saved { model.background.notifyIfInBackground(InstallNotification.signed(appTitle: title)) }
                    }
                }
            } catch {
                let text = error is CancellationError ? "Signing stopped before it finished. Try again with Wax open."
                    : (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ImportLogs.shared.log("sign: failed \(ImportLog.describe(error))")
                await MainActor.run {
                    guard model.activeSigningRun == run else { return }
                    model.runningSign = false
                    model.activeSigningRun = nil
                    model.busyMessage = nil
                    guard model.inputRevision == revision else {
                        if backgroundJob, let id = jobForRun { model.background.end(id, success: false) }
                        return
                    }
                    model.preparedSigning?.discard()
                    model.preparedSigning = nil
                    model.errorText = text; model.busyMessage = nil
                    if backgroundJob, let id = jobForRun { model.background.end(id, success: false) }
                }
            }
        }
        if backgroundJob, let id = jobForRun {
            background.onExpiration(of: id) {
                preparedToSign?.cancel()
                worker.cancel()
            }
        }
        return worker
    }

    private var skippedProfiles: [String] = []

    /// Public identifiers of what a run signed with: certificate fingerprint, team, app ID prefix and every profile used.
    nonisolated static func signingRecord(original: String, final: String, certificate: CertificateInfo, selections: [ProfileSelection],
                                          profiles: [ProfileInfo], at date: Date = Date()) -> SigningRecord {
        let main = selections.first { $0.bundlePath == "." } ?? selections.first
        var seen = Set<UUID>(), used: [SigningRecord.Profile] = []
        for s in (main.map { [$0] } ?? []) + selections where seen.insert(s.profileID).inserted {
            used.append(.init(id: s.profileID, name: s.profileName, kind: s.profileKind, expires: s.profileExpiration))
        }
        return SigningRecord(signedAt: date, originalBundleID: original, finalBundleID: final, teamID: certificate.teamID,
                             appIDPrefix: main.flatMap { m in appIDPrefix(profiles.first { $0.id == m.profileID }) },
                             certificateSHA1: certificate.sha1Fingerprint, certificateExpires: certificate.notAfter, profiles: used)
    }

    /// The Passport row comparing this plan with the last copy Wax signed of the same app. Nil without such a record.
    nonisolated static func continuityFinding(original: String, selections: [ProfileSelection], certificate: CertificateInfo,
                                              profiles: [ProfileInfo], entries: [LibraryEntry]) -> PreflightFinding? {
        guard let main = selections.first(where: { $0.bundlePath == "." }),
              let a = IdentityContinuity.assess(originalBundleID: original, finalBundleID: main.bundleIdentifier, teamID: certificate.teamID,
                                                appIDPrefix: appIDPrefix(profiles.first { $0.id == main.profileID }), entries: entries)
        else { return nil }
        return PreflightFinding(id: "identity-continuity", status: a.isWarning ? .warning : .pass, title: a.title, detail: a.detail)
    }

    nonisolated private static func appIDPrefix(_ profile: ProfileInfo?) -> String? {
        profile?.applicationIdentifier.split(separator: ".", maxSplits: 1).first.map(String.init)
    }

    nonisolated private static func minimumOSFinding(_ minimum: String?) -> PreflightFinding {
        guard let minimum else {
            return PreflightFinding(id: "minimum-ios", status: .unknown, title: "Minimum iOS version is not listed",
                                    detail: "Wax cannot compare this app's requirement with the iPhone's iOS version.")
        }
        let rawComponents = minimum.split(separator: ".", omittingEmptySubsequences: false)
        let components = rawComponents.compactMap { Int($0) }
        guard (1...3).contains(components.count), components.count == rawComponents.count,
              components.allSatisfy({ $0 >= 0 }) else {
            return PreflightFinding(id: "minimum-ios", status: .unknown, title: "Minimum iOS version could not be compared",
                                    detail: "The IPA lists an unreadable minimum iOS version: \(minimum).")
        }
        let required = OperatingSystemVersion(majorVersion: components[0],
                                             minorVersion: components.count > 1 ? components[1] : 0,
                                             patchVersion: components.count > 2 ? components[2] : 0)
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let currentText = "\(current.majorVersion).\(current.minorVersion).\(current.patchVersion)"
        let compatible = ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
        return PreflightFinding(id: "minimum-ios", status: compatible ? .pass : .warning,
                                title: compatible ? "iOS version meets the app's minimum" : "This app requires a newer iOS version",
                                detail: compatible ? "This iPhone is running iOS \(currentText)."
                                    : "The app needs iOS \(minimum); this iPhone runs iOS \(currentText).",
                                evidence: "Read from the app's MinimumOSVersion and this device's iOS version.")
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
