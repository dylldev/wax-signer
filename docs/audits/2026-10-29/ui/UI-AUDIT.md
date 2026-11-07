# Wax UI/UX audit

Date: 2026-10-29. Baseline: local commit518156f plus the existing uncommitted report/notification patch, copied into an isolated worktree. This is newer than public main. No phone app was changed for this audit. Prior phone checks are separate evidence and do not validate this branch.

## Assessment

Wax already looks like one product. Warm cream, burgundy, the wax seal and consistent grouped rows provide a recognizable identity. Standard-size Sign and Settings screenshots have balanced margins and readable hierarchy. Settings' last row and footer sit above the bottom bar in the captured standard layout. A new visual style would not solve the most important defects.

Prioritize truthful task status, safer deletion and accessibility before decorative polish. The recommended direction is **Refined Wax**; see DESIGN-DIRECTIONS.md. Scores are provisional expert assessment, not user-study results; see UI-SCORECARD.md.

## Evidence boundaries

- Source review covers the UI files listed below, model callers and persistence/status paths.
- Real XCTest captures are stored outside Git in the local audit evidence directory. The screenshot manifest records actual device and capture name. Images are never mockups.
- Initial standard navigation reached eight named screenshots. Its first run failed on a harness expectation: an empty report field returns an empty string, not its placeholder. That is not an app defect. The assertion was corrected.
- Small/large screen, appearance, Dynamic Type and automated accessibility results belong in IMPLEMENTATION-REPORT.md once the runs complete.
- Static source confirmation establishes an unconditional label or code path. It does not prove perceived lag, clipping, assistive-technology focus or phone installation.
- Private credentials and private IPA uploads are excluded. No release or merge is authorized by this report.

## Screen and state inventory

| Screen/component | Entry | Source | Coverage / main observation |
|---|---|---|---|
| Global tabs | Root | App/LocalIPASignerApp.swift; App/WaxTabBar.swift | Four persistent screens; selected traits, reselection and hidden accessibility; largest text removes visible tab names in baseline |
| Sources root/add | Sources | App/SourcesView.swift:9 | Empty capture; field and source actions reviewed; direct IPA job lacks a visible root card |
| Source actions | Source row | App/SourcesView.swift:55 | Reviewed fixed detents and destructive/refresh controls; no live source mutation |
| Source app list | Source row | App/SourcesView.swift:177 | Search and 300-result cap exist; lazy source rows already implemented |
| Source app details | App row | App/SourcesView.swift:260; App/SourceAppDetails.swift | Source claims separated from previously saved IPA metadata |
| Download/save state | Get | App/SourcesView.swift:311; App/SourcesModel.swift:127 | Download and save distinction exists; cancellation and local job errors need work |
| IPA shelves | IPA | App/ContentView.swift:29 | Populated synthetic standard shelf captured; no search/sort UI |
| IPA actions | Library row | App/ContentView.swift:90 | Export/re-sign/install/recovery retained; baseline Delete lacks confirmation |
| IPA details/expiry | Details | App/ContentView.swift:174 | Archive metadata and cached expiry reviewed; large-library cost unmeasured |
| Signing setup | Sign | App/SignView.swift:20 | Real empty capture; strong checklist and one primary action |
| Signing options | Options/Settings | App/SigningOptionsView.swift | Real compression capture; defaults, per-app edits and advanced disclosure reviewed |
| Signing preview | Prepare | App/SignView.swift:314 | Passport preserves blocked/warning/unknown states; credential-dependent runtime screen not forced |
| Signing progress | Sign operation | App/SignView.swift:414; App/WaxMelt.swift | Stage/progress source reviewed; hidden-tab animation eligibility confirmed, CPU effect unmeasured |
| Signing result | Job completion | App/SignView.swift:470 | Baseline success shelf link ignores save failure; retained export behavior already in model tests |
| Credentials | Settings | App/CredentialsView.swift | Import, password retry, expiration, identity/profile details and deletion reviewed; no real credential modifications |
| Host/install | Setup/Settings | App/InstallSection.swift; App/OTAInstallModel.swift | Local/server setup and session ownership reviewed; configuration is not verified reachability |
| Settings | Settings | App/SettingsView.swift | Top and bottom captured; maintenance, help, notifications and about grouped coherently |
| Permission setup | Fresh launch | App/FirstRunGuide.swift; App/NotificationPermissionModel.swift | Prior phone session verified native prompt separately; branch testing recorded in implementation report |
| Animated guide | Fresh/replay | App/FirstRunGuide.swift | Five pages, Skip, replay, Reduce Motion branch reviewed |
| Report preview | Settings/shake | App/BugReportView.swift; App/ShakeReporter.swift | Actual empty/keyboard captures; cancel clears draft; plain preview exposes Markdown markers (polish proposal) |

## Ranked finding register

Findings UX-F01 onward below preserve baseline code references. File lines move after fixes; use the referenced component/function and final diff to locate changed code. Additional accessibility and performance registers are in their dedicated reports.


### UX-F01. High, confirmed: successful-signing screen claims a shelf save that may have failed

Evidence: `App/SigningModel.swift:101-122` publishes `report` before commit and records `.failed` without setting signing error. `App/SignView.swift:470-495,524-539` renders the Signed-shelf link for every report without check failures. SignView never reads `shelfSaveState` or calls `retrySignedSave`.

Scenario: finish signing, then fail the pending library commit. The screen still says “Saved in the IPA tab, under Signed.”

Acceptance: show Saving, Saved, or Save failed from the existing state; expose Retry Save and retained export on failure. Keep export available and do not announce committed storage before acknowledgement.

Priority: **UX-P1**. Effort: Small (under one engineering day). Regression risk: Low: presentation-only; retain existing model action. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F02. High, confirmed: one tap deletes an IPA without confirmation or undo

Evidence: `App/ContentView.swift:112-123`; `App/Theme.swift:356-360`; `Sources/InstallKit/IPALibrary.swift:265-271`. Destructive styling only changes color; the action closes the sheet and runs removal.

Scenario: open app actions and accidentally tap Delete. Acceptance: confirm the named file and explain that deletion removes Wax's copy, or provide a working undo retention period. Do not imply uninstalling the installed app.

Priority: **UX-P1**. Effort: Small (under one engineering day). Regression risk: Low: presentation-only; retain existing model action. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F03. Medium, confirmed: direct IPA downloads have no visible job row

Evidence: `App/SourcesModel.swift:75-80,127-141`; `App/SourcesView.swift:23-46,137-142`. A pasted IPA starts `get` with no source ID; only SourceAppsView calls the progress UI.

Scenario: paste a large direct IPA URL and tap Add. The field clears, but no app row exists to show progress or Retry Save. Acceptance: show a direct-download card with filename, phase, retry/export as applicable, and committed shelf destination.

Priority: **UX-P1**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F04. Medium, confirmed: source addition clears the address before success and offers no pending state

Evidence: `App/SourcesView.swift:105-118,137-142`; `App/SourcesModel.swift:82-88`.

Scenario: submit a valid HTTPS address whose source parse or network load fails. The address disappears before the asynchronous operation finishes. Acceptance: retain the failed address, show loading for the attempted source, and let the user retry or edit it.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F05. Medium, confirmed: cancellation sits away from the active installation

Evidence: `App/SignView.swift:414-436,470-495` has no cancel action; `App/InstallSection.swift:124-126` exposes cancellation only in Settings. The model already supports `App/SigningModel.swift:332`.

Scenario: start an installation from Sign or a Signed shelf row, then want to stop it. Acceptance: provide cancel beside the owning job, explain that signed/saved files remain, and show the resulting state there.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F06. Medium, confirmed: downloads have no user cancellation control

Evidence: `App/SourcesView.swift:311-336` replaces Get with noninteractive progress; `App/SourcesModel.swift:127-197` returns a task but the view does not retain it. Only background expiration cancels it.

Scenario: start the wrong large app. Acceptance: expose a per-download cancel action and distinguish canceled partial transfer from retained complete bytes. Keep completed files available for retry.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F07. Medium, confirmed: “Ready” means configuration, not a checked connection

Evidence: `App/SignView.swift:204-208` gives configured hosts a green Ready pill. The same screen's passport says configuration does not prove reachability (`:314-324`). `App/OTAInstallModel.swift:146-153` evaluates configuration.

Scenario: use valid-looking host settings while the server is offline. Acceptance: label the row “Configured” unless a dated, relevant host check supports a stronger claim. Preserve the iOS acceptance caveat.

Priority: **UX-P2**. Effort: Small (under one engineering day). Regression risk: Low: presentation-only; retain existing model action. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F08. Medium, confirmed: every signing/install error offers “Choose another file”

Evidence: `App/SignView.swift:52-55,145-147,556-560` merges model and OTA errors into one card with the same file-picker recovery.

Scenario: fail a host upload, certificate lookup, or file read. Acceptance: map recovery to the failed step: host settings/retry upload, credentials, retry save, or choose file. Keep the original app and valid signed output.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F09. Medium, confirmed: visual source checkmark hides its “download again” action

Evidence: `App/SourcesView.swift:322-327`. The green checkmark is a button that downloads again. Only accessibility text describes prior download and retry semantics.

Scenario: sighted user taps the apparent saved-status indicator expecting open/details. Acceptance: pair saved status with an explicit Open IPA or Download again action; distinguish prior bytes from current remote contents.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F10. Medium, confirmed: app and download errors share one global source message

Evidence: `App/SourcesModel.swift:70,98,118,132,188-193`; `App/SourcesView.swift:193,287`. A second job resets `message`; errors appear on unrelated app detail sheets.

Scenario: run two downloads, fail one, then start the other or open another app's details. Acceptance: keep errors and retries attached to the relevant source/app/job; reserve the top banner for list-wide problems.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F11. Medium, confirmed: credentials become hard to distinguish when organization and kind match

Evidence: `App/CredentialsView.swift:189-191` truncates identity and team to one line. `App/SignView.swift:248-250` builds identity choices from organization/common name and kind only. Certificate fingerprint appears only in developer builds (`App/CredentialsView.swift:204-208`).

Scenario: import renewed certificates from the same team. Acceptance: show a useful distinguishing expiry/team suffix in the picker and a selectable full identifier in ordinary credential details, without exposing private material.

Priority: **UX-P2**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F12. Medium, confirmed: profile deletion and certificate deletion confirmations omit the item name

Evidence: `App/CredentialsView.swift:141-155` uses generic prompts. Acceptance: include the selected certificate/profile name and explain that future signing may require reimport. Test long and duplicate names.

Priority: **UX-P2**. Effort: Small (under one engineering day). Regression risk: Low: presentation-only; retain existing model action. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F13. Low, confirmed: library has no search or sort controls

Evidence: `App/ContentView.swift:23-79` renders all entries in a ScrollView/VStack; no searchable or sort control exists. Sources has search (`App/SourcesView.swift:205`).

Scenario: keep many versions across Unsigned/Signed. Acceptance: search by app name and bundle ID, with clear empty results; consider newest-first ordering if the storage order does not already provide it. This is a scale/usability opportunity, not a broken small library.

Priority: **UX-P3**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F14. Low, confirmed: source refresh errors lack source attribution in the combined banner

Evidence: `App/SourcesModel.swift:109-118` joins error descriptions without adding the source name. Acceptance: prefix each error with the affected source and put Retry on its row. Keep cached apps and their freshness visible.

Priority: **UX-P2**. Effort: Small (under one engineering day). Regression risk: Low: presentation-only; retain existing model action. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F15. Low, confirmed: unsigned empty-state text confuses imported input with signed output

Evidence: `App/ContentView.swift:138-146` says “Add an IPA from Files, or sign one from the Sign tab. It lands here.” on Unsigned. Signed results belong in Signed. Acceptance: explain that choosing an input on Sign can retain its original under Unsigned while the signed output goes under Signed; make Add an IPA the direct empty-state action.

Priority: **UX-P2**. Effort: Small (under one engineering day). Regression risk: Low: presentation-only; retain existing model action. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F16. Low, source-grounded risk: fixed action-sheet heights may clip large text

Evidence: `App/ContentView.swift:94-98` and `App/SourcesView.swift:63-69` compute fixed heights from action count. `App/Theme.swift:349-365` uses a non-scrolling VStack with one-line title. Runtime clipping remains untested.

Scenario: largest accessibility text, long app/source name, Signed actions. Acceptance: allow scrolling or content-driven/large detents; keep Delete, Export, and dismissal reachable; allow full-name inspection.

Priority: **UX-P3**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F17. Low, source-grounded risk: signing option field layout compresses long values

Evidence: `App/SigningOptionsView.swift:168-179` fixes label width to 96 and places the text field beside it. Injected filenames have one line (`:275-284`). Acceptance: test largest text and long IDs/filenames; stack label/value at accessibility sizes and provide a full selected filename view. Current rendered behavior remains unverified.

Priority: **UX-P3**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F18. Low, subjective copy improvement: option descriptions promise runtime effects

Evidence: `App/SigningOptionsView.swift:77-85` says high frame rate lets the app run at full refresh and removing device limits lets another-device app run on this iPhone. These controls edit app settings and cannot guarantee app/runtime compatibility. Acceptance: describe the setting change and qualify app/device support, preserving concrete user benefit.

Priority: **UX-P3**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

### UX-F19. Low, subjective scope clarification: explain session switches versus saved defaults

Evidence: `App/SigningModel.swift:354-359` resets per-app edits through defaultsOnly when choosing another IPA. `Sources/SigningKit/AppEditor.swift:66-71` preserves current switches, while `App/SigningModel.swift:43-46` writes saved defaults only on explicit save. Current names, versions, IDs, icons and injected libraries do not persist across app selection. The page correctly groups switches under “Changes to every app.”

Acceptance: explain that those switches affect subsequent selections in the current session, while Save as defaults keeps them for later launches. Treat this as optional copy polish, not an established persistence bug.

Priority: **UX-P3**. Effort: Medium (1–3 engineering days including controlled regression coverage). Regression risk: Medium: coordinate job state, navigation or adaptive layout. Screenshot: no fault-specific runtime capture unless named in IMPLEMENTATION-REPORT.md; source evidence above is the current basis.

## Five strongest qualities

1. The palette and wax branding remain recognizable in ordinary utility screens.
2. Recovery retains useful artifacts instead of treating a failed index write as lost signing work.
3. Source metadata and inspected IPA metadata have separate provenance.
4. Signing preview preserves compatibility warnings and iOS acceptance caveats.
5. The guide and progressive disclosure keep normal setup smaller than the developer interface.

## Most urgent screens

Sign results need truthful save status; IPA actions need safe deletion; navigation and shared controls need accessibility fixes. Sources needs direct-download feedback and job-specific recovery before richer artwork. Settings' standard bottom layout is already working in the recorded capture.

## Remaining evidence

Manual VoiceOver, real shake, display zoom, all orientation combinations, credential-dependent signing screens, full source networking and Instruments hitches are not inferred from source or a passing compiler. See the implementation report for the final execution matrix.
