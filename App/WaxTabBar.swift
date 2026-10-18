import SwiftUI
import UIKit

/// The Wax tab icons, drawn as paths so they match the seal and scale cleanly.
struct WaxGlyph: Shape {
    enum Kind { case sources, ipa, sign, credentials, settings }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y) }
        var p = Path()
        switch kind {
        case .ipa:
            // A box with a lid and a small wax seal on its front.
            p.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.14, y: rect.minY + rect.height * 0.36, width: rect.width * 0.72, height: rect.height * 0.5),
                             cornerSize: CGSize(width: rect.width * 0.08, height: rect.width * 0.08))
            p.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.16, width: rect.width * 0.84, height: rect.height * 0.2),
                             cornerSize: CGSize(width: rect.width * 0.07, height: rect.width * 0.07))
            p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.4, y: rect.minY + rect.height * 0.5, width: rect.width * 0.2, height: rect.width * 0.2))
        case .sign:
            // A wax seal: scalloped edge, inner ring and a W.
            let c = pt(0.5, 0.5), lobes = 10.0, steps = 80
            for i in 0...steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                let r = rect.width * 0.5 * (0.88 + 0.12 * (0.5 + 0.5 * cos(a * lobes)))
                let q = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                i == 0 ? p.move(to: q) : p.addLine(to: q)
            }
            p.closeSubpath()
            p.move(to: pt(0.3, 0.38)); p.addLine(to: pt(0.4, 0.64)); p.addLine(to: pt(0.5, 0.44))
            p.addLine(to: pt(0.6, 0.64)); p.addLine(to: pt(0.7, 0.38))
        case .sources:
            // A compass: ring, a needle, and four ticks.
            p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.08, width: rect.width * 0.84, height: rect.height * 0.84))
            p.move(to: pt(0.34, 0.66)); p.addLine(to: pt(0.46, 0.46)); p.addLine(to: pt(0.66, 0.34)); p.addLine(to: pt(0.54, 0.54)); p.closeSubpath()
        case .settings:
            // Three sliders: a line each with a round knob.
            for (y, x) in [(0.22, 0.34), (0.5, 0.68), (0.78, 0.44)] {
                p.move(to: pt(0.1, y)); p.addLine(to: pt(0.9, y))
                p.addEllipse(in: CGRect(x: rect.minX + rect.width * (x - 0.1), y: rect.minY + rect.height * (y - 0.1),
                                        width: rect.width * 0.2, height: rect.height * 0.2))
            }
        case .credentials:
            // A key whose bow is a drop of wax.
            p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.1, y: rect.minY + rect.height * 0.1, width: rect.width * 0.4, height: rect.height * 0.4))
            p.move(to: pt(0.42, 0.42)); p.addLine(to: pt(0.88, 0.88))
            p.move(to: pt(0.7, 0.7)); p.addLine(to: pt(0.84, 0.56))
            p.move(to: pt(0.58, 0.58)); p.addLine(to: pt(0.7, 0.46))
        }
        return p
    }
}

/// The bottom bar: equal buttons, the selected one in a wax-colored pill that slides between them.
struct WaxTabBar: View {
    @Binding var selection: Router.Tab
    var onReselect: (Router.Tab) -> Void = { _ in }
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let items: [(tab: Router.Tab, title: String, glyph: WaxGlyph.Kind)] = [
        (.sources, "Sources", .sources), (.ipa, "IPA", .ipa), (.sign, "Sign", .sign), (.settings, "Settings", .settings),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.tab) { item in
                let selected = selection == item.tab
                Button {
                    guard !selected else { onReselect(item.tab); return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72)) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        WaxGlyph(kind: item.glyph)
                            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .frame(width: 24, height: 24)
                            .scaleEffect(selected ? 1.08 : 1)
                        Text(item.title).font(.caption2.weight(.semibold)).lineLimit(1)
                    }
                    .foregroundStyle(selected ? Wax.onAccent : Wax.sub)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Wax.accent)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(TabPressStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(Wax.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Wax.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .padding(.horizontal, Wax.inset)
        .padding(.bottom, 6)
    }
}

private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
