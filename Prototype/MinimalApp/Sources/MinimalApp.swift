import SwiftUI

// SwiftUI App: scene-based lifecycle, which iOS 27 requires (a plain UIApplicationMain app without scenes
// is terminated by UIKit at launch).
@main
struct MinimalApp: App {
    var body: some Scene {
        WindowGroup {
            Text("signing test app\nlaunched OK")
                .multilineTextAlignment(.center)
                .font(.title2)
        }
    }
}
