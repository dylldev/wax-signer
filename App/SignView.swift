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
    @ObservedObject private var inbox: InstallInbox
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picking = false
    @State private var chooseIdentity = false
    @State private var showDetails = false
    @State private var stamped = false
    /// The running job is "sign only", so the bar fills at the end of signing instead of waiting for an upload.
    @State private var exportRun = false
    /// One outcome per run: the haptic and the spoken line must not repeat themselves.
    @State private var announced = false
    /// The percent and the stage glyph grow with the reader's text size instead of staying at one size.
    @ScaledMetric(relativeTo: .largeTitle) private var percentSize: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var stageGlyphSize: CGFloat = 17

    init(inbox: InstallInbox? = nil) { self.inbox = inbox ?? .shared }

    // MARK: Derived state

    private var certificate: CertificateInfo? {
        model.certificateID.flatMap { id in credentials.certificates.first { $0.id == id } }
    }

    private var isReading: Bool { model.busyMessage?.hasPrefix("Reading") == true }

    private var primary: SignPrimary {
        SignPrimary.resolve(hasApp: model.ipaInfo != nil, hasCertificates: !credentials.certificates.isEmpty,
                            certificateChosen: certificate != nil, inputIsInstallable: model.signedInputTarget != nil,
                            serverReady: ota.isConfigured, hasProfiles: !credentials.profiles.isEmpty)
    }

    private var phase: SignPhase {
        SignPhase.resolve(busy: model.busyMessage != nil && !isReading, hasError: errorText != nil, hasReport: model.report != nil)
    }

    private var uploading: Bool { if case .uploading = ota.state { return true } else { return false } }

    /// Handed to iOS but (for the phone host) iOS has not finished taking the app yet, so success must not be claimed.
    private var waitingForTransfer: Bool { handedToiOS && model.installing && ota.hostKind == .phone }

    private var errorText: String? {
        if let e = model.errorText { return e }
        if case .failed(let t) = ota.state { return t }
        return nil
    }

    private var handedToiOS: Bool { ota.state == .handedToiOS }

    /// The step Wax is on while it works, or nil when it is waiting for the person.
    private var stage: SignStage? {
        return SignStage.resolve(reading: isReading,
                                 signing: model.busyMessage != nil && !isReading,
                                 uploading: uploading,
                                 preparing: preparingHost,
                                 handed: waitingForTransfer)
    }

    private var preparingHost: Bool {
        if case .preparing = ota.state { return true } else { return false }
    }

    /// The waiting state: nothing running, nothing failed, no finished report. It is the state that owns the primary action.
    private var showsIdleActions: Bool {
        stage == nil && errorText == nil && !(phase == .done && model.report != nil)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: Wax.Space.m) {
                        header.id("top")
                        if showsIdleActions && dynamicTypeSize.isAccessibilitySize { idleActions }
                        summaryCard
                        if let stage {
                            if waitingForTransfer, let link = model.readyLink {
                                Text("Keep Wax open while iOS takes the app.")
                                    .font(.subheadline).foregroundStyle(Wax.sub)
                                    .multilineTextAlignment(.center)
                                Button("Open install again") { openURL(link) }
                                    .buttonStyle(WaxSecondaryButtonStyle())
                            }
                            progressCard(stage)
                            // iOS shows its own prompt and gives no callback when it is dismissed, so the wait needs a way out.
                            if waitingForTransfer { cancelWaitButton }
                        } else if phase == .done && errorText == nil, let r = model.report {
                            resultCard(r)
                        } else {
                            if let error = errorText { errorCard(error) }
                            if !dynamicTypeSize.isAccessibilitySize { idleActions }
                            optionsRow
                        }
                    }
                    .padding(.horizontal, Wax.inset)
                    .padding(.bottom, Wax.Space.tabBarClearance)
                }
                .scrollIndicators(.hidden)
                .background(Wax.bg.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .onChange(of: router.reselectTick[.sign]) { _, _ in withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("top", anchor: .top) } }
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
        .onChange(of: phase) { _, new in if new == .done { if !waitingForTransfer { stamp() } } else { stamped = false } }
        .onChange(of: model.busyMessage) { _, busy in if busy != nil { announced = false } }   // a new run earns its own feedback
        .onChange(of: model.ipaInfo != nil) { _, ready in if ready { announceRead() } }
        .onChange(of: model.report != nil) { _, done in if done { announceOutcome(success: true) } }
        .onChange(of: model.errorText) { _, text in if let text { announceOutcome(success: false, message: text) } }
        .onChange(of: model.installing) { _, new in if !new && handedToiOS && ota.hostKind == .phone { stamp() } }
        .onChange(of: credentials.certificates) { _, _ in model.discardPreflight() }
        .onChange(of: credentials.profiles) { _, _ in model.discardPreflight() }
        .onChange(of: inbox.pendingLink) { _, _ in openPendingInstall() }
        .onAppear { openPendingInstall() }   // a tap that launched Wax from scratch
        .onChange(of: handedToiOS) { _, new in if new && !waitingForTransfer { stamp() } }
    }

    /// A tapped "Ready to install" notification: go to this screen and bring up iOS's install prompt.
    private func openPendingInstall() {
        guard let link = inbox.pendingLink else { return }
        router.tab = .sign
        inbox.pendingLink = nil
        // iOS ignores the install request while Wax is still coming to the front, so wait until it is active.
        Task { @MainActor in
            _ = await model.openInstallLink(link, ota: ota, prepare: {
                for _ in 0..<30 where UIApplication.shared.applicationState != .active { try await Task.sleep(for: .milliseconds(100)) }
                try await Task.sleep(for: .milliseconds(300))
            }, open: { openURL($0) })
        }
    }

    // MARK: Pieces

    private var header: some View { WaxHeader(title: "Sign", subtitle: "Sign an app and hand it to iOS to install.") }

    /// One card with the three things signing needs: the app, the identity, the install host. Stays on screen
    /// through signing and results so the selection is never lost and the layout does not jump.
    private var summaryCard: some View {
        WaxPanel {
            appRow
            WaxDivider()
            identityRow
            WaxDivider()
            hostRow
        }
    }

    /// Both states are buttons. The empty one used to be a summary with a red "Choose" that did nothing, so at
    /// accessibility sizes the only way to pick a file was the big button below the fold.
    private var appRow: some View {
        Button { picking = true; ImportLogs.shared.log("sign: choose tapped") } label: {
            if let info = model.ipaInfo {
                setupRow(icon: SignSetupChecklist.app.icon,
                         title: info.displayName.isEmpty ? "App" : info.displayName,
                         subtitle: appSubtitle(info)) { WaxLinkText(text: "Change") }
            } else {
                setupRow(icon: SignSetupChecklist.app.icon, title: SignSetupChecklist.app.title,
                         subtitle: SignSetupChecklist.app.detail) {
                    // At accessibility sizes this row's trailing cue repeats the big "Choose an app" button above it,
                    // and the extra line pushed the cue under the floating tab bar, where its contrast failed.
                    if !dynamicTypeSize.isAccessibilitySize { WaxLinkText(text: "Choose") }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil || model.installing)
        .accessibilityHint(model.ipaInfo == nil ? "Opens Files to pick an IPA" : "Opens Files to pick another IPA")
    }

    private var identityRow: some View {
        Button { identityTapped() } label: {
            if credentials.certificates.isEmpty {
                setupRow(icon: SignSetupChecklist.identity.icon, title: SignSetupChecklist.identity.title,
                         subtitle: SignSetupChecklist.identity.detail) { WaxLinkText(text: "Import") }
            } else if let cert = certificate {
                setupRow(icon: SignSetupChecklist.identity.icon, title: credentials.displayName(for: cert),
                         subtitle: identitySubtitle(cert)) {
                    let status = credentials.identityStatus(for: cert)
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(status.label).font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                    } else { status.pill }
                }
            } else {
                setupRow(icon: SignSetupChecklist.identity.icon, title: SignSetupChecklist.identity.title,
                         subtitle: SignSetupChecklist.identity.detail) { WaxLinkText(text: "Choose") }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil || model.installing)
        .accessibilityHint("Opens your signing identities")
    }

    private var hostRow: some View {
        Button { router.openInstallHost() } label: {
            if ota.isConfigured {
                setupRow(icon: SignSetupChecklist.host.icon, title: "Install host", subtitle: ota.hostSummary) {
                    WaxChevron()
                }
            } else {
                setupRow(icon: SignSetupChecklist.host.icon, title: SignSetupChecklist.host.title,
                         subtitle: SignSetupChecklist.host.detail) { WaxLinkText(text: "Set up") }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil || model.installing)
        .accessibilityHint("Opens Settings to set the install host")
    }

    /// One line of the setup card: icon tile, the value or what to do, something on the right.
    private func setupRow<T: View>(icon: String, title: String, subtitle: String, @ViewBuilder trailing: () -> T) -> some View {
        // The icon stays inline at every text size: stacking it above the copy cost
        // a whole line per row and pushed the primary button off screen at XXXL.
        HStack(alignment: .top, spacing: Wax.Space.m) {
            WaxIconTile(symbol: icon)
            VStack(alignment: .leading, spacing: Wax.Space.hairline) {
                Text(title).font(Wax.Ramp.body).foregroundStyle(Wax.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    trailing().padding(.top, Wax.Space.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize {
                trailing()
            }
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
        [credentials.displayName(for: cert), IdentityReadiness.kindLabel(for: cert, profiles: credentials.profiles)]
            .compactMap { $0 }.joined(separator: Wax.separator)
    }

    private func identitySubtitle(_ cert: CertificateInfo) -> String {
        [IdentityReadiness.kindLabel(for: cert, profiles: credentials.profiles) ?? "No matching profile",
         cert.notAfter.formatted(.dateTime.month(.abbreviated).year())].joined(separator: Wax.separator)
    }

    private var optionsRow: some View {
        Button { showDetails = true } label: {
            WaxPanel {
                setupRow(icon: "slider.horizontal.3", title: "Options",
                         subtitle: model.edits.isEmpty ? "Compression and app edits" : "App edits changed") {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                }
                .padding(.vertical, Wax.Space.xs)
            }
        }
        .buttonStyle(.plain)
        .disabled(model.busyMessage != nil || model.installing)
        .accessibilityHint("Opens signing options")
    }

    // MARK: Action zone

    private var idleActions: some View {
        VStack(spacing: Wax.Space.s) {
            Button { runPrimary() } label: {
                Label(primary.title, systemImage: primaryIcon)
            }
            .buttonStyle(WaxPrimaryButtonStyle())
            .disabled(model.installing)
            .padding(.top, Wax.Space.xs)
            Text(primary.reason)
                .font(Wax.Ramp.secondary).foregroundStyle(Wax.sub).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if primary.isSigning && model.bundleIDMode == .rename {
                HStack(spacing: Wax.Space.s) {
                    Image(systemName: "exclamationmark.triangle.fill").font(Wax.Ramp.secondary).foregroundStyle(Wax.warn)
                    Text("The app will be renamed to fit the profile. It installs as a new app.")
                        .font(Wax.Ramp.secondary.weight(.semibold)).foregroundStyle(Wax.warn)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            if model.canSign && (primary == .install || primary == .needServer) {
                Button("Sign only and export") {
                    exportRun = true; model.sign()
                }
                .buttonStyle(WaxSecondaryButtonStyle())
            }

        }
    }

    private var primaryIcon: String {
        switch primary {
        case .install: "arrow.down.app"
        case .needProfile: "doc.badge.gearshape"
        case .needServer: "icloud.and.arrow.up"
        case .needIdentity(let canImport): canImport ? "key" : "person.badge.key"
        case .needApp: "shippingbox"
        }
    }

    private func runPrimary() {
        switch primary {
        case .needApp: picking = true
        case .needIdentity(let canImport): if canImport { router.openCredentials() } else { chooseIdentity = true }
        case .needProfile: router.openCredentials()
        case .needServer: router.openInstallHost()
        case .install: exportRun = false; Task { await model.signAndInstall(ota: ota) { openURL($0) } }
        }
    }

    /// The share of the job that is measured done. Unpacking, signing and packing each move the whole file, so the
    /// sign pass is the measured part. A run that uploads splits the bar between signing and uploading; a run that
    /// hands the file straight to iOS has nothing to measure after signing, so signing is the whole bar and the
    /// handoff completes it. No time estimate is involved. A reserved install session and the "installing" flag are
    /// true before signing starts, so they cannot count as past it: the melt starts at 0 and only the handoff reaches 100.
    private var measuredFraction: Double {
        SignProgress.fraction(signFraction: model.signFraction,
                              signed: model.report != nil,
                              uploading: uploading,
                              uploadFraction: uploadProgress,
                              handedToHost: handedToiOS,
                              exportOnly: exportRun,
                              remoteHost: ota.isConfigured && ota.hostKind != .phone)
    }

    /// Stops waiting when iOS's install prompt was dismissed; the signed app stays in the IPA tab.
    private var cancelWaitButton: some View {
        Button("Cancel install") { model.cancelInstallation(ota: ota) }
            .buttonStyle(WaxSecondaryButtonStyle())
            .accessibilityHint("Stops waiting for iOS. The signed app stays in the IPA tab.")
    }

    /// While Wax works: the melting wax, the percent, the stage, and the engine's own words underneath.
    private func progressCard(_ current: SignStage) -> some View {
        let percent = Int(measuredFraction * 100)
        let message = progressMessage
        let sequence = SignStage.sequence(exportOnly: exportRun)
        return VStack(spacing: Wax.Space.m) {
            WaxMelt(progress: measuredFraction, height: 230, isVisible: router.tab == .sign)
            Text("\(percent)%")
                .font(.system(size: min(percentSize, 64), weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Wax.text)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: percent)
            stageStrip(current, sequence: sequence)
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
        .accessibilityValue("\(current.spoken(in: sequence)). \(percent) percent. \(message)")
    }

    /// The run's stages in order: the one in hand is wax-red, the ones before it are ticked. At accessibility
    /// sizes the strip becomes one sentence, because five labels side by side cannot be read there.
    private func stageStrip(_ current: SignStage, sequence: [SignStage]) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(current.spoken(in: sequence))
                    .font(Wax.Ramp.secondary.weight(.semibold))
                    .foregroundStyle(Wax.text)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: Wax.Space.s) {
                    ForEach(sequence, id: \.self) { stage in
                        VStack(spacing: 4) {
                            Image(systemName: stage.isDone(current: current) ? "checkmark.circle.fill"
                                            : (stage == current ? "circle.fill" : "circle"))
                                .font(.system(size: min(stageGlyphSize, 26), weight: .semibold))
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
            }
        }
        .waxMotion(value: current)
    }

    /// What Wax is doing right now, in the engine's own words. Host-aware: never claims work that has not started.
    private var progressMessage: String {
        if waitingForTransfer { return "Waiting for iOS to take the app…" }
        if uploading {
            switch ota.hostKind {
            case .bucket: return "Sending to your bucket…"
            case .server: return "Sending to your server…"
            case .phone: return "Sending the app from this iPhone…"
            }
        }
        if waitingForTransfer { return "Waiting for iOS to take the app…" }
        if isReading { return model.ipaName ?? "Reading the file…" }
        if let busy = model.busyMessage { return busy.hasSuffix("…") ? busy : busy + "…" }
        return preparingHost || model.installing ? "Preparing installation…" : "Signing the app…"
    }

    private var uploadProgress: Double? { if case .uploading(let p) = ota.state { return p } else { return nil } }

    private func resultCard(_ r: SigningModel.Report) -> some View {
        let failed = !r.checkFailures.isEmpty
        return VStack(spacing: Wax.Space.s) {
            resultHeader(failed)
            if !failed { shelfSaveFeedback }
            if let link = model.readyLink {
                Button { openURL(link) } label: { Label(waitingForTransfer ? "Open install again" : "Install", systemImage: "arrow.down.app") }
                    .buttonStyle(WaxPrimaryButtonStyle())
            }
            exportButton(r)
            Button { model.clearResult(); ota.reset() } label: {
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
        .padding(.top, Wax.Space.xs)
    }

    private func resultHeader(_ failed: Bool) -> some View {
        HStack(spacing: Wax.Space.l) {
            WaxSeal(size: 76)
                .scaleEffect(stamped || reduceMotion ? 1 : 1.9)
                .rotationEffect(.degrees(stamped || reduceMotion ? 0 : -14))
                .opacity(stamped || reduceMotion ? 1 : 0)
            VStack(alignment: .leading, spacing: Wax.Space.xs) {
                Text(resultTitle(failed: failed))
                    .font(.headline).foregroundStyle(failed ? Wax.bad : (waitingForTransfer ? Wax.text : Wax.ok))
                Text(resultSubtitle).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Wax.Space.l).padding(.vertical, Wax.Space.m)
        .frame(maxWidth: .infinity)
        .background(failed ? Wax.badBg : (waitingForTransfer ? Wax.chip : Wax.okBg), in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func resultTitle(failed: Bool) -> String {
        if failed { return "Signed, with problems" }
        if waitingForTransfer { return "Handed to iOS" }
        if handedToiOS { return "Signed and handed to iOS" }
        return "Signed"
    }

    private var resultSubtitle: String {
        if waitingForTransfer { return "Waiting for iOS to take the app. Keep Wax open." }
        if handedToiOS { return "Wax checked the file. iOS decides whether it installs." }
        return "Wax checked the file. Export it or sign again."
    }

    @ViewBuilder private var shelfSaveFeedback: some View {
        switch model.shelfSaveState {
        case .idle:
            Text("Signed file ready to export.")
                .font(.footnote).foregroundStyle(Wax.sub)
        case .saving:
            ProgressView("Saving signed IPA…")
                .font(.footnote).foregroundStyle(Wax.sub)
        case .saved:
            signedShelfLink
        case .failed(let failure):
            WaxFeedbackCard(tone: .bad, text: failure.localizedDescription)
            Button("Retry Save") { Task { await model.retrySignedSave() } }
                .buttonStyle(WaxSecondaryButtonStyle())
        }
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

    /// A problem sits below the selection, with the way back into Files only when another file is a real choice.
    @ViewBuilder private func errorCard(_ text: String) -> some View {
        if model.recovery != nil {
            VStack(spacing: Wax.Space.s) {
                WaxFeedbackCard(tone: .bad, text: text, actionTitle: "Remove app extensions") {
                    model.removeUnsupportedExtensions()
                }
                .accessibilityIdentifier("removeUnsupportedExtensions")
                Text("Removes widgets and other extensions from the signed copy. Your original IPA stays unchanged.")
                    .font(.footnote).foregroundStyle(Wax.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if model.ipaInfo != nil {
            WaxFeedbackCard(tone: .bad, text: text, actionTitle: "Choose another file") {
                picking = true
                ImportLogs.shared.log("sign: choose another from error")
            }
        } else {
            WaxFeedbackCard(tone: .bad, text: text)
        }
    }

    // MARK: Details

    private var detailsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Wax.Space.m) {
                    WaxPanel {
                        if let info = model.ipaInfo {
                            WaxListRow(icon: "app", title: "App's bundle ID", detail: info.bundleIdentifier)
                                .textSelection(.enabled)
                            WaxRowDivider()
                        }
                        BundleIDModePicker(mode: $model.bundleIDMode)
                        WaxRowDivider()
                        WaxListRow(icon: "doc.text", title: "Profile") {
                            WaxRowValue(text: "\(credentials.profiles.count) imported · automatic")
                        }
                        WaxRowDivider()
                        NavigationLink { SigningOptionsView(model: model) } label: {
                            WaxListRow(icon: "slider.horizontal.3", title: "Signing options") {
                                if !model.edits.isEmpty { WaxPill(text: "Changed", tone: .ok) }
                                WaxChevron()
                            }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                    }
                    if let passport = model.passportReport {
                        WaxPanel { passportDetails(passport).padding(.vertical, Wax.Space.m) }
                    }
                    if let r = model.report { WaxPanel { reportDetails(r).padding(.vertical, Wax.Space.m) } }
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
        VStack(alignment: .leading, spacing: Wax.Space.s) {
            Text("What Wax checked").font(Wax.Ramp.rowLabel).foregroundStyle(Wax.text)
            HStack(alignment: .top, spacing: Wax.Space.s) {
                Image(systemName: r.checkFailures.isEmpty ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(r.checkFailures.isEmpty ? Wax.ok : Wax.bad)
                    .accessibilityHidden(true)
                Text(r.checkSummary + " (Wax's own consistency checks, not Apple's verifier.)")
                    .font(Wax.Ramp.paragraph).foregroundStyle(Wax.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !r.checkFailures.isEmpty || !r.warnings.isEmpty {
                Text("Needs attention").font(Wax.Ramp.section).foregroundStyle(Wax.sub)
                    .padding(.top, Wax.Space.xs)
                ForEach(r.checkFailures, id: \.self) { failure in
                    findingLine(symbol: "xmark.octagon.fill", color: Wax.bad, text: failure)
                }
                ForEach(r.warnings, id: \.self) { warning in
                    findingLine(symbol: "exclamationmark.triangle.fill", color: Wax.warn, text: warning)
                }
            }
            if !r.profileLines.isEmpty {
                detailGroup(title: "Profiles") {
                    ForEach(r.profileLines, id: \.self) { Text($0).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub) }
                }
            }
            if !r.archiveLines.isEmpty {
                detailGroup(title: "Archive details") {
                    ForEach(r.archiveLines, id: \.self) { Text($0).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub) }
                }
            }
        }
    }

    @ViewBuilder private func passportDetails(_ report: SigningPreflightReport) -> some View {
        let blocked = report.findings.filter { $0.status == .blocked }
        let warnings = report.findings.filter { $0.status == .warning }
        let unknowns = report.findings.filter { $0.status == .unknown }
        let passes = report.findings.filter { $0.status == .pass }
        VStack(alignment: .leading, spacing: Wax.Space.s) {
            Text("Installability preview").font(Wax.Ramp.rowLabel).foregroundStyle(Wax.text)
            Text("Wax checks these inputs before signing. Only iOS can make the final install decision.")
                .font(Wax.Ramp.paragraph).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            if !blocked.isEmpty {
                Text("Blocking").font(Wax.Ramp.section).foregroundStyle(Wax.sub)
                ForEach(blocked) { finding in findingRow(finding) }
            }
            if !warnings.isEmpty {
                Text("Needs attention").font(Wax.Ramp.section).foregroundStyle(Wax.sub)
                ForEach(warnings) { finding in findingRow(finding) }
            }
            if !unknowns.isEmpty {
                detailGroup(title: "Wax cannot know (\(unknowns.count))") {
                    ForEach(unknowns) { finding in findingRow(finding) }
                }
            }
            if !passes.isEmpty {
                detailGroup(title: "Checked and passed (\(passes.count))") {
                    ForEach(passes) { finding in findingRow(finding) }
                }
            }
        }
    }

    private func findingLine(symbol: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: Wax.Space.s) {
            Image(systemName: symbol).foregroundStyle(color).accessibilityHidden(true)
            Text(text).font(Wax.Ramp.secondary).foregroundStyle(Wax.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func findingRow(_ finding: PreflightFinding) -> some View {
        VStack(alignment: .leading, spacing: Wax.Space.xs) {
            HStack(alignment: .top, spacing: Wax.Space.s) {
                Image(systemName: findingSymbol(finding.status))
                    .foregroundStyle(findingColor(finding.status)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Wax.Space.hairline) {
                    Text(finding.title).font(Wax.Ramp.rowLabel).foregroundStyle(Wax.text)
                    Text(finding.status.rawValue.capitalized).font(Wax.Ramp.caption).foregroundStyle(findingColor(finding.status))
                }
            }
            Text(finding.detail).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            if !finding.evidence.isEmpty {
                Text(finding.evidence).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Wax.Space.xs)
    }

    private func detailGroup<Content: View>(title: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: Wax.Space.s) { content() }
                .padding(.top, Wax.Space.xs)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(title).font(Wax.Ramp.rowLabel).foregroundStyle(Wax.text)
        }
        .tint(Wax.link)
    }

    private func findingSymbol(_ status: PreflightStatus) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    private func findingColor(_ status: PreflightStatus) -> Color {
        switch status {
        case .pass: Wax.ok
        case .warning: Wax.warn
        case .blocked: Wax.bad
        case .unknown: Wax.sub
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
