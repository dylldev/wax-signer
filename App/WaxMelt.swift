import SwiftUI

/// A candle melting into a pool. `progress` is the real progress of the job (0...1): the candle shrinks and its flame
/// with it, the pool grows, and at 1 the candle is gone, the flame is out and the seal is pressed into the pool.
struct WaxMelt: View {
    let progress: Double
    var height: CGFloat = 230
    var isVisible = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { isVisible && scenePhase == .active && !reduceMotion && progress < 1 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { timeline in
            Canvas { context, size in
                draw(&context, size, time: animates ? timeline.date.timeIntervalSinceReferenceDate : 0)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Melting wax")
        .accessibilityValue("\(Int((min(1, max(0, progress))) * 100)) percent")
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, time: Double) {
        let p = min(1, max(0, progress))
        let wax = GraphicsContext.Shading.color(Wax.seal)
        let sheen = GraphicsContext.Shading.color(.white.opacity(0.24))
        let shade = GraphicsContext.Shading.color(.black.opacity(0.16))
        let maxRy: CGFloat = 20
        let base = size.height - maxRy - 2          // puddle centre line; the puddle never leaves the canvas
        let midX = size.width / 2

        // Puddle: grows with progress.
        let eased = 1 - pow(1 - p, 2)
        let bw = min(96, size.width * 0.34)
        let rx = bw * 0.62 + (size.width * 0.47 - bw * 0.62) * eased
        let ry = 6 + (maxRy - 6) * eased
        let puddle = CGRect(x: midX - rx, y: base - ry, width: rx * 2, height: ry * 2)
        context.fill(Path(ellipseIn: puddle), with: .color(Wax.seal.opacity(0.92)))
        context.fill(Path(ellipseIn: puddle.insetBy(dx: rx * 0.32, dy: ry * 0.42).offsetBy(dx: -rx * 0.1, dy: -ry * 0.22)), with: sheen)

        // Candle: a cylinder that gets shorter and a little narrower as it melts.
        let maxHeight = size.height - 56 - 36
        let height = maxHeight * pow(1 - p, 0.9)
        drawSeal(&context, puddle: puddle, alpha: min(1, max(0, (p - 0.8) / 0.2)))
        guard height > 3 else { return }
        let width = bw * (1 - 0.22 * p)
        let topRy: CGFloat = 7
        let bottom = base - 2
        let top = bottom - height
        let left = midX - width / 2, right = midX + width / 2

        // Body: a rectangle with an elliptical bottom edge.
        var body = Path()
        body.move(to: CGPoint(x: left, y: top))
        body.addLine(to: CGPoint(x: left, y: bottom))
        body.addEllipse(in: CGRect(x: left, y: bottom - topRy, width: width, height: topRy * 2))
        body.addRect(CGRect(x: left, y: top, width: width, height: height))
        context.fill(body, with: wax)
        context.fill(Path(roundedRect: CGRect(x: left + width * 0.12, y: top + topRy, width: width * 0.1, height: max(0, height - topRy * 3)),
                          cornerRadius: width * 0.05), with: sheen)

        // Molten top: a glossy face with a darker pool in the middle.
        let face = CGRect(x: left, y: top - topRy, width: width, height: topRy * 2)
        context.fill(Path(ellipseIn: face), with: wax)
        context.fill(Path(ellipseIn: face), with: sheen)
        context.fill(Path(ellipseIn: face.insetBy(dx: width * 0.18, dy: topRy * 0.35)), with: shade)

        // Flame: a teardrop on a short wick that shrinks with the candle and goes out near the end.
        let burn = min(1, max(0, (0.97 - p) / 0.1))
        if burn > 0 {
            let sway = reduceMotion ? 0 : sin(time * 6.3) * 1.8 + sin(time * 10.1) * 0.8
            let fh = (14 + 20 * (1 - p)) * burn * CGFloat(reduceMotion ? 1 : 0.92 + 0.08 * sin(time * 8.7))
            let fw = fh * 0.46
            let wickTop = top - topRy * 0.6 - 5
            context.stroke(Path { $0.move(to: CGPoint(x: midX, y: top - topRy * 0.4)); $0.addLine(to: CGPoint(x: midX, y: wickTop)) },
                           with: .color(.black.opacity(0.55)), lineWidth: 1.6)
            let glow = CGRect(x: midX - 44, y: wickTop - fh - 30, width: 88, height: 88)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [Wax.flame.opacity(0.28 * burn), .clear]), center: CGPoint(x: midX, y: wickTop - fh * 0.45),
                startRadius: 2, endRadius: 44))
            func teardrop(_ w: CGFloat, _ h: CGFloat) -> Path {
                Path { q in
                    q.move(to: CGPoint(x: midX, y: wickTop))
                    q.addCurve(to: CGPoint(x: midX + sway * 0.6, y: wickTop - h),
                               control1: CGPoint(x: midX + w, y: wickTop - h * 0.1), control2: CGPoint(x: midX + w * 0.5 + sway, y: wickTop - h * 0.6))
                    q.addCurve(to: CGPoint(x: midX, y: wickTop),
                               control1: CGPoint(x: midX - w * 0.5 + sway, y: wickTop - h * 0.6), control2: CGPoint(x: midX - w, y: wickTop - h * 0.1))
                }
            }
            context.fill(teardrop(fw, fh), with: .color(Wax.flame))
            context.fill(teardrop(fw * 0.55, fh * 0.62), with: .color(Wax.flameCore))
        }

        // Drips run down the sides from the rim, lengthening as it melts, with a bulb at the end. One drop falls.
        let drips: [(x: CGFloat, phase: Double, reach: CGFloat)] = [(-0.86, 0, 0.55), (0.80, 1.7, 0.8), (-0.18, 3.1, 0.4)]
        for (i, d) in drips.enumerated() {
            let breathe = reduceMotion ? 0.8 : 0.55 + 0.45 * sin(time * 1.1 + d.phase)
            let length = min(height - topRy, (10 + 40 * p) * d.reach * (0.7 + 0.3 * CGFloat(breathe)) + 6)
            let x = midX + d.x * width / 2 * 0.92
            let startY = top + topRy * (d.x > 0 ? 0.6 : 0.5)
            let w: CGFloat = 6.5
            context.fill(Path(roundedRect: CGRect(x: x - w / 2, y: startY, width: w, height: length), cornerRadius: w / 2), with: sheen)
            context.fill(Path(ellipseIn: CGRect(x: x - w * 0.7, y: startY + length - w * 0.9, width: w * 1.4, height: w * 1.6)), with: sheen)
            guard !reduceMotion, p < 0.99 else { continue }
            let phase = (time * 0.7 + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
            let fallFrom = startY + length + w
            let dropY = fallFrom + CGFloat(phase * phase) * max(0, base - ry * 0.5 - fallFrom)
            let r: CGFloat = 3.4 * (1 - 0.35 * CGFloat(phase))
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: dropY - r, width: r * 2, height: r * 2.4)), with: wax)
        }
    }
}

extension WaxMelt {
    /// The seal's mark pressed into the finished pool: a ring and a W, fading in over the last fifth of the job.
    fileprivate func drawSeal(_ context: inout GraphicsContext, puddle: CGRect, alpha: Double) {
        guard alpha > 0 else { return }
        let c = CGPoint(x: puddle.midX, y: puddle.midY)
        let rx = puddle.width * 0.2, ry = puddle.height * 0.36
        let ink = GraphicsContext.Shading.color(Wax.sealInk.opacity(0.85 * alpha))
        context.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2)), with: ink, lineWidth: 1.5)
        context.stroke(Path(ellipseIn: CGRect(x: c.x - rx * 0.82, y: c.y - ry * 0.82, width: rx * 1.64, height: ry * 1.64)),
                       with: .color(Wax.sealInk.opacity(0.4 * alpha)), lineWidth: 0.8)
        context.draw(Text("W").font(.system(size: max(10, ry * 1.5), weight: .heavy)).italic().foregroundColor(Wax.sealInk.opacity(0.85 * alpha)), at: c)
    }
}

#if DEBUG
/// Debug only (launch argument `-meltprogress 0.5`): the melt on its own at a fixed progress.
struct MeltDemo: View {
    let progress: Double
    var body: some View {
        VStack(spacing: 12) {
            Text("Melting wax into your app").font(.callout.weight(.semibold)).foregroundStyle(Wax.text)
            WaxMelt(progress: progress)
            Text("\(Int(progress * 100))%").font(.title.monospacedDigit().bold()).foregroundStyle(Wax.text)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Wax.bg.ignoresSafeArea())
    }
}
#endif
