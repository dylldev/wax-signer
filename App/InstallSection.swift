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

    var body: some View {
        Section {
            Picker("Install host", selection: $model.hostKind) {
                Text("This iPhone").tag(OTAInstallModel.HostKind.phone)
                Text("My server").tag(OTAInstallModel.HostKind.server)
                Text("Bucket").tag(OTAInstallModel.HostKind.bucket)
            }
            .pickerStyle(.segmented)
        }
        switch model.hostKind {
        case .phone: phoneSection
        case .bucket: bucketSection
        case .server: serverSection
        }
    }

    private var phoneSection: some View {
        Section("This iPhone") {
            Text("Wax hands the signed app to iOS from this phone, so you need no server, bucket or account. "
                 + "It uses a free certificate the project publishes and renews. While Wax is open iOS downloads the app; "
                 + "keep Wax on screen until the install starts. If it does not work, use My server or Bucket.")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("Certificate feed (https://…)", text: $model.certificateFeedText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).font(.footnote)
            statusLine
        }
    }

    private var bucketSection: some View {
        Section("Cloud bucket") {
            Text("Wax puts the signed app in a private bucket you own and gives iOS a link that stops working after 6 hours. "
                 + "Any S3-compatible bucket works (Cloudflare R2, Backblaze B2, Oracle Object Storage, MinIO). "
                 + "Free tiers exist, but some providers ask for a card at sign-up to verify you; check theirs. "
                 + "Add a one-day expiry rule on the bucket so nothing is left behind.")
                .font(.footnote).foregroundStyle(.secondary)
            TextField("Endpoint (https://…)", text: $model.bucketEndpoint)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            TextField("Bucket name", text: $model.bucketName).textInputAutocapitalization(.never).autocorrectionDisabled()
            LabeledContent("Region") { TextField("auto for R2", text: $model.bucketRegion).multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never).autocorrectionDisabled() }
            if model.hasBucketKeys {
                Label("Keys stored (Keychain, this device only)", systemImage: "lock.shield")
                Button("Forget keys", role: .destructive) { model.forgetBucketKeys() }
            } else {
                SecureField("Access key", text: $model.accessKeyDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Secret key", text: $model.secretKeyDraft).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save keys") { model.saveBucketKeys() }.disabled(model.accessKeyDraft.isEmpty || model.secretKeyDraft.isEmpty)
            }
            Button("Test the bucket") { model.testBucket() }
            if let note = model.bucketNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
            statusLine
        }
    }

    private var serverSection: some View {
        Section("Install server") {
            if eligibilityUnknown {
                Text("Wax cannot tell whether this certificate can install over the air. Only Distribution (Ad Hoc or Enterprise) certificates were seen to work.")
                    .font(.footnote).foregroundStyle(.secondary)
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
        case .idle: if let note = model.tokenNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
        case .uploading(let p): ProgressView("Uploading…", value: p)
        case .handedToiOS: Text("Uploaded. iOS will now ask you to confirm the install.").font(.footnote)
        case .failed(let text): Text(text).font(.footnote).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var setupFields: some View {
        Text("Wax sends the signed app to your own HTTPS server, and iOS installs it from there. The server deletes it "
             + "after a while (6 hours by default), not when the install finishes. "
             + "iOS does not allow installing from a server on the phone itself.")
            .font(.footnote).foregroundStyle(.secondary)

        PasteButton(payloadType: String.self) { strings in
            Task { @MainActor in model.applySetup(strings.first ?? "") }
        }

        TextField("https://…", text: $model.serverText)
            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)

        if model.hasToken {
            Label("Token stored (Keychain, this device only)", systemImage: "lock.shield")
            Button("Forget token", role: .destructive) { model.forgetToken() }
        } else {
            SecureField("Server token", text: $model.tokenDraft)
            Button("Save token") { model.saveToken() }.disabled(model.tokenDraft.isEmpty)
        }
    }
}
