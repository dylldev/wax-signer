# Wax workflow audit

Read-only inspection on 2026-10-29. No build, simulator, phone, network request, signing operation, or secret read. Findings below establish source behavior. Reproduction steps describe scenarios to exercise during later UI testing; they are not claims of runtime reproduction. Paths and line references refer to this checkout.

## Coverage and strengths

The app has four persistent tabs: Sources, IPA, Sign, Settings (`App/LocalIPASignerApp.swift:93-105`). Sources contains its add form, source actions, searchable app list, and app details. IPA contains Unsigned/Signed shelves, import, retained-file recovery, per-app actions, and metadata details. Sign contains input/identity/host setup, preparation report, progress, outcome, options sheet, and nested signing options. Credentials lives inside Settings and includes import, password retry, compatibility rows, and deletion confirmations. Install status and cancellation live inside Settings' InstallSection. First-run guide and shake report are app-wide presentations. Developer identity testing and advanced plist/entitlement editing sit behind WAX_DEVELOPMENT.

Existing strengths worth preserving:

- Source details distinguish source claims from a previous committed download, display differences, and allow selecting field text (`App/SourcesView.swift:271-305`).
- Source saving separates download progress from shelf saving and offers Retry Save (`App/SourcesView.swift:311-336`).
- Import awaits a real library commit; retained artifacts have retry/export paths (`App/ContentView.swift:44-60,150-165`).
- Library index repair explains retention and unknown provenance before proceeding (`App/ContentView.swift:82-84`).
- Sign preparation stops for an Installability Passport review. The user sees blocked, warning, pass, and unknown states (`App/SignView.swift:314-368`; `App/SigningModel.swift:438-480`).
- Result copy limits checks to Wax's own verifier and says iOS decides installation (`App/SignView.swift:519-521,601-609`).
- Credentials support password retry without reselecting the file, clear typed passwords, and confirm private-key deletion (`App/CredentialsView.swift:41-44,100-105,132-155`).
- Saved installation copies the selected artifact and checks metadata before upload (`App/SigningModel.swift:242-279`). Preserve those checks.

## Conditional journey counts

These counts describe explicit user actions in source, excluding scrolling, typing characters, iOS file-provider navigation, password entry, or iOS installation confirmation. They are not measured completion times.

| Journey | Conditions | App actions |
|---|---|---|
| Import IPA to Unsigned | Start on IPA/Unsigned; Files supplies one valid file | Tap Add, choose file: 2; wait for commit |
| Open imported app on Sign | IPA already exists on Unsigned | Tap row, tap Sign: 2 |
| Sign and export | IPA and valid identity selected | Tap Sign only and export, review preparation, tap Continue signing and export, tap Export: 4 before share-sheet choice |
| Sign and install | IPA, identity and host configured | Tap Install, review preparation, tap Continue to install: 2; then respond to iOS prompt |
| Install retained signed app | Start on IPA/Signed; host configured | Tap row, tap Install: 2; then respond to iOS prompt |
| Add source and download | Start on Sources; valid HTTPS source URL entered | Tap Add, open source, tap Get: 3; optional details adds one action |
| Import certificate | Start on Credentials; provider supplies valid file | Tap Import, choose file, enter password if requested and tap Import: 2 or 3 app actions |
| Import provisioning profile | Start on Credentials; valid file | Tap Import profile, choose file: 2 |

Additional actions depend on credentials, host setup, expired links, source authentication, blocked preparation findings, and storage recovery. A configured host does not establish reachability. A handed-off install does not establish that iOS accepted or launched the app.

## Baseline and pending changes

The parent audit captured eight standard simulator screens. A failing harness assertion required correction; it did not establish an app defect. This document primarily records source findings, and does not claim runtime reproduction of the scenarios below. After baseline capture, the audit added shelf-save feedback and named IPA deletion confirmation. Source regression checks pass after red-green-revert-red-restore-green verification. Runtime dialog, layout, and storage-retry verification remain separate checks in the parent audit.

## Ranked findings and opportunities

### 1. High, confirmed baseline; fixed in source: successful-signing screen claims a shelf save that may have failed

Evidence: `App/SigningModel.swift:101-122` publishes `report` before commit and records `.failed` without setting signing error. `App/SignView.swift:470-495,524-539` renders the Signed-shelf link for every report without check failures. SignView never reads `shelfSaveState` or calls `retrySignedSave`.

Scenario: finish signing, then fail the pending library commit. The screen still says “Saved in the IPA tab, under Signed.”

Acceptance: show Saving, Saved, or Save failed from the existing state; expose Retry Save and retained export on failure. Keep export available and do not announce committed storage before acknowledgement.

### 2. High, confirmed baseline; fixed in source: one tap deletes an IPA without confirmation or undo

Evidence: `App/ContentView.swift:112-123`; `App/Theme.swift:356-360`; `Sources/InstallKit/IPALibrary.swift:265-271`. Destructive styling only changes color; the action closes the sheet and runs removal.

Scenario: open app actions and accidentally tap Delete. Acceptance: confirm the named file and explain that deletion removes Wax's copy, or provide a working undo retention period. Do not imply uninstalling the installed app.

### 3. Medium, confirmed: direct IPA downloads have no visible job row

Evidence: `App/SourcesModel.swift:75-80,127-141`; `App/SourcesView.swift:23-46,137-142`. A pasted IPA starts `get` with no source ID; only SourceAppsView calls the progress UI.

Scenario: paste a large direct IPA URL and tap Add. The field clears, but no app row exists to show progress or Retry Save. Acceptance: show a direct-download card with filename, phase, retry/export as applicable, and committed shelf destination.

### 4. Medium, confirmed: source addition clears the address before success and offers no pending state

Evidence: `App/SourcesView.swift:105-118,137-142`; `App/SourcesModel.swift:82-88`.

Scenario: submit a valid HTTPS address whose source parse or network load fails. The address disappears before the asynchronous operation finishes. Acceptance: retain the failed address, show loading for the attempted source, and let the user retry or edit it.

### 5. Medium, confirmed: cancellation sits away from the active installation

Evidence: `App/SignView.swift:414-436,470-495` has no cancel action; `App/InstallSection.swift:124-126` exposes cancellation only in Settings. The model already supports `App/SigningModel.swift:332`.

Scenario: start an installation from Sign or a Signed shelf row, then want to stop it. Acceptance: provide cancel beside the owning job, explain that signed/saved files remain, and show the resulting state there.

### 6. Medium, confirmed: downloads have no user cancellation control

Evidence: `App/SourcesView.swift:311-336` replaces Get with noninteractive progress; `App/SourcesModel.swift:127-197` returns a task but the view does not retain it. Only background expiration cancels it.

Scenario: start the wrong large app. Acceptance: expose a per-download cancel action and distinguish canceled partial transfer from retained complete bytes. Keep completed files available for retry.

### 7. Medium, confirmed: “Ready” means configuration, not a checked connection

Evidence: `App/SignView.swift:204-208` gives configured hosts a green Ready pill. The same screen's passport says configuration does not prove reachability (`:314-324`). `App/OTAInstallModel.swift:146-153` evaluates configuration.

Scenario: use valid-looking host settings while the server is offline. Acceptance: label the row “Configured” unless a dated, relevant host check supports a stronger claim. Preserve the iOS acceptance caveat.

### 8. Medium, confirmed: every signing/install error offers “Choose another file”

Evidence: `App/SignView.swift:52-55,145-147,556-560` merges model and OTA errors into one card with the same file-picker recovery.

Scenario: fail a host upload, certificate lookup, or file read. Acceptance: map recovery to the failed step: host settings/retry upload, credentials, retry save, or choose file. Keep the original app and valid signed output.

### 9. Medium, confirmed: visual source checkmark hides its “download again” action

Evidence: `App/SourcesView.swift:322-327`. The green checkmark is a button that downloads again. Only accessibility text describes prior download and retry semantics.

Scenario: sighted user taps the apparent saved-status indicator expecting open/details. Acceptance: pair saved status with an explicit Open IPA or Download again action; distinguish prior bytes from current remote contents.

### 10. Medium, confirmed: app and download errors share one global source message

Evidence: `App/SourcesModel.swift:70,98,118,132,188-193`; `App/SourcesView.swift:193,287`. A second job resets `message`; errors appear on unrelated app detail sheets.

Scenario: run two downloads, fail one, then start the other or open another app's details. Acceptance: keep errors and retries attached to the relevant source/app/job; reserve the top banner for list-wide problems.

### 11. Medium, confirmed: credentials become hard to distinguish when organization and kind match

Evidence: `App/CredentialsView.swift:189-191` truncates identity and team to one line. `App/SignView.swift:248-250` builds identity choices from organization/common name and kind only. Certificate fingerprint appears only in developer builds (`App/CredentialsView.swift:204-208`).

Scenario: import renewed certificates from the same team. Acceptance: show a useful distinguishing expiry/team suffix in the picker and a selectable full identifier in ordinary credential details, without exposing private material.

### 12. Medium, confirmed: profile deletion and certificate deletion confirmations omit the item name

Evidence: `App/CredentialsView.swift:141-155` uses generic prompts. Acceptance: include the selected certificate/profile name and explain that future signing may require reimport. Test long and duplicate names.

### 13. Low, confirmed: library has no search or sort controls

Evidence: `App/ContentView.swift:23-79` renders all entries in a ScrollView/VStack; no searchable or sort control exists. Sources has search (`App/SourcesView.swift:205`).

Scenario: keep many versions across Unsigned/Signed. Acceptance: search by app name and bundle ID, with clear empty results; consider newest-first ordering if the storage order does not already provide it. This is a scale/usability opportunity, not a broken small library.

### 14. Low, confirmed: source refresh errors lack source attribution in the combined banner

Evidence: `App/SourcesModel.swift:109-118` joins error descriptions without adding the source name. Acceptance: prefix each error with the affected source and put Retry on its row. Keep cached apps and their freshness visible.

### 15. Low, confirmed: unsigned empty-state text confuses imported input with signed output

Evidence: `App/ContentView.swift:138-146` says “Add an IPA from Files, or sign one from the Sign tab. It lands here.” on Unsigned. Signed results belong in Signed. Acceptance: explain that choosing an input on Sign can retain its original under Unsigned while the signed output goes under Signed; make Add an IPA the direct empty-state action.

### 16. Low, source-grounded risk: fixed action-sheet heights may clip large text

Evidence: `App/ContentView.swift:94-98` and `App/SourcesView.swift:63-69` compute fixed heights from action count. `App/Theme.swift:349-365` uses a non-scrolling VStack with one-line title. Runtime clipping remains untested.

Scenario: largest accessibility text, long app/source name, Signed actions. Acceptance: allow scrolling or content-driven/large detents; keep Delete, Export, and dismissal reachable; allow full-name inspection.

### 17. Low, source-grounded risk: signing option field layout compresses long values

Evidence: `App/SigningOptionsView.swift:168-179` fixes label width to 96 and places the text field beside it. Injected filenames have one line (`:275-284`). Acceptance: test largest text and long IDs/filenames; stack label/value at accessibility sizes and provide a full selected filename view. Current rendered behavior remains unverified.

### 18. Low, subjective copy improvement: option descriptions promise runtime effects

Evidence: `App/SigningOptionsView.swift:77-85` says high frame rate lets the app run at full refresh and removing device limits lets another-device app run on this iPhone. These controls edit app settings and cannot guarantee app/runtime compatibility. Acceptance: describe the setting change and qualify app/device support, preserving concrete user benefit.

### 19. Low, subjective scope clarification: explain session switches versus saved defaults

Evidence: `App/SigningModel.swift:354-359` resets per-app edits through defaultsOnly when choosing another IPA. `Sources/SigningKit/AppEditor.swift:66-71` preserves current switches, while `App/SigningModel.swift:43-46` writes saved defaults only on explicit save. Current names, versions, IDs, icons and injected libraries do not persist across app selection. The page correctly groups switches under “Changes to every app.”

Acceptance: explain that those switches affect subsequent selections in the current session, while Save as defaults keeps them for later launches. Treat this as optional copy polish, not an established persistence bug.

## Limits and next validation

No visual clipping, phone installation, VoiceOver focus, actual error recovery, network cancellation, or storage-failure reproduction ran. Exercise items 1-8 first using controlled fixtures and existing failure-injection support. Do not weaken certificate/profile validation, library commit checks, artifact provenance, install-session ownership, or iOS acceptance wording to simplify these flows.

## Final integration status, 2026-10-30

See IMPLEMENTATION-REPORT.md for the final checkout, test counts and screenshot comparisons. The targeted source fixes are applied. Small-screen AX5 navigation and large dark journeys pass. The automated Dynamic Type audit remains failing; manual VoiceOver and active-job Instruments profiling remain unverified. The free-only three-model panel is incomplete (0/3); no paid fallback. This status supersedes earlier in-progress notes.
