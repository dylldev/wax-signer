import SwiftUI

/// Keep original / Rename to fit, with the same help text everywhere it appears.
struct BundleIDModePicker: View {
    @Binding var mode: SigningModel.BundleIDMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bundle ID")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Wax.text)
            Picker("Bundle ID", selection: $mode) {
                Text("Keep original").tag(SigningModel.BundleIDMode.keep)
                Text("Rename to fit").tag(SigningModel.BundleIDMode.rename)
            }
            .pickerStyle(.segmented)
            Text(mode == .keep
                 ? "Signs under the profile's app ID and leaves the app's own ID alone. Recommended."
                 : "Renames the app to fit a profile that allows one app ID. Only needed if iOS refuses the original ID.")
                .font(.footnote)
                .foregroundStyle(Wax.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
