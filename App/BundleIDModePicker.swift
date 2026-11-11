import SwiftUI

/// Keep original / Rename to fit, laid out like the other grouped rows so it lines up with them.
struct BundleIDModePicker: View {
    @Binding var mode: SigningModel.BundleIDMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Wax.Space.s) {
            WaxListRow(icon: "tag", title: "Bundle ID",
                       detail: mode == .keep ? "Keeps the app's own ID. Best for most profiles." : "Renames the app to fit the profile. Installs as a new app.")
                .animation(nil, value: mode)
            Picker("Bundle ID", selection: $mode.animation(reduceMotion ? nil : Wax.spring)) {
                Text("Keep original").tag(SigningModel.BundleIDMode.keep)
                Text("Rename to fit").tag(SigningModel.BundleIDMode.rename)
            }
            .pickerStyle(.segmented)
        }
        .padding(.bottom, Wax.Space.m)
    }
}
