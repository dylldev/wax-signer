# Screen audit: Sign

Base: `2326af0` on `ui/02-sign-flow`. I changed `App/SignView.swift`, `App/SigningOptionsView.swift`, `App/InstallSection.swift` and `App/BundleIDModePicker.swift`. I did not edit `App/Theme.swift` and I did not touch `SigningModel.swift`.

## Verification

I ran these commands on the final code:

```
xcodegen generate
# XCODEGEN_EXIT:0

xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'platform=iOS Simulator,name=iPhone 17' build
# ** BUILD SUCCEEDED **
# BUILD_EXIT:0

swift test
# Executed 150 tests, with 1 test skipped and 0 failures (IPAKit)
# Executed 83 tests, with 13 tests skipped and 0 failures (CredentialKit)
# TEST_EXIT:0
```

I also ran a temporary UI screenshot harness (`Tests/UITests/SignFlowAuditTests.swift`, deleted before commit) on a second simulator named “Wax02 iPhone 17” (same device type, separate container). It writes PNGs to `/tmp/wax-audit/` via `XCUIScreenshot.image.pngData()`. It seeds `Tests/SigningKitTests/Fixtures/TestApp.ipa` and a broken 12-byte file into the library, then drives the app: Choose, Import signing files, Options, Signing options, Install host, dark (device appearance where noted) and Accessibility XXXL via `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`.

RED/GREEN for the hierarchy fix: `testEmptyReasonLine` asserts the primary reason text “Pick an IPA to sign.” exists on the empty Sign screen. On the old code it failed (`** TEST FAILED **`, exit 65). On the new code it passed. The full harness run on the new code first hit a test-runner restart during `testSigningOptions` (light); I reran that single test and it passed (`** TEST SUCCEEDED **`, exit 0, 29.5s). The broken-IPA harness first asserted the word “unreadable” while the engine returns “Not a valid zip archive (corrupt or truncated).” I fixed the harness to wait for “Choose an app” and reran it; both before and after failure shots then passed.

## Screenshots

Light = device light. XXXL = Accessibility XXXL. Dark is described per-state below because the first harness dark used `-AppleInterfaceStyle Dark`, which does not change Wax on iOS, so those files showed light and I discarded them.

Before (old code):

- [shots-before/sign-empty.png](shots-before/sign-empty.png): empty Sign, light from the harness
- [shots-before/empty-light-default.png](shots-before/empty-light-default.png), [shots-before/empty-light-xxxl.png](shots-before/empty-light-xxxl.png), [shots-before/empty-dark-default.png](shots-before/empty-dark-default.png): empty Sign from `xcrun simctl io booted screenshot` on iPhone 17
- [shots-before/app-chosen.png](shots-before/app-chosen.png): SigningTestApp chosen, no identity, light
- [shots-before/app-chosen-xxxl.png](shots-before/app-chosen-xxxl.png): same at XXXL
- [shots-before/failure-broken-light.png](shots-before/failure-broken-light.png): broken IPA chosen, no app read, light
- [shots-before/options-sheet-top.png](shots-before/options-sheet-top.png) and [shots-before/options-sheet-bottom.png](shots-before/options-sheet-bottom.png): Options sheet, light. The two frames are identical because the sheet fits without scrolling at default size. The swipe changes nothing.
- [shots-before/options-sheet-xxxl.png](shots-before/options-sheet-xxxl.png): Options sheet at XXXL
- [shots-before/signing-options-top.png](shots-before/signing-options-top.png), [shots-before/signing-options-mid.png](shots-before/signing-options-mid.png), [shots-before/signing-options-more.png](shots-before/signing-options-more.png), [shots-before/signing-options-bottom.png](shots-before/signing-options-bottom.png): Signing options top to bottom, light
- [shots-before/signing-options-xxxl.png](shots-before/signing-options-xxxl.png): Signing options at XXXL
- [shots-before/install-host.png](shots-before/install-host.png): Install host, light
- [shots-before/install-host-xxxl.png](shots-before/install-host-xxxl.png): Install host at XXXL

After (new code):

- [shots-after/sign-empty.png](shots-after/sign-empty.png): empty Sign, light. The app row now shows “Choose”, and the button now shows its reason, “Pick an IPA to sign.” The subtitle now reads “Sign an app and hand it to iOS to install.”
- [shots-after/empty-dark.png](shots-after/empty-dark.png): empty Sign in dark. I captured this manually because the harness dark did not switch the device. I set the device with `xcrun simctl ui "Wax02 iPhone 17" appearance dark`, installed the Debug build (`LocalIPASigner.app` from DerivedData), launched with `-firstRun.completed YES`, waited 5 seconds, and saved `xcrun simctl io "Wax02 iPhone 17" screenshot`. The frame shows the dark tokens, the “Choose” hint and the reason line in dark.
- [shots-after/app-chosen.png](shots-after/app-chosen.png): SigningTestApp chosen, no identity, light. The button reads “Import signing files” with the reason “Bring your own .p12 certificate and .mobileprovision profile. Wax does not provide them.”
- [shots-after/app-chosen-xxxl.png](shots-after/app-chosen-xxxl.png): same at XXXL
- [shots-after/failure-broken-light.png](shots-after/failure-broken-light.png): broken IPA chosen, light. The banner has no “Choose another file” link in this state. You get one picker action: the primary button.
- [shots-after/options-sheet-top.png](shots-after/options-sheet-top.png) and [shots-after/options-sheet-bottom.png](shots-after/options-sheet-bottom.png): Options sheet, light (identical frames, same as before)
- [shots-after/options-sheet-xxxl.png](shots-after/options-sheet-xxxl.png): Options sheet at XXXL
- [shots-after/signing-options-top.png](shots-after/signing-options-top.png), [shots-after/signing-options-mid.png](shots-after/signing-options-mid.png), [shots-after/signing-options-more.png](shots-after/signing-options-more.png), [shots-after/signing-options-bottom.png](shots-after/signing-options-bottom.png): Signing options, light
- [shots-after/signing-options-xxxl.png](shots-after/signing-options-xxxl.png): Signing options at XXXL
- [shots-after/install-host.png](shots-after/install-host.png): Install host, light
- [shots-after/install-host-xxxl.png](shots-after/install-host-xxxl.png): Install host at XXXL
- [shots-after/empty-xxxl.png](shots-after/empty-xxxl.png): empty Sign at XXXL

States I did not screenshot: signing (the Reading transient is under a second for the 30K fixture, so I could not freeze the frame in a stable way), uploaded/handed-to-iOS waiting during a phone transfer, signed success and signed-with-problems results, and preflight blocked or warning. Signing those states needs a `.p12` and a `.mobileprovision` imported through the Files picker. UI automation cannot drive the document picker reliably here, and I did not seed the Keychain from the test runner because `WaxUITests` links only `InstallKit`, not the credential store. I changed the code for those states (reason, host-aware messages, result header, grouped result details and the Passport panel) and I verified them with the build, the unit tests and code reading. I cite the exact lines below so you can read the logic against the screenshots I did capture (app-chosen, failure, options, install host) and the report fields you see in the sheets.

A second agent (brief 04 sweep) kept shutting down booted simulators while I worked, which killed several harness runs with “Busy” and “channel disconnected” errors. I worked around it by using the separate “Wax02 iPhone 17” device. I could not capture dark variants for every state for the same reason. I captured dark for the empty state manually and I did not invent the others.

## Findings and changes

### 1. Hierarchy

`App/SignView.swift:271` rendered the primary title and hid the reason. `SignPrimary.reason` in `Sources/InstallKit/SignScreenLogic.swift:113` already said what happens next (“Pick an IPA to sign.”, “Bring your own…”, “Signs the app, uploads it, and asks iOS to install.”) and the tests check it is non-empty, but no view read it. I print `primary.reason` under the button in `Wax.Ramp.secondary`, centered. See [shots-after/sign-empty.png](shots-after/sign-empty.png) and [shots-after/app-chosen.png](shots-after/app-chosen.png). The empty-state reason wraps to two lines for “Import signing files” and still reads as one block under the button.

`App/SignView.swift:282` showed “Sign only and export” whenever `model.canSign` held. When a certificate existed but the host or profile was missing, that secondary competed with the primary (“Set up installation” plus “Sign only and export”). I gate it on `primary == .install`. The secondary now appears only alongside “Sign & Install”, where it is an alternative route, not a second primary.

`App/SignView.swift:164` had no trailing affordance on the empty app row while “Import” and “Set up” marked the sibling rows as tappable. I print “Choose” in `WaxLinkText` there. The row stays a summary: only the primary button picks the file. You now read three rows that all end with a hint, and only one big button that acts.

`App/SignView.swift:73` kept the summary card inside the idle branch, so the selection vanished during signing and results and the page jumped. I move `summaryCard` above the stage/result/idle branch (`App/SignView.swift:81`). The header and the three selection rows stay put while the lower area swaps. I also disable the three rows while `model.installing` is true (`App/SignView.swift:159`, `186`, `202`). You can still read what is selected during a run, and you cannot start a pick or a settings jump mid-run.

The header subtitle said “install it on this iPhone” even for My server and Bucket. I change it to “Sign an app and hand it to iOS to install.” (`App/SignView.swift:139`).

### 2. States

Loading swapped the whole page. The persistent summary (above) reduces the jump: only the area below the card changes. The melt, percent, stage strip and message remain in `progressCard`.

Failure doubled the way back into Files. `App/SignView.swift:495` always added “Choose another file” to the error banner. When the read itself failed you got two picker actions at once: the banner link and the primary “Choose an app”. I show the link only when `model.ipaInfo != nil`. Compare [shots-before/failure-broken-light.png](shots-before/failure-broken-light.png) (banner link plus primary) with [shots-after/failure-broken-light.png](shots-after/failure-broken-light.png) (banner only, one primary).

The empty Sign at XXXL was already tall before this change and stays tall. Compare [shots-before/empty-light-xxxl.png](shots-before/empty-light-xxxl.png) with [shots-after/empty-xxxl.png](shots-after/empty-xxxl.png). The new “Choose” hint is visible at XXXL, and the primary action sits below the fold and needs a scroll, the same as before. I report this under “still wrong”. I did not flatten the XXXL row in this brief because the stacking comes from `WaxIconTile` and the accessibility-size layout in `Theme.swift`, which is brief 01.

### 3. Preflight and Passport

The post-sign detail in `App/SignView.swift` (old `reportDetails`) printed checkSummary, archive lines, profile lines and warnings as one flat footnote list in engine order. A warning looked like archive trivia. I split it (`App/SignView.swift:544`): the summary with a check or cross icon, a “Needs attention” group for failures and warnings that stays visible, and DisclosureGroups for “Profiles” and “Archive details”. Failures and warnings no longer hide behind disclosure.

The Passport lived only in Developer settings. `model.passportReport` is set by `SigningModel.sign(reviewBeforeSigning:)` and `App/SignView.swift` never read it, so the main flow hid the same findings. I render it in the Options sheet when it exists (`App/SignView.swift:531`, `passportDetails` at line 584). I group by consequence: “Blocking” and “Needs attention” stay visible, “Wax cannot know” and “Checked and passed” collapse under disclosure. Each row shows the title, the status word in its tone color, the detail and the evidence. The intro keeps the limit in plain words: “Wax checks these inputs before signing. Only iOS can make the final install decision.” That matches the Passport spec (`docs/superpowers/specs/2026-10-18-wax-installability-passport-design.md:41`) and it never shows unknown as pass.

Bundle ID changes lived in three places: the explicit field in Signing options, “Randomize bundle ID” under More options, and Keep/Rename in the Options sheet. I kept the controls where they were and made each change visible where it lives. In `App/SigningOptionsView.swift:44`, when `model.edits.bundleIdentifier` is set you now see: “Bundle ID will change to [id]. The app installs as a new app.” The rename warning under the primary button (`App/SignView.swift:274`) now reads: “The app will be renamed to fit the profile. It installs as a new app.” The picker copy in `App/BundleIDModePicker.swift:10` now reads: “Keeps the app's own ID. Best for most profiles.” and “Renames the app to fit the profile. Installs as a new app.”

### 4. Install handoff

The progress message said “Sending to your server…” for every host. I make it host-aware in `App/SignView.swift:368` and in `App/InstallSection.swift:128`: “Sending to your bucket…”, “Sending to your server…” or “Sending the app from this iPhone…”.

Preparation announced itself as signing. When `ota.state == .preparing` the stage strip still shows the Signing stage (that stage list has no Preparing case, see “still wrong”), but the message now says “Preparing installation…” (`App/SignView.swift:377`). When `busyMessage` is nil and an install is running, the message no longer falls back to “Signing the app…” (`App/SignView.swift:378`).

The result header said “Signed and uploaded” in green as soon as iOS had the link, even for the phone host where the transfer was still waiting. I add `waitingForTransfer` (`App/SignView.swift:49`: handed, installing, phone host). The header then reads “Handed to iOS” in `Wax.text` on `Wax.chip` with “Waiting for iOS to take the app. Keep Wax open.” (`App/SignView.swift:435`, `441`). The primary button in that window reads “Open install again” (`App/SignView.swift:390`). For server and bucket, where handed means the upload finished, the header reads “Signed and handed to iOS”. The seal stamp no longer fires while waiting: the phase and handed handlers check `waitingForTransfer` (`App/SignView.swift:108`, `118`) and the phone completion stamps from the `installing` change (`App/SignView.swift:112`).

`App/InstallSection.swift:119` said “Uploaded. iOS will now ask you to confirm the install.” I split that into `handoffLabel` (`App/InstallSection.swift:136`): phone, “Handed to iOS. Keep Wax open until iOS takes the app.”. Server and bucket, “Sent to iOS. Confirm the install when iOS asks.”. The uploading label in the same file (`App/InstallSection.swift:118`) is now host-aware. The collapsed server summary (`App/InstallSection.swift:100`) said “Ready:”. `InstallSetupPanel.resolve` always returns `eligibilityUnknown: true` (`Sources/InstallKit/SignScreenLogic.swift:83`), so “Ready” overclaimed. I changed it to “Setup saved:”.

### 5. Options sheet

`App/SigningOptionsView.swift:192` gave text fields `minHeight: 48` while grouped rows elsewhere used 56. I set fields to 56 (`App/SigningOptionsView.swift:192`). Library rows and add buttons also move from 48 to 56 (`App/SigningOptionsView.swift:300`, `305`, `361`). The remove button now has a full 44-point target (`App/SigningOptionsView.swift:297`). Toggle and appearance padding moves from a one-off 10 to `Wax.Space.s` (`App/SigningOptionsView.swift:203`, `348`). That trims the toggle stack by a small amount and puts the toggles on the same token as the grouped rows.

The “More options” container recreated the card with `padding(.horizontal, 14)` and a 9-point corner (`App/SigningOptionsView.swift:111`). I set it to `Wax.Space.l`, `Wax.radiusTile` and `Wax.stroke`, the same values `WaxPanel` uses. The icon preview corner (`App/SigningOptionsView.swift:222`) now uses `Wax.radiusTile` instead of 10.

I replaced one-off spacing and footnote sizes in this file with `Wax.Space` and `Wax.Ramp` (`App/SigningOptionsView.swift:29`, `182`, `197`, `211` and neighbors). The field rows, toggles, the disclosure header and the save buttons now sit on the shared scale. I kept the toggle explanations as they were: each names one concrete effect in one sentence.

### 6. Alignment

`App/SignView.swift` and `App/SigningOptionsView.swift` used literal 10, 8, 12, 16, 24 and inset 14. I moved those to `Wax.Space` and `Wax.Ramp` (`App/SignView.swift:73`, `207`, `215` and neighbors; `App/SigningOptionsView.swift:29` and neighbors). The body gap moves from 10 to `Wax.Space.m`, the setup row from 12 to `Wax.Space.m`, the result header from 16 to `Wax.Space.l`, and the Options card edge from 14 to `Wax.Space.l`, so section labels, card edges, icons and buttons share the app anchors without new padding numbers.

## Still wrong (read before you ship)

I did not fix these in this brief. Each one needs a shared change outside my four files or a signing change I was told not to make.

- XXXL Sign needs scrolls to reach the primary action. The header and each summary row triple in height at Accessibility XXXL. The stacked row (`App/SignView.swift:207`) and the large header come from `Theme.swift`. Fix in `Theme.swift`: let the header subtitle use a smaller ramp at accessibility sizes, or collapse the summary card at XXXL into a compact checklist. My `Choose` hint at XXXL proves the row offers a next step, but the button is still below the fold in [shots-after/empty-xxxl.png](shots-after/empty-xxxl.png).

- The stage strip cannot tell the truth for preparation or handoff. `SignStage` has only Reading, Signing and Uploading (`Sources/InstallKit/SignScreenLogic.swift:15`). During host preparation the strip highlights Signing while the message says “Preparing installation…”. During the phone wait the strip is hidden behind the result card. Fix in `Sources/InstallKit/SignScreenLogic.swift` and `App/SignView.swift:progressCard`: add Preparing and Handed stages, or hide the strip and show a single status line while preparing.

- The large percent is a weighted estimate, not a tape measure. `JobProgress.overall` (`Sources/InstallKit/JobProgress.swift:14`) blends the real signing and upload fractions by expected seconds (`App/SignView.swift:305`). The integer in `progressCard` still reads as exact. Fix in `App/Theme.swift`: offer the progress bar from `WaxProgressBar` for the Uploading stage and a stage label without a number for Reading and Signing, or label the number “about”. I left the estimate in place because the weighting lives in `SigningModel.jobProgress`.

- The Profile row wraps the explanation to three lines at default size. In [shots-after/signing-options-top.png](shots-after/signing-options-top.png) “Which provisioning profile signs this app.” splits because the “Automatic” picker takes the right side of the row. Fix in `App/SigningOptionsView.swift:profileRow` (or `Theme.swift` if the row should stack the picker below the text at all sizes): put the picker under the two-line label, or give the label the full width and move the picker to the next line.

- `InstallSection` still lives in the native Settings list, so its section heads (“This iPhone”, “Cloud bucket”, “Install server”) use the system small-caps style, not `WaxSectionLabel`, and its fields use `LabeledContent` row heights instead of the Wax rows. I polished the copy and the status line only. Fix by replacing `Section` with the Wax card pattern in `App/InstallSection.swift` and `App/SettingsView.swift:InstallHostSettingsView`, which is brief 04.

- Appearance word “Phone” (`App/SigningOptionsView.swift:340`) is unclear. It means “follow the phone”, but the segmented control is too narrow for “Follow phone”. Fix the label in this file only if brief 04 accepts the wider control, or shorten the nearby explainer.

- “Sign only and export” gating stays a view check (`App/SignView.swift:282`). If `SignPrimary` gains a new case tomorrow, this gate can drift again. Fix in `Sources/InstallKit/SignScreenLogic.swift`: expose `showsExportSecondary` on `SignPrimary` and read it in the view.
