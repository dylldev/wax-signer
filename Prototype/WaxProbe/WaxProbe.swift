import SwiftUI

/// Source-built installation probe v1. Scheme detection is not proof of launch/capability execution.
@main
struct WaxProbe: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("Wax Probe").font(.largeTitle)
                Text("This probe opened on this iPhone.")
                Text("Return to Wax to review the observed installation result. This screen does not establish entitlement or keychain compatibility.")
                    .font(.footnote)
            }
            .padding()
            .multilineTextAlignment(.center)
        }
    }
}
