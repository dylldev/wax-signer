import SwiftUI

/// A candle melting into a pool. `progress` is the real progress of the job (0...1): the candle shrinks, the pool
/// spreads, and the flame keeps burning on the stub at 1.
/// Callers must pass measured work (signing/upload fractions), never an invented percentage; this view only renders it.
/// The renderer pauses when hidden, backgrounded, under Reduce Motion, or finished, so it costs no frames offstage.
struct WaxMelt: View {
    var progress: Double
    var height: CGFloat = 230
    var isVisible = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { isVisible && scenePhase == .active && !reduceMotion }

    /// The measured share, clamped so a bad caller cannot push the shader out of range.
    var clampedProgress: Double { min(1, max(0, progress)) }

    var body: some View {
        WaxCandleView(progress: clampedProgress, isAnimating: animates)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Wax.radius, style: .continuous)
                    .strokeBorder(Wax.line.opacity(0.55), lineWidth: Wax.stroke)
            )
            .accessibilityElement()
            .accessibilityLabel("Melting wax")
            .accessibilityValue("\(Int(clampedProgress * 100)) percent")
    }
}

#if WAX_DEVELOPMENT
/// Developer Settings preview; does not run a signing or installation job.
struct MeltDemo: View {
    @State private var progress: Double

    init(progress: Double) { _progress = State(initialValue: progress) }

    var body: some View {
        VStack(spacing: 12) {
            Text("Melting wax into your app").font(.callout.weight(.semibold)).foregroundStyle(Wax.text)
            WaxMelt(progress: progress)
            Slider(value: $progress, in: 0...1).accessibilityLabel("Preview progress")
            Text("\(Int(progress * 100))%").font(.title.monospacedDigit().bold()).foregroundStyle(Wax.text)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wax.bg.ignoresSafeArea())
    }
}
#endif
