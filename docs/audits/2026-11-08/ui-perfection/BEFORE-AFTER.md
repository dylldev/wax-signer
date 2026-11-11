# Before / after — Brief 05

Base: `84029ab` (merged 01–04). After: `ui/05-motion-qa` with the WaxMelt
hardening, two new test files, and the six reports themselves.

## What changed in code

`App/WaxMelt.swift` (3 small hunks, no API change):

1. `animatableData` setter now writes `min(1, max(0, newValue))`
   (was `progress = newValue`). Before: a springy caller could overshoot
   past 1.0 into `pow(1 - p, 0.9)` with a negative base → `NaN` candle
   height → candle vanishes early. After: every write is clamped, and
   `draw` already clamped `p` for rendering, so the two now agree.
2. Drip length is `max(0, min(height - topRy, …))` (was no `max(0, …)`).
   Before: short-candle tail (`height` between 4 and 7 pt) produced a
   negative `roundedRect` height. After: zero-height drip is a no-op path.
3. Type doc adds the measured-work contract ("Callers must pass measured
   work (signing/upload fractions), never an invented percentage") and the
   pause conditions. Before: doc said "real progress" without naming the
   paused states. After: the pause rule is on the type so the next caller
   cannot unknowingly put an estimate in and call it real.

No durations, curves, candle geometry, flame math, pool growth, seal
timing, centring, `TimelineView` interval, or accessibility label were
altered. `App/Theme.swift` was not touched (forbidden). Every other fix
found (A1–A7, E1–E3, S1–S9) is recorded with file:line in
`ANIMATION-REPORT.md` / `ACCESSIBILITY-REPORT.md` / `VISUAL-AUDIT.md`
and left for its owner.

## What changed in tests

Added (nothing removed, nothing renamed):

- `Tests/AppModelTests/MotionAccessibilityQATests.swift` — 7 tests:
  text-pair WCAG AA, feedback-pair WCAG AA, touch targets, WaxMelt clamp
  + default height, stage-truthfulness gap, weighted-estimate contract,
  spacing order. Result: `WaxModelTests` **119 → 126 tests, 0 failures**.
- `Tests/UITests/WaxPerfectionQATests.swift` — 4 tests: tab equal widths
  (1.5 pt), primary touch target, content-vs-bar overlap, tab labels.
  Result: `WaxUITests` **17 → 21 tests**, new 4 **0 failures in 26.0 s**,
  pre-existing 2 failures unchanged (the XXXL layout fails in
  `ACCESSIBILITY-REPORT.md`).

## Screenshots

Before (from 02/03, still valid on this base — Sign empty light/dark/XXXL
rank unchanged): `shots-before/empty-light-default.png`,
`shots-before/empty-light-xxxl.png`, `shots-before/empty-dark-default.png`,
plus `shots-after/` from 02/03. After (this brief, new):
`05-shots/05-sign-light.png`, `05-shots/05-sign-dark.png`,
`05-shots/05-sign-xxxl-dark.png`, `05-shots/05-sign-xxxl-light.png`.
WaxMelt mid-blur is **not** shown: reaching a signing frame needs a
certificate + profile through the Files picker, which this environment
cannot drive, so no mid-melt pixels are claimed. The dev-build
`developer-animation-quarter` / `developer-animation-eighty` captures from
`WaxUITests/testDeveloperToolsStayInSettingsAndAnimationPreviewResponds`
cover the `MeltDemo` stand-in on the dev bundle.

## Verification (real output, quoted)

- `xcodegen generate` — exit 0.
- `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner
  -destination 'platform=iOS Simulator,name=iPhone 17' build` —
  `** BUILD SUCCEEDED **`, exit 0.
- `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner
  -destination 'platform=iOS Simulator,name=iPhone 17' test` —
  exit **66**: `Scheme LocalIPASigner is not currently configured for the
  test action.` (scheme has `test.targets: []` in `project.yml`; the
  command as written cannot pass on this base).
- `xcodebuild -project LocalIPASigner.xcodeproj -scheme WaxModelTests
  -destination 'platform=iOS Simulator,name=iPhone 17' test` —
  `** TEST SUCCEEDED **`, exit 0, 126 tests, 0 failures.
- `xcodebuild -project LocalIPASigner.xcodeproj -scheme WaxUITests
  -destination 'platform=iOS Simulator,name=iPhone 17' test` —
  `** TEST FAILED **`, exit 65, 21 tests, 2 failures (the two pre-existing
  XXXL failures; new 4 passed).
- `swift test` — exit 0, 83 tests, 0 failures.

No push, no PR, no change to `publish/main` or `main`.

## Afterwards

Everything this brief left open was fixed on `ui/05-motion-qa` afterwards:
A1–A7, E1–E3 and S1–S9 (S1 partly, with the reason stated). The verification
block above is the brief-05 run of the merged base and is kept as written;
`FIXES-AFTER-05.md` has the current results, and the two XXXL failures listed
there now pass.
