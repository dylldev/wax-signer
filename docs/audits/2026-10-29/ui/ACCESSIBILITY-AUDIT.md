# Wax accessibility audit

Review date: 2026-10-29. This records baseline findings and applied source changes for A1, A2 and A3. The coordinating agent owns runtime checks; changed-build small-screen accessibility-size results remain pending. This reviewer did not run VoiceOver, build the app, operate a simulator or phone, or measure rendered accessibility frames.

## Finding register

| ID | Status and priority | Evidence | Effect and acceptance |
|---|---|---|---|
| A1 | Confirmed source behavior; medium | `App/Theme.swift:182-183`, `App/WaxTabBar.swift:111-112` | Press scaling and springs ignore Reduce Motion. After a fix, press/release primary actions and tabs with the setting on: no scale or spring. With it off, preserve existing feedback. |
| A2 | Confirmed source behavior; medium | `App/WaxTabBar.swift:80-82` | Accessibility sizes remove visible tab names. Keep all four visible names readable at the largest size and narrow supported width. VoiceOver names exist at line 95; this is not a proven missing spoken-label defect. |
| A3 | Confirmed constraint; clipping risk; medium | `App/Theme.swift:161-164`; callers `App/IdentityReadiness.swift:47-49`, `App/SignView.swift:208` | Scalable footnote text sits inside height 26. Test all status labels at the largest size; text must fit its capsule and avoid neighboring content. Proposed fix: minimum height 26. |
| A4 | Confirmed constraints; content-loss risk; medium | `App/Theme.swift:350-364`, `App/ContentView.swift:96`, `App/SourcesView.swift:67` | Action sheets cannot scroll and offer one fixed-height detent. Title/subtitle each limit to one line. Test long names and every action at the largest size and in landscape. Proposed follow-up: wrapping, scrolling and a large detent. |
| A5 | Missing explicit target sizing; runtime risk; medium | `App/SigningOptionsView.swift:283-286,375`; text actions at 205-208 and 260-262 | Parent row height does not establish the nested button's target. Inspect actual frames and edge taps; require distinct targets at least 44 by 44 points. Preserve contextual removal labels. |
| A6 | Confirmed missing source trait; enhancement | `App/Theme.swift:237,253`; existing tutorial pattern `App/FirstRunGuide.swift:172` | Shared custom headings omit a heading trait. Add it to screen titles; decide separately which section labels belong in the rotor. Verify each screen title appears once in the Headings rotor. |
| A7 | Confirmed source behavior; low | `App/Theme.swift:211,214-215` | Determinate progress animates width without the preference guard used for indeterminate progress. Decide whether immediate updates should replace interpolation with Reduce Motion on. Keep spoken percentages accurate. |

A4's custom action button changes destructive color but omits the destructive Button role (`App/Theme.swift:360`). Verify the spoken action and interaction behavior before deciding whether to change the role. Neither source color nor a role by itself proves the final announcement.

## Existing support

- Tabs provide explicit labels and selected traits, and a 52-point minimum height (`App/WaxTabBar.swift:85,95-96`).
- Inactive tab content hides from accessibility (`App/LocalIPASignerApp.swift:145`).
- WaxMelt pauses time-driven effects under Reduce Motion and supplies a clamped spoken percentage (`App/WaxMelt.swift:9-23`). The signing progress card exposes stage, percentage and full message as one element (`App/SignView.swift:433-435`).
- Shared key/value rows combine their content (`App/Theme.swift:306`). Decorative seals, tiles and chevrons hide from accessibility (`App/Theme.swift:88,118,468,498`).
- The tutorial marks and focuses page headings (`App/FirstRunGuide.swift:172-173`). Sources posts model-message announcements (`App/SourcesView.swift:57`).
- Shared primary/secondary/destructive actions use 54- or 44-point minimum heights (`App/Theme.swift:178,193,324`). These heights do not prove every control reaches 44 points in both dimensions.

## Contrast

See [DESIGN-SYSTEM-AUDIT.md](DESIGN-SYSTEM-AUDIT.md) for calculations and limits. Opaque page/card/status text pairs exceed 4.5:1. Light secondary/page contrast is 4.524410:1. No screenshot, color-filter or increased-contrast certification follows from token calculations.

## Required manual checks

Use a normal-user build. On narrow and standard supported screens, exercise ordinary, XXXL and all five accessibility sizes in light/dark appearances. Read navigation labels, card titles, pills, sheets, progress messages and errors. Check keyboard visibility and scrolling on editable forms.

With VoiceOver, verify order, labels, selected states, headings, sheet dismissal focus, feedback actions and job progress announcements. A combined source element can still expose an unexpected runtime tree; inspect it. Check action target frames and edge taps. Enable Reduce Motion before launch, then toggle it while the app remains active. Test increased contrast and Differentiate Without Color separately. The color constructor branches on appearance only (`App/Theme.swift:65`).

## Implementation evidence boundary

A dedicated source policy check at `Tests/SourceChecks/test_visual_accessibility.py` covers A1, A2 and A3. Baseline: four failures, exit 1. Initial edited state: four passes, exit 0. Reverting the two owned files: four failures, exit 1. Both files returned to baseline for UI capture, then the edits returned after capture. Final source run: four passes, exit 0. The coordinating agent reported an actual baseline XCTest failure for the visible Sources tab title on a small-screen accessibility size. Changed-build UI verification remains pending. These checks inspect source and cannot prove rendered layout, actual motion, VoiceOver output or touch frames.

## A8: Notifications row squeezes its title beside its action

**Runtime-confirmed baseline defect; medium priority; source fix applied, rendered retest pending.** The coordinating agent inspected `before-small-ax/299FF745-BABD-4605-9C3B-6601F6EA06A1.png`: the Settings Notifications title wrapped into four broken lines beside an enlarged Turn on action. `WaxListRow` used one HStack for icon, text and trailing controls (`App/Theme.swift:462` in the baseline). The action and title competed for a narrow width.

The shared row now reads Dynamic Type and follows the existing setupRow AnyLayout pattern. Accessibility sizes use a leading VStack; ordinary sizes keep the existing HStack. The text block and trailing control occupy separate vertical positions. Labels, actions, roles and colors remain unchanged. This fix covers the confirmed grouped-row pattern; WaxRow remains outside this change.

The new grouped-row source check failed before the change, passed after it, failed after reverting only this change, and passed after restoration. Final source run: five tests passed, exit 0. `git diff --check` passed. These checks establish the layout-selection policy. Acceptance still requires a changed-build screenshot showing the full Notifications title and reachable Turn on action at the same small-screen accessibility size, plus standard-size regression coverage. This reviewer has not inspected that screenshot or run VoiceOver.

## Final integration status, 2026-10-30

See IMPLEMENTATION-REPORT.md for the final checkout, test counts and screenshot comparisons. The targeted source fixes are applied. Small-screen AX5 navigation and large dark journeys pass. The automated Dynamic Type audit remains failing; manual VoiceOver and active-job Instruments profiling remain unverified. The free-only three-model panel is incomplete (0/3); no paid fallback. This status supersedes earlier in-progress notes.
