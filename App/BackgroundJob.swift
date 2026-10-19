import BackgroundTasks
import InstallKit
import UIKit
import UserNotifications

/// Small adapter seam: tests exercise adoption/expiration without manufacturing system-owned BGTasks.
@MainActor
protocol ContinuedJobHandle: AnyObject {
    var expiration: (@MainActor () -> Void)? { get set }
    func update(fraction: Double, title: String, subtitle: String)
    func complete(success: Bool)
}

@available(iOS 26.0, *)
@MainActor
private final class AppleContinuedJob: ContinuedJobHandle {
    private let task: BGContinuedProcessingTask
    var expiration: (@MainActor () -> Void)? {
        didSet { task.expirationHandler = { [weak self] in Task { @MainActor in self?.expiration?() } } }
    }
    init(_ task: BGContinuedProcessingTask) { self.task = task; task.progress.totalUnitCount = 100 }
    func update(fraction: Double, title: String, subtitle: String) {
        task.progress.completedUnitCount = Int64(fraction * 100); task.updateTitle(title, subtitle: subtitle)
    }
    func complete(success: Bool) { task.expirationHandler = nil; task.setTaskCompleted(success: success) }
}

/// Each operation owns a token and grace task. One continued task covers the aggregate until all jobs end.
/// iOS may refuse/expire resources; this does not make synchronous signing magically cancellable.
@MainActor
final class BackgroundJob {
    static let shared = BackgroundJob()
    @MainActor struct System {
        var beginGrace: @MainActor (String, @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
        var endGrace: @MainActor (UIBackgroundTaskIdentifier) -> Void
        var requestContinued: @MainActor (String) -> Void
        var cancelContinued: @MainActor () -> Void
        static var live: System {
            System(beginGrace: { title, expired in
                UIApplication.shared.beginBackgroundTask(withName: title) { Task { @MainActor in expired() } }
            }, endGrace: { UIApplication.shared.endBackgroundTask($0) }, requestContinued: { title in
                guard #available(iOS 26.0, *), let id = Bundle.main.bundleIdentifier else { return }
                let request = BGContinuedProcessingTaskRequest(identifier: InstallNotification.taskIdentifier(bundleID: id), title: title, subtitle: "Starting…")
                request.strategy = .queue
                do { try BGTaskScheduler.shared.submit(request); ImportLogs.shared.log("background: aggregate requested") }
                catch { ImportLogs.shared.log("background: aggregate refused") }
            }, cancelContinued: {
                guard #available(iOS 26.0, *), let id = Bundle.main.bundleIdentifier else { return }
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: InstallNotification.taskIdentifier(bundleID: id))
            })
        }
    }
    private struct Job {
        let title: String
        var fraction = 0.0
        var halfwayNotified = false
        var grace: UIBackgroundTaskIdentifier = .invalid
        var graceExpired = false
    }
    private let system: System
    private let halfway: ((String) -> Void)?
    private var jobs: [UUID: Job] = [:]
    private var continued: ContinuedJobHandle?
    private var completedCount = 0
    private var groupSucceeded = true
    var activeCount: Int { jobs.count }

    init(system: System? = nil, halfway: ((String) -> Void)? = nil) { self.system = system ?? .live; self.halfway = halfway }

    nonisolated static func registerHandler() {
        guard #available(iOS 26.0, *), let id = Bundle.main.bundleIdentifier else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: InstallNotification.taskIdentifier(bundleID: id), using: nil) { task in
            guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
            Task { @MainActor in BackgroundJob.shared.adopt(AppleContinuedJob(task)) }
        }
    }
    /// A queued task can arrive after its foreground work ended. It must still complete exactly once.
    func adopt(_ handle: ContinuedJobHandle) {
        if continued === handle { return }
        guard !jobs.isEmpty, continued == nil else { handle.complete(success: false); return }
        continued = handle
        handle.expiration = { [weak self, weak handle] in
            guard let self, let handle, self.continued === handle else { return }
            self.continued = nil; handle.expiration = nil; handle.complete(success: false)
            ImportLogs.shared.log("background: aggregate expired")
        }
        refresh(subtitle: "Working…")
    }
    @discardableResult func begin(title: String) -> UUID {
        let id = UUID(), first = jobs.isEmpty
        if first { completedCount = 0; groupSucceeded = true }
        jobs[id] = Job(title: title)
        let grace = system.beginGrace(title) { [weak self] in self?.endGrace(id) }
        if jobs[id]?.graceExpired == true {
            if grace != .invalid { system.endGrace(grace) }
        } else { jobs[id]?.grace = grace }
        if first { system.requestContinued(title) }
        refresh(subtitle: "Starting…")
        return id
    }
    func update(_ id: UUID, fraction: Double, subtitle: String) {
        guard fraction.isFinite, var job = jobs[id] else { return }
        job.fraction = max(job.fraction, min(1, max(0, fraction)))
        let notify = job.fraction >= 0.5 && !job.halfwayNotified
        if notify { job.halfwayNotified = true }
        jobs[id] = job
        if notify {
            if let halfway { halfway(job.title) }
            else { notifyIfInBackground(InstallNotification.halfway(appTitle: job.title), sound: false) }
        }
        refresh(subtitle: subtitle)
    }
    func end(_ id: UUID, success: Bool) {
        guard jobs[id] != nil else { return }
        endGrace(id); jobs.removeValue(forKey: id)
        completedCount += 1; groupSucceeded = groupSucceeded && success
        if jobs.isEmpty {
            let owned = continued; continued = nil
            owned?.expiration = nil; owned?.complete(success: groupSucceeded)
            system.cancelContinued()
        } else { refresh(subtitle: "Working…") }
    }
    private func endGrace(_ id: UUID) {
        guard jobs[id] != nil else { return }
        jobs[id]?.graceExpired = true
        guard let grace = jobs[id]?.grace, grace != .invalid else { return }
        jobs[id]?.grace = .invalid; system.endGrace(grace)
    }
    private func refresh(subtitle: String) {
        guard !jobs.isEmpty else { return }
        let fraction = (Double(completedCount) + jobs.values.reduce(0) { $0 + $1.fraction }) / Double(completedCount + jobs.count)
        let title = jobs.count == 1 ? jobs.values.first!.title : "Wax · \(jobs.count) operations"
        continued?.update(fraction: fraction, title: title, subtitle: subtitle)
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
