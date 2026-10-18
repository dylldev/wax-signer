import CredentialKit
import InstallKit
import IPAKit
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

    private var uploading: Bool { if case .uploading = ota.state { return true } else { return false } }

    private var errorText: String? {
        if let e = model.errorText { return e }
        if case .failed(let t) = ota.state { return t }
        return nil
    }

    private var handedToiOS: Bool { ota.state == .handedToiOS }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    header.id("top")
                    if phase == .signing || uploading {
                        progressCard
                    } else if phase == .done && errorText == nil, let r = model.report {
                        resultCard(r)
                    } else {
                        summaryCard
                        idleActions
                        if let error = errorText { errorCard(error) }
                        optionsRow
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
        .onChange(of: phase) { _, new in if new == .done { playStamp() } else { stamped = false } }
        .onChange(of: inbox.pendingLink) { _, _ in openPendingInstall() }
        .onAppear { openPendingInstall() }   // a tap that launched Wax from scratch
        .onChange(of: handedToiOS) { _, new in if new { playStamp() } }
    }

    /// A tapped "Ready to install" notification: go to this screen and bring up iOS's install prompt.
    private func openPendingInstall() {
        guard let link = inbox.pendingLink else { return }
        router.tab = .sign
        inbox.pendingLink = nil
        // iOS ignores the install request while Wax is still coming to the front, so wait until it is active.
        Task { @MainActor in
            for _ in 0..<30 where UIApplication.shared.applicationState != .active { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(300))
            openURL(link)
        }
    }

    // MARK: Pieces

    private var header: some View { WaxHeader(title: "Sign", subtitle: "Sign an app and install it on this iPhone.") }

    /// One card: the app on top, the identity below. Each row opens its own picker.
    private var summaryCard: some View {
        WaxPanel {
            Button { picking = true; ImportLogs.shared.log("sign: choose tapped") } label: { appRow }
                .buttonStyle(.plain)
                .disabled(model.busyMessage != nil)
                .accessibilityHint("Opens Files to pick an IPA")
            WaxDivider()
            Button { identityTapped() } label: { identityRow }
                .buttonStyle(.plain)
                .disabled(model.busyMessage != nil)
        }
    }

    private func summaryRow<T: View>(icon: String, title: String, subtitle: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium)).foregroundStyle(Wax.link)
                .frame(width: 40, height: 40)
                .background(Wax.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Wax.text).lineLimit(1)
                Text(subtitle).font(.footnote).foregroundStyle(Wax.sub).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: Wax.rowHeight)
        .contentShape(Rectangle())
    }

    private var appRow: some View {
        Group {
            if let info = model.ipaInfo {
                summaryRow(icon: "shippingbox", title: info.displayName.isEmpty ? "App" : info.displayName,
                           subtitle: appSubtitle(info)) { WaxLinkText(text: "Change") }
            } else {
                summaryRow(icon: "shippingbox", title: isReading ? "Reading the app…" : "Choose an app",
                           subtitle: isReading ? (model.ipaName ?? "") : "Pick an IPA from Files") {
                    if isReading { ProgressView() } else { WaxLinkText(text: "Choose") }
                }
            }
        }
    }

    private func appSubtitle(_ info: IPAMetadata) -> String {
        let version = [info.version, info.build.isEmpty ? "" : "(\(info.build))"].filter { !$0.isEmpty }.joined(separator: " ")
        return version.isEmpty ? "Version unknown" : version
    }

    private var identityRow: some View {
        Group {
            if credentials.certificates.isEmpty {
                summaryRow(icon: "key", title: "Add a signing identity", subtitle: "Import a certificate and profile") { WaxLinkText(text: "Import") }
            } else if let cert = certificate {
                summaryRow(icon: "key", title: cert.organization ?? cert.commonName, subtitle: identitySubtitle(cert)) {
                    IdentityReadiness.status(for: cert, profiles: credentials.profiles).pill
                }
            } else {
                summaryRow(icon: "key", title: "Choose an identity", subtitle: "Pick the certificate to sign with") { WaxLinkText(text: "Choose") }
            }
        }
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
            HStack {
                Text("Options").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Wax.sub)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { WaxDivider() }
        .padding(.top, 6)
    }

    // MARK: Action zone

    private var idleActions: some View {
        VStack(spacing: 8) {
            Button { runPrimary() } label: {
                Label(primary.title, systemImage: primaryIcon)
            }
            .buttonStyle(WaxPrimaryButtonStyle())
            .disabled(model.installing)
            .padding(.top, 4)
            Text(primary.reason)
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
                Button("Sign only and export") { exportRun = true; model.sign() }.buttonStyle(WaxSecondaryButtonStyle())
            }
        }
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
        case .install: exportRun = false; Task { await model.signAndInstall(ota: ota) { openURL($0) } }
        }
    }

    /// 0...1 for the whole job, from the real signing and upload progress weighted by expected time.
    private var jobFraction: Double {
        let signing = (model.report != nil || uploading) ? 1 : model.signFraction
        return model.jobProgress(uploadFraction: uploadProgress ?? 0, exportOnly: exportRun).overall(sign: signing, upload: uploadProgress ?? 0)
    }

    /// While Wax works the screen is just the animation, the percent and one line of status.
    private var progressCard: some View {
        let percent = Int(jobFraction * 100)
        let status = uploading ? "Sending to your server…"
            : (model.busyMessage.map { $0.hasSuffix("…") ? $0 : $0 + "…" } ?? "Signing the app…")
        return VStack(spacing: 10) {
            WaxMelt(progress: jobFraction, height: 270)
            Text("\(percent)%")
                .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Wax.text)
                .contentTransition(.numericText())
            Text(status).font(.subheadline).foregroundStyle(Wax.sub).lineLimit(1)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signing")
        .accessibilityValue("\(percent) percent. \(status)")
    }

    private var uploadProgress: Double? { if case .uploading(let p) = ota.state { return p } else { return nil } }

    private func resultCard(_ r: SigningModel.Report) -> some View {
        let failed = !r.checkFailures.isEmpty
        return VStack(spacing: 8) {
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

            if let link = model.readyLink {
                Button { openURL(link) } label: { Label("Install", systemImage: "arrow.down.app") }
                    .buttonStyle(WaxPrimaryButtonStyle())
            }
            let size = ByteCountFormatter.string(fromByteCount: Int64(r.outputSize), countStyle: .file)
            if model.readyLink == nil {
                ShareLink(item: r.output) { Label("Export signed IPA · \(size)", systemImage: "square.and.arrow.up") }
                    .buttonStyle(WaxPrimaryButtonStyle())
            } else {
                ShareLink(item: r.output) { Label("Export signed IPA · \(size)", systemImage: "square.and.arrow.up") }
                    .buttonStyle(WaxSecondaryButtonStyle())
            }
            Button("Start over") { model.clearResult(); ota.reset() }.buttonStyle(WaxSecondaryButtonStyle())
            Button("What Wax checked") { showDetails = true }
                .font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub).frame(minHeight: 44)
        }
        .padding(.top, 4)
    }

    private var resultSubtitle: String {
        if handedToiOS { return "Wax checked the file. iOS decides whether it installs." }
        return "Wax checked the file. Export it or sign again."
    }

    private func errorCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Wax.bad).frame(width: 22, height: 22)
            Text(text).font(.footnote).foregroundStyle(Wax.text).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Wax.badBg, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Problem. \(text)")
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bundle ID").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                        Picker("Bundle ID", selection: $model.bundleIDMode) {
                            Text("Keep original").tag(SigningModel.BundleIDMode.keep)
                            Text("Rename to fit").tag(SigningModel.BundleIDMode.rename)
                        }
                        .pickerStyle(.segmented)
                        Text(model.bundleIDMode == .keep
                             ? "Signs under the profile's app ID and leaves the app's own ID alone. Recommended."
                             : "Renames the app to fit a profile that allows one app ID. Only needed if iOS refuses the original ID.")
                            .font(.footnote).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
                    }
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

    // MARK: Motion

    private func playStamp() {
        stamped = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.55)) { stamped = true }
    }
}
