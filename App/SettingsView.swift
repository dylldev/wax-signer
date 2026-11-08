import InstallKit
import SwiftUI

/// Everything that is set once: install server, signing choices, notifications, storage, about.
struct SettingsView: View {
    @EnvironmentObject private var ota: OTAInstallModel
    @EnvironmentObject private var signing: SigningModel
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var credentials: CredentialsModel
    @EnvironmentObject private var permissions: NotificationPermissionModel
    @EnvironmentObject private var guide: FirstRunGuideModel
    @EnvironmentObject private var shake: ShakeReporter
    @AppStorage("signAfterDownload") private var signAfterDownload = false
    @AppStorage("expiryReminders") private var remindersEnabled = true
    @State private var showServer = false
    @State private var confirmClear: LibraryEntry.Kind?

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    WaxHeader(title: "Settings", subtitle: "Set once, then forget.").id("top")

                    WaxSectionLabel(text: "Setup")
                    WaxPanel {
                        NavigationLink(value: Router.SettingsRoute.credentials) {
                            WaxListRow(icon: "key", title: "Certificates & profiles", detail: credentialSummary) { WaxChevron() }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                        WaxRowDivider()
                        Button { showServer = true } label: {
                            WaxListRow(icon: "icloud.and.arrow.up", title: "Install host") {
                                WaxRowValue(text: ota.isConfigured ? ota.hostSummary : "Not set up")
                                WaxChevron()
                            }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                    }

                    WaxSectionLabel(text: "Signing")
                    WaxPanel {
                        BundleIDModePicker(mode: $signing.bundleIDMode)
                        WaxRowDivider()
                        NavigationLink(value: Router.SettingsRoute.signingOptions) {
                            WaxListRow(icon: "slider.horizontal.3", title: "Signing options") {
                                if !signing.edits.isEmpty { WaxPill(text: "Changed", tone: .ok) }
                                WaxChevron()
                            }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                        WaxRowDivider()
                        WaxListRow(icon: "arrow.down.circle", title: "Sign after download") {
                            Toggle("Sign after download", isOn: $signAfterDownload).labelsHidden().tint(Wax.accent)
                        }
                    }

                    WaxSectionLabel(text: "Notifications")
                    WaxPanel {
                        NotificationPermissionControls(model: permissions)
                        WaxRowDivider()
                        WaxListRow(icon: "calendar.badge.clock", title: "Expiry reminders",
                                   detail: remindersEnabled && !permissions.canNotify ? "Needs notifications on." : nil) {
                            Toggle("Expiry reminders", isOn: $remindersEnabled).labelsHidden().tint(Wax.accent)
                        }
                    }

                    WaxSectionLabel(text: "Storage")
                    if let message = library.message { WaxFeedbackCard(tone: .bad, text: message) }
                    WaxPanel {
                        storageRow("Unsigned", icon: "shippingbox", kind: .unsigned, count: library.unsigned.count)
                        WaxRowDivider()
                        storageRow("Signed", icon: "checkmark.seal", kind: .signed, count: library.signed.count)
                    }

                    WaxSectionLabel(text: "Help")
                    WaxPanel {
                        Button { guide.replay() } label: {
                            WaxListRow(icon: "play.rectangle", title: "Replay guide") { WaxChevron() }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                        WaxRowDivider()
                        Button { shake.present() } label: {
                            WaxListRow(icon: "exclamationmark.bubble", title: "Report a problem") { WaxChevron() }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                        WaxRowDivider()
                        WaxListRow(icon: "iphone.radiowaves.left.and.right", title: "Shake to report") {
                            Toggle("Shake to report", isOn: $shake.shakeEnabled).labelsHidden().tint(Wax.accent)
                        }
                        WaxRowDivider()
                        Link(destination: URL(string: "https://github.com/dylldev/wax-signer")!) {
                            WaxListRow(icon: "chevron.left.forwardslash.chevron.right", title: "Wax on GitHub") { externalMark }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                        #if WAX_DEVELOPMENT
                        WaxRowDivider()
                        NavigationLink(value: Router.SettingsRoute.importLog) {
                            WaxListRow(icon: "doc.text.magnifyingglass", title: "Import log") { WaxChevron() }
                        }
                        .buttonStyle(WaxRowButtonStyle())
                        WaxRowDivider()
                        WaxListRow(icon: "barcode", title: "Bundle ID") { WaxRowValue(text: Bundle.main.bundleIdentifier ?? "—") }
                        #endif
                        WaxRowDivider()
                        WaxListRow(icon: "info.circle", title: "Version") { WaxRowValue(text: aboutVersion) }
                            .accessibilityElement(children: .combine)
                    }
                    Text("Free and open source. Signing happens on this iPhone.")
                        .font(.footnote).foregroundStyle(Wax.sub)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.top, Wax.Space.s)
                        .padding(.bottom, Wax.Space.xl)
                }
                .padding(.horizontal, Wax.inset)
            }
            .scrollIndicators(.hidden)
            .background(Wax.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: router.reselectTick[.settings]) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
            .navigationDestination(for: Router.SettingsRoute.self) { route in
                switch route {
                case .credentials: CredentialsView()
                case .signingOptions: SigningOptionsView(model: signing)
                #if WAX_DEVELOPMENT
                case .importLog: ImportLogView()
                #endif
                }
            }
        }
        .sheet(isPresented: $showServer) { serverSheet }
        .confirmationDialog("Delete \(confirmClear == .signed ? library.signed.count : library.unsigned.count) \(confirmClear == .signed ? "signed" : "unsigned") apps (\(Self.size(library.bytes(confirmClear ?? .unsigned))))?",
                            isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let k = confirmClear { Task { await library.clear(k) } } }
        }
    }


    private var credentialSummary: String {
        let c = credentials.certificates.count, p = credentials.profiles.count
        if c == 0 && p == 0 { return "None yet" }
        return "\(c) certificate\(c == 1 ? "" : "s") · \(p) profile\(p == 1 ? "" : "s")"
    }

    private var aboutVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    private func storageRow(_ title: String, icon: String, kind: LibraryEntry.Kind, count: Int) -> some View {
        WaxListRow(icon: icon, title: title, detail: "\(count) app\(count == 1 ? "" : "s") · \(Self.size(library.bytes(kind)))") {
            Button("Clear") { confirmClear = kind }
                .font(.subheadline.weight(.semibold)).foregroundStyle(count == 0 ? Wax.sub : Wax.bad)
                .frame(minHeight: Wax.touch)
                .disabled(count == 0)
        }
    }

    private var externalMark: some View {
        Image(systemName: "arrow.up.right").font(.footnote.weight(.bold)).foregroundStyle(Wax.sub).accessibilityHidden(true)
    }

    private static func size(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(bytes))
    }

    private var serverSheet: some View {
        NavigationStack {
            List { InstallSection(model: ota, collapsed: false, eligibilityUnknown: false).listRowBackground(Wax.card) }
                .scrollContentBackground(.hidden)
                .background(Wax.bg.ignoresSafeArea())
                .tint(Wax.link)
                .navigationTitle("Install host")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Wax.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showServer = false } } }
        }
        .presentationDetents([.large])
    }
}
