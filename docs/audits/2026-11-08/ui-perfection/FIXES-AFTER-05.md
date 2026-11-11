# Fixes applied after brief 05

Brief 05 scored the merged build at 71/100 and named nine visual defects (S1–S9),
seven motion defects (A1–A7) and three accessibility defects (E1–E3). Every one
of them was fixed on `ui/05-motion-qa`, except A6 (accepted by design, see
below) and the last part of S1 (explained below). This file records what
changed and what proves it.

## Motion (A1–A7)

| Defect | Fix | Where |
|---|---|---|
| A1 progress fill ignored Reduce Motion | `reduceMotion ? nil : .easeOut(0.3)` | `Theme.swift`, `WaxProgressBar` |
| A2 row highlight ignored Reduce Motion | same guard around the press highlight | `Theme.swift`, `WaxRowButtonStyle` |
| A3 four rescrolls ignored Reduce Motion | `withAnimation(reduceMotion ? nil : .default)` at all four tab-reselect sites | `SignView.swift`, `ContentView.swift`, `SourcesView.swift`, `SettingsView.swift` |
| A4 credentials scroll ignored Reduce Motion | same guard | `CredentialsView.swift` |
| A5 four unguarded `Wax.spring` sites | every one now `reduceMotion ? nil : Wax.spring` | `SigningOptionsView.swift` (2), `BundleIDModePicker.swift`, `NotificationPermissionModel.swift` |
| A6 busy overlay / feedback cards appear instantly | **Accepted by design.** An import in progress must be noticed at once, and an error must not fade in; both are announced instead (see E2). | — |
| A7 programmatic tab changes snapped the pill | one named `pillSpring` plus `.animation(pillSpring, value: selection)` on the bar, so a tap and a programmatic change slide identically | `WaxTabBar.swift` |

After these, every Wax-owned animation in the app is either guarded or the
system's own. No new curves or durations were introduced.

## Accessibility (E1–E3)

- **E1 / S5 — XXXL contrast failure under the tab bar.** The failing element
  was a setup row sitting under the floating bar, not a token contrast
  failure. Two changes: the setup card's icon now stays inline at every text
  size (it used to stack above the copy, costing a full line per row), and
  scrolling tab screens use `Wax.Space.tabBarClearance` (104 pt) as their
  bottom padding. `testAccessibilityAuditAtLargestText` passes on the final
  build.
- **E2 — the credentials busy overlay was silent to VoiceOver.** The overlay
  is not focused when it appears, so `busyMessage` now posts a
  `UIAccessibility.announcement`. The overlay itself is unchanged.
- **E3 — the last library rows could not be reached at XXXL.** This was a real
  layout bug, not a test artefact. `ContentView` had a `LazyVStack` nested
  inside the `VStack` that sits in the `ScrollView`; the lazy stack
  under-reported its height, so the scroll view stopped before the last rows
  even though they had been laid out. Replacing it with a plain `VStack`
  fixes it. The list is a handful of rows, so laziness bought nothing.
  `testSettingsAndLibraryBottomRowsStayAboveTabsAtLargestText` now passes
  (it failed identically on the untouched base commit `84029ab`).

## Visual (S1–S9)

- **S1 — the primary action was below the fold at XXXL.** Partly fixed, and
  the remainder is inherent. The setup rows keep their icon inline (about
  48 pt saved per row), and the empty "No app chosen" row is now a real
  button: it used to show a red "Choose" that did nothing, leaving the
  off-screen button as the only way to pick a file. At AX5 the summary button
  still needs a scroll, because a three-row card plus a full-size header
  cannot fit a 6.3-inch screen; every action is now reachable on screen
  without it. See `05-shots/06-sign-xxxl-light.png`.
- **S2 — the stage strip had no Preparing or Handed step.** `SignStage` now
  has five cases in pipeline order (`reading, signing, uploading, preparing,
  handed`). A sign-only export shows only `reading, signing`, so it never
  promises steps it will not reach. At accessibility sizes the strip becomes
  one sentence ("Stage 2 of 2, Signing") because five labels cannot be read
  side by side there.
- **S3 — the percent was a time-weighted estimate.** The Sign screen now shows
  measured work: signing and uploading each move the whole file, so a full run
  is `(sign + upload) / 2`, and a sign-only run is `sign`. `JobProgress` is
  still used by the system background task, where an estimate is the only
  thing available.
- **S4 — the Profile row wrapped to three lines.** The subtitle is now
  "Overrides the automatic choice.", the copy has `layoutPriority(1)`, and the
  picker stacks under the copy at accessibility sizes.
- **S5** — fixed with E1.
- **S6 — `WaxListRow` had no title line limit.** Added `titleLineLimit`
  (nil keeps the old unlimited behaviour) and applied a two-line cap to the
  two rows whose titles come from outside the app: certificate organisation
  names and provisioning profile names.
- **S7 — no paragraph style in the ramp.** Added `Wax.Ramp.paragraph`
  (`Font.callout`) and used it at the five long-copy sites: the first-run
  guide (2), the Sign result summary, the preflight note, and the install-host
  explanations.
- **S8 — the install-host screen still used `List`.** `InstallSection` is
  rebuilt from `WaxPanel` pieces (section label, panel, field, action,
  status), and `InstallHostSettingsView` is a `ScrollView`. The only `List`
  left in the app is the developer-only import log.
- **S9 — no dark populated-library screenshot.** Captured now:
  `05-shots/06-library-dark-populated.png`, from
  `testDarkPopulatedLibraryShowsEverySavedApp`, which seeds two fixture apps,
  asserts both rows exist and the empty state does not, and captures the
  screen in dark mode.

## Evidence

- `xcodebuild … -scheme LocalIPASigner build` — **BUILD SUCCEEDED**, exit 0.
- `swift test` — 0 failures (150/33/12/26/12/83 across the suites).
- `xcodebuild … -scheme WaxModelTests test` — 126 tests, 0 failures.
- `xcodebuild … -scheme WaxUITests test` — **22 tests, 0 failures, 0 skipped**
  (307.2 s, run 21:59:46–22:04:54 on the final build).
- Targeted, on the final build:
  `testSettingsAndLibraryBottomRowsStayAboveTabsAtLargestText` — **passed**
  (failed on `84029ab`);
  `testDarkPopulatedLibraryShowsEverySavedApp` — **passed**.

## Tried and reverted

Capping `WaxHeader` title and subtitle at `DynamicTypeSize.accessibility1`.
It shrank the header, but the accessibility audit then failed with
"Dynamic Type font sizes are partially unsupported". Capping display type costs
more than it buys, so the cap was removed. Body copy scales uncapped.
