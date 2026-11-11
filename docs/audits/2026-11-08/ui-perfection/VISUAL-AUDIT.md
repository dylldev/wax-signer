# Visual audit — Brief 05

Harness: `Tests/UITests/WaxPerfectionQATests.swift` (4 tests) +
`Tests/AppModelTests/MotionAccessibilityQATests.swift` (7 tests). Same
device every time: iPhone 17 simulator (`BCE070AC…`), iOS 27.0. Baseline
launch arguments: `-firstRun.completed YES`. Geometry tolerances: 1.5 pt for
equal widths / touch targets (ignores anti-aliasing, fails on real drift).

## New screenshots (this brief, real captures)

Captured on `Wax02 iPhone 17` (`0EA21001…`) via
`xcrun simctl io … screenshot`, app installed from the `LocalIPASigner`
Debug build, each with `EXIT:0` on `simctl io`:

- `05-shots/05-sign-light.png` — Sign empty, light, default size
- `05-shots/05-sign-dark.png` — Sign empty, dark, default size
  (`simctl ui … appearance dark`)
- `05-shots/05-sign-xxxl-dark.png` — Sign empty, dark,
  `accessibility-extra-extra-extra-large`
- `05-shots/05-sign-xxxl-light.png` — Sign empty, light, XXXL
  (recaptured after resetting appearance to light so light/dark XXXL are
  both honest)

Captured after the fix pass (same device, current build):

- `05-shots/06-sign-xxxl-light.png` — Sign empty, light, XXXL, showing the
  setup rows with the icon inline and the empty app row acting as a button
- `05-shots/06-library-dark-populated.png` — dark library with two saved
  apps, captured by `testDarkPopulatedLibraryShowsEverySavedApp` (the test
  seeds the fixtures, asserts both rows exist, and restores light mode)

States **not** captured (reached by no agent in this environment, and
not invented here): signing in progress (Reading transient < 1 s for the
30 KB fixture; full signing needs a `.p12` + `.mobileprovision` through
the Files picker, which UI automation cannot drive, and `WaxUITests`
links only `InstallKit` — no credential-store seeding), uploaded / handed
to iOS during the phone wait, signed-success / signed-with-problems
results, preflight blocked/warning. The `WaxMelt` mid-melt frame is
therefore **not** shown as a screenshot in 05. The existing
`testDeveloperToolsStayInSettingsAndAnimationPreviewResponds` capture
(`developer-animation-quarter` / `developer-animation-eighty`) covers the
`MeltDemo` slider in the dev build if a mid-melt visual is needed.

## Geometry assertions (new harness)

- `testTabBarEqualWidths` — four tab widths equal within 1.5 pt. **Passed.**
  Pill is a background (`WaxTabBar.swift:84-89`), so equal frames are the
  contract by construction; the test pins it.
- `testPrimaryButtonMeetsTouchTarget` — primary height ≥ 52.5 pt and width
  ≥ 200 pt at default size. **Passed.** Pins `Wax.buttonHeight = 54`.
- `testNoOverlapBetweenContentAndTabBar` — header `maxY` ≤ tab-top + 1.5 pt
  at default size. **Passed.** Catches the floating-bar overlap that
  `testAccessibilityAuditAtLargestText` flags at XXXL, at the size where it
  currently passes.
- `testAccessibilityLabelsOnEveryTab` — all four tabs exist with non-empty
  labels. **Passed.**
- Unit pins (no simulator): `Wax.touch == 44`, `Wax.buttonHeight >= 54`,
  `Wax.rowHeight >= 56`, `Wax.barHeight == 14`, spacing scale ordered,
  `Wax.inset == 16`, `Wax.radius == 16`. All **passed** (126 total in
  `WaxModelTests`).

What the harness does **not** yet assert (and a future brief should add):
shared leading/trailing anchors across library rows (needs a populated
library + `debugDescription` tree walk), common row heights for grouped
`WaxListRow`s at XXXL, and dark-populated-library pixels (see below).

## Defect register (05 confirms or refutes, with fix)

Confirmed (9 from the task list, all reproduced or read on `84029ab`):

- **S1** Sign at XXXL needs scrolling to reach the primary button (02).
  Cause: summary rows triple at accessibility sizes
  (`SignView.swift:209-211` stacked layout, `Theme.swift:506-508` same),
  header `minHeight 44` grows with type. Fix in `Theme.swift` /
  `SignView.swift`.
- **S2** Stage strip has no Preparing and no Handed stage (02).
  `SignStage` cases are reading/signing/uploading only
  (`Sources/InstallKit/SignScreenLogic.swift:15`).
- **S3** Signing percent is an estimate, not measured work (02).
  `JobProgress.overall` (`Sources/InstallKit/JobProgress.swift:14`)
  blends by expected seconds (`SigningModel.jobProgress`).
- **S4** Profile row wraps to 3 lines (02). `SigningOptionsView.swift:248-261`
  `HStack` squeezes "Which provisioning profile signs this app." against
  the `Automatic` picker.
- **S5** XXXL contrast failure on the Sign caption at
  `SignScreenLogic.swift:62` (04). **Reproduced** in
  `Test-WaxUITests-2026.11.08_20-39-13--0500.xcresult`:
  element "Add your signing files" frames `{{32,731},{272,121}}` under the
  tab bar; token ratios pass ≥ 5.35:1, so the fix is geometric (see E1).
- **S6** `WaxListRow` needs a `titleLineLimit` parameter (04).
  `Theme.swift:518` title has no explicit limit (wraps unlimited) while
  `WaxRow` pins `lineLimit(2)` (`Theme.swift:177`).
- **S7** The Ramp has no paragraph token (04). Long copy uses `.body` /
  `.subheadline` / `.footnote` ad hoc (`FirstRunGuide.swift:105,177`,
  `SignView.swift:332,554`).
- **S8** `InstallHostSettingsView` still uses List chrome (04).
  `SettingsView.swift:182` — the only `List` left; `scrollContentBackground(.hidden)` hides the style but not the List animation/scroll semantics.
- **S9** Dark populated library was never captured (03). `shots-after/`
  has `empty-dark` only; 03 removed the byte-identical fake. Header of
  `docs/audits/2026-11-08/ui-perfection/SCREEN-BY-LIBRARY.md` confirms it.

Refuted: none. Every 01–04 claim held up on the merged base. New defects
found by 05 (motion A1–A7, accessibility E2–E3) are in their own reports;
this register is the single list to work from.

## Status after the fix pass

| Defect | Status |
|---|---|
| S1 | **Partly fixed.** Setup icons stay inline, and the empty "No app chosen" row is now a real button, so every action is on screen at XXXL. The summary button still needs a scroll at AX5; a three-row card and a full-size header cannot fit one screen. |
| S2 | **Fixed.** Five stages, and a sign-only run shows two. |
| S3 | **Fixed.** Measured work: `(sign + upload) / 2`, or `sign` for export-only. |
| S4 | **Fixed.** Shorter subtitle, `layoutPriority(1)`, picker stacks at accessibility sizes. |
| S5 | **Fixed** with E1. The audit passes at XXXL. |
| S6 | **Fixed.** `titleLineLimit` added and applied to certificate and profile names. |
| S7 | **Fixed.** `Wax.Ramp.paragraph` used at five long-copy sites. |
| S8 | **Fixed.** `InstallSection` is Wax panels; `InstallHostSettingsView` is a `ScrollView`. |
| S9 | **Fixed.** `05-shots/06-library-dark-populated.png`. |
