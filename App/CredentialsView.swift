import CredentialKit
import InstallKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CredentialsView: View {
    var showDeveloperTools = false
    @EnvironmentObject private var model: CredentialsModel
    @EnvironmentObject private var ota: OTAInstallModel
    #if WAX_DEVELOPMENT
    @EnvironmentObject private var tester: IdentityTester
    #endif
    @EnvironmentObject private var router: Router
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showImportSheet = false
    @State private var certToDelete: CertificateInfo?
    @State private var profileToDelete: ProfileInfo?
    @State private var successNote: String?

    // Any file can be picked and is validated by content. Filtering by type greyed out real certificates
    // and profiles whose extension iOS does not map to a known type (renamed files, iCloud downloads, .pfx).

    var body: some View {
        dialogChrome
    }

    /// Each certificate with every profile, so you can see which pairs work without picking anything.

    // MARK: Presentation chrome

    /// Lifecycle chrome kept off the list property so each expression type-checks quickly.
    private var stateChrome: some View {
        Group {
            credentialsList
        }
        // VoiceOver has no other way to learn an import started: the overlay is not focused when it appears.
        .onChange(of: model.busyMessage) { _, busy in
            guard let busy else { return }
            successNote = nil
            UIAccessibility.post(notification: .announcement, argument: busy)
        }
        .onDisappear { model.dismissImport() }
        // Tabs stay mounted behind opacity, so clear an abandoned draft when switching tabs.
        .onChange(of: router.tab) { _, tab in
            if tab != .settings { showImportSheet = false; model.dismissImport() }
        }
    }

    private var pickerChrome: some View {
        stateChrome
            .sheet(isPresented: $showImportSheet, onDismiss: { model.dismissImport(); model.message = nil }) {
                CredentialImportSheet().environmentObject(model)
            }
            .overlay {
                busyOverlay
            }
    }

    private var alertChrome: some View {
        pickerChrome
            .alert("Credentials", isPresented: Binding(
                get: { if !showImportSheet, let message = model.message { return !message.hasPrefix("Imported ") }; return false },
                set: { if !$0 { model.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.message ?? "") }
    }

    private var dialogChrome: some View {
        alertChrome
            .confirmationDialog("Delete this certificate and its private key?",
                                isPresented: Binding(get: { certToDelete != nil }, set: { if !$0 { certToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete certificate and key", role: .destructive) {
                    if let c = certToDelete { model.delete(certificate: c) }
                    certToDelete = nil
                }
            } message: {
                certificateDeleteMessage
            }
            .confirmationDialog("Delete this provisioning profile?",
                                isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete profile", role: .destructive) {
                    if let p = profileToDelete { model.delete(profile: p) }
                    profileToDelete = nil
                }
            } message: {
                profileDeleteMessage
            }
    }

    /// The floating import-progress card.
    @ViewBuilder private var busyOverlay: some View {
        if !showImportSheet, let busy = model.busyMessage {
            VStack(spacing: 10) {
                WaxProgressBar(progress: nil)
                Text(busy).font(Wax.Ramp.value).foregroundStyle(Wax.text)
                if model.canCancelReading { Button("Cancel opening") { model.cancelPassword() } }
            }
            .padding(Wax.Space.l)
            .background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous).stroke(Wax.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
    }

    /// Import successes become the inline card; later non-import messages clear a stale card.
    private func handleMessage(_ message: String?) {
        if let message, message.hasPrefix("Imported ") {
            successNote = message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            successNote = nil
        }
        AccessibilityNotification.Announcement(message ?? "").post()
    }

    // MARK: Page sections

    /// The scrolling list. Kept separate from the alerts so the expression type-checks.
    private var credentialsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    importSection
                    certificateSection
                    profileSection
                    privacySection
                    #if WAX_DEVELOPMENT
                    if showDeveloperTools {
                        WaxSectionLabel(text: "For testing")
                        WaxPanel {
                            NavigationLink { ImportLogView() } label: {
                                WaxListRow(icon: "doc.text.magnifyingglass", title: "Import log") { WaxChevron() }
                            }
                            .buttonStyle(WaxRowButtonStyle())
                        }
                    }
                    #endif
                }
                .padding(.horizontal, Wax.inset)
                .padding(.bottom, Wax.Space.tabBarClearance)
            }
            .scrollIndicators(.hidden)
            .background(Wax.bg.ignoresSafeArea())
            .navigationTitle("Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.message) { _, message in handleMessage(message) }
            .onChange(of: model.importedItemID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : Wax.spring) { proxy.scrollTo(id, anchor: .center) }
            }
            .toolbarBackground(Wax.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    @ViewBuilder private var importSection: some View {
        WaxPanel {
            importRow(icon: "key", title: "Import credentials", subtitle: "Certificate and provisioning profile") {
                model.dismissImport(); model.message = nil; showImportSheet = true
            }
        }
        if let successNote { WaxFeedbackCard(tone: .ok, text: successNote) }
    }

    @ViewBuilder private var certificateSection: some View {
        WaxSectionLabel(text: "Certificates")
        if model.certificates.isEmpty {
            WaxEmptyState(symbol: "key", title: "Bring your own signing files",
                          message: "Wax needs a certificate (.p12 or .pfx) and a matching profile (.mobileprovision). Import both using the button above. Wax does not issue these files.")
        }
        ForEach(model.certificates) { cert in
            identityCard(cert).id("credential-\(cert.id)")
        }
    }

    @ViewBuilder private var profileSection: some View {
        WaxSectionLabel(text: "Provisioning profiles")
        if model.profiles.isEmpty {
            WaxEmptyState(symbol: "doc.text", title: "Import the matching profile",
                          message: "Choose the .mobileprovision file supplied with your certificate using the button above. Then return to Sign and choose your certificate.")
        }
        ForEach(model.profiles) { profile in
            profileCard(profile).id("credential-\(profile.id)")
        }
    }

    @ViewBuilder private var privacySection: some View {
        WaxPanel {
            DisclosureGroup {
                Text("Private keys are held in the iOS Keychain. Passwords are never stored. Before signing, Wax checks profile signatures and their certificate chains. An intact signature alone does not establish Apple trust. Revocation is not checked, and iOS makes the final installation decision.")
                    .font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Wax.Space.s)
            } label: {
                Text("Privacy & checks").font(Wax.Ramp.body).foregroundStyle(Wax.text)
            }
            .tint(Wax.link)
            .padding(.vertical, Wax.Space.s)
        }
    }

    // MARK: Pieces

    private func importRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            WaxRow(icon: icon, title: title, subtitle: subtitle) { WaxLinkText(text: "Import") }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .disabled(model.busyMessage != nil)
    }

    private func identityCard(_ cert: CertificateInfo) -> some View {
        let status = model.identityStatus(for: cert)
        return WaxPanel {
            WaxListRow(icon: "key", title: model.displayName(for: cert),
                       detail: [IdentityReadiness.kindLabel(for: cert, profiles: model.profiles) ?? "No matching profile",
                                cert.teamID ?? "unknown team"].joined(separator: Wax.separator), titleLineLimit: 2) {
                status.pill
            }
            switch status {
            case .needsAttention(let detail):
                WaxFeedbackCard(tone: .bad, text: detail)
            case .installFailed:
                WaxFeedbackCard(tone: .warn, text: status.detail)
            default: EmptyView()
            }
            WaxRowDivider()
            WaxKV(key: "Expires", value: certExpiry(cert))
            if let org = cert.organization, org != cert.commonName {
                WaxRowDivider()
                WaxKV(key: "Common name", value: cert.commonName, small: true).textSelection(.enabled)
            }
            #if WAX_DEVELOPMENT
            if showDeveloperTools {
                WaxRowDivider()
                WaxKV(key: "SHA-1", value: cert.sha1Fingerprint, small: true)
                installTestRow(cert)
            }
            #endif
            if !model.profiles.isEmpty {
                WaxDivider()
                Text("Works with").font(Wax.Ramp.secondary).foregroundStyle(Wax.sub).padding(.top, Wax.Space.m)
                ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { WaxRowDivider() }
                    compatibilityRow(cert, profile)
                }
            }
            WaxDivider()
            WaxDestructiveRow(title: "Delete certificate") { certToDelete = cert }.disabled(model.busyMessage != nil)
        }
    }

    private func certExpiry(_ cert: CertificateInfo) -> String {
        let date = cert.notAfter.formatted(date: .abbreviated, time: .omitted)
        return cert.notAfter < Date() ? date + Wax.separator + "Expired" : date
    }

    #if WAX_DEVELOPMENT
    private func installTestRow(_ cert: CertificateInfo) -> some View {
        let status = model.identityStatus(for: cert)
        let mine = tester.testing == cert.id
        return VStack(alignment: .leading, spacing: 8) {
            Text(status.detail).font(.footnote).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            if mine || (tester.testing == nil && tester.lastTested == cert.id && tester.state != .idle) { testProgress }
            HStack(spacing: 16) {
                Button {
                    Task { await tester.test(cert, credentials: model, ota: ota) { openURL($0) } }
                } label: {
                    Label(mine ? "Testing…" : "Test install on this phone", systemImage: "arrow.down.app").font(.subheadline.weight(.semibold))
                }
                .disabled(tester.isRunning || !ota.canInstall)
                .tint(Wax.link)
                if mine { Button("Cancel test", role: .destructive) { tester.cancel() } }
                if InstallTestStore().result(for: cert.sha1Fingerprint) != nil {
                    Button("Forget result") { tester.forget(cert) }.font(.subheadline).tint(Wax.sub)
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var testProgress: some View {
        switch tester.state {
        case .idle: EmptyView()
        case .signing: Label("Signing the test app…", systemImage: "signature").font(.footnote).foregroundStyle(Wax.text)
        case .uploading(let f): ProgressView("Sending the test app…", value: f).font(.footnote)
        case .waiting(let left):
            Label("Tap Install when iOS asks. Waiting for the app… \(left)s", systemImage: "hourglass").font(.footnote).foregroundStyle(Wax.text)
        case .finished(let result, let text):
            Label(text, systemImage: result == .installed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.footnote).foregroundStyle(result == .installed ? Wax.ok : Wax.bad)
        case .problem(let text):
            Label(text, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Wax.bad)
        }
    }

    #endif

    private func compatibilityRow(_ cert: CertificateInfo, _ profile: ProfileInfo) -> some View {
        let report = CompatibilityReport.evaluate(certificate: cert, profile: profile, now: Date())
        let failures = report.checks.filter { $0.status == .fail }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(failures.isEmpty ? Wax.ok : Wax.bad).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(Wax.Ramp.value).foregroundStyle(Wax.text)
                Text(failures.isEmpty ? "Compatible. Static checks pass." : failures.map(\.detail).joined(separator: " "))
                    .font(Wax.Ramp.secondary).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func profileCard(_ profile: ProfileInfo) -> some View {
        WaxPanel {
            WaxListRow(icon: "doc.text",
                       title: profile.name,
                       detail: profile.applicationIdentifier, titleLineLimit: 2) {
                WaxRowValue(text: profileExpiry(profile))
            }
            .textSelection(.enabled)
            WaxRowDivider()
            WaxKV(key: "Team", value: profile.teamName.map { "\($0) (\(profile.teamID))" } ?? profile.teamID)
            WaxRowDivider()
            WaxKV(key: "App ID prefix", value: profile.applicationIdentifierPrefix)
            WaxRowDivider()
            WaxKV(key: "Type (inferred)", value: kind(profile))
            WaxRowDivider()
            WaxKV(key: "Devices", value: devices(profile))
            WaxDivider()
            WaxDestructiveRow(title: "Delete profile") { profileToDelete = profile }.disabled(model.busyMessage != nil)
        }
    }

    private func profileExpiry(_ profile: ProfileInfo) -> String {
        let date = profile.expirationDate.formatted(date: .abbreviated, time: .omitted)
        return profile.isExpired(at: Date()) ? date + Wax.separator + "Expired" : date
    }

    private var certificateDeleteMessage: Text {
        if let c = certToDelete { return Text("\(c.organization ?? c.commonName) and its private key are removed from Wax. Apps already installed stay. You can import the .p12 file again.") }
        return Text("Apps already installed stay. You can import the .p12 file again.")
    }

    private var profileDeleteMessage: Text {
        if let p = profileToDelete { return Text("\(p.name) is removed from Wax. Apps already installed stay. You can import the .mobileprovision file again.") }
        return Text("Apps already installed stay. You can import the .mobileprovision file again.")
    }

    private func kind(_ profile: ProfileInfo) -> String { profile.kind.title }

    private func devices(_ profile: ProfileInfo) -> String {
        if profile.provisionsAllDevices { return "All devices" }
        if let n = profile.provisionedDeviceCount { return "\(n) provisioned" }
        return "No device list"
    }
}
