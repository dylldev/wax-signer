# Performance report — Brief 05

No frame-rate claim is made here. Every number below was measured with a
stopwatch or a test clock on the iPhone 17 simulator, or is labeled as a
code-level invalidation cost. Signing could not be run end-to-end in this
environment (no certificate + profile imported through the Files picker;
UI automation cannot drive the document picker reliably — same limit the 02
report records), so signing numbers are model-level, not on-device draws.

## What was measured

| Probe | Result | How |
|---|---|---|
| `xcodegen generate` | exit 0 | re-run after every edit below |
| `xcodebuild … -scheme LocalIPASigner … build` | `** BUILD SUCCEEDED **`, exit 0 | after WaxMelt + tests |
| `xcodebuild … -scheme LocalIPASigner … test` | exit **66**, `Scheme … not currently configured for the test action` | the brief's literal command cannot pass: `LocalIPASigner` scheme has `test.targets: []` in `project.yml`. Correct commands are below. |
| `xcodebuild … -scheme WaxModelTests … test` | `** TEST SUCCEEDED **`, exit 0, **126 tests, 0 failures** in 6.9 s | includes new `MotionAccessibilityQATests` (7 tests, 0.002 s) |
| `xcodebuild … -scheme WaxUITests … test` | exit **65**, **21 tests, 2 failures** (the pre-existing XXXL ones), 318 s | includes new `WaxPerfectionQATests` (4 tests, **26.0 s**, 0 failures) |
| `swift test` | exit 0, **83 tests** (CredentialKit), 13 skipped, 0 failures | covers only `Package.swift` targets; app tests are the `WaxModelTests` scheme above |

Test wall-clock is itself a signal: unit suite 6.9 s, full UI suite 318 s
with 2 known failures. No Instruments trace was captured — this brief did
not build capture infrastructure (per task rules), so main-thread cost is
reasoned from invalidation counts below, not profiled in the debugger.

## Sign screen during signing — invalidation cost (reasoned, not profiled)

`progressCard` (`SignView.swift:319-343`) rebuilds on every `jobFraction`
change. `jobFraction` derives from `model.signFraction`, which the engine
publishes through `ProgressThrottle` (`SigningModel.swift:661-674`):
a new value is published only when the message changes or the fraction
moves ≥ 0.01. Worst case during a large signing run that is 100 publishes.
Each publish re-renders `WaxMelt` (Canvas at 60 fps while `animates`), the
46 pt percent, the stage strip, and the message. Canvas redraw is
`rendersAsynchronously: true`, so the main thread only re-records path
data on publish; per-frame flame flicker is off-main-thread. Animated
interpolation (`.linear(0.25)`) smooths between the 1%-step publishes, so
at steady state the screen does ~1 invalidation per ~0.25 s of a morph,
plus the 60 fps off-thread flicker. No measured frame rate is claimed; the
structural cost is bounded by the throttle (≤ 100 rebuilds per run), which
is the right budget.

Background cost: `SigningModel.sign` runs unpacking/signing on
`Task.detached(priority: .userInitiated)` and publishes back via
`Task { @MainActor in }` per throttled step. Main-thread work per publish
is a `@Published` assignment + one `body` pass of `progressCard`. Nothing
in the path reads the IPA, touches the Keychain, or does archive I/O on
the main actor. Upload watcher (`SigningModel.swift:299-302`) forwards
`.uploading` fractions the same way.

`WaxMelt` CPU (code-reading): `draw` builds ~10 paths per frame (puddle 2,
body complex, face 3, flame 2, drips ≤ 6, seal 3). The 05 clamp/doc edits
add no per-frame work. `TimelineView` is paused when hidden
(`isVisible=false` → `paused:true`), backgrounded (`scenePhase != .active`),
Reduce-Motion, or finished (`progress >= 1`) — verified by reading
`animates` (`WaxMelt.swift:17`). So the brand signature costs zero frames
on every other tab.

**Before / after for 05:** the `animatableData` clamp and drip-length guard
are O(1) integer ops per publish; no before/after frame delta is claimed
because no before measurement exists. The change exists to remove the
`NaN` risk, not to speed anything up.

## Library during scroll — invalidation cost (reasoned)

`ContentView` rows live in `LazyVStack(spacing: 8)` (`ContentView.swift:70`);
each `WaxRow` is a fixed 68 pt-min row whose trailing slot is independent of
its title/subtitle. `SignedExpiryPill` per row (`ContentView.swift:259-288`)
caches by `path@mtime` in a static dict, so a signed file is read once, on
`Task.detached(priority: .utility)`, then reused. Scrolling invalidates
only newly-visible cells. No measured scroll frame time is claimed; the
existing large-library test seed (03, `03-shell-light-populated-library.png`)
shows the list rendering without an empty-state flash, but that is a
screenshot, not a profile.

## Honest gaps

- Signing end-to-end (real `.p12` + `.mobileprovision` → real signing →
  real upload) was **not reached** in this environment. The signing numbers
  above stop at throttle/view-instantiation; they do not cover engine
  stages per megabyte.
- Library scroll frame rate was **not measured**. No Instruments session,
  no `signpost`, no `measure {}` block was added. If the next brief wants a
  frame budget, add a `measure` in `WaxPerfectionQATests` that scrolls the
  populated library ten rows and records average frame time — do not infer
  it from "feels smooth".
- The two existing XXXL failures (`testAccessibilityAuditAtLargestText`,
  `testSettingsAndLibraryBottomRows…`) are layout failures, not perf
  failures; they both cost wall-clock (the library one alone runs 60 s of
  swipes before failing) but they are correctness gates in
  `ACCESSIBILITY-REPORT.md`, not here.
