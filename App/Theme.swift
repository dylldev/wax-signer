import SwiftUI
import UIKit

/// The Wax look: oxblood and cream, taken from the app icon. Colors adapt to light and dark.
enum Wax {
    static let bg = Color(light: 0xF5EFE2, dark: 0x170C0B)
    static let card = Color(light: 0xFFFCF5, dark: 0x241413)
    static let line = Color(light: 0xE6DCC6, dark: 0x3A2422)
    static let text = Color(light: 0x2A1A14, dark: 0xF3E9D6)
    static let sub = Color(light: 0x7A6A5E, dark: 0xA8978A)
    static let accent = Color(light: 0x8B2520, dark: 0xE8DCC2)
    static let accentPressed = Color(light: 0x6F1B17, dark: 0xD6C7A8)
    static let onAccent = Color(light: 0xF7EFDD, dark: 0x5E1612)
    /// Links and icons on the page background (the accent itself is a fill color in dark mode).
    static let link = Color(light: 0x8B2520, dark: 0xE8C9A0)
    static let chip = Color(light: 0xF0E4CC, dark: 0x33201E)
    static let ok = Color(light: 0x3E6B3C, dark: 0x9CC98F)
    static let okBg = Color(light: 0xE7EFD9, dark: 0x1F2D1C)
    static let warn = Color(light: 0x9A5B0A, dark: 0xE3B160)
    static let warnBg = Color(light: 0xF9ECD0, dark: 0x35260E)
    static let bad = Color(light: 0xB3261E, dark: 0xF2B8B5)
    static let badBg = Color(light: 0xFBE6E2, dark: 0x3A1A18)
    static let seal = Color(light: 0x8B2520, dark: 0xF2EAD8)
    static let flame = Color(light: 0xF0A93B, dark: 0xF6C26B)
    static let flameCore = Color(light: 0xFFF3C4, dark: 0xFFF6D6)
    static let sealInk = Color(light: 0xF2EAD8, dark: 0x8B2520)

    static let inset: CGFloat = 16
    static let radius: CGFloat = 16
    static let rowHeight: CGFloat = 68
    static let buttonHeight: CGFloat = 54
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// A wax seal: a cream disc with a scalloped edge and a red W.
struct WaxSeal: View {
    var size: CGFloat = 36
    var body: some View {
        ZStack {
            ScallopedDisc().fill(Wax.seal)
            Circle().stroke(Wax.sealInk, lineWidth: max(1, size * 0.02)).padding(size * 0.2)
            Text("W")
                .font(.system(size: size * 0.40, weight: .heavy)).italic()
                .foregroundStyle(Wax.sealInk)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ScallopedDisc: Shape {
    func path(in rect: CGRect) -> Path {
        let lobes = 14.0, steps = 14 * 8
        let c = CGPoint(x: rect.midX, y: rect.midY), half = rect.width / 2
        var p = Path()
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let m = (44 + 6 * (0.5 + 0.5 * cos(a * lobes))) / 50 * half   // lobe tips reach the frame edge exactly
            let pt = CGPoint(x: c.x + m * cos(a), y: c.y + m * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

/// One row of a card: icon tile, two lines of text, and something on the right. Everything is vertically centered.
struct WaxRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    var subtitleLines = 1
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Wax.link)
                .frame(width: 40, height: 40)
                .background(Wax.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(Wax.text).lineLimit(1)
                Text(subtitle).font(.footnote).foregroundStyle(Wax.sub).lineLimit(subtitleLines)
                    .fixedSize(horizontal: false, vertical: subtitleLines > 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: Wax.rowHeight)
        .background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous).stroke(Wax.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
    }
}

struct WaxLinkText: View {
    let text: String
    var body: some View { Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Wax.link) }
}

struct WaxPill: View {
    enum Tone { case ok, warn }
    let text: String
    let tone: Tone
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tone == .ok ? Wax.ok : Wax.warn)
            .padding(.horizontal, 10).frame(height: 26)
            .background(tone == .ok ? Wax.okBg : Wax.warnBg, in: Capsule())
    }
}

struct WaxPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(Wax.onAccent)
            .frame(maxWidth: .infinity, minHeight: Wax.buttonHeight)
            .background(configuration.isPressed ? Wax.accentPressed : Wax.accent,
                        in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WaxSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Wax.link)
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A wax-colored progress bar. With a value it fills; without one a lump of wax sweeps back and forth.
struct WaxProgressBar: View {
    let progress: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Wax.chip)
                if let progress {
                    Capsule().fill(Wax.link).frame(width: max(14, w * min(1, max(0, progress))))
                        .animation(.easeOut(duration: 0.3), value: progress)
                } else {
                    Capsule().fill(Wax.link).frame(width: w * 0.35)
                        .offset(x: reduceMotion ? 0 : (sweep ? w * 0.65 : 0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: sweep)
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 14)
        .onAppear { sweep = true }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "Working")
    }
}

// MARK: Shared screen pieces

/// Large title with the seal on the right and one line of purpose underneath. Edges match the cards below it.
struct WaxHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.largeTitle.bold()).foregroundStyle(Wax.text)
                Spacer()
                WaxSeal(size: 36)
            }
            .frame(height: 44)
            Text(subtitle).font(.subheadline).foregroundStyle(Wax.sub)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct WaxSectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Wax.sub)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }
}

/// A card holding stacked rows (separate them with `WaxDivider`).
struct WaxPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous).stroke(Wax.line, lineWidth: 1))
    }
}

struct WaxDivider: View {
    var body: some View { Rectangle().fill(Wax.line).frame(height: 1) }
}

/// A label on the left and its value on the right, both on the same first line.
struct WaxKV: View {
    let key: String
    let value: String
    var small = false

    private var valueText: some View {
        Text(value)
            .font(small ? .caption.monospaced() : .subheadline)
            .foregroundStyle(Wax.text)
            .textSelection(.enabled)
    }

    var body: some View {
        Group {
            if small {
                stacked
            } else {
                // Side by side when the value fits on one line; otherwise the value wraps under its label.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(key).font(.subheadline).foregroundStyle(Wax.sub).lineLimit(1)
                        Spacer(minLength: 8)
                        valueText.lineLimit(1).multilineTextAlignment(.trailing)
                    }
                    stacked
                }
            }
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key).font(.subheadline).foregroundStyle(Wax.sub)
            valueText.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WaxDestructiveRow: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Wax.bad)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// One choice in a Wax action sheet.
struct WaxAction: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var destructive = false
    /// When set the row shares this file with the system share sheet instead of running `perform`.
    var share: URL?
    var perform: () -> Void = {}
}

/// The Wax look for a list of actions: the same icon tiles and cards as the rest of the app, in place of the system menu.
struct WaxActionSheet: View {
    let title: String
    let subtitle: String
    let actions: [WaxAction]
    /// Closes the sheet; `then` runs once it has finished closing.
    let close: (_ then: (() -> Void)?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(title).font(.headline).foregroundStyle(Wax.text).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(Wax.sub).lineLimit(1) }
            }
            .padding(.top, 22).padding(.bottom, 4)
            ForEach(actions) { action in
                if let url = action.share {
                    ShareLink(item: url) { row(action) }.buttonStyle(.plain)
                } else {
                    Button { close(action.perform) } label: { row(action) }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Wax.inset)
        .background(Wax.bg.ignoresSafeArea())
    }

    private func row(_ a: WaxAction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(a.destructive ? Wax.bad : Wax.link)
                .frame(width: 40, height: 40)
                .background(a.destructive ? Wax.badBg : Wax.chip, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            Text(a.title).font(.callout.weight(.semibold)).foregroundStyle(a.destructive ? Wax.bad : Wax.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(Wax.card, in: RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous).stroke(Wax.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Wax.radius, style: .continuous))
    }
}
