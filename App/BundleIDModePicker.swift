import SwiftUI

/// Keep original / Rename to fit, laid out like the other grouped rows so it lines up with them.
struct BundleIDModePicker: View {
    @Binding var mode: SigningModel.BundleIDMode

    var body: some View {
        VStack(alignment: .leading, spacing: Wax.Space.s) {
            WaxListRow(icon: "tag", title: "Bundle ID",
                       detail: mode == .keep ? "Recommended. The app keeps its own ID." : "Renames the app to fit a single-app profile.")
                .animation(nil, value: mode)
            Picker("Bundle ID", selection: $mode.animation(Wax.spring)) {
                Text("Keep original").tag(SigningModel.BundleIDMode.keep)
                Text("Rename to fit").tag(SigningModel.BundleIDMode.rename)
            }
            .pickerStyle(.segmented)
        }
        .padding(.bottom, Wax.Space.m)
    }
}
