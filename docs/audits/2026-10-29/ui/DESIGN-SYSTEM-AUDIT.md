# Wax design-system audit

Source review date: 2026-10-29. This document records baseline findings and the applied source changes. Rendered verification of the changes remains pending.

## Shared design language

`App/Theme.swift:6-26` defines semantic light/dark colors. Screens share cream and oxblood surfaces, status colors, rounded cards and wax imagery. Shared constants establish 16-point page insets and card corners, a 44-point touch target and a 54-point primary action (`App/Theme.swift:28-45`). The tab bar uses four custom path icons (`App/WaxTabBar.swift:62-64`). These choices give the app a coherent visual identity without depending on repeated screen-specific colors.

The standard-spacing baseline screenshot, reviewed by the coordinating agent, shows clear row spacing and bottom navigation. I reviewed source rather than that rendered image. Small-screen accessibility-size runtime checks remain pending.

## Component strengths

- `WaxHeader` grows beyond its minimum height (`App/Theme.swift:241`).
- `WaxKV` falls back from horizontal to stacked content (`App/Theme.swift:294-314`).
- `WaxListRow` gives grouped settings consistent icon and text columns (`App/Theme.swift:460-480`).
- Primary, secondary and destructive actions use minimum heights (`App/Theme.swift:178,193,324`).
- `WaxMelt` connects wax imagery to real job progress and pauses its timeline for inactive scenes, completion and Reduce Motion (`App/WaxMelt.swift:9-17`).

## Inconsistencies and proposals

| Baseline evidence | Implication | Proposed scope |
|---|---|---|
| `App/Theme.swift:182-183`, `App/WaxTabBar.swift:111-112` apply unconditional press scaling/animation | Press feedback ignores the motion preference even though selection motion honors it | Read Reduce Motion in both button styles; retain size 1 and omit animation when enabled |
| `App/Theme.swift:163` fixes status pills at height 26 | Scalable text can exceed the capsule height | Change to minimum height 26 |
| `App/WaxTabBar.swift:80-82` hides names at accessibility sizes | Users who enlarge visible text must identify custom icons without labels | Keep labels visible, permit wrapping and let the bar grow |
| `App/Theme.swift:350-364` uses a non-scrolling action stack; callers offer fixed sheet heights | Large text may exceed the sheet's height | Separate follow-up: scrolling and a large detent |

The first three changes now appear in Theme.swift and WaxTabBar.swift. Four source policy checks pass after restore. The action-sheet proposal remains a separate follow-up.

## Token contrast calculations

I calculated opaque sRGB token pairs from `App/Theme.swift:6-22` with Python. For channel c in [0,1], linearize with c/12.92 when c <= 0.04045, otherwise ((c + 0.055)/1.055)^2.4. Luminance is 0.2126R + 0.7152G + 0.0722B. Contrast is (lighter + 0.05)/(darker + 0.05). Values round to six decimals.

| Foreground/background | Light | Dark |
|---|---:|---:|
| text/bg | 14.588225:1 | 15.941368:1 |
| text/card | 16.313426:1 | 14.721666:1 |
| sub/bg | 4.524410:1 | 6.818655:1 |
| sub/card | 5.059466:1 | 6.296948:1 |
| link/bg | 7.689954:1 | 12.152852:1 |
| link/card | 8.599366:1 | 11.223016:1 |
| onAccent/accent | 7.697603:1 | 9.658067:1 |
| onAccent/accentPressed | 9.943120:1 | 7.874049:1 |
| ok/okBg | 5.261052:1 | 7.697877:1 |
| warn/warnBg | 4.629101:1 | 7.473320:1 |
| bad/badBg | 5.452916:1 | 9.172416:1 |
| sub/chip | 4.116350:1 | 5.459725:1 |
| line/card | 1.329328:1 | 1.228689:1 |
| line/bg | 1.188747:1 | 1.330487:1 |

The page/card/status text pairs exceed 4.5:1. Light secondary text on the page has a narrow margin. The hypothetical light sub/chip pair falls below 4.5:1, but I did not establish an enabled small-text use of that pair. Low border contrast alone does not establish a defect when the border decorates a spaced card rather than identifying a control. These calculations do not verify screenshots, opacity effects, increased contrast, color filters or disabled text.

## Validation boundary

Source policy tests cover the proposed changes and have demonstrated baseline failures and an initial edited pass. Final restore passed all four source checks, exit 0. The coordinating agent reported a baseline XCTest failure for the visible Sources title at a small-screen accessibility size. A changed-build UI result remains pending. I have not built the app, operated a simulator or phone, run VoiceOver, or measured rendered hit regions. The coordinating agent owns build and UI evidence. Source checks cannot establish legibility at large sizes or full accessibility compliance.

## Runtime follow-up: grouped-row layout

The coordinating agent confirmed a baseline Settings defect in `before-small-ax/299FF745-BABD-4605-9C3B-6601F6EA06A1.png`: Notifications wrapped into four broken lines beside the enlarged Turn on action. WaxListRow now uses the existing AnyLayout convention to stack icon, text and trailing controls at accessibility sizes, while preserving its ordinary HStack. This addresses the confirmed shared-row constraint without changing screen-specific actions. Five source policy checks pass after red-green and revert verification. Changed-build screenshots and manual accessibility checks remain pending.

## Final integration status, 2026-10-30

See IMPLEMENTATION-REPORT.md for the final checkout, test counts and screenshot comparisons. The targeted source fixes are applied. Small-screen AX5 navigation and large dark journeys pass. The automated Dynamic Type audit remains failing; manual VoiceOver and active-job Instruments profiling remain unverified. The free-only three-model panel is incomplete (0/3); no paid fallback. This status supersedes earlier in-progress notes.
