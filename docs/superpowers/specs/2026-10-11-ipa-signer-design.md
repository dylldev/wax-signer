# Local IPA Signer: design (milestone 1 scope)

Goal: free, open-source, iPhone-only, local-first IPA signer. Native SwiftUI.

## Module boundaries
- `IPAKit` (Swift Package, no UI, no network): zip reading, archive validation, metadata. Milestone 1.
- App target (SwiftUI): import + display only. Depends on `IPAKit`.
- Later, each its own module: certificate/profile store (Keychain), signing engine, installer.

## Milestone 1: import, validate, inspect
- Read-only zip reader: EOCD + central directory, stored and deflate (via Compression framework), CRC32 verified.
  Nothing is extracted to disk, so zip-slip cannot write files; unsafe names are still rejected for later milestones.
- Rejected with a specific error: not a zip, zip64, encrypted, unsupported method, unsafe path,
  no `Payload/*.app`, multiple apps, missing/invalid Info.plist, missing bundle id, missing executable, CRC mismatch.
- Metadata shown: bundle id, name, version, build, min iOS, executable, entry count,
  whether `_CodeSignature` and `embedded.mobileprovision` are present.
- "Signature present" means files exist. It is never reported as valid.

## Not in milestone 1 (YAGNI)
Signing, installation, certificates, icon rendering (CgBI PNG / Assets.car), zip64.

## Platform limits (see chat audit)
Installed apps need a valid signature + profile with the device UDID. Install routes: itms-services over trusted
HTTPS, or loopback-VPN + pairing file. Neither is verified yet; each needs its own milestone and device test.
Signing engine candidate: zsign + OpenSSL 3 (license review pending, before milestone 2).

## Verification
`swift test` on macOS (no simulator runtime installed); `xcodebuild` compile for iOS Simulator SDK.
Device behavior unverified.

## Archive audit (2026-10-11)
Reader rejects: duplicate names (exact, case-insensitive, Unicode-normalized), non-canonical or non-UTF-8 names,
local/central header disagreement, overlapping entries, multi-disk, ambiguous end-of-central-directory,
stream longer than declared size, oversized entries (16 MB cap on anything read into memory).

Carry-forward for any milestone that extracts to disk (not covered by the reader today):
- enforce a total uncompressed-size and entry-count budget before writing anything
- handle symlink entries explicitly (legit in frameworks, a traversal vector otherwise)
- copy the IPA to app storage first and re-validate, to avoid check-then-use races on the source file

## Third-party license review (2026-10-11, for the Milestone 3 signing engine)

Evidence: files fetched from upstream on 2026-10-11. Not legal advice.

| Component | Version / pin | License | Evidence |
|---|---|---|---|
| zsign | master `614caa8d1c` (2026-08-21); no tagged releases, so pin a commit | MIT (c) zhlynn | `LICENSE` and README "zsign is licensed under the MIT License" |
| zlib (vendored in zsign `src/third-party/zlib`) | 1.3.1 | zlib license | `zlib.h`, (c) 1995-2024 Gailly, Adler |
| minizip (vendored `src/third-party/minizip`) | 1.1 (2010) | zlib-style ("same condition of use as zlib") | file headers: Vollant, Svensson |
| OpenSSL 3.x | latest 3.x tag seen: 3.6.5 (3.5 is the LTS line, not re-verified) | Apache-2.0 | `LICENSE.txt` at `openssl-3.6.5`; no `NOTICE` file at that tag (404) |
| OpenSSL 4.x | 4.0.3 (2026-09-29) | Apache-2.0 | `LICENSE.txt` on master |
| zsign `src/common/json.*` | n/a | no license header found | provenance unverified |

Obligations if we ship zsign + OpenSSL:
- MIT/zlib: keep copyright and permission notices in source and in a bundled third-party notices file.
- Apache-2.0 (OpenSSL): ship the license text, mark modified files, keep notices; patent license ends for a licensee who sues over a patent in the Work.
- No copyleft in any component, so no source-disclosure duty beyond what we publish anyway.

Compatibility with our license (not yet chosen, no LICENSE file exists): compatible with MIT, BSD, Apache-2.0
and GPL-3.0. Not compatible with GPL-2.0-only (Apache-2.0 patent terms). Recommendation: Apache-2.0 (patent grant, matches OpenSSL).
The project licence is the owner's decision and is not added by this milestone.

Blocking issues: none for Milestone 2, which adopts no third-party code (Apple Security framework only).
Before Milestone 3 adoption: (1) pick the project licence, (2) resolve the `json.*` provenance, (3) decide whether
OpenSSL is needed at all (Security framework may cover CMS signing; unverified), (4) pin a commit and vendor with notices.
Feather is GPL-3.0 per repo metadata; we do not copy or link it.

## Milestone 2: certificate and provisioning-profile manager

New module `CredentialKit` (Swift package target, Foundation + Security only, no SwiftUI). App target adds a UI.

### Scope
- Import `.p12` (+ password) and `.mobileprovision` via the document picker.
- Validate and report: wrong password, malformed/unsupported file, no private key, expired or not-yet-valid
  certificate, invalid or expired profile.
- Private key and certificate go to the Keychain (`SecItemAdd`, `WhenUnlockedThisDeviceOnly`). The p12 password is
  never stored, logged, or put in metadata.
- Metadata index (JSON, no secrets): certificate subject, team, serial, SHA-1 fingerprint, validity dates;
  profile name, UUID, team, app identifier, dates, type, device count, listed certificate fingerprints.
- Raw profile bytes are stored in a file (complete file protection, excluded from backup) because a later signing
  step must embed the exact original. This is the one place we keep more than UI metadata, and why.
- Static compatibility report between one certificate and one profile (see below).
- Delete a certificate (removes its Keychain key and certificate items) or a profile (file and index entry).
- Read API for a future signer: `identity(for:)`, `profileData(for:)`. Nothing signs in this milestone.

### Explicit limits (must be shown to the user, not hidden)
- iOS exposes no CMS decoder; the profile's CMS signature is parsed but **not verified**.
- Certificate revocation is **not checked** (needs network OCSP; out of scope).
- The device UDID is not available to apps, so "is this device in the profile" is **not determinable**; we show the
  provisioned device count or "all devices", and say so.
- A passing compatibility report is not a guarantee that installation will succeed.

### Compatibility checks (each reports pass / fail / unknown with a reason)
1. profile lists the certificate (DER equality of an entry in `DeveloperCertificates`)
2. certificate team ID (subject OU) is in the profile's `TeamIdentifier`
3. certificate currently valid; 4. profile not expired
5. profile type (development / ad hoc / enterprise / App Store) vs. what is installable on-device

### Acceptance tests
macOS `swift test` and iOS 27 simulator, both must pass:
- p12: valid import; wrong password -> `incorrectPassword`; random bytes and truncated file -> `malformed`;
  certificate-only p12 -> `noPrivateKey`; expired -> `certificateExpired`; not yet valid -> `certificateNotYetValid`.
- profile: valid (DER and BER-indefinite CMS); non-CMS bytes, CMS without plist, plist missing required keys,
  expired -> typed errors.
- compatibility: matching pair passes; certificate not listed fails; team mismatch fails; expired members fail.
- keychain: import then fetch identity with a usable private key; delete removes both items; duplicate import
  handled; injected keychain failure leaves no metadata or orphaned items.
- secrecy: the metadata JSON and `String(describing:)` of every public type contain neither password nor key bytes.
- UI (simulator): import a certificate and a profile through the picker, see details and compatibility,
  reject a wrong password, delete both.

### Milestone 2 outcome and findings
- Keychain tests need a host app with a keychain entitlement. Unsigned macOS `swift test` hosts get
  `errSecMissingEntitlement`, so those 5 tests skip there and run for real in the iOS-simulator app-hosted bundle
  (`CredentialAppTests`, app is ad-hoc signed with `App/LocalIPASigner.entitlements`).
- iOS Keychain items outlive app deletion while the metadata index does not. Re-importing a certificate whose
  stale item remains returned `errSecDuplicateItem`; the store now replaces the stale item and retries once.
  Stale *keys* from an earlier install (unknown tag) are not garbage-collected.
- `.p12` import via `SecPKCS12Import` accepted both legacy 3DES/SHA-1 and PBES2/AES-256/SHA-256 containers.
- Real Apple-issued profiles (BER indefinite-length CMS) parse; verified against 4 profiles on the dev machine.
- `CMSDecoder` is not in the iOS SDK; profile CMS signatures remain unverified.
- Test fixtures are throwaway self-signed credentials generated by `Tests/CredentialKitTests/generate_fixtures.py`.
