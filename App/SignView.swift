import CredentialKit
import InstallKit
import IPAKit
import SigningKit
import SwiftUI
import UIKit

struct SignView: View {
    @EnvironmentObject private var model: SigningModel
    @EnvironmentObject private var credentials: CredentialsModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var ota: OTAInstallModel
    @ObservedObject private var inbox = InstallInbox.shared
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picking = false
    @State private var chooseIdentity = false
    @State private var showDetails = false
    @State private var stamped = false
    /// The running job is "sign only", so the bar fills at the end of signing instead of waiting for an upload.
    @State private var exportRun = false
    /// One outcome per run: the haptic and the spoken line must not repeat themselves.
    @State private var announced = false
    @State private var pendingInstallTask: Task<Void, Never>?

    // MARK: Derived state

    private var certificate: CertificateInfo? {
        model.certificateID.flatMap { id in credentials.certificates.first { $0.id == id } }
    }

    private var isReading: Bool { model.busyMessage?.hasPrefix("Reading") == true }

    private var testResult: InstallTestResult? { certificate.flatMap { InstallTestStore().result(for: $0.sha1Fingerprint) } }

    private var primary: SignPrimary {
        SignPrimary.resolve(hasApp: model.ipaInfo != nil, hasCertificates: !credentials.certificates.isEmpty,
                            certificateChosen: certificate != nil, inputIsInstallable: model.signedInputTarget != nil,
                            serverReady: ota.isConfigured)
    }

    private var phase: SignPhase {
        SignPhase.resolve(busy: model.busyMessage != nil && !isReading, hasError: errorText != nil, hasReport: model.report != nil)
    }

    private var uploading: Bool { ota.activeSession != nil && model.installing && model.busyMessage == nil }

    private var errorText: String? {
        if let e = model.errorText { return e }
        if case .failed(let t) = ota.state { return t }
        return nil
    }

    private var handedToiOS: Bool { ota.state == .handedToiOS }

    /// The step Wax is on while it works, or nil when it is waiting for the person.
    private var stage: SignStage? {
        SignStage.resolve(reading: isReading, signing: model.busyMessage != nil && !isReading, uploading: uploading)
    }

    private var firstRun: Bool {
        SignSetupChecklist.isFirstRun(hasApp: model.ipaInfo != nil, hasIdentity: certificate != nil, hostReady: ota.isConfigured)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 10) {
                        header.id("top")
                        if model.ownsInstallation(ota) {
                            Button("Cancel installation", role: .destructive) { model.cancelInstallation(ota: ota) }
                                .accessibilityHint("Keeps signed and saved IPA files. Signing already in progress may finish safely before stopping.")
                        }
                        if let preview = model.preview {
                            previewCard(preview)
                        } else if let r = model.report {
                            resultCard(r)
                        } else if let stage {
                            progressCard(stage)
                        } else if phase == .done && errorText == nil, let r = model.report {
                            resultCard(r)
                        } else {
                            idleScreen
                        }
                    }
                    .padding(.horizontal, Wax.inset)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .background(Wax.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: router.reselectTick[.sign]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
        }
        .sheet(isPresented: $picking) {
            DocumentPicker { picked in
                picking = false
                guard let picked else { ImportLogs.shared.log("sign: picker cancelled"); return }
                model.picked(ipa: picked)
            }
        }
        .sheet(isPresented: $showDetails) { detailsSheet }
        .confirmationDialog("Sign with", isPresented: $chooseIdentity, titleVisibility: .visible) {
            ForEach(credentials.certificates) { cert in
                Button(identityTitle(cert)) { model.certificateID = cert.id }
            }
        }
        .onChange(of: phase) { _, new in if new == .done { stamp() } else { stamped = false } }
        .onChange(of: model.busyMessage) { _, busy in if busy != nil { announced = false } }   // a new run earns its own feedback
        .onChange(of: model.preview != nil) { _, ready in
            if ready { UIAccessibility.post(notification: .announcement, argument: "Signing preview ready. Review the changes before confirming.") }
        }
        .onChange(of: model.ipaInfo != nil) { _, ready in if ready { announceRead() } }
        .onChange(of: model.shelfSaveState.confirmedSaved) { _, saved in if saved { announceOutcome(success: true, message: "Signed and saved. Wax checked the file.") } }
        .onChange(of: model.shelfSaveState.isSaving) { _, saving in
            if saving { announced = false }
            else if case .failed = model.shelfSaveState { announceOutcome(success: false, message: "Signing succeeded. Shelf saving failed. Retry Save or export the retained IPA.") }
        }
        .onChange(of: model.errorText) { _, text in if let text { announceOutcome(success: false, message: text) } }
        .onChange(of: inbox.pendingLink) { _, _ in openPendingInstall() }
        .onAppear { openPendingInstall() }   // a tap that launched Wax from scratch
        .onChange(of: handedToiOS) { _, new in if new { stamp() } }
    }

    /// A tapped "Ready to install" notification: go to this screen and bring up iOS's install prompt.
    private func openPendingInstall() {
        pendingInstallTask?.cancel()
        guard let link = inbox.pendingLink, model.canOpenInstallLink(link, ota: ota) else { return }
        router.tab = .sign
        pendingInstallTask = Task { @MainActor in
            let opened = await model.openInstallLink(link, ota: ota, prepare: {
                for _ in 0..<30 where UIApplication.shared.applicationState != .active { try await Task.sleep(for: .milliseconds(100)) }
                try await Task.sleep(for: .milliseconds(300))
                guard inbox.pendingLink == link else { throw CancellationError() }
            }, open: { openURL($0) })
            if opened, inbox.pendingLink == link { inbox.pendingLink = nil }
        }
    }

    // MARK: Pieces

    private var header: some View { WaxHeader(title: "Sign", subtitle: "Sign an app and install it on this iPhone.") }

    /// Nothing to do but say what is missing: the setup card, any problem, the one button, and the options.
    private var idleScreen: some View {
        Group {
            if firstRun { WaxSectionLabel(text: "Before you can sign") }
            summaryCard
            if let error = errorText { errorCard(error) }
            idleActions
            optionsRow
        }
    }

    /// One card with the three things signing needs: the app, the identity, the install host. Each line opens its
    /// own place to set it.
    private var summaryCard: some View {
        WaxPanel {
            appRow
            WaxDivider()
            identityRow
            WaxDivider()
            hostRow
        }
    }

    /// With no app chosen this line is only a summary: the big button below is the one way to choose one.
    @ViewBuilder private var appRow: some View {
        if let info = model.ipaInfo {
            Button { picking = true; ImportLogs.shared.log("sign: choose tapped") } label: {
                setupRow(icon: SignSetupChecklist.app.icon,
                          title: info.displayName.isEmpty ? "App" : info.displayName,
                          subtitle: appSubtitle(info)) { WaxLinkText(text: "Change") }
            }
            .buttonStyle(.plain)
            .disabled(model.busyMessage != nil)
            .accessibilityHint("Opens Files to pick another IPA")
        } else {
            setupRow(icon: SignSetupChecklist.app.icon, title: SignSetupChecklist.app.title,
                     subtitle: SignSetupChecklist.app.detail) { EmptyView() }
        }
    }

    private var identityRow: some View {
        Button { identityTapped() } label: {
            if credentials.certificates.isEmpty {
                setupRow(icon: SignSetupChecklist.identity.icon, title: SignSetupChecklist.identity.title,
                         subtitle: SignSetupChecklist.identity.detail) { WaxLinkText(text: "Import") }
            } else if let cert = certificate {
                setupRow(icon: SignSetupChecklist.identity.icon, title: cert.organization ?? cert.commonName,
                         subtitle: identitySubtitle(cert)) {
                    IdentityReadiness.status(for: cert, profiles: credentials.profiles).pill
                }
            } else {
                setupRow(icon: SignSetupChecklist.identity.icon, title: SignSetupChecklist.identity.title,
                         subtitle: SignSetupChecklist.identity.detail) { WaxLinkText(text: "Choose") }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil)
        .accessibilityHint("Opens your signing identities")
    }

    private var hostRow: some View {
        Button { router.tab = .settings } label: {
            if ota.isConfigured {
                setupRow(icon: SignSetupChecklist.host.icon, title: "Install host", subtitle: ota.hostSummary) {
                    WaxPill(text: "Ready", tone: .ok)
                }
            } else {
                setupRow(icon: SignSetupChecklist.host.icon, title: SignSetupChecklist.host.title,
                         subtitle: SignSetupChecklist.host.detail) { WaxLinkText(text: "Set up") }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil)
        .accessibilityHint("Opens Settings to set the install host")
    }

    /// One line of the setup card: icon tile, the value or what to do, something on the right.
    private func setupRow<T: View>(icon: String, title: String, subtitle: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            WaxIconTile(symbol: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Wax.text).lineLimit(2)
                Text(subtitle).font(.footnote).foregroundStyle(Wax.sub).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: Wax.rowHeight)
        .contentShape(Rectangle())
    }

    private func appSubtitle(_ info: IPAMetadata) -> String {
        let version = [info.version, info.build.isEmpty ? "" : "(\(info.build))"].filter { !$0.isEmpty }.joined(separator: " ")
        return version.isEmpty ? "Version unknown" : version
    }

    private func identityTapped() {
        if credentials.certificates.isEmpty { router.openCredentials() } else { chooseIdentity = true }
    }

    private func identityTitle(_ cert: CertificateInfo) -> String {
        [cert.organization ?? cert.commonName, IdentityReadiness.kindLabel(for: cert, profiles: credentials.profiles)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func identitySubtitle(_ cert: CertificateInfo) -> String {
        [IdentityReadiness.kindLabel(for: cert, profiles: credentials.profiles) ?? "No matching profile",
         cert.notAfter.formatted(.dateTime.month(.abbreviated).year())].joined(separator: " · ")
    }

    private var optionsRow: some View {
        Button { showDetails = true } label: {
            WaxRow(icon: "slider.horizontal.3", title: "Options",
                   subtitle: model.edits.isEmpty ? "Names, versions and app edits" : "App edits changed") {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil)
        .accessibilityHint("Opens signing options")
    }

    // MARK: Action zone

    private var idleActions: some View {
        VStack(spacing: 8) {
            Button { runPrimary() } label: {
                Label(primary.isSigning ? "Prepare signing preview" : primary.title, systemImage: primaryIcon)
            }
            .buttonStyle(WaxPrimaryButtonStyle())
            .disabled(model.installing || ota.activeSession != nil)
            .padding(.top, 4)
            Text(primary.isSigning ? "Review the exact changes before signing. Nothing is installed during preview." : primary.reason)
                .font(.footnote).foregroundStyle(Wax.sub).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if primary == .install && testResult == .failed {
                Text("A test install with this identity didn't complete. You can still try.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Wax.warn).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if primary.isSigning && model.bundleIDMode == .rename {
                Text("The app will be renamed to fit the profile.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Wax.warn).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            if model.canSign {
                Button("Preview signing for export") { exportRun = true; model.prepareForSigning() }.buttonStyle(WaxSecondaryButtonStyle())
            }
        }
    }

    private func previewCard(_ preview: PreparedIPA.Preview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review signing").font(.title2.bold()).foregroundStyle(Wax.text)
            WaxPanel {
                previewLine("App", preview.original.name, preview.proposed.name)
                WaxDivider()
                previewLine("Bundle ID", preview.original.identifier, preview.proposed.identifier)
                WaxDivider()
                previewLine("Version / build", "\(preview.original.version) (\(preview.original.build))", "\(preview.proposed.version) (\(preview.proposed.build))")
            }
            Text("The IPA was unpacked and edited once. Confirm signs this retained tree using the decisions below. Changes to settings or credentials require a new preview.")
                .font(.footnote).foregroundStyle(Wax.sub)
            Text("Expires \(preview.expiresAt.formatted(date: .omitted, time: .shortened))").font(.footnote).foregroundStyle(Wax.sub)
            ForEach(Array(preview.changes.enumerated()), id: \.offset) { _, line in
                Text(line).font(.footnote).foregroundStyle(Wax.sub)
            }
            ForEach(preview.identifierChanges.keys.sorted(), id: \.self) { original in
                Text(original + " → " + (preview.identifierChanges[original] ?? original))
                    .font(.footnote.monospaced()).textSelection(.enabled)
            }
            DisclosureGroup("Code to sign (\(preview.code.count))") {
                ForEach(Array(preview.code.enumerated()), id: \.offset) { _, code in
                    Text("\(code.path) · \(code.kind) → \(code.identifier)")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Existing signatures and resource seals will be replaced. Universal executables are reduced to the supported arm64 slice.")
                    .font(.footnote).foregroundStyle(Wax.warn)
            }
            ForEach(Array(preview.bundles.enumerated()), id: \.offset) { _, bundle in
                DisclosureGroup(bundle.path == "." ? "App profile and capabilities" : bundle.path) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(bundle.originalIdentifier) → \(bundle.identifier)").font(.footnote.monospaced())
                        Text("Profile: \(bundle.profile.profileName)").font(.subheadline.weight(.semibold))
                        Text(SigningModel.describe(bundle.profile.signatureStatus)).font(.footnote).foregroundStyle(Wax.warn)
                        Text("Team ID and App ID prefix can differ. Review application-identifier, team-identifier and keychain-access-groups below; changed prefixes may prevent access to earlier keychain data.")
                            .font(.footnote).foregroundStyle(Wax.sub)
                        ForEach(Array(bundle.entitlements.enumerated()), id: \.offset) { _, entitlement in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entitlement.key) · \(entitlement.disposition.rawValue)").font(.footnote.weight(.semibold))
                                Text("Requested: " + entitlementValue(entitlement.requestedValueXML)).font(.caption.monospaced())
                                Text("Will sign: " + entitlementValue(entitlement.signedValueXML)).font(.caption.monospaced())
                            }.textSelection(.enabled)
                        }
                        ForEach(Array(bundle.profile.rejected.enumerated()), id: \.offset) { _, rejection in
                            Text("Not selected: \(rejection.profile) · \(rejection.reason)").font(.footnote).foregroundStyle(Wax.sub)
                        }
                        Picker("Override profile (requires a new preview)", selection: Binding<UUID?>(
                            get: { bundle.path == "." ? model.profileChoice : model.bundleProfiles[bundle.path] },
                            set: { id in
                                if bundle.path == "." { model.profileChoice = id }
                                else { model.bundleProfiles[bundle.path] = id }
                            })) {
                            Text("Automatic").tag(UUID?.none)
                            ForEach(credentials.profiles) { profile in Text(profile.name).tag(UUID?.some(profile.id)) }
                        }.tint(Wax.link)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            WaxFeedbackCard(tone: .bad, text: "This is a local signing plan. Even an intact CMS or a chain identified as Apple does not establish revocation status, provisioning eligibility, installation approval or successful launch. iOS makes those decisions.")
            Button(model.previewInstalls ? "Confirm, sign and install" : "Confirm and sign") {
                if model.previewInstalls { Task { await model.signAndInstall(ota: ota) { openURL($0) } } }
                else { model.sign() }
            }.buttonStyle(WaxPrimaryButtonStyle()).disabled(model.installing || ota.activeSession != nil)
            Button("Cancel preview", role: .destructive) { model.clearResult() }.buttonStyle(WaxSecondaryButtonStyle())
        }.foregroundStyle(Wax.text)
    }

    private func previewLine(_ title: String, _ original: String, _ proposed: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(original == proposed ? proposed : original + " → " + proposed)
                .font(.footnote).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
    }
    private func entitlementValue(_ xml: Data?) -> String {
        guard let xml, let value = (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any],
              let item = value["value"] else { return "Absent" }
        return String(describing: item)
    }

    private var primaryIcon: String {
        switch primary {
        case .install: "arrow.down.app"
        case .needServer: "icloud.and.arrow.up"
        case .needIdentity(let canImport): canImport ? "key" : "person.badge.key"
        case .needApp: "shippingbox"
        }
    }

    private func runPrimary() {
        switch primary {
        case .needApp: picking = true
        case .needIdentity(let canImport): if canImport { router.openCredentials() } else { chooseIdentity = true }
        case .needServer: router.tab = .settings
        case .install:
            exportRun = false
            if model.certificateID != nil { model.prepareForSigning(installAfter: true) }
            else { Task { await model.signAndInstall(ota: ota) { openURL($0) } } }
        }
    }

    /// 0...1 for the whole job, from the real signing and upload progress weighted by expected time.
    private var jobFraction: Double {
        let signing = (model.report != nil || uploading) ? 1 : model.signFraction
        return model.jobProgress(uploadFraction: uploadProgress ?? 0, exportOnly: exportRun).overall(sign: signing, upload: uploadProgress ?? 0)
    }

    /// While Wax works: the melting wax, the percent, the stage, and the engine's own words underneath.
    private func progressCard(_ current: SignStage) -> some View {
        let percent = Int(jobFraction * 100)
        let message = progressMessage
        return VStack(spacing: Wax.Space.m) {
            WaxMelt(progress: jobFraction, height: 230, isVisible: router.tab == .sign)
            Text("\(percent)%")
                .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Wax.text)
                .contentTransition(.numericText())
            Button("Cancel", role: .destructive) { model.clearResult() }
                .accessibilityHint("Stops before publication and keeps previously completed IPAs")
            stageStrip(current)
            Text(message)
                .font(.subheadline).foregroundStyle(Wax.sub)
                .multilineTextAlignment(.center).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Working")
        .accessibilityValue("\(current.spoken). \(percent) percent. \(message)")
    }

    /// Reading, Signing, Uploading: the one in hand is wax-red, the ones before it are ticked.
    private func stageStrip(_ current: SignStage) -> some View {
        HStack(alignment: .top, spacing: Wax.Space.s) {
            ForEach(SignStage.allCases, id: \.self) { stage in
                VStack(spacing: 4) {
                    Image(systemName: stage.isDone(current: current) ? "checkmark.circle.fill"
                                    : (stage == current ? "circle.fill" : "circle"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(stage.isDone(current: current) ? Wax.ok : (stage == current ? Wax.link : Wax.sub))
                        .frame(width: 24, height: 24)
                    Text(stage.title)
                        .font(.footnote.weight(stage == current ? .semibold : .regular))
                        .foregroundStyle(stage == current ? Wax.text : Wax.sub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .waxMotion(value: current)
    }

    /// What Wax is doing right now, in the engine's own words.
    private var progressMessage: String {
        if uploading { return "Sending to your server…" }
        if isReading { return model.ipaName ?? "Reading the file…" }
        guard let busy = model.busyMessage else { return "Signing the app…" }
        return busy.hasSuffix("…") ? busy : busy + "…"
    }

    private var uploadProgress: Double? { if case .uploading(let p) = ota.state { return p } else { return nil } }

    private func resultCard(_ r: SigningModel.Report) -> some View {
        let failed = !r.checkFailures.isEmpty
        return VStack(spacing: 8) {
            resultHeader(failed)
            if let errorText { WaxFeedbackCard(tone: .bad, text: errorText) }
            if !failed {
                switch model.shelfSaveState {
                case .saved(let saved):
                    signedShelfLink
                    if let warning = saved.warning { WaxFeedbackCard(tone: .bad, text: warning) }
                case .saving:
                    ProgressView("Saving to the IPA shelf…")
                case .failed(let failure):
                    WaxFeedbackCard(tone: .bad, text: "Signing succeeded, but shelf saving failed. " + failure.localizedDescription)
                    Button("Retry Save") { announced = false; Task { await model.retrySignedSave() } }.buttonStyle(WaxSecondaryButtonStyle())
                case .idle:
                    Text("The signed file is retained. It has not been saved on the shelf.").font(.footnote).foregroundStyle(Wax.sub)
                }
            }
            if let link = model.readyLink {
                Button { openURL(link) } label: { Label("Install", systemImage: "arrow.down.app") }
                    .buttonStyle(WaxPrimaryButtonStyle())
                    .disabled(!model.canOpenInstallLink(link, ota: ota))
            }
            exportButton(r).disabled(model.shelfSaveState.isSaving)
            Button { model.startOver(ota: ota) } label: {
                Label("Start over", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Wax.sub)
                    .frame(maxWidth: .infinity, minHeight: Wax.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Clears this result so you can sign another app")
            Button { showDetails = true } label: {
                Text("What Wax checked").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                    .frame(maxWidth: .infinity, minHeight: Wax.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the checks Wax made")
        }
        .padding(.top, 4)
    }

    private func resultHeader(_ failed: Bool) -> some View {
        HStack(spacing: 16) {
            WaxSeal(size: 76)
                .scaleEffect(stamped || reduceMotion ? 1 : 1.9)
                .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -14))
                .opacity(stamped || reduceMotion ? 1 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(failed ? "Signed, with problems" : (handedToiOS ? "Signed and uploaded" : "Signed"))
                    .font(.headline).foregroundStyle(failed ? Wax.bad : Wax.ok)
                Text(resultSubtitle).font(.footnote).foregroundStyle(Wax.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(failed ? Wax.badBg : Wax.okBg, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var resultSubtitle: String {
        if handedToiOS { return "Wax checked the file. iOS decides whether it installs." }
        return "Wax checked the file. Export it or sign again."
    }

    /// The copy is already on the shelf; the line takes the person there instead of only saying so.
    private var signedShelfLink: some View {
        Button {
            router.tab = .ipa
            router.shelf = .signed
        } label: {
            HStack(spacing: 6) {
                Text("Saved in the IPA tab, under Signed").font(.footnote.weight(.semibold))
                Image(systemName: "chevron.right").font(.caption.weight(.bold))
            }
            .foregroundStyle(Wax.link)
            .frame(maxWidth: .infinity, minHeight: Wax.touch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Goes to the Signed shelf in the IPA tab")
    }

    /// Install is the one big button; with no install link left, Export takes its place.
    @ViewBuilder private func exportButton(_ r: SigningModel.Report) -> some View {
        let size = ByteCountFormatter.string(fromByteCount: Int64(r.outputSize), countStyle: .file)
        let export = ShareLink(item: r.output) {
            Label("Export signed IPA · \(size)", systemImage: "square.and.arrow.up")
        }
        if model.readyLink == nil {
            export.buttonStyle(WaxPrimaryButtonStyle())
        } else {
            export.buttonStyle(WaxSecondaryButtonStyle())
        }
    }

    /// A problem sits above the big button, with the way back into Files.
    private func errorCard(_ text: String) -> some View {
        WaxFeedbackCard(tone: .bad, text: text, actionTitle: "Choose another file") {
            picking = true
            ImportLogs.shared.log("sign: choose another from error")
        }
    }

    // MARK: Details

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let info = model.ipaInfo {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("App's bundle ID").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                            Text(info.bundleIdentifier).font(.footnote).foregroundStyle(Wax.sub)
                                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    BundleIDModePicker(mode: $model.bundleIDMode)
                    HStack {
                        Text("Profile").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                        Spacer()
                        Text("\(credentials.profiles.count) imported · automatic").font(.footnote).foregroundStyle(Wax.sub)
                    }
                    if let r = model.report { reportDetails(r) }
                    NavigationLink { SigningOptionsView(model: model) } label: {
                        HStack {
                            Text("Signing options").font(.subheadline.weight(.semibold))
                            Spacer()
                            if !model.edits.isEmpty { WaxPill(text: "Changed", tone: .ok) }
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Wax.link)
                        .frame(minHeight: 44)
                    }
                }
                .padding(Wax.inset)
            }
            .background(Wax.bg.ignoresSafeArea())
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDetails = false } } }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private func reportDetails(_ r: SigningModel.Report) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What Wax checked").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
            Text(r.checkSummary + " (Wax's own consistency checks, not Apple's verifier.)")
                .font(.footnote).foregroundStyle(Wax.sub)
            ForEach(r.checkFailures, id: \.self) { Text($0).font(.footnote).foregroundStyle(Wax.bad) }
            ForEach(r.archiveLines, id: \.self) { Text($0).font(.footnote).foregroundStyle(Wax.sub) }
            ForEach(r.profileLines, id: \.self) { Text($0).font(.footnote).foregroundStyle(Wax.sub) }
            ForEach(r.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Wax.warn) }
        }
    }

    // MARK: Feedback

    /// The seal presses into the pool. Motion only: the haptic and the spoken line belong to the run's outcome.
    private func stamp() {
        stamped = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55)) { stamped = true }
    }

    /// The chosen file has been read: one spoken line, no haptic for something the person just did.
    private func announceRead() {
        guard !announced else { return }
        announced = true
        UIAccessibility.post(notification: .announcement, argument: "\(model.ipaInfo?.displayName ?? "The app") is ready to sign.")
    }

    /// A run finished: felt once and spoken once, never twice for the same run.
    private func announceOutcome(success: Bool, message: String? = nil) {
        guard !announced else { return }
        announced = true
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        UIAccessibility.post(notification: .announcement, argument: message ?? (success ? "Signed. Wax checked the file." : "Signing failed."))
    }
}