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

/// Where the signed app is sent so iOS can install it. The Sign & Install button lives above, with its result.
struct InstallSection: View {
    @ObservedObject var model: OTAInstallModel
    /// Setup is complete: show one line and an Edit button instead of the fields.
    var collapsed = false
    /// The certificate is not a known Distribution one, so installing may still be refused.
    var eligibilityUnknown = false
    @State private var editing = false
    @State private var forgetting: String?

    var body: some View {
        Group {
        Section {
            Picker("Install host", selection: $model.hostKind) {
                ForEach(OTAInstallModel.HostKind.allCases, id: \.self) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        }
        switch model.hostKind {
        case .phone: phoneSection
        case .bucket: bucketSection
        case .server: serverSection
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

    private var phoneSection: some View {
        Section("This iPhone") {
            Text("Wax hands the signed app to iOS from this phone, so you need no server, bucket or account. "
                 + "It uses a free certificate the project publishes and renews. While Wax is open iOS downloads the app; "
                 + "keep Wax on screen until the install starts. If it does not work, use My server or Bucket.")
                .font(.footnote).foregroundStyle(Wax.sub)
            LabeledContent("Certificate feed") { TextField("https://…", text: $model.certificateFeedText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).font(.footnote)
            }
            statusLine
        }
    }

    private var bucketSection: some View {
        Section("Cloud bucket") {
            Text("Wax puts the signed app in a private bucket you own and gives iOS a link that stops working after 6 hours. "
                 + "Any S3-compatible bucket works (Cloudflare R2, Backblaze B2, Oracle Object Storage, MinIO). "
                 + "Free tiers exist, but some providers ask for a card at sign-up to verify you; check theirs. "
                 + "Add a one-day expiry rule on the bucket so nothing is left behind.")
                .font(.footnote).foregroundStyle(Wax.sub)
            LabeledContent("Endpoint") { TextField("https://…", text: $model.bucketEndpoint)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            }
            LabeledContent("Bucket") { TextField("Name", text: $model.bucketName).textInputAutocapitalization(.never).autocorrectionDisabled() }
            LabeledContent("Region") { TextField("auto for R2", text: $model.bucketRegion).multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled() }
            if model.hasBucketKeys {
                Label("Keys stored (Keychain, this device only)", systemImage: "lock.shield")
                Button("Forget keys", role: .destructive) { forgetting = "bucket keys" }
            } else {
                SecureField("Access key", text: $model.accessKeyDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Secret key", text: $model.secretKeyDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save keys") { model.saveBucketKeys() }.disabled(model.accessKeyDraft.isEmpty || model.secretKeyDraft.isEmpty)
            }
            Button("Test the bucket") { model.testBucket() }
            if let note = model.bucketNote {
                if note.hasPrefix("Checking") { ProgressView(note).font(.footnote) }
                else { Label(note, systemImage: note.contains("accepted") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.footnote).foregroundStyle(note.contains("accepted") ? Wax.ok : Wax.bad) }
            }
            statusLine
        }
    }

    private var serverSection: some View {
        Section("Install server") {
            if eligibilityUnknown {
                Text("Wax cannot tell whether this certificate can install over the air. Only Distribution (Ad Hoc or Enterprise) certificates were seen to work.")
                    .font(.footnote).foregroundStyle(Wax.sub)
            }
            if collapsed && !editing {
                Label("Ready: \(model.serverText)", systemImage: "checkmark.seal")
                Button("Edit install server") { editing = true }
            } else {
                setupFields
            }
            statusLine
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch model.state {
        case .idle:
            if let note = model.tokenNote {
                if note.hasPrefix("Checking") { ProgressView(note).font(.footnote) }
                else { Label(note, systemImage: note.contains("accepted") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.footnote).foregroundStyle(note.contains("accepted") ? Wax.ok : Wax.bad) }
            }
        case .uploading(let p): ProgressView("Uploading…", value: p)
        case .handedToiOS: Text("Uploaded. iOS will now ask you to confirm the install.").font(.footnote)
        case .failed(let text): Text(text).font(.footnote).foregroundStyle(Wax.bad)
        }
    }

    @ViewBuilder private var setupFields: some View {
        Text("Wax sends the signed app to your own HTTPS server, and iOS installs it from there. The server deletes it "
             + "after a while (6 hours by default), not when the install finishes. "
             + "iOS does not allow installing from a server on the phone itself.")
            .font(.footnote).foregroundStyle(Wax.sub)

        PasteButton(payloadType: String.self) { strings in
            Task { @MainActor in model.applySetup(strings.first ?? "") }
        }

        LabeledContent("Server") { TextField("https://…", text: $model.serverText)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        }

        if model.hasToken {
            Label("Token stored (Keychain, this device only)", systemImage: "lock.shield")
            Button("Forget token", role: .destructive) { forgetting = "server token" }
        } else {
            SecureField("Server token", text: $model.tokenDraft)
            Button("Save token") { model.saveToken() }.disabled(model.tokenDraft.isEmpty)
        }
    }
}
