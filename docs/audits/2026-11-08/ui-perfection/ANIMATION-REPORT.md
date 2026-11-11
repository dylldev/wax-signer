# Animation report — Brief 05 (motion, accessibility, QA)

Branch: `ui/05-motion-qa` from `84029ab`. Scope: `App/WaxMelt.swift` plus
read-only audit of every interaction. No other source was edited.

## Motion vocabulary

There is one standard motion in `App/Theme.swift`: `Wax.spring`
(`.spring(response:0.35, dampingFraction:0.85)`, `Theme.swift:89`), and one
guard `View.waxMotion(value:)` (`Theme.swift:92-100`) which maps it to `nil`
under Reduce Motion. Everything else is a named exception, not a second
vocabulary. Durations and curves actually used in the app:

| Interaction | Declaration | Duration / curve | Guarded by Reduce Motion? |
|---|---|---|---|
| Standard state change (expand, select, stage strip) | `Wax.spring` via `waxMotion` | spring 0.35 / 0.85 | Yes (`Theme.swift:95`) |
| Tab pill slide + glyph pop | `withAnimation(.spring(0.38, 0.72))` `WaxTabBar.swift:72` | spring 0.38 / 0.72 | Yes, explicit `reduceMotion ? nil` |
| Primary-button press | `.easeOut(0.12)` `Theme.swift:227` | 0.12 s ease-out, scale 0.97 | Yes (`Theme.swift:226`) |
| Tab-press scale | `.spring(0.25, 0.6)` `WaxTabBar.swift:111` | spring 0.25 / 0.6, scale 0.94 | Yes |
| Row-button highlight | `.easeOut(0.05/0.25)` `Theme.swift` `WaxRowButtonStyle` | 0.05 in, 0.25 out | Yes (A2 fixed) |
| Progress fill | `.easeOut(0.3)` `Theme.swift` `WaxProgressBar` | 0.3 s ease-out | Yes (A1 fixed) |
| Progress sweep (indeterminate) | `.easeInOut(1.0).repeatForever` `Theme.swift:259` | 1.0 s ease-in-out, autoreverse | Yes |
| WaxMelt progress interpolation | `.linear(0.25)` `SignView.swift:324`, `WaxMelt.swift:150` | 0.25 s linear | Yes |
| Percent numeric transition | `.easeOut(0.18)` `SignView.swift:329` | 0.18 s ease-out + `.numericText()` | Yes |
| Seal stamp | `.spring(0.45, 0.55)` `SignView.swift:670` | spring 0.45 / 0.55, scale 1.9→1 | Yes |
| Guide pulse | `.phaseAnimator` `FirstRunGuide.swift:218` | 0.9 s ease-in-out, scale 1.03 | Yes via `animatesExamples` |
| Flame flicker + drips | `TimelineView(.animation(1/60))` `WaxMelt.swift:20` | 60 fps, only when animating | Yes (paused + static sway) |
| Rescroll-to-top on tab reselect | `withAnimation(reduceMotion ? nil : .default)` four places | system default | Yes (A3 fixed) |
| Credentials scroll-to-imported | `withAnimation(reduceMotion ? nil : Wax.spring)` `CredentialsView` | `Wax.spring` | Yes (A4 fixed) |
| Disclosure / compression select | guarded `Wax.spring` in `SigningOptionsView` (2), `BundleIDModePicker`, `NotificationPermissionModel` | `Wax.spring` | Yes (A5 fixed) |

Reduce Motion is the rule everywhere it is applied. The five unguarded sites
above were the whole motion finding; there are no competing spring constants
outside the table. **All five were fixed on this branch** (A1–A5), and A7 was
fixed by animating the pill on `selection` changes rather than only inside the
tap handler.

## Interaction audit

Every interaction was read, not inferred. Findings by surface:

1. **Tab changes.** Pill slide and glyph scale share one transaction in
   `WaxTabBar.swift`. No double animation on the same property. Wrong origin
   in one case: programmatic tab changes (`router.tab = .sign` from
   `ContentView.swift:133`, `router.tab = .ipa` from `SignView.swift:466`)
   bypass `WaxTabBar`'s `withAnimation`, so the pill snaps instead of sliding.
   No layout shift: the pill is a background, not a layout item.
2. **Buttons.** Primary and tab-press scale only `scaleEffect`; they never
   move layout. Row highlight uses `WaxRowButtonStyle` background opacity,
   also layout-neutral. No flicker observed in code: opacity/scale are
   continuous functions of `isPressed`.
3. **Toggles.** System toggles tinted `Wax.accent`/`Wax.link`. No custom
   animation around them; the thumb is the system animation. Inconsistent
   only in that toggle state changes have no Wax name for their curve — they
   are the system default, which is fine and documented here.
4. **Sheets.** Document picker, action sheet, install host, details — all use
   the system sheet animation with no extra wrapper. No double animation,
   no layout animation inside the sheet content. `WaxActionSheet` heights are
   fixed by `presentationDetents`, so content does not push the tab bar.
5. **Expanding sections.** `SigningOptionsView` "More options" uses
   `$moreOpen.animation(Wax.spring)`; `SignView` passport/report groups use
   `DisclosureGroup` with no explicit animation (system collapse). Both
   expand the `ScrollView` content — this *is* a layout animation, but it is
   the standard expansion and the page scrolls with it; no sibling shifts
   horizontally. The unguarded spring is defect A5.
6. **Progress.** Equal to its own section above: fill is unguarded (A1),
   sweep is guarded. The fill width is `max(14, w * progress)` inside a
   `GeometryReader`; width animation does not shift any sibling because the
   track is a fixed-height capsule. No layout jump.
7. **Imports.** Credentials busy card (`CredentialsView.swift:107-118`) is a
   floating overlay with `WaxProgressBar(progress:nil)` sweep. The sweep is
   guarded. The overlay itself has no enter/exit animation — it appears.
   That is a missed motion moment (entry is instant while exit of sheets is
   animated), recorded as minor: see A6.
8. **Signing stages.** Stage strip (`SignView.swift:346-365`) uses
   `waxMotion(value: current)`, so check→dot uses the standard spring and is
   guarded. What it cannot tell the truth about is covered by defect S2.
9. **Success / failure.** `resultHeader` stamp: `scale 1.9→1`, `rotation -14→0`,
   `opacity 0→1` in one spring transaction, guarded, and suppressed entirely
   under Reduce Motion (renders final state). Feedback cards have no entry
   animation — again instant appearance, same nit as A6. No motion restarts:
   `stamp()` resets `stamped=false` before animating, once per run
   (`SignView.swift:668-671`).

Double-animation verdict: **none on the same property**. Two clocks run in
parallel during signing (progress interpolation at 0.25 s linear + flame
flicker at 60 fps) but they drive different things (candle height vs flame
shape) and were designed that way. Delayed response: none found. Motion that
restarts: none — `WaxProgressBar.sweep` starts once in `onAppear`, and
`WaxMelt`'s `TimelineView` is paused when finished (`progress < 1` gate).

## Status after the fix pass

A1, A2, A3, A4, A5 and A7 are fixed on `ui/05-motion-qa`; A6 is accepted by
design (the busy overlay and feedback cards appear without animation on
purpose, and the busy state is announced for VoiceOver). The defect entries
below are kept as written by brief 05 so the finding and the fix can be read
side by side.

## Defects in this file (read-only elsewhere)

- **A1** `App/Theme.swift:255` — progress fill `.animation(.easeOut(0.3))`
  has no Reduce Motion guard. Fix: `reduceMotion ? nil : .easeOut(0.3)` and
  add `@Environment(\.accessibilityReduceMotion)` to `WaxProgressBar` (it
  already has sweep state, so one more environment read is enough).
- **A2** `App/Theme.swift:566` — `WaxRowButtonStyle` highlight animates in
  both directions regardless of Reduce Motion. Fix: guard with the same
  ternary, or accept a 0.05 s in-only highlight and drop the 0.25 s out.
- **A3** Tab-reselect rescroll `withAnimation { proxy.scrollTo }` in four
  files (`SignView.swift:92`, `SettingsView.swift:119`,
  `SourcesView.swift:56`, `ContentView.swift:84`) ignores Reduce Motion.
  Fix: `withAnimation(reduceMotion ? nil : .default)`.
- **A4** `App/CredentialsView.swift:165` — same, plus uses bare `Wax.spring`
  with no guard. Fix: route through `waxMotion` semantics or the same
  ternary.
- **A5** Unguarded `Wax.spring` unfixed: `SigningOptionsView.swift:73,169`,
  `BundleIDModePicker.swift:12`, `NotificationPermissionModel.swift:83`.
  Fix: every one becomes `reduceMotion ? nil : Wax.spring`.
- **A6** (minor) Busy overlay and feedback cards appear instantly. Fix:
  `.transition(.opacity)` paired with the existing parents' `withAnimation`,
  or leave as-is by design and document "instant by choice". Currently
  undocumented.
- **A7** (minor) Programmatic tab changes snap the pill (see §1). Fix:
  set `selection` via `withAnimation` in a `Router.tab` setter or observe
  `selection` with `.animation(..., value: selection)` on the pill.

## What 05 changed

`App/WaxMelt.swift` only: clamped `animatableData` writes to `0...1` so a
spring overshoot cannot produce `pow(negative)` → `NaN` in
`maxHeight * pow(1 - p, 0.9)`; guarded drip length with `max(0, …)` for the
short-candle tail where `height - topRy` goes negative; and documented the
measured-work contract on the type. No durations, curves, or geometry were
altered. See `BEFORE-AFTER.md`.
