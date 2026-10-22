# IPA library, Settings tab, calmer Sign screen (design, approved in chat 2026-10-17)

## Goal
Less on each screen. Wax keeps its own IPAs, split into Unsigned and Signed. A Settings tab holds everything that is
configured once. The Sign screen is one decision and, while working, one animation.

## Pieces
1. **IPALibrary** (`Sources/InstallKit/IPALibrary.swift`, pure Swift, tested). Folder `Application Support/Library/` with
   `unsigned/`, `signed/` and `index.json`. Entry: id, kind, name, version, bundle ID, size, added date, file name.
   Adding the same bundle ID + version + size again replaces the older entry. Operations: add (copy in), entries(kind),
   url(for:), remove, clear(kind), totalBytes.
2. **IPA tab.** Segmented Unsigned / Signed. Rows: name, version, size, age. Add button picks from Files into Unsigned.
   Row actions: Unsigned: Sign, Details, Delete. Signed: Export, Details, Delete. Empty states say what goes here.
3. **Sign tab.** Picking an app, or signing, feeds the library: picked unsigned IPA goes to Unsigned (signed IPA to
   Signed); a finished signing result goes to Signed. One summary card holds app + identity. One primary button.
   Bundle ID mode, signing options, import log and the install server move behind "Options" (a sheet) and Settings.
   While working the whole screen is the wax animation, a percent and one status line. Done: seal, Install, Export,
   Start over, Details (what Wax checked) in a sheet.
4. **Settings tab.** Install server, signing options and saved defaults, bundle ID mode, notifications, storage (library
   size, clear signed / unsigned), import log, about (version, build).
5. **Tab bar** gets a fourth button (gear-like glyph). Signing model moves to the app so tabs can share it.
6. **Wax animation.** Candle melts into a pool with drips, the flame shrinks with progress, the pool rises into the
   seal at 100% (stamp already exists). Reduce Motion: static fill.

## Not doing
No iCloud sync of the library, no sharing between Wax copies, no re-signing of signed IPAs from the library beyond
the existing "signed input" install path.

## Checks
Library: unit tests (add/list/replace/remove/clear/size, survives reload, ignores missing files). UI: simulator
screenshots (light/dark), then the phone.
