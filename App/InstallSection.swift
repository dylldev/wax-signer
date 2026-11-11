import InstallKit
import SwiftUI

/// What the install needs to know about the file being installed.
struct InstallTarget {
    let ipa: URL
    let bundleIdentifier: String
    let version: String
    /// CFBundleVersion: what iOS compares when an app is updated; the manifest advertises it.
    let build: String
    let title: String
}

/// Where the signed app is sent so iOS can install it. Built from Wax panels, not a List, so it matches
/// every other settings surface. The Sign & Install button lives above, with its result.
struct InstallSection: View {
    @ObservedObject var model: OTAInstallModel
    /// Setup is complete: show one line and an Edit button instead of the fields.
    var collapsed = false
    /// The certificate is not a known Distribution one, so installing may still be refused.
    var eligibilityUnknown = false
    @State private var editing = false
    @State private var forgetting: String?
    /// Off by default: a signed app can be hundreds of megabytes, and cellular plans are not free.
    @AppStorage("allowCellularUploads") private var allowCellularUploads = false

    var body: some View {
        VStack(alignment: .leading, spacing: Wax.Space.m) {
            WaxPanel {
                Picker("Install host", selection: $model.hostKind) {
                    ForEach(OTAInstallModel.HostKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, Wax.Space.m)
            }
            switch model.hostKind {
            case .phone: phoneSection
            case .bucket: bucketSection
            case .server: serverSection
            }
            if model.hostKind != .phone {
                WaxPanel {
                    Toggle("Upload over cellular", isOn: $allowCellularUploads)
                        .padding(.vertical, Wax.Space.s)
                }
                paragraph("Off by default so a large app does not arrive as a surprise bill. The phone host never uses the network.")
            }
        }
        .confirmationDialog("Forget saved access?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), titleVisibility: .visible) {
            Button("Forget \(forgetting ?? "saved access")", role: .destructive) {
                if forgetting == "bucket keys" { model.forgetBucketKeys() } else { model.forgetToken() }
                forgetting = nil
            }
        } message: {
            Text("Wax will remove this secret from the phone. You will need to enter it again before using this host.")
        }
    }

    // MARK: Sections

    private var phoneSection: some View {
        section("This iPhone") {
            paragraph("Keep Wax open while iOS downloads the app. If this host fails, use My server or export the signed IPA.")
            field("Certificate feed") {
                TextField("https://…", text: $model.certificateFeedText)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            statusLine
        }
    }

    private var bucketSection: some View {
        section("Cloud bucket") {
            paragraph("Wax puts the signed app in a private bucket you own and gives iOS a link that stops working after 6 hours. "
                      + "Any S3-compatible bucket works (Cloudflare R2, Backblaze B2, Oracle Object Storage, MinIO). "
                      + "Free tiers exist, but some providers ask for a card at sign-up to verify you; check theirs. "
                      + "Add a one-day expiry rule on the bucket so nothing is left behind.")
            field("Endpoint") {
                TextField("https://…", text: $model.bucketEndpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            field("Bucket") {
                TextField("Name", text: $model.bucketName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            field("Region") {
                TextField("auto for R2", text: $model.bucketRegion)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if model.hasBucketKeys {
                storedSecret("Keys stored (Keychain, this device only)")
                destructiveAction("Forget keys") { forgetting = "bucket keys" }
            } else {
                field("Access key") {
                    SecureField("Access key", text: $model.accessKeyDraft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                field("Secret key") {
                    SecureField("Secret key", text: $model.secretKeyDraft)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                action("Save keys") { model.saveBucketKeys() }
                    .disabled(model.accessKeyDraft.isEmpty || model.secretKeyDraft.isEmpty)
            }
            action("Test the bucket") { model.testBucket() }
            action("Retry expired upload cleanup") { model.retryBucketCleanup() }
            if let note = model.bucketNote { statusRow(note) }
            statusLine
        }
    }

    private var serverSection: some View {
        section("Install server") {
            if eligibilityUnknown {
                paragraph("Wax cannot tell whether this certificate can install over the air. Only Distribution (Ad Hoc or Enterprise) certificates were seen to work.")
            }
            if collapsed && !editing {
                Label("Setup saved: \(model.serverText)", systemImage: "checkmark.seal")
                    .font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
                    .padding(.vertical, Wax.Space.s)
                action("Edit install server") { editing = true }
            } else {
                setupFields
            }
            statusLine
        }
    }

    @ViewBuilder private var setupFields: some View {
        paragraph("Wax sends the signed app to your own HTTPS server, and iOS installs it from there. The server deletes it "
                  + "after a while (6 hours by default), not when the install finishes.")
        PasteButton(payloadType: String.self) { strings in
            Task { @MainActor in model.applySetup(strings.first ?? "") }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, minHeight: Wax.touch, alignment: .leading)
        field("Server") {
            TextField("https://…", text: $model.serverText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        }
        if model.hasToken {
            storedSecret("Token stored (Keychain, this device only)")
            destructiveAction("Forget token") { forgetting = "server token" }
        } else {
            field("Server token") {
                SecureField("Server token", text: $model.tokenDraft)
            }
            action("Save token") { model.saveToken() }.disabled(model.tokenDraft.isEmpty)
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Wax.Space.s) {
            WaxSectionLabel(text: title)
            WaxPanel { content() }
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text).font(Wax.Ramp.paragraph).foregroundStyle(Wax.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Wax.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Wax.Space.xs) {
            Text(title).font(Wax.Ramp.section).foregroundStyle(Wax.sub)
            content()
                .font(Wax.Ramp.value)
                .padding(.horizontal, Wax.Space.m)
                .frame(maxWidth: .infinity, minHeight: Wax.touch, alignment: .leading)
                .background(Wax.chip, in: RoundedRectangle(cornerRadius: Wax.radiusSmall, style: .continuous))
        }
        .padding(.vertical, Wax.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func storedSecret(_ title: String) -> some View {
        Label(title, systemImage: "lock.shield")
            .font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, Wax.Space.s)
    }

    private func action(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .font(Wax.Ramp.rowLabel).foregroundStyle(Wax.link)
            .frame(maxWidth: .infinity, minHeight: Wax.touch, alignment: .leading)
    }

    private func destructiveAction(_ title: String, perform: @escaping () -> Void) -> some View {
        Button(title, role: .destructive, action: perform)
            .font(Wax.Ramp.rowLabel).foregroundStyle(Wax.bad)
            .frame(maxWidth: .infinity, minHeight: Wax.touch, alignment: .leading)
    }

    private func statusRow(_ note: String) -> some View {
        Group {
            if note.hasPrefix("Checking") {
                ProgressView(note).font(Wax.Ramp.secondary)
            } else {
                Label(note, systemImage: note.contains("accepted") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(Wax.Ramp.secondary).foregroundStyle(note.contains("accepted") ? Wax.ok : Wax.bad)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Wax.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var statusLine: some View {
        switch model.state {
        case .idle:
            if let note = model.tokenNote { statusRow(note) }
        case .preparing:
            ProgressView("Preparing installation…").font(Wax.Ramp.secondary)
                .padding(.vertical, Wax.Space.s)
        case .uploading(let p):
            ProgressView(uploadingLabel, value: p).font(Wax.Ramp.secondary)
                .padding(.vertical, Wax.Space.s)
        case .handedToiOS:
            Text(handoffLabel).font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Wax.Space.s)
        case .failed(let text):
            Text(text).font(Wax.Ramp.secondary).foregroundStyle(Wax.bad)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Wax.Space.s)
        }
        if model.activeSession != nil {
            destructiveAction("Cancel installation") { model.cancelActive() }
            Text("Host changes apply to the next installation. Canceling keeps saved and signed IPA files.")
                .font(Wax.Ramp.secondary).foregroundStyle(Wax.sub)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Wax.Space.s)
        }
    }

    private var uploadingLabel: String {
        switch model.hostKind {
        case .bucket: return "Uploading to your bucket…"
        case .server: return "Uploading to your server…"
        case .phone: return "Sending the app from this iPhone…"
        }
    }

    private var handoffLabel: String {
        switch model.hostKind {
        case .phone: return "Handed to iOS. Keep Wax open until iOS takes the app."
        case .server, .bucket: return "Sent to iOS. Confirm the install when iOS asks."
        }
    }
}
