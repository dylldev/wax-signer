# Independent conformance and physical-device evidence (R12)

No new physical-device result has been observed in this program. A green package/Simulator run is not an installation or launch result. Do not fill an outcome with "pass" based on scheme availability, transfer completion or local signature consistency.

## Source-built probe v1

`Prototype/WaxProbe/WaxProbe.swift` and the WaxProbe target in `project.yml` replace the unexplained bundled binary in app builds. The old tracked `App/Resources/WaxProbe.ipa` remains for history but is excluded from app resources. A build dependency compiles the probe for the same SDK, then `scripts/package-probe.py` packages its actual bytes and emits `probe-build.json` with IPA/executable/source hashes and public metadata. The app-hosted test checks the actual bundled IPA hash against this manifest. A source hash is not an attestation, Apple trust claim or claim of bit-reproducible compilation. No IPA is uploaded or released by these changes.

Probe v1 registers `waxprobe://` and displays a launch screen only when actually opened. Existing Wax observes scheme availability after an install attempt; it does not observe launch, extensions or entitlement behavior. Delete an existing probe before a fresh attempt. No nonce binding, keychain/extension capability test or remote rule execution exists in v1; those remain R20 work. Probe's manifest build is 1, matching its actual CFBundleVersion.

## Mac conformance protocol

1. Record git SHA, clean/dirty state, `xcodebuild -version`, `swift --version`, SDK/simulator IDs and fixture SHA-256. Use only synthetic or owner-authorized credentials outside Git.
2. Run full `swift test`; retain output and enumerate every skip/reason. Existing optional real-profile/IPA/live-server tests do not count as executed without their inputs.
3. Build unsigned iOS and execute all simulator bundles. CI retains `package-tests.log` and `WaxTests.xcresult` for seven days, including failures; no IPA artifact is uploaded. Inspect raw xcresult, not only job color.
4. Sign/export final IPA using the engine. Re-extract the actual packaged output; run `/usr/bin/codesign --verify --deep --strict -vv <app>`, extract XML/DER entitlements and compare intended profiles/prefixes. Independently verify extracted CMS using OpenSSL with explicitly supplied certificates; distinguish cryptographic integrity from Apple trust.
5. Include an Xcode-signed baseline control and tampered resource/page/CMS negative controls. Existing SigningKit tests supply static fixture checks; they do not replace the physical matrix below.

## Physical matrix (every row currently NOT RUN)

For iOS 17 and current supported stable iOS, test the minimum supported phone and a current phone where available. Record exact model/OS, app/commit/build/input/output hashes and public credential fingerprint/type, never UDIDs, private keys, passwords, server tokens or capability URLs.

| Journey | Record independently |
|---|---|
| Credential import | Modern/legacy P12, wrong-password retry, profile validity, Keychain access and responsiveness |
| Normal app and nested framework/extension | Final-byte verification; install observed; main app launch observed; extension execution observed |
| Distinct App ID prefix | Entitlement extraction, update behavior, authorized keychain/group continuity |
| Supported edits and library injection | Planned vs actual mutations; independent signature verification; app launch |
| Library save/export | Files/iCloud lifetime; wrong duplicate prevention; save-failure retry/export; low disk; prior artifact hashes |
| Local/server/bucket handoff | Delivery completion; OS prompt; install observed; launch observed; cancellation and expired-link retry |
| Background/lock/termination | Expire/kill at each journal/pipeline stage; verify originals survive and stale callbacks cannot revive work |
| Accessibility | VoiceOver, AX1–AX5 narrow phones, Dynamic Type, Reduce Motion and real share sheet |

Keep anonymized results under a new reviewed file with observed timestamps and a separate outcome for every stage. Mark unsupported/unknown cases explicitly. Do not infer a successful launch from `canOpenURL` or a failed install solely from local delivery timeout. Without the authorized devices/domain/profiles, these gates remain open.
