# Direct install from Wax: options and recommendation

Status: research / proposal. Nothing here is implemented. Needs a human decision before any code.

## Problem

Wax signs an IPA on the phone and exports a signed file. Installing that file still happens outside Wax:
the Mac (`devicectl device install app`) or a sideloader. The question is whether Wax can install what it signs.

## What is verified (this project, this device)

- Wax signs on-device; Apple `codesign --verify --strict --deep` passes on the exported app.
- `devicectl install` of the unpacked signed `.app` over USB succeeds and upgrades in place.
- Credentials (Keychain key + container metadata) survive an in-place update when bundle ID and team are unchanged.
- An app cannot install another app through any public iOS API.

## Options

### A. Keep export + Mac `devicectl` / sideloader (status quo)
- Works today, no new trust surface, no publishing.
- Cost: needs a Mac or a sideloader for the last step.

### B. OTA install via `itms-services://`
- Wax opens `itms-services://?action=download-manifest&url=https://HOST/manifest.plist`.
- Requires: HTTPS with a certificate iOS already trusts, a manifest plist (bundle identifier, bundle version,
  title, kind, software-package URL), and the IPA reachable by the phone at that URL.
- The signed app must be installable on the device by profile (device UDID listed for development profiles).
- Not verified on this device or on iOS 27. Treat every claim in this section as unconfirmed until tested.
- `localhost` and plain HTTP are not valid hosts. A self-signed host needs a root profile the user installs and
  trusts first, which is more steps than export.
- Hosting means the signed IPA and manifest are served from somewhere the phone can reach. A signed IPA is a
  signed copy of the app; do not publish IPAs signed with a purchased certificate.

### C. Loopback pairing-file route (as SideStore-style tools do)
- Uses a device pairing file and a local VPN loopback to reach lockdown / installation proxy from the phone itself.
- Heavy: pairing-file handling, a VPN extension, and Apple-service protocol code.
- Licence: reference implementations are AGPL; Wax is Apache-2.0. Do not copy code without a licence decision.
- Not evaluated beyond this paragraph.

## Research findings: how existing signers install (sourced 2026-10-14, not tested here)

| Project | Licence | Install mechanism |
|---|---|---|
| SideStore / minimuxer | AGPL-3.0 | on-device lockdown muxer over a loopback VPN + pairing file; installs via installation proxy |
| Feather | GPL-3.0 | local HTTPS server (was `*.backloop.dev` cert) + Safari redirect to `itms-services://`; also an idevice-based pairing path |
| idevice (jkcoxson) | MIT | pure Rust: lockdownd, AFC, installation_proxy, house_arrest, heartbeat; used by StikDebug-style apps |
| StikDebug | AGPL-3.0 | uses idevice + loopback VPN (LocalDevVPN) + pairing file |

- `backloop.dev` is discontinued (service ended 2026-09-04; certificates revoked, key was public). The "publicly
  trusted localhost certificate" trick is not available. Anything `itms-services`-based locally needs our own CA
  that the user installs and trusts, or a real hosted domain.
- AGPL/GPL code (minimuxer, Feather, StikDebug) cannot be copied or linked into an Apache-2.0 Wax. Their designs can
  be studied; their code cannot be reused.
- idevice is MIT, so it is the only reusable building block found. Its Swift/FFI packaging for iOS and its
  installation_proxy completeness on iOS 27 are unverified.

## Recommendation

Stay on A. Revisit B only if there is a hosting location the owner is willing to make public for the manifest,
and a decision about what the IPA behind it may contain (unsigned IPA only? never a purchased-cert build).
C is now feasible only through idevice (MIT) and requires: a pairing file (one-time, from the Mac), a loopback VPN
app the user installs separately, and storing the pairing file in the Keychain (it is a full device-trust secret;
never log or export it). Prototype before committing: connect, heartbeat, upload via AFC, installation_proxy Install,
on this iPhone, with a Personal-Team-signed test app only.

## If B is chosen: minimum test before building anything

1. Serve a manifest and a Personal-Team-signed Wax Dev build over HTTPS from a throwaway host.
2. Open the itms-services link in Safari on the phone and record exactly what iOS 27.2 shows.
3. Only if that installs, add a Wax feature that builds the manifest and opens the link.

## Open questions

- Is there a host the owner accepts as public?
- Is an in-app install worth a hosted dependency, given the project principle that signing stays local-first?

## Decision (2026-10-15)

Option C through idevice (MIT) is implemented, all free and local:

- `Rust/wax-install`: heartbeat, streamed AFC upload to `PublicStaging`, installation_proxy install. Refuses any
  address that is not loopback / private / link-local, and any hostname (no DNS involved).
- `Sources/InstallKit` (pure Swift, tested on macOS): `DeviceAddress`, `PairingRecord` structure check (names
  missing keys, never values), `KeychainPairingStore` (this device only, not synced).
- App: Install section under the signing result; pairing record is imported from Files and kept in the Keychain.

Not verified on a device: that installation_proxy accepts the install on iOS 27.2 over the loopback VPN, the VPN
app's address (10.7.0.1 is a convention, unverified), and KeychainPairingStore under iOS (macOS tested only).
Pairing record creation and the VPN install are still separate human-approved steps. Anti-revoke DNS is not
implemented and will not be.

## Result of the on-device test (2026-10-15, iPhone 17, iOS 27.2): route blocked

Setup: fresh pairing record (created over USB with `Rust/pair-tool`), LocalDevVPN connected (Tunnel IP 10.7.0.1/30,
Device IP 10.7.0.2/32), Personal-Team-signed Wax Dev, `NSLocalNetworkUsageDescription` present.

Plain BSD `connect()` from inside the app (debug-only probe, removed):

| Target | port 62078 (lockdown) | ports 80 / 443 |
|---|---|---|
| 10.7.0.1 (tunnel IP) | `EPERM` at connect() | refused (reachable) |
| 127.0.0.1 | `EPERM` at connect() | refused (reachable) |
| 10.7.0.2 (device IP) | connects, then reset on the first request | refused (reachable) |
| own loopback listener | works | n/a |
| LAN router 192.168.1.1:80 | connects | n/a |

Conclusion: on this device and OS the app is denied access to the lockdown port; it is not an address, permission
prompt, pairing-record, or Local Network problem (all three were tried or excluded). The project rule applies:
do not weaken anything to force it. The install section stays only as an experimental, clearly labelled feature
(or can be hidden); the supported routes are export + Mac `devicectl` or a sideloader.

Not tested: iOS 26 or earlier, other VPN apps, or Apple-signed entitlement paths.
Cleanup done: pairing record deleted from Wax Dev's Keychain and the Mac, staged file removed, test payload removed
from iCloud. The pairing record created on the phone itself remains in its trusted-computers list until
Settings > General > Transfer or Reset iPhone > Reset > Reset Location & Privacy.

## Result of the OTA spike (2026-10-15, iPhone 17, iOS 27.2): self-hosted OTA install is blocked

Question: can Wax serve its own signed IPA over HTTPS (own on-device CA) and install it through `itms-services://`?
Setup: throwaway app, name-constrained test CAs installed as configuration profiles and fully trusted, Personal-Team
payload, manifest + IPA served by the app itself.

| Test | Result |
|---|---|
| Safari loads `https://localhost:8443/manifest.plist` served by the app | works, TLS trusted |
| itms-services link, host `localhost` | installer: "Cannot connect to localhost"; no connection reached the app |
| itms-services link, host `127.0.0.1` | installer: "Cannot connect to 127.0.0.1" |
| itms-services link, host = the phone's own LAN IP (app serving) | installer: "Cannot connect to 192.168.1.222" |
| itms-services link, host = a Mac on the LAN (same CA trust) | **installer fetched the manifest and showed "would like to install"** |

Conclusion: the CA trust and manifest format are fine; iOS's installer will not fetch from a server on the same
phone (loopback or own LAN address). A different host works. Remaining free options: another LAN device (not
standalone), or a hosted HTTPS location with a publicly trusted certificate (a presigned/unlisted URL).
Combined with the lockdown-port result above, there is no fully on-device, fully local install route on iOS 27.2.

## Result: over-the-air install through the owner's own server WORKS (2026-10-16, iPhone 17, iOS 27.2)

Design in use: Wax signs on the phone, uploads the IPA and a manifest to an HTTPS server the owner controls
(`Server/wax-ota`, behind Caddy + Let's Encrypt on an Oracle Always-Free VM), then opens an `itms-services` link.

| Signing certificate | Result |
|---|---|
| Development (`iPhone Developer`, Personal Team and purchased) | iOS prompt appears, then **installd fails**: `Trust evaluate failure: [leaf IssuerCommonName LeafMarkerOid SubjectCommonName]`, `Verification stage failed` ("Unable to Install") |
| **Distribution (ad hoc)** | **Installs and launches.** Confirmed with Wax 0.5.2 signed in-app and installed on the phone with no Mac |

Notes:
- The OTA path (appstored -> installd) accepts distribution-signed apps; development-signed apps installed fine from a
  Mac over USB but not through `itms-services`. Wax therefore checks certificate name and the profile's
  `get-task-allow` before uploading and explains instead of letting iOS fail vaguely.
- Server must send `Content-Type` for `.ipa` (application/octet-stream) and `.plist` (text/xml); done in Caddy.
- A p12 that Apple's importer refuses ("incorrect password" / "not readable") is now checked by Wax's own MAC
  verification and re-encoded in memory (`PKCS12Modern.swift`); this is what made the Distribution p12 importable.
- The distribution profile was for a different team/App ID, so the app installs as a separate second Wax.

## Result: a fixed-ID profile does not force a bundle ID change (2026-10-16, iPhone 17, iOS 27.2)

Assumption corrected: Wax's "profile does not permit this app ID" refusal was stricter than iOS.

- Feather (open source, GPL; read, not copied) keeps the app's bundle ID and builds entitlements from the *profile's own*
  entitlements, so `application-identifier` is the profile's value, not `TEAM.<app bundle id>`.
- Wax `keepBundleIdentifier` does the same. Wax's own IPA (`dev.localsigner.app`) signed with the explicit-ID Distribution
  profile (`TEAMID.app.example.profile`) installed over the air through the owner's server and launched.
- Also verified: the repo's test app (main app + app extension + framework, `Tests/SigningKitTests/Fixtures/TestApp.ipa`)
  signed in keep mode with the same single explicit-ID profile installed over the air on the same device. Both the app and
  the extension carry the profile's application identifier.
- Not verified: launching an app that uses its extension, app groups, or keychain sharing under this mode. Keychain groups
  are moved onto the profile's team; app-group values are kept only if the profile grants them.
- Migration: the new bundle ID (`io.github.dylankirkgirg.wax`) is a different app, so its credentials start empty and the
  certificates and profiles must be imported again. The older renamed copy keeps its own.

## Correction (2026-10-17): development identities CAN install over the air

The earlier table above says development-signed apps fail installd's trust check over the air. That is not true in
general. Re-tested on iPhone 17 / iOS 27.2: the repo's test app (app + extension + framework) signed in keep mode with
the Development certificate and its explicit-ID Development profile, uploaded to the owner's server, installed after the
iOS prompt. The owner also reports the same certificate installing apps in ESign and Feather.

The earlier failure (`Trust evaluate failure ... LeafMarkerOid`) is not explained; it happened with relabelled
bundle IDs and other certificates (Personal Team and a purchased one) and was never isolated. Treat the earlier row as
"failed in those runs", not as a rule. The profile's device list still decides which phones accept a development app.

Also found while checking Feather (GPL, read only): its "Server" install mode hosts the IPA on the phone itself over
HTTPS using a certificate pack for a host that resolves to 127.0.0.1, and keeps the app alive with the audio
background mode; it uses BGContinuedProcessingTask (iOS 26) for background work. The shared host it used
(`*.backloop.dev`) no longer resolves in DNS, so an on-phone route would need its own domain.
