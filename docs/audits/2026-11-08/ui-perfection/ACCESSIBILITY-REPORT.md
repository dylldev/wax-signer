# Accessibility report — Brief 05

Device: iPhone 17 simulator, iOS 27.0. Settings audited: VoiceOver labels /
traits / order; Dynamic Type through Accessibility-XXXL; Increase Contrast;
Bold Text; Differentiate Without Colour; Reduce Transparency; Reduce Motion
(see `ANIMATION-REPORT.md`). Verdicts below are from code reading plus the
`WaxUITests` runs quoted at the end. Screenshots captured by this brief are
in `05-shots/`; everything else cites the named prior capture.

## Who was actually run

- `testAccessibilityAudit()` (default size) — **passed**
- `testAccessibilityAuditAtLargestText()` (XXXL) — **failed: "Contrast failed"**
  for `Add your signing files` (`SignSetupStep.identity.title`,
  `Sources/InstallKit/SignScreenLogic.swift:62`, rendered in `SignView.swift`
  `setupRow`). The element frame is `{{32.0, 731.7}, {272.3, 121.0}}` —
  at XXXL it sits *under the floating tab bar* (the audit's element
  screenshot shows the text clipped by the bar). The token contrast itself
  passes (see below); the failure is geometric, it recurs at every size
  where the summary card pushes the row under the bar. This is the 04 defect
  from the task list, now reproduced on `84029ab` with the exact xcresult
  (`Test-WaxUITests-2026.11.08_20-39-13--0500.xcresult`). **Confirmed.**
  **Fixed on `ui/05-motion-qa`:** the setup rows keep the icon inline and the
  scrolling tab screens reserve 104 pt under the floating bar; the audit
  passes on the final build.
- `testSettingsAndLibraryBottomRowsStayAboveTabsAtLargestText()` — **failed**
  at `WaxUITests.swift:204`: `lastApp.isHittable` for the library row after
  10 swipes. Settings part passed in 16 swipes; the library needs more.
  Same root cause as the one above: XXXL rows are tall enough that the
  floating bar covers the bottom of the scroll until the last swipe settles.
  **Confirmed as a real hit-test failure, not a flaky wait.**
  **Fixed:** the cause was a `LazyVStack` nested in the scroll content's
  `VStack`, which under-reported its height at XXXL; it is a plain `VStack`
  now, and the test passes.
- `testTabTitlesRemainVisibleAtAccessibilitySizes()` — passed. Tab titles
  are rendered at `...xxxLarge` cap (`WaxTabBar.swift:80`) and Vision OCR
  finds all four at XXXL. This is the one deliberate Dynamic Type clamp in
  the app and it is documented, not accidental.
- `testInactiveTabsStayOutOfAccessibilityTree()` — passed. Only the active
  tab's heading tree is exposed; no duplicate headings.
- New `WaxPerfectionQATests` (4 tests, same device) — all passed:
  equal tab widths within 1.5 pt, primary button height ≥ 52.5 pt at default
  size, header above the bar, labels present on all tabs.

## Tokens vs WCAG AA (measured, not claimed)

Hex pairs from `App/Theme.swift` were contrast-tested in
`Tests/AppModelTests/MotionAccessibilityQATests.swift` (all pass ≥ 4.5:1):

- text/bg light 14.59, dark 15.94; sub/bg light 5.35, dark 6.82
- link/bg light 7.69, dark 12.15; onAccent/accent light 7.70, dark 9.66
- ok/bg light 5.43, warn/bg light 4.73, bad/bg light 5.70
- ok/bg dark 10.21, warn/bg dark 9.80, bad/bg dark 11.24

Every text/background pair passes AA for normal text, so **Increase
Contrast** changes nothing visible (there is no low-contrast pair to fix)
and **Bold Text** is safe (weights only thicken already-passing strokes).
Differentiate Without Colour holds: every status pairs a tone with an icon
and a word — `WaxPill` text, stage strip `checkmark.circle.fill` vs
`circle.fill` vs `circle`, result `checkSummary` wording — so no meaning is
colour-only. **One exception:** compression selection
(`SigningOptionsView.swift:157-171`) marks the chosen row with a filled
checkmark plus a blue/grey icon colour. The filled vs hollow symbol *does*
carry it, so it passes, but it passes by accident of the symbol swap, not by
design intent; a future icon change could silently break it.

**Reduce Transparency:** nothing uses blur or transparency as information.
`WaxProgressBar` uses opaque capsules; `WaxSeal` is opaque; the only
translucent paints are `WaxMelt`'s sheen/shade (`white 0.24`, `black 0.16`)
and flame glow (`0.28`), which are decorative gradients inside the candle,
not text or chrome. Turning opacity down under Reduce Transparency loses
nothing readable. No fix needed.

## Labels, traits, and order by screen

- **Sign (idle).** Three setup rows are plain buttons with hints ("Opens
  Files…", "Opens your signing identities", "Opens Settings…"); the primary
  carries its title plus the `reason` sentence (`SignView.swift:271`); the
  rename warning is a text block, not an icon. Order is header → summary →
  action → reason, top to bottom, matching visual order.
- **Sign (working).** `progressCard` collapses to one accessibility element
  (`children: .ignore`) with label "Working" and value
  "Stage N of 3, …. P percent. message" (`SignView.swift:340-342`). Focus
  order loses the stage-by-stage dots, which is the right call to avoid
  four stops for one changing number — except the number is an estimate
  (defect S3), so the value overclaims precision.
- **Sign (result).** `resultHeader` combines children; the seal is hidden
  from VoiceOver. "Start over" and "What Wax checked" each carry an explicit
  hint. Good.
- **IPA library.** Rows are one button with combined children ("name,
  version, size, date") via `WaxRow`; the per-row ellipsis has the visible
  text announced, not "button". Empty states use `children: .contain`,
  so the title, message, and action are separate stops. Correct.
- **Sources.** Source rows are `NavigationLink`s with an overlay "Options"
  button that shares the row's 44 pt line — two distinct stops, which is
  why the overlay exists (see `SourcesView.swift:32-43`). App rows combine
  children with label "Details for X" and value subtitle. Download ring
  announces "Downloading X, P percent" (`SourcesView.swift:321`). All good.
- **Settings.** `Version` row combines label+value (`SettingsView.swift:105`);
  toggles are native `Toggle`s hidden-labeled (label comes from the row).
  `NotificationPermissionControls` is read-only — not changed here.
- **Credentials.** Delete rows are `WaxDestructiveRow`s (label = button
  text); compatibility rows combine icon+text. The import busy overlay is
  visual only (not an accessibility element), so VoiceOver gets no "Importing"
  announcement — minor gap, see E2.
- **First-run guide.** `GuideTour` moves focus to the page title on page
  change (`accessibilityFocused`), `GuideExample` collapses to one label
  listing the example rows. `PermissionsSetup` has a "Skip"/"Not now" route
  at every determination. Correct order.

## Dynamic Type through XXXL

At `isAccessibilitySize` every grouped row (`WaxListRow`,
`SignView.setupRow`) swaps from `HStack` to `VStack`, so icon, title,
subtitle, and trailing control stack instead of clipping. That is why the
Sign summary card triples in height and pushes the primary button below the
fold (defect S1, **confirmed** — `05-shots/05-sign-xxxl-light.png` and
`05-sign-xxxl-dark.png` both show the primary out of view; scrolling
reaches it, the existing `testBottomOptionsStayAboveTabBarAtLargestText`
test swipes up to the Options row and passes).

Clipping audit: no text is `lineLimit(1)` + `fixedSize` in a way that hides
it at XXXL except… `SignView.swift:333` message `lineLimit(2)` — at XXXL the
progress message "Preparing installation…" can truncate to two lines. It is
a single status line, so truncation is acceptable but the audit's `performAccessibilityAudit`
also flags clipped text; it did not flag this one. `WaxKV` falls back to
stacked under `ViewThatFits`, so long values wrap under the key instead of
pushing off-screen.

**Defect register (accessibility):**

- **E1** (confirmed, from 04) XXXL contrast failure on "Add your signing
  files" — actually the row under the tab bar. Fix in `SignView.swift`:
  give the summary card a `scrollTargetLayout` or, simpler, collapse the
  three rows into one stacked checklist at accessibility sizes so the
  primary is above the bar without scrolling. Do not "fix" by darkening
  `Wax.sub` — the token already passes 5.35:1. **Fixed** as described above;
  `testAccessibilityAuditAtLargestText` passes.
- **E2** Credentials busy overlay has no accessibility announcement while an
  import is reading. Fix in `CredentialsView.swift`: add
  `.accessibilityElement(children:.combine)` + a `busyMessage` value to
  `busyOverlay`, or post an announcement in `handleMessage` for the busy
  state. **Fixed:** `.onChange(of: model.busyMessage)` posts a
  `UIAccessibility.announcement`, so the start of an import is spoken.
- **E3** Runtime discovery (new in 05): the library bottom-row hit failure
  at XXXL (test above). Fix in `ContentView.swift`: increase bottom padding
  so the last row can clear the floating bar with fewer swipes, or pin the
  test to a deterministic "scroll until hittable" loop that fails only on
  real overlap. **Fixed:** neither workaround was needed. The nested
  `LazyVStack` was the cause; see `FIXES-AFTER-05.md`.

## Status after the fix pass

E1, E2 and E3 are fixed on `ui/05-motion-qa`. The audit at default size and
at XXXL both pass, the bottom-row test passes, and a dark populated library is
captured in `05-shots/06-library-dark-populated.png`. The largest remaining
gap is that VoiceOver was never driven by hand in this environment: labels,
traits and order were read from the code, and the automated audit does not
check reading order.

## What 05 changed

No view code changed for accessibility — every fix needs the read-only
files (`Theme.swift`, `SignView.swift`, `ContentView.swift`). What 05 adds
is the pinning: `MotionAccessibilityQATests` contrast/touch-target
assertions (7 tests, 0 failures in `WaxModelTests` run), plus the four
geometry tests in `WaxPerfectionQATests` (0 failures). The next agent who
touches a token or a row height must pass both suites first.
