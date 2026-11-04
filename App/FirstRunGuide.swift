import SwiftUI

/// Whether to show the first-run setup and tour. Decided once, before any model creates its storage.
@MainActor
final class FirstRunGuideModel: ObservableObject {
    enum Stage { case permissions, tutorial }

    static let completedKey = "firstRun.completed"
    /// Set when a new installation was detected and the guide is owed, so a relaunch before Skip or Finish shows it again.
    static let owedKey = "firstRun.owed"

    @Published private(set) var isPresented: Bool
    @Published private(set) var stage: Stage
    @Published var page = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, hasLegacyState: Bool) {
        self.defaults = defaults
        if defaults.bool(forKey: Self.completedKey) {
            isPresented = false; stage = .tutorial
        } else if defaults.bool(forKey: Self.owedKey) {
            isPresented = true; stage = .permissions
        } else if hasLegacyState {
            // Someone who already used Wax does not need the tour; Settings ▸ Replay guide still has it.
            defaults.set(true, forKey: Self.completedKey)
            isPresented = false; stage = .tutorial
        } else {
            defaults.set(true, forKey: Self.owedKey)
            isPresented = true; stage = .permissions
        }
    }

    func continueToGuide() { page = 0; stage = .tutorial }
    func skip() { close() }
    func finish() { close() }
    func replay() { page = 0; stage = .tutorial; isPresented = true }

    private func close() {
        defaults.set(true, forKey: Self.completedKey)
        defaults.removeObject(forKey: Self.owedKey)
        isPresented = false
    }

    static func animatesExamples(reduceMotion: Bool) -> Bool { !reduceMotion }

    // MARK: Telling a new installation from an existing one

    /// Keys only Wax writes. iOS may put its own keys in the app's domain, so a general "anything saved" test is not used.
    private static let waxKeys: Set<String> = [
        "expiryReminders", "signAfterDownload", "storeUncompressed", "fastDeflate", "rewriteBundleID", "keepBundleID",
        "otaServer", "installHost", "certificateFeed", "s3Region", "s3Endpoint", "s3Bucket", "s3Pending",
    ]

    /// True when Wax has run here before: any of its storage folders exists, or it saved one of its own preferences.
    /// A folder that exists but cannot be read still counts. An old installation that left nothing behind looks new.
    static func detectLegacyState(savedPreferences: [String: Any], storageURLs: [URL]) -> Bool {
        if storageURLs.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) { return true }
        return savedPreferences.keys.contains { waxKeys.contains($0) || $0.hasPrefix("wax.") || $0.hasPrefix("signing.") }
    }

    /// Reads this installation's real state. Call before `CredentialsModel`, `LibraryModel` or `SourcesModel` exist.
    static func live() -> FirstRunGuideModel {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folders = ["Credentials", "Library", "Sources", "Install"].map { support.appendingPathComponent($0, isDirectory: true) }
        let saved = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        return FirstRunGuideModel(hasLegacyState: detectLegacyState(savedPreferences: saved, storageURLs: folders))
    }
}

/// Full-screen first run: optional notification setup, then a short tour of the four tabs.
struct FirstRunGuideView: View {
    @ObservedObject var model: FirstRunGuideModel
    @ObservedObject var permissions: NotificationPermissionModel

    var body: some View {
        Group {
            switch model.stage {
            case .permissions: PermissionsSetup(model: model, permissions: permissions)
            case .tutorial: GuideTour(model: model)
            }
        }
        .background(Wax.bg.ignoresSafeArea())
        .tint(Wax.link)
    }
}

private struct PermissionsSetup: View {
    @ObservedObject var model: FirstRunGuideModel
    @ObservedObject var permissions: NotificationPermissionModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { model.skip() }.font(.callout.weight(.semibold)).frame(minHeight: Wax.touch)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    WaxSeal(size: 56).padding(.top, 12)
                    Text("Welcome to Wax").font(.largeTitle.bold()).foregroundStyle(Wax.text)
                    Text("One thing to set up first. Wax asks for nothing else up front: files and photos come through the iOS pickers, which need no permission.")
                        .font(.body).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
                    WaxPanel { NotificationPermissionControls(model: permissions) }
                    Text("You can change these later in Settings.")
                        .font(.footnote).foregroundStyle(Wax.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            Button(permissions.status == .notDetermined ? "Not now" : "Continue") { model.continueToGuide() }
                .buttonStyle(WaxPrimaryButtonStyle())
                .padding(.vertical, 8)
        }
        .padding(.horizontal, Wax.inset)
    }
}

/// One page of the tour.
private struct GuidePage {
    let title: String
    let body: String
    let glyph: WaxGlyph.Kind
    let tab: Router.Tab?
    let rows: [(icon: String, title: String, subtitle: String)]
    /// The example row the animation points at.
    let highlight: Int

    static let all: [GuidePage] = [
        GuidePage(title: "Bring your signing files",
                  body: "Wax signs with your own certificate (a .p12 file and its password) and a provisioning profile (.mobileprovision). Wax does not make these; get them from your Apple developer account or whoever provides your certificate.",
                  glyph: .credentials, tab: nil,
                  rows: [("key", "Certificate", "my-certificate.p12 · password"), ("doc.text", "Profile", "my-profile.mobileprovision")], highlight: 0),
        GuidePage(title: "Sources",
                  body: "Add a source address to browse the apps it lists, or paste a direct link to an IPA. Downloads land on the IPA tab.",
                  glyph: .sources, tab: .sources,
                  rows: [("link", "Add a source", "Paste an address"), ("arrow.down.circle", "An app from a source", "Get")], highlight: 1),
        GuidePage(title: "IPA",
                  body: "Your shelf. Unsigned apps wait to be signed; signed ones Wax made can be installed again or exported.",
                  glyph: .ipa, tab: .ipa,
                  rows: [("shippingbox", "Unsigned app", "Ready to sign"), ("checkmark.seal", "Signed app", "Install or export")], highlight: 0),
        GuidePage(title: "Sign",
                  body: "Pick an app and a certificate. Wax checks the profile first, then signs on this iPhone and hands the app to iOS to install.",
                  glyph: .sign, tab: .sign,
                  rows: [("app", "App", "Chosen from the shelf"), ("signature", "Sign & Install", "Checked, signed, installed")], highlight: 1),
        GuidePage(title: "Settings",
                  body: "Import your certificates and profiles, set where installs come from, and choose signing options. Replay this guide from here any time.",
                  glyph: .settings, tab: .settings,
                  rows: [("key", "Certificates & profiles", "Import"), ("icloud.and.arrow.up", "Install host", "This iPhone or your own server")], highlight: 0),
    ]
}

private struct GuideTour: View {
    @ObservedObject var model: FirstRunGuideModel
    @AccessibilityFocusState private var titleFocused: Bool
    private let pages = GuidePage.all

    var body: some View {
        let index = min(max(model.page, 0), pages.count - 1)
        let page = pages[index]
        let last = index == pages.count - 1
        VStack(spacing: 0) {
            HStack {
                Text("\(index + 1) of \(pages.count)").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                Spacer()
                if !last { Button("Skip") { model.skip() }.font(.callout.weight(.semibold)).frame(minHeight: Wax.touch) }
            }
            .frame(minHeight: Wax.touch)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GuideExample(page: page).id(index)
                    Text(page.title).font(.title.bold()).foregroundStyle(Wax.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    Text(page.body).font(.body).foregroundStyle(Wax.sub).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            HStack(spacing: 12) {
                if index > 0 {
                    Button("Back") { model.page = index - 1 }
                        .buttonStyle(WaxSecondaryButtonStyle())
                        .frame(maxWidth: 120)
                }
                Button(last ? "Get started" : "Next") { last ? model.finish() : (model.page = index + 1) }
                    .buttonStyle(WaxPrimaryButtonStyle())
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, Wax.inset)
        .onChange(of: model.page) { _, _ in titleFocused = true }
    }
}

/// A small, made-up picture of the screen: example rows and the tab bar, with the row to look at gently pulsing.
/// Nothing in it can be tapped, and with Reduce Motion it stays still.
private struct GuideExample: View {
    let page: GuidePage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animates = FirstRunGuideModel.animatesExamples(reduceMotion: reduceMotion)
        VStack(spacing: 10) {
            ForEach(Array(page.rows.enumerated()), id: \.offset) { i, row in
                let lit = i == page.highlight
                WaxRow(icon: row.icon, title: row.title, subtitle: row.subtitle) {
                    if lit { Image(systemName: "hand.tap").foregroundStyle(Wax.link) }
                }
                .phaseAnimator(animates && lit ? [false, true] : [false]) { view, on in
                    view.scaleEffect(on ? 1.03 : 1)
                        .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous)
                            .stroke(Wax.accent.opacity(on ? 0.8 : (lit ? 0.4 : 0)), lineWidth: 2))
                } animation: { _ in .easeInOut(duration: 0.9) }
            }
            HStack(spacing: 4) {
                ForEach([(Router.Tab.sources, WaxGlyph.Kind.sources), (.ipa, .ipa), (.sign, .sign), (.settings, .settings)], id: \.0) { tab, glyph in
                    let selected = page.tab == tab
                    WaxGlyph(kind: glyph)
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(selected ? Wax.onAccent : Wax.sub)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background { if selected { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Wax.accent) } }
                }
            }
            .padding(4)
            .background(Wax.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Wax.line, lineWidth: 1))
        }
        .padding(14)
        .background(Wax.chip.opacity(0.5), in: RoundedRectangle(cornerRadius: Wax.radius + 4, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Example: \(page.rows.map(\.title).joined(separator: ", "))")
    }
}
