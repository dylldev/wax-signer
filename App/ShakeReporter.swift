import InstallKit
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted when the person finishes shaking the iPhone.
    static let waxDeviceShaken = Notification.Name("wax.deviceShaken")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake { NotificationCenter.default.post(name: .waxDeviceShaken, object: nil) }
    }
}

/// Whether the on-screen keyboard is up. The tab bar steps aside for it, and a shake never interrupts typing.
@MainActor
final class KeyboardWatch: ObservableObject {
    @Published private(set) var isVisible = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = true }
        })
        observers.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isVisible = false }
        })
    }
}

/// Opens a local draft when a shake can safely interrupt the screen.
@MainActor
final class ShakeReporter: ObservableObject {
    @Published var isPresenting = false
    @Published var draft: BugReport.Draft
    @Published var shakeEnabled: Bool {
        didSet { defaults.set(shakeEnabled, forKey: Self.preferenceKey) }
    }
    private static let preferenceKey = "wax.shakeReportingEnabled"
    private let defaults: UserDefaults
    private let hasPresentation: () -> Bool

    init(defaults: UserDefaults = .standard, somethingPresented: (() -> Bool)? = nil) {
        self.defaults = defaults
        self.hasPresentation = somethingPresented ?? Self.somethingPresented
        self.shakeEnabled = defaults.object(forKey: Self.preferenceKey) as? Bool ?? true
        self.draft = BugReport.Draft(about: BugReport.About(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            osVersion: "iOS \(UIDevice.current.systemVersion)"))
    }

    func present() {
        guard !isPresenting else { return }
        draft.reset()
        isPresenting = true
    }

    func dismiss() {
        isPresenting = false
        draft.reset()
    }

    func shaken(busy: Bool, guideShowing: Bool, editingText: Bool) {
        guard shakeEnabled else { return }
        let context = ShakeGate.Context(presenting: isPresenting, somethingOnTop: guideShowing || hasPresentation(),
                                        editingText: editingText, busy: busy)
        if ShakeGate.shouldOpen(context) { present() }
    }

    /// Any sheet, picker or alert already on screen.
    private static func somethingPresented() -> Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }
}
