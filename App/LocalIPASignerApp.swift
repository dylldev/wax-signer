import CredentialKit
import InstallKit
import SwiftUI
import UIKit

/// Lets one screen send the user to another tab.
final class Router: ObservableObject {
    enum Tab: Int { case sources, ipa, sign, settings }
    /// Screens that can be pushed inside Settings.
    enum SettingsRoute: Hashable { case credentials, signingOptions, importLog }

    @Published var tab = Tab.sign
    /// Which shelf the IPA tab shows, so another screen can send the person straight to the Signed one.
    @Published var shelf = LibraryEntry.Kind.unsigned
    @Published var settingsPath: [SettingsRoute] = []
    /// The source whose apps are open on the Sources tab, if any.
    @Published var sourcesPath: [UUID] = []
    /// Bumped each time the tab you are already on is tapped; screens scroll to the top when it changes.
    @Published private(set) var reselectTick: [Tab: Int] = [:]

    /// Tapping the tab you are on goes back to its first screen, like most iOS apps.
    func reselect(_ tab: Tab) {
        if tab == .settings { settingsPath = [] }
        if tab == .sources { sourcesPath = [] }
        reselectTick[tab, default: 0] += 1
    }

    func openCredentials() { settingsPath = [.credentials]; tab = .settings }
}

@main
struct LocalIPASignerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var credentials: CredentialsModel
    @StateObject private var signing: SigningModel
    @StateObject private var library = LibraryModel.shared
    @StateObject private var sources = SourcesModel()
    @StateObject private var router = Router()
    @StateObject private var ota = OTAInstallModel()
    @StateObject private var tester = IdentityTester()
    @AppStorage("expiryReminders") private var remindersEnabled = true

    init() {
        // Older builds stored the signing keys and the install token "when unlocked"; background work needs "after first unlock".
        SystemIdentityKeychain().migrateAccessibility()
        KeychainSecretStore().migrateAccessibility()
        let creds = CredentialsModel()
        _credentials = StateObject(wrappedValue: creds)
        _signing = StateObject(wrappedValue: SigningModel(credentials: creds))
        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(Wax.sub)
        item.normal.titleTextAttributes = [.foregroundColor: UIColor(Wax.sub)]
        let bar = UITabBarAppearance()
        bar.configureWithDefaultBackground()
        bar.stackedLayoutAppearance = item
        bar.inlineLayoutAppearance = item
        bar.compactInlineLayoutAppearance = item
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = UIColor(Wax.accent)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(Wax.onAccent)], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor(Wax.text)], for: .normal)
        seg.backgroundColor = UIColor(Wax.chip)
        UITabBar.appearance().standardAppearance = bar
        UITabBar.appearance().scrollEdgeAppearance = bar
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let i = CommandLine.arguments.firstIndex(of: "-meltprogress"), i + 1 < CommandLine.arguments.count,
               let value = Double(CommandLine.arguments[i + 1]) {
                MeltDemo(progress: value)   // debug only: look at the melt at a fixed progress
            } else { appRoot }
            #else
            appRoot
            #endif
        }
    }

    private var appRoot: some View {
        // The three screens stay alive so each keeps its state; only the selected one is shown.
        ZStack {
            screen(.sources) { SourcesView() }
            screen(.ipa) { ContentView() }
            screen(.sign) { SignView() }
            screen(.settings) { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { WaxTabBar(selection: $router.tab, onReselect: router.reselect).ignoresSafeArea(.keyboard) }
        .background(Wax.bg.ignoresSafeArea())
        .tint(Wax.link)
        .environmentObject(credentials)
        .environmentObject(signing)
        .environmentObject(library)
        .environmentObject(sources)
        .environmentObject(router)
        .environmentObject(ota)
        .environmentObject(tester)
        .task { ExpiryReminder.reschedule(profiles: credentials.profiles, enabled: remindersEnabled) }
        .onChange(of: credentials.profiles) { _, new in ExpiryReminder.reschedule(profiles: new, enabled: remindersEnabled) }
        .onChange(of: remindersEnabled) { _, on in ExpiryReminder.reschedule(profiles: credentials.profiles, enabled: on) }
    }

    private func screen<Content: View>(_ tab: Router.Tab, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(router.tab == tab ? 1 : 0)
            .allowsHitTesting(router.tab == tab)
            .accessibilityHidden(router.tab != tab)
            .zIndex(router.tab == tab ? 1 : 0)
    }
}
