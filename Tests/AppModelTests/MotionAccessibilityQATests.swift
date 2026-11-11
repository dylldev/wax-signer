import Foundation
import InstallKit
import XCTest
import UIKit
@testable import LocalIPASigner

/// Motion/accessibility QA: token geometry, WCAG contrast, and progress-honesty contracts.
/// These run without a simulator so the token facts are pinned on every build.
final class MotionAccessibilityQATests: XCTestCase {
    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testTextPairsMeetWCAGAA() throws {
        // Hex values mirror App/Theme.swift Wax tokens. Changing a token requires
        // updating these literals too, so the check stays honest.
        let pairs: [(String, UIColor, UIColor)] = [
            ("text/bg light", UIColor(hex: 0x2A1A14), UIColor(hex: 0xF5EFE2)),
            ("text/bg dark", UIColor(hex: 0xF3E9D6), UIColor(hex: 0x170C0B)),
            ("sub/bg light", UIColor(hex: 0x6E5F53), UIColor(hex: 0xF5EFE2)),
            ("sub/bg dark", UIColor(hex: 0xA8978A), UIColor(hex: 0x170C0B)),
            ("link/bg light", UIColor(hex: 0x8B2520), UIColor(hex: 0xF5EFE2)),
            ("link/bg dark", UIColor(hex: 0xE8C9A0), UIColor(hex: 0x170C0B)),
            ("onAccent/accent light", UIColor(hex: 0xF7EFDD), UIColor(hex: 0x8B2520)),
            ("onAccent/accent dark", UIColor(hex: 0x5E1612), UIColor(hex: 0xE8DCC2)),
        ]
        for (name, fg, bg) in pairs {
            XCTAssertGreaterThanOrEqual(contrast(fg, bg), 4.5, "\(name): \(contrast(fg, bg))")
        }
    }

    func testFeedbackPairsMeetWCAGAA() throws {
        let pairs: [(String, UIColor, UIColor)] = [
            ("ok/bg light", UIColor(hex: 0x3E6B3C), UIColor(hex: 0xF5EFE2)),
            ("warn/bg light", UIColor(hex: 0x9A5B0A), UIColor(hex: 0xF5EFE2)),
            ("bad/bg light", UIColor(hex: 0xB3261E), UIColor(hex: 0xF5EFE2)),
            ("ok/bg dark", UIColor(hex: 0x9CC98F), UIColor(hex: 0x170C0B)),
            ("warn/bg dark", UIColor(hex: 0xE3B160), UIColor(hex: 0x170C0B)),
            ("bad/bg dark", UIColor(hex: 0xF2B8B5), UIColor(hex: 0x170C0B)),
        ]
        for (name, fg, bg) in pairs {
            XCTAssertGreaterThanOrEqual(contrast(fg, bg), 4.5, "\(name): \(contrast(fg, bg))")
        }
    }

    func testTouchTargetsMeetMinimum() {
        XCTAssertEqual(Wax.touch, 44)
        XCTAssertGreaterThanOrEqual(Wax.buttonHeight, 54)
        XCTAssertGreaterThanOrEqual(Wax.rowHeight, 56)
        XCTAssertEqual(Wax.barHeight, 14)
    }

    func testWaxMeltProgressClamps() {
        // The renderer smooths its own copy, so the view hands it a clamped share: out-of-range input must not
        // reach the shader, and the candle must never run past the measured work.
        XCTAssertEqual(WaxMelt(progress: 0.4).clampedProgress, 0.4)
        XCTAssertEqual(WaxMelt(progress: 2).clampedProgress, 1.0)
        XCTAssertEqual(WaxMelt(progress: -1).clampedProgress, 0.0)
        XCTAssertEqual(WaxMelt(progress: 0).height, 230)
    }

    func testSignStageTellsPreparationAndHandoff() {
        // The strip used to stop at Uploading, so the host preparing the install and
        // the handoff to iOS had no step. Both are stages now, in pipeline order.
        XCTAssertEqual(SignStage.allCases, [.reading, .signing, .preparing, .uploading, .handed])
        XCTAssertEqual(SignStage.resolve(reading: true, signing: false, uploading: false), .reading)
        XCTAssertEqual(SignStage.resolve(reading: false, signing: true, uploading: false), .signing)
        XCTAssertEqual(SignStage.resolve(reading: false, signing: false, uploading: true), .uploading)
        XCTAssertEqual(SignStage.resolve(reading: false, signing: false, uploading: false, preparing: true), .preparing)
        XCTAssertEqual(SignStage.resolve(reading: false, signing: true, uploading: false, preparing: true), .signing)
        XCTAssertEqual(SignStage.resolve(reading: false, signing: false, uploading: false, preparing: true, handed: true), .handed)
        XCTAssertNil(SignStage.resolve(reading: false, signing: false, uploading: false))
    }

    func testJobProgressBlendsByExpectedSeconds() {
        // Used by the system background task, not by the Sign screen: the on-screen
        // percent is measured work now. This blend is still an estimate by construction.
        let weights = JobProgress(signSeconds: 8, uploadSeconds: 24)
        XCTAssertEqual(weights.overall(sign: 1, upload: 0), 0.25, accuracy: 0.0001)
        XCTAssertEqual(weights.overall(sign: 0, upload: 1), 0.75, accuracy: 0.0001)
        XCTAssertEqual(weights.overall(sign: 1, upload: 1), 1.0, accuracy: 0.0001)
        let zero = JobProgress(signSeconds: 0, uploadSeconds: 0)
        XCTAssertEqual(zero.overall(sign: 0.3, upload: 0.9), 0.3, accuracy: 0.0001)
    }

    func testSpacingScaleIsOrdered() {
        XCTAssertLessThan(Wax.Space.xs, Wax.Space.s)
        XCTAssertLessThan(Wax.Space.s, Wax.Space.m)
        XCTAssertLessThan(Wax.Space.m, Wax.Space.l)
        XCTAssertLessThan(Wax.Space.l, Wax.Space.xl)
        XCTAssertEqual(Wax.inset, 16)
        XCTAssertEqual(Wax.radius, 16)
    }
}
