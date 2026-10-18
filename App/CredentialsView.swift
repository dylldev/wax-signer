import CredentialKit
import InstallKit
import SwiftUI
import UniformTypeIdentifiers

struct CredentialsView: View {
    @EnvironmentObject private var model: CredentialsModel
    @EnvironmentObject private var ota: OTAInstallModel
    @EnvironmentObject private var tester: IdentityTester
    @Environment(\.openURL) private var openURL
    private enum ImportKind { case certificate, profile }
    // One picker for both kinds. It is the system document picker in copy mode (see DocumentPicker).
    @State private var importKind: ImportKind = .certificate
    @State private var showImporter = false
    @State private var password = ""
    @State private var certToDelete: CertificateInfo?
    @State private var profileToDelete: ProfileInfo?

    // Any file can be picked and is validated by content. Filtering by type greyed out real certificates
    // and profiles whose extension iOS does not map to a known type (renamed files, iCloud downloads, .pfx).

    var body: some View {
        Group {
            ScrollView {
                VStack(spacing: 10) {
                    WaxHeader(title: "Credentials", subtitle: "Your certificates and provisioning profiles.")
                    importRow(icon: "key", title: "Import a certificate", subtitle: ".p12 or .pfx file") {
                        ImportLogs.shared.log("p12: import tapped")
                        importKind = .certificate; showImporter = true
                    }
                    importRow(icon: "doc.badge.gearshape", title: "Import a provisioning profile", subtitle: ".mobileprovision file") {
                        ImportLogs.shared.log("profile: import tapped")
                        importKind = .profile; showImporter = true
                    }

                    WaxSectionLabel(text: "Identities")
                    if model.certificates.isEmpty {
                        emptyCard("No certificates yet", "Import a certificate to sign apps.")
                    }
                    ForEach(model.certificates) { cert in identityCard(cert) }

                    WaxSectionLabel(text: "Provisioning profiles")
                    if model.profiles.isEmpty {
                        emptyCard("No profiles yet", "A profile ties a certificate to your device.")
                    }
                    ForEach(model.profiles) { profile in profileCard(profile) }

                    Text("Private keys are held in the iOS Keychain. Passwords are never stored. Profile signatures and certificate revocation are not verified.")
                        .font(.footnote).foregroundStyle(Wax.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)

                    NavigationLink { ImportLogView() } label: {
                        HStack {
                            Text("Import log").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(Wax.sub)
                        .frame(minHeight: 52)
                        .overlay(alignment: .top) { WaxDivider() }
                    }
                }
                .padding(.horizontal, Wax.inset)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Wax.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Wax.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { picked in
                showImporter = false
                guard let picked else {
                    ImportLogs.shared.log("\(importKind == .certificate ? "p12" : "profile"): picker cancelled")
                    return
                }
                switch importKind {
                case .certificate: model.picked(p12: .success(picked))
                case .profile: model.picked(profile: .success(picked))
                }
            }
        }
        .overlay {
            if let busy = model.busyMessage {
                ProgressView(busy)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Password for \(model.pendingFileName)", isPresented: $model.awaitingPassword) {
            SecureField("Password", text: $password)
            Button("Import") { let p = password; password = ""; model.confirmPassword(p) }
            Button("Cancel", role: .cancel) { password = ""; model.cancelPassword() }
        }
        .alert("Credentials", isPresented: Binding(get: { model.message != nil },
                                                   set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(model.message ?? "") }
        .confirmationDialog("Delete this certificate and its private key?",
                            isPresented: Binding(get: { certToDelete != nil }, set: { if !$0 { certToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete certificate and key", role: .destructive) {
                if let c = certToDelete { model.delete(certificate: c) }
                certToDelete = nil
            }
        }
        .confirmationDialog("Delete this provisioning profile?",
                            isPresented: Binding(get: { profileToDelete != nil }, set: { if !$0 { profileToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                if let p = profileToDelete { model.delete(profile: p) }
                profileToDelete = nil
            }
        }
    }

    /// Each certificate with every profile, so you can see which pairs work without picking anything.

    // MARK: Pieces

    private func importRow(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            WaxRow(icon: icon, title: title, subtitle: subtitle) { WaxLinkText(text: "Import") }
        }
        .buttonStyle(.plain)
    }

    private func emptyCard(_ title: String, _ text: String) -> some View {
        WaxPanel {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Wax.text)
                Text(text).font(.footnote).foregroundStyle(Wax.sub)
            }
            .frame(maxWidth: .infinity, minHeight: Wax.rowHeight, alignment: .leading)
        }
    }

    private func identityCard(_ cert: CertificateInfo) -> some View {
        WaxPanel {
            HStack(spacing: 12) {
                Image(systemName: "key").font(.system(size: 19, weight: .medium)).foregroundStyle(Wax.link)
                    .frame(width: 40, height: 40)
                    .background(Wax.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cert.organization ?? cert.commonName).font(.callout.weight(.semibold)).foregroundStyle(Wax.text).lineLimit(1)
                    Text("\(IdentityReadiness.kindLabel(for: cert, profiles: model.profiles) ?? "No matching profile") · \(cert.teamID ?? "unknown team")")
                        .font(.footnote).foregroundStyle(Wax.sub).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IdentityReadiness.status(for: cert, profiles: model.profiles).pill
            }
            .padding(.vertical, 14)
            WaxDivider()
            WaxKV(key: "Expires", value: cert.notAfter.formatted(date: .abbreviated, time: .omitted))
            WaxDivider()
            WaxKV(key: "SHA-1", value: cert.sha1Fingerprint, small: true)
            WaxDivider()
            installTestRow(cert)
            if !model.profiles.isEmpty {
                WaxDivider()
                Text("Works with").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub).padding(.top, 11)
                ForEach(model.profiles) { profile in compatibilityRow(cert, profile) }
            }
            WaxDivider()
            WaxDestructiveRow(title: "Delete certificate") { certToDelete = cert }
        }
    }

    private func installTestRow(_ cert: CertificateInfo) -> some View {
        let status = IdentityReadiness.status(for: cert, profiles: model.profiles)
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
                .disabled(tester.isRunning)
                .tint(Wax.link)
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

    private func compatibilityRow(_ cert: CertificateInfo, _ profile: ProfileInfo) -> some View {
        let report = CompatibilityReport.evaluate(certificate: cert, profile: profile, now: Date())
        let failures = report.checks.filter { $0.status == .fail }
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(failures.isEmpty ? Wax.ok : Wax.bad).frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.subheadline).foregroundStyle(Wax.text)
                Text(failures.isEmpty ? "Compatible. Static checks pass." : failures.map(\.detail).joined(separator: " "))
                    .font(.footnote).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func profileCard(_ profile: ProfileInfo) -> some View {
        WaxPanel {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.callout.weight(.semibold)).foregroundStyle(Wax.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.applicationIdentifier).font(.footnote).foregroundStyle(Wax.sub)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, minHeight: Wax.rowHeight, alignment: .leading)
            .padding(.vertical, 4)
            WaxDivider()
            WaxKV(key: "Team", value: profile.teamName.map { "\($0) (\(profile.teamID))" } ?? profile.teamID)
            WaxDivider()
            WaxKV(key: "Type (inferred)", value: kind(profile))
            WaxDivider()
            WaxKV(key: "Devices", value: devices(profile))
            WaxDivider()
            WaxKV(key: "Expires", value: profile.expirationDate.formatted(date: .abbreviated, time: .omitted))
            WaxDivider()
            WaxKV(key: "Status", value: profile.isExpired(at: Date()) ? "Expired" : "Not expired")
            WaxDivider()
            WaxDestructiveRow(title: "Delete profile") { profileToDelete = profile }
        }
    }

    private func kind(_ profile: ProfileInfo) -> String {
        switch profile.kind {
        case .development: "Development"
        case .adHoc: "Ad hoc"
        case .enterprise: "Enterprise"
        case .appStore: "App Store"
        }
    }

    private func devices(_ profile: ProfileInfo) -> String {
        if profile.provisionsAllDevices { return "All devices" }
        if let n = profile.provisionedDeviceCount { return "\(n) provisioned" }
        return "No device list"
    }
}
