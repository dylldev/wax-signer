import UIKit
import TestKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIViewController()
        let label = UILabel(frame: vc.view.bounds)
        label.text = TestKit.greeting()
        label.textAlignment = .center
        vc.view.addSubview(label)
        window?.rootViewController = vc
        window?.makeKeyAndVisible()
        return true
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
