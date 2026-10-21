import BackgroundTasks
import InstallKit
import UIKit
import UserNotifications

/// Keeps signing and uploading going when Wax is not on screen, and tells the user when the app is ready.
/// iOS 26 can run a user-started job in the background and shows its progress; older systems only get the
/// short grace period every app gets.
@MainActor
final class BackgroundJob {
    static let shared = BackgroundJob()

    private var task: Any?                      // BGContinuedProcessingTask on iOS 26+
    private var graceTask: UIBackgroundTaskIdentifier = .invalid
    private var jobTitle = ""
    private var halfwayNotified = false

    /// Called once at launch. The task handler must exist before the app finishes launching.
    nonisolated static func registerHandler() {
        guard #available(iOS 26.0, *), let id = Bundle.main.bundleIdentifier else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: InstallNotification.taskIdentifier(bundleID: id), using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else { return }
            Task { @MainActor in BackgroundJob.shared.adopt(task) }
        }
    }

    @available(iOS 26.0, *)
    private func adopt(_ task: BGContinuedProcessingTask) {
        self.task = task
        ImportLogs.shared.log("background: continued task started")
        task.progress.totalUnitCount = 100
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                // Complete the task exactly once: if end(success:) already did, there is nothing left to do.
                guard let self, self.task != nil else { return }
                ImportLogs.shared.log("background: continued task expired")
                self.task = nil
                task.setTaskCompleted(success: false)   // iOS expects every task to be completed
            }
        }
    }

    /// Call from a user action while Wax is on screen.
    func begin(title: String) {
        jobTitle = title
        halfwayNotified = false
        if #available(iOS 26.0, *), let id = Bundle.main.bundleIdentifier {
            let request = BGContinuedProcessingTaskRequest(
                identifier: InstallNotification.taskIdentifier(bundleID: id), title: title, subtitle: "Starting…")
            request.strategy = .queue
            do {
                try BGTaskScheduler.shared.submit(request)
                ImportLogs.shared.log("background: continued task requested")
            } catch {
                ImportLogs.shared.log("background: continued task refused: \(error)")
            }
        }
        graceTask = UIApplication.shared.beginBackgroundTask(withName: "wax.signing") { [weak self] in self?.endGrace() }
    }

    func update(fraction: Double, subtitle: String) {
        if fraction >= 0.5, !halfwayNotified {
            halfwayNotified = true
            notifyIfInBackground(InstallNotification.halfway(appTitle: jobTitle), sound: false)
        }
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = Int64(min(1, max(0, fraction)) * 100)
            task.updateTitle(task.title, subtitle: subtitle)
        }
    }

    func end(success: Bool) {
        if #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask { task.setTaskCompleted(success: success) }
        task = nil
        endGrace()
    }

    private func endGrace() {
        if graceTask != .invalid { UIApplication.shared.endBackgroundTask(graceTask); graceTask = .invalid }
    }

    // MARK: Notifications

    func askForNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts the notification only when Wax is not the app on screen (the install prompt opens by itself then).
    func notifyIfInBackground(_ content: InstallNotification.Content, sound: Bool = true) {
        guard UIApplication.shared.applicationState != .active else { return }
        let c = UNMutableNotificationContent()
        c.title = content.title
        c.body = content.body
        c.userInfo = content.userInfo
        c.sound = sound ? .default : nil
        c.interruptionLevel = sound ? .timeSensitive : .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

/// A tapped "Ready to install" notification leaves its link here; the Sign screen picks it up.
@MainActor
final class InstallInbox: ObservableObject {
    static let shared = InstallInbox()
    @Published var pendingLink: URL?
    @Published var openedFromNotification = false
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BackgroundJob.registerHandler()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let link = InstallNotification.link(from: response.notification.request.content.userInfo)
        await MainActor.run {
            InstallInbox.shared.pendingLink = link
            InstallInbox.shared.openedFromNotification = true
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
