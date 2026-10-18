import InstallKit
import SwiftUI
import UserNotifications

/// Everything that is set once: install server, signing choices, notifications, storage, about.
struct SettingsView: View {
    @EnvironmentObject private var ota: OTAInstallModel
    @EnvironmentObject private var signing: SigningModel
    @EnvironmentObject private var library: LibraryModel
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var credentials: CredentialsModel
    @Environment(\.openURL) private var openURL
    @AppStorage("signAfterDownload") private var signAfterDownload = false
    @AppStorage("expiryReminders") private var remindersEnabled = true
    @State private var showServer = false
    @State private var notifications: UNAuthorizationStatus = .notDetermined
    @State private var confirmClear: LibraryEntry.Kind?

    var body: some View {
        NavigationStack(path: $router.settingsPath) {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 10) {
                    WaxHeader(title: "Settings", subtitle: "Set once, then forget.").id("top")

                    WaxSectionLabel(text: "Signing identities")
                    NavigationLink(value: Router.SettingsRoute.credentials) {
                        WaxRow(icon: "key", title: "Certificates & profiles",
                               subtitle: "\(credentials.certificates.count) identit\(credentials.certificates.count == 1 ? "y" : "ies") · \(credentials.profiles.count) profile\(credentials.profiles.count == 1 ? "" : "s")") {
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                        }
                    }
                    .buttonStyle(.plain)

                    WaxSectionLabel(text: "Install")
                    Button { showServer = true } label: {
                        WaxRow(icon: "icloud.and.arrow.up", title: "Install host",
                               subtitle: ota.isConfigured ? ota.hostSummary : "Not set up yet") {
                            WaxLinkText(text: ota.isConfigured ? "Edit" : "Set up")
                        }
                    }
                    .buttonStyle(.plain)

                    WaxSectionLabel(text: "Signing")
                    WaxPanel {
                        BundleIDModePicker(mode: $signing.bundleIDMode)
                            .padding(.vertical, 12)
                        WaxDivider()
                        NavigationLink(value: Router.SettingsRoute.signingOptions) {
                            HStack {
                                Text("Signing options").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                                Spacer()
                                if !signing.edits.isEmpty { WaxPill(text: "Changed", tone: .ok) }
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                    }

                    WaxSectionLabel(text: "Sources")
                    WaxPanel {
                        Toggle(isOn: $signAfterDownload) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sign right after download").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                                Text("Opens the app on the Sign tab as soon as it is downloaded.").font(.footnote).foregroundStyle(Wax.sub)
                            }
                        }
                        .tint(Wax.accent)
                        .padding(.vertical, 10)
                    }

                    WaxSectionLabel(text: "Notifications")
                    WaxPanel {
                        HStack {
                            Text("Ready to install").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                            Spacer()
                            switch notifications {
                            case .authorized, .provisional, .ephemeral: WaxPill(text: "On", tone: .ok)
                            case .denied: WaxPill(text: "Off", tone: .warn)
                            default: Text("Asked on first sign").font(.footnote).foregroundStyle(Wax.sub)
                            }
                        }
                        .frame(minHeight: 52)
                        WaxDivider()
                        Toggle(isOn: $remindersEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Profile expiry reminder").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                                Text("A nudge the day before a signing profile expires.").font(.footnote).foregroundStyle(Wax.sub)
                            }
                        }
                        .tint(Wax.accent)
                        .padding(.vertical, 10)
                        if notifications == .denied {
                            WaxDivider()
                            Button("Turn on in iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                            .buttonStyle(WaxSecondaryButtonStyle())
                        }
                    }

                    WaxSectionLabel(text: "Storage")
                    WaxPanel {
                        storageRow("Unsigned", kind: .unsigned, count: library.unsigned.count)
                        WaxDivider()
                        storageRow("Signed", kind: .signed, count: library.signed.count)
                    }

                    WaxSectionLabel(text: "Help")
                    WaxPanel {
                        NavigationLink(value: Router.SettingsRoute.importLog) {
                            HStack {
                                Text("Import log").font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
                            }
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                    }

                    WaxSectionLabel(text: "About")
                    WaxPanel {
                        WaxKV(key: "Version", value: aboutVersion)
                        WaxDivider()
                        WaxKV(key: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                        WaxDivider()
                        Link(destination: URL(string: "https://github.com/dylldev/wax-signer")!) {
                            Label("Wax on GitHub", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
                                .frame(maxWidth: .infinity, minHeight: Wax.touch, alignment: .leading)
                        }
                    }
                    Text("Wax is free and open source (Apache-2.0). Signing happens on this phone.")
                        .font(.footnote).foregroundStyle(Wax.sub)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)
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
                case .importLog: ImportLogView()
                }
            }
        }
        .sheet(isPresented: $showServer) { serverSheet }
        .confirmationDialog("Delete \(confirmClear == .signed ? library.signed.count : library.unsigned.count) \(confirmClear == .signed ? "signed" : "unsigned") apps (\(Self.size(library.bytes(confirmClear ?? .unsigned))))?",
                            isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let k = confirmClear { library.clear(k) } }
        }
        .task { await refreshNotifications() }
        .onChange(of: showServer) { _, _ in Task { await refreshNotifications() } }
    }


    private var aboutVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    private func storageRow(_ title: String, kind: LibraryEntry.Kind, count: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Wax.text)
                Text("\(count) app\(count == 1 ? "" : "s") · \(Self.size(library.bytes(kind)))")
                    .font(.footnote).foregroundStyle(Wax.sub)
            }
            Spacer()
            Button("Clear") { confirmClear = kind }
                .font(.subheadline.weight(.semibold)).foregroundStyle(count == 0 ? Wax.sub : Wax.bad)
                .disabled(count == 0)
        }
        .frame(minHeight: 60)
    }

    private static func size(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(bytes))
    }

    private func refreshNotifications() async {
        notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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
