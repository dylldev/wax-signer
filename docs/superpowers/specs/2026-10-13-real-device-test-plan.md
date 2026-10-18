# Real-device test plan (iPhone 17, iOS 27.2 beta)

Status: **not executed.** Nothing has been installed on any device. This plan exists so the first device test is
controlled, reversible and interpretable. Date written: 2026-10-13.

## 0. Rules for this test

- Only the owner's own iPhone.
- Only credentials the owner created in their own Apple Developer account for this test.
- Only a test app we build ourselves (`Prototype/MinimalApp`, `Prototype/TestApp`). No third-party IPAs.
- Success of `codesign`, `SignatureVerifier` or `devicectl install` is never reported as "works on iOS"; only an
  observed launch of the app is.
- Any failure is evidence to investigate, not a verdict on the engine. The OS is a beta.

## 1. Environment facts (observed on 2026-10-13, read-only commands)

| Fact | Value | Source |
|---|---|---|
| Target device | iPhone 17 (`iPhone18,3`), iOS 27.2, build 24B5099f | `xcrun devicectl device info details` |
| Pairing / state | paired (manual), connected | same |
| Developer Mode | Enabled | same |
| Host Xcode | 27.0 (27A266a), CoreDevice 642.16 | `xcodebuild -version`, `devicectl` |
| Host DDI | built for 27A266a | `xcrun devicectl list preferredDDI` |
| Developer disk image on device | **"could not be mounted on this device"** | `devicectl device info details` |
| Install command takes | an unpacked `.app` bundle, not an IPA | `devicectl device install app --help` |

The DDI error is the main environment risk: Xcode 27.0's image does not match a 27.2 beta device. Whether
`install` works without it, and whether `process launch`/`--console` work, is **unknown**; plan section 4 treats
launch-by-tapping as the primary observation.

## 2. Requirements: confirmed vs assumed

Confirmed (Apple documentation found, or observed above)
- iOS 16+ requires Developer Mode to run development-signed apps; it is enabled on the target. (Apple docs, WWDC22 110344.)
- The signed bundle needs an embedded profile that lists the signing certificate and the device, and an
  application identifier that permits the bundle id. (Standard Apple provisioning model; enforced by our selector.)
- Apple's own `codesign` from this Xcode produces SHA-256 CodeDirectory v0x20400 with DER and XML entitlements for
  an iOS 15 target (observed here); our output matches that structure.

Assumed (not verified, could differ on 27.2)
- A development profile and certificate from a free or paid account validate the same way as on released iOS.
- The "trust the developer" step (Settings > General > VPN & Device Management) may be required for apps
  installed outside Xcode. Apple documents it for enterprise apps; applicability to development builds unconfirmed.
- Our Requirements blob form (`certificate root = H"..."`, as `codesign` writes for non-Apple chains) is
  acceptable for an Apple-issued chain. Apple's own development signatures use `anchor apple generic ...`.
- Nothing in 27.2 beta changed signature, entitlement or profile validation.

## 3. Minimum legitimate setup (done by the owner, not by the tool)

1. An Apple ID team the owner controls, signed in to Xcode on this Mac.
2. A bundle identifier registered to that team, e.g. `com.<yourname>.signtest.minimal`.
3. An Apple Development certificate for that team in the login keychain (Xcode creates it on first build).
4. A development provisioning profile for that bundle id that includes this iPhone's UDID (Xcode creates it
   with automatic signing when the device is connected).
5. The certificate and key exported once from Keychain Access as a `.p12` with a password the owner chooses; the
   profile copied from `~/Library/MobileDevice/Provisioning Profiles/`. These two files are the only credentials
   the engine will see.

Free accounts: profiles last 7 days and the number of App IDs per week is limited. A paid account avoids that.

## 4. Procedure

Each step records: date, device model, iOS version and build, Xcode version, signing method, profile type
(from `ProfileInfo.kind`), result of install, result of launch, and the raw error text if any.

**T0 control (Xcode signs).** Build `Prototype/MinimalApp` in Xcode with automatic signing for the team, install
and launch on the device. Purpose: prove device, Developer Mode, trust and profile are fine, and capture the
DDI behaviour. If T0 fails, stop; the engine is not the variable yet.

**T1 static checks, our output (no device).**
```
Prototype/build-minimal-app.sh <your-bundle-id> /tmp/devtest
SIGNER_P12_PASSWORD=... .build/debug/signer-poc /tmp/devtest/MinimalApp-unsigned.ipa /tmp/devtest/out.ipa \
    <your.p12> <your.mobileprovision> --app-out /tmp/devtest/Signed/MinimalApp.app
codesign --verify --deep --strict -vvvv /tmp/devtest/Signed/MinimalApp.app
codesign -d --entitlements - --xml /tmp/devtest/Signed/MinimalApp.app
```
Compare with T0: `codesign -dvvv` (CodeDirectory version, flags, hashes), entitlements, `embedded.mobileprovision`.
Differences are investigated before touching the device. The CLI already prints archive structure, self-check, the
profile's own signature status, and "installation eligibility: not determined".

**T2 install our app.** `xcrun devicectl device install app --device <udid> /tmp/devtest/Signed/MinimalApp.app`.
Record the exact outcome. Do not retry with modifications silently.

**T3 launch.** Tap the app icon. If untrusted, trust the developer in Settings and record that this was needed.
Optionally `xcrun devicectl device process launch --device <udid> <bundle-id> --console` if the DDI allows.

**T4 nested code (only after T3 passes).** Repeat with `Prototype/TestApp` (framework + extension). The extension
needs its own App ID and profile or a wildcard profile; the engine's per-bundle selector reports which is used.

**Rollback.** `xcrun devicectl device uninstall app --device <udid> <bundle-id>`. No device settings are changed
by the tool; Developer Mode is already on.

## 5. Interpreting failures

| Symptom | Likely layer | Evidence required before saying so |
|---|---|---|
| devicectl install error mentioning signature/verification | signature rejected | exact error string and device log |
| install error mentioning profile / provisioning / entitlement | profile or entitlement rejected | exact string; compare entitlements to profile |
| installs, icon greyed or "unable to verify app" | profile trust or revocation | Settings > VPN & Device Management state |
| installs, launch terminates immediately | code signing at exec time | crash report termination reason (CODESIGNING) |
| install fails only where DDI is required | tooling, not signing | T0 result under the same DDI condition |

A diagnosis is recorded only with the error text and, where possible, the device log excerpt that supports it.

## 6. Not covered

Distribution profiles, enterprise certificates, OTA install, TestFlight, Mac Catalyst, watchOS, anti-revoke
behaviour, any non-self-created app.
