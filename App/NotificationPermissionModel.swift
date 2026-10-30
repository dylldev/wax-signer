import SwiftUI
import UIKit
import UserNotifications

/// The one place Wax asks iOS for notification permission, and only when the person taps Enable notifications.
/// Signing, installing and expiry reminders read the state here; they never ask.
@MainActor
final class NotificationPermissionModel: ObservableObject {
    static let shared = NotificationPermissionModel()

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    @Published private(set) var errorMessage: String?
    @Published private(set) var asking = false
    private let readStatus: () async -> UNAuthorizationStatus
    private let request: () async throws -> Void

    init(readStatus: @escaping () async -> UNAuthorizationStatus = { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
         request: @escaping () async throws -> Void = { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }) {
        self.readStatus = readStatus; self.request = request
    }

    static func allowsNotifications(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// The pill text for the real iOS state; nil before iOS has asked.
    static func stateLabel(_ status: UNAuthorizationStatus) -> String? {
        switch status {
        case .authorized: "On"
        case .provisional: "Quiet"
        case .ephemeral: "Temporary"
        case .denied: "Off"
        default: nil
        }
    }

    var canNotify: Bool { Self.allowsNotifications(status) }

    func refresh() async { status = await readStatus() }

    /// Shows the iOS prompt when iOS has not asked yet. After a decision iOS never shows it again; the state is re-read either way.
    func enable() async {
        guard !asking else { return }
        asking = true; errorMessage = nil
        defer { asking = false }
        await refresh()
        guard status == .notDetermined else { return }
        do { try await request() }
        catch { errorMessage = "iOS could not turn on notifications: \(error.localizedDescription)" }
        await refresh()
    }
}

/// The notification row used in Settings and the first-run setup: the real iOS state and the one action that fits it.
struct NotificationPermissionControls: View {
    @ObservedObject var model: NotificationPermissionModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WaxListRow(icon: model.canNotify ? "bell.badge" : "bell", title: "Notifications", detail: note) {
                switch model.status {
                case .notDetermined:
                    Button("Turn on") { Task { await model.enable() } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
                        .frame(minHeight: Wax.touch)
                        .disabled(model.asking)
                case .denied:
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link)
                    .frame(minHeight: Wax.touch)
                default:
                    if let label = NotificationPermissionModel.stateLabel(model.status) {
                        WaxPill(text: label, tone: .ok).transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animation(Wax.spring, value: model.status)
        }
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    /// Only said when there is something to know: iOS will not ask twice, or asking failed.
    private var note: String? {
        if let error = model.errorMessage { return error }
        switch model.status {
        case .denied: return "Off. iOS will not ask again; turn them on in iOS Settings."
        case .provisional: return "Delivered quietly to Notification Center, without sound."
        default: return nil
        }
    }
}
