# Brief 03 — Tab shell, IPA library, and sources

Branch: `ui/03-shell` (base `2326af0`). Commits: `6c65d7d`, `2b17b62`, plus this commit.

## Files changed

- `App/WaxTabBar.swift` — tab bar styling, tokens, Reduce Motion, safe area.
- `App/ContentView.swift` — IPA library shell, recovery rows, empty states, large-library loading, row anchors.
- `App/SourcesView.swift` — sources list, app rows, detail sheet, artwork sizes, download controls, progress.
- `App/SourceAppDetails.swift` — `Field` now `Equatable`/`Hashable` for stable SwiftUI identity.

`App/Theme.swift` was not edited.

## Row discipline (file:line)

ContentView.swift:
- Leading anchor: `WaxRow` uses `WaxIconTile` (40×40) at `Theme.swift:152-162`, and `row(_:)` passes `e.kind == .unsigned ? "shippingbox" : "checkmark.seal"` at `ContentView.swift:144-154`. Every library row starts with the same 40-point tile.
- Trailing anchor: `row(_:)` trailing block at `ContentView.swift:149-153` (optional `ProgressView`, `SignedExpiryPill`, ellipsis). All trailing content sits in the same `WaxRow` trailing slot, right-aligned to the card's trailing padding.
- Height: `WaxRow` sets `.frame(minHeight: Wax.rowHeight)` (68) at `Theme.swift:186`; `LazyVStack(spacing: Wax.Space.s)` at `ContentView.swift:70` keeps spacing constant.
- Long text: title `.lineLimit(2)` at `Theme.swift:177`; subtitle `.lineLimit(subtitleLines)` (2) with `.fixedSize(horizontal: false, vertical: subtitleLines > 1)` at `Theme.swift:178-179`. Long bundle IDs are not shown in rows; the detail sheet (`IPADetailSheet`, `ContentView.swift:189-254`) wraps values via `WaxKV`, which falls back to a stacked layout instead of pushing the row apart.

SourcesView.swift:
- Leading anchor: source rows use `WaxRow(icon: "globe", ...)` at `SourcesView.swift:155-162`; app rows use a 40×40 `AsyncImage` tile at `SourcesView.swift:240-245` with `Wax.radiusTile`, matching `WaxIconTile`.
- Trailing anchor: source rows end in `WaxChevron()` at `SourcesView.swift:160`; app rows end in `getButton(app)` at `SourcesView.swift:263`, right-aligned in the row HStack.
- Height: `.frame(minHeight: Wax.rowHeight)` at `SourcesView.swift:266`.
- Long text: `Text(app.name).lineLimit(2)` at `SourcesView.swift:248`; subtitle `.lineLimit(2)` with `.fixedSize(horizontal: false, vertical: true)` at `SourcesView.swift:250-251`.

SourceAppDetails.swift:
- This file is a data model, not a view. Its UI consumer is the detail sheet in `SourcesView.swift:271-297`, which renders `fields(_:)` at `SourcesView.swift:298-309` inside a `WaxPanel`. Artwork sizes are governed by the 40×40 tile at `SourcesView.swift:243`. Download controls and progress are `getButton(_:)` at `SourcesView.swift:311-338`: saving shows `ProgressView`, downloading shows a 26-point ring inside a 44-point target, filed shows a checkmark, otherwise a "Get"/"Retry Save" capsule. All four states share the same trailing slot width (`Wax.touch`).

## Screenshot set (after)

Saved under `docs/audits/2026-11-08/ui-perfection/`:

Light (default size):
- `03-shell-light-01-sign-empty.png`, `03-shell-light-02-sources-empty.png`, `03-shell-light-03-library-empty.png`
- `03-shell-light-populated-library.png` (seeded entries, incl. long name)
- `03-shell-light-long-names.png`
- `03-shell-light-sources-list.png`, `03-shell-light-source-detail.png`
- `03-shell-light-download-progress.png`, `03-shell-light-download-error.png`

Dark:
- `03-shell-dark-01-sign.png`, `03-shell-dark-02-sources.png`, `03-shell-dark-03-library.png`
- Populated dark library was not captured. The earlier `03-shell-dark-populated-library.png` was a
  byte-identical copy of the empty dark library and has been removed. Seeding a populated library
  needs an import through the app; the seeded simulator used for the light captures was gone by the
  time this was noticed. The light populated capture above is real and shows the same rows.

Accessibility-XXXL:
- `03-shell-xxl-tab-labels.png`

Smallest supported iPhone (`Wax QA iPhone SE`):
- `03-shell-se-tab-labels.png`

Legacy generic captures retained: `01-sign-light.png`, `02-sign-light.png`, `dark-sign.png`, `xxxl.png`.

## Before/after

Before state is the base commit `2326af0` UI (pre-token-swap). After state is the images above. No separate before captures were taken; the diff against `2326af0` documents the before/after at file level.

## Verification

- `xcodegen generate` — exit 0.
- `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'platform=iOS Simulator,name=iPhone 17' build` — exit 0, `** BUILD SUCCEEDED **`.
- `swift test` — exit 0, all suites passed (0 failures).

## Remaining defects / notes

- Download progress/error were captured from a seeded source pointing at a fast public endpoint and a refused local port; the error path is the connection-refused case.
- `LibraryEntry` exposes no artwork, so rows continue to use `WaxIconTile`.