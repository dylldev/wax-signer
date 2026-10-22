# Signing engine: technical design and prototype results

Status: design + working EXPERIMENTAL prototype (`SigningKit`, `signer-poc`). Not production-ready, not device-verified.
Date: 2026-10-13. Everything below marked "verified" was run in this repository; "not verified" was not.

## 1. Scope

In: re-signing an unsigned or signed `.ipa` locally with a certificate + provisioning profile the user already holds.
Out (this stage): tweak/dylib injection, anti-revoke, installation, fat (multi-arch) Mach-O, SHA-1 dual CodeDirectory,
native zip writer. No backend, no paid service, no external certificate service.

## 2. Dependency decision: Security framework, not OpenSSL, not zsign

| Need | Provided by | Notes |
|---|---|---|
| Hash (SHA-1/256/384/512) | CryptoKit | system |
| RSA PKCS#1 v1.5 signature | `SecKeyCreateSignature` | private key never leaves the Security framework |
| Read X.509 / PKCS#12 | `SecPKCS12Import`, own DER reader | `SecCertificateCopyValues` is macOS-only, so own reader |
| Build CMS SignedData | own DER writer (about 80 lines) | `CMSEncoder` is macOS-only; layout verified against Apple's output |
| Verify CMS signature | `SecKeyVerifySignature` + own parser | `CMSDecoder.h` is absent from the iOS SDK |
| Mach-O rewrite, CodeDirectory, CodeResources | own code | formats are public (`cs_blobs.h`) |
| Zip read | `IPAKit` (own, audited) | zip write is still to do |

Why not OpenSSL / zsign: zsign signs through OpenSSL `PKCS7_sign`, which needs an `EVP_PKEY`, i.e. exported private-key
material. The Security framework route signs with the key in place. No third-party code is adopted, so the
`json.*` provenance question is moot (history: owner commits since 2019 plus three contributors, no foreign-library
markers, no licence header; unresolved in the strict sense and therefore not used).
Licence of what is shipped: Apache-2.0 (`LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`); no third-party code is shipped.

## 3. Key custody (investigated)

Verified on the iOS 27 simulator, app-hosted test, key stored via `SecItemAdd` after `SecPKCS12Import`:
- Signing works through a Keychain-resident key with no export (`SecKeyCreateSignature`), for a full app+framework+extension.
- The key is nonetheless **extractable**: `kSecAttrIsExtractable = 1` and `SecKeyCopyExternalRepresentation` succeeds.
- Passing `kSecAttrIsExtractable: false` to `SecItemAdd` had no effect (still extractable, no error).
- RSA keys cannot live in the Secure Enclave (EC P-256 only), so a `.p12` RSA key cannot be made hardware-bound.

Conclusion: the interface supplies every signing operation without the engine exporting anything, and the engine never
calls an export API. The OS does not enforce non-extractability for imported keys; "never exported by us" is a
code-discipline property, not an OS guarantee. Mitigations in place: `WhenUnlockedThisDeviceOnly`, no key bytes
in logs, files or index, password never stored.

## 4. Architecture

```
IPAKit        zip read, structural validation, metadata          (no crypto)
CredentialKit p12/profile import, Keychain, profile signature    (Security, CryptoKit)
SigningKit    Mach-O, CodeDirectory, CMS, CodeResources, bundle  (depends on CredentialKit)
ArchiveKit    zip write                                          (to do)
App           SwiftUI                                            (no signing logic)
```
`SigningKit` takes a `CodeSigningIdentity` (certificate chain + `signRSAPKCS1SHA256`). It has no UI and no Keychain
dependency; `SecurityFrameworkIdentity` adapts a `SecIdentity` from the in-memory p12 or from the Keychain.

Signing order (depth first): nested frameworks/dylibs, then extensions, then the app. Per bundle: rewrite identifier
if needed, embed profile (apps and extensions only), resolve entitlements, build `CodeResources` over the final bytes of
everything below it, hash `Info.plist`/`CodeResources`/requirements/entitlements into special slots, write the
signature. The signature size is computed in a first pass because load-command and `__LINKEDIT` edits are inside the
hashed region.

## 5. Facts established against Apple's `codesign`

Captured by signing the same test app with `codesign` and diffing structures (all reproduced and verified):
- SuperBlob slots: 0 CodeDirectory, 2 requirements, 5 XML entitlements, 7 DER entitlements, 0x10000 CMS.
- CodeDirectory 0x20400, SHA-256, 4 KiB pages, `execSeg` base/limit from `__TEXT`, flags `0x1` for executables plus
  `0x10` when `get-task-allow` is true. Special slots: -1 Info.plist, -2 requirements, -3 CodeResources, -5, -7.
- DER entitlements: `[APPLICATION 16]{ INTEGER 1, [CONTEXT 16]{ SEQUENCE{ UTF8 key, value }... } }`, keys sorted,
  dict `[CONTEXT 16]`, array `SEQUENCE`. Byte-for-byte equal to Apple's output in tests.
- CMS: detached SignedData; signed attributes contentType, signingTime, messageDigest, `1.2.840.113635.100.9.2`
  (SHA-256 cdhash) and `1.2.840.113635.100.9.1` (plist of 20-byte cdhashes); RSA/SHA-256.
- A parent's `CodeResources` seals nested bundles' `_CodeSignature/CodeResources` (excluded only for its own
  `_CodeSignature`). Getting this wrong made `codesign --verify` fail, which is how it was found.

## 6. Entitlements and application identifiers

- Identity entitlements (`application-identifier`, `com.apple.developer.team-identifier`, `get-task-allow`) always come
  from the profile and the final bundle id. Other requested entitlements are kept only if the profile grants the key;
  removed ones are reported as warnings, never silently.
- `application-identifier` matching: exact, `TEAM.prefix.*`, `TEAM.*`. A mismatch is an error unless
  `rewriteBundleIdentifier` is set, which rewrites the main id and derives extension ids beneath it; frameworks keep
  their ids. An extension that the profile does not permit is an error naming the extension (it needs its own profile).
- Not handled yet: entitlement value rewriting beyond `keychain-access-groups`, app groups, associated domains
  provisioning checks, `WKCompanionAppBundleIdentifier` and similar cross-references on rewrite.

## 7. Separate verdicts (never conflated)

| Check | What it establishes | Source | Status here |
|---|---|---|---|
| Archive integrity | zip structure, CRCs, expected layout | `IPAKit` | verified in tests |
| Code signature | seals match bytes; CMS signature valid | Apple `codesign` (macOS); own self-check elsewhere | verified on macOS with `codesign`; self-check on iOS simulator |
| Profile structure | parses, required fields, not expired | `CredentialKit` | verified |
| Profile trust | CMS signature intact and chained to Apple Root CA | `ProfileTrust` | verified (see 8) |
| Installation eligibility | UDID in profile, revocation, entitlement approval, AMFI acceptance | device only | **not determinable here** |

A generated signature is never reported as proof the IPA is correctly signed; only an independent verifier (macOS
`codesign`, or ultimately the device) does that.

## 8. Profile CMS signature on public APIs

Findings (verified against 4 real Apple-issued profiles and the self-signed fixtures):
- iOS has no public CMS decoder (`CMSDecoder.h` not in the iOS SDK). Parsing is by hand (BER including indefinite
  length and chunked octet strings, which Apple's profiles use).
- Verification is possible with public API: digest check, `SecKeyVerifySignature` with the embedded signer
  certificate, `SecTrust` with `SecPolicyCreateBasicX509`, then require the chain to end at "Apple Root CA".
  Real profiles evaluated to `Apple iPhone OS Provisioning Profile Signing > Apple iPhone Certification Authority >
  Apple Root CA`.
- Limits: iOS applies an Apple-private profile-signing policy that is not public, so `appleChainVerified` means
  "looks Apple-signed", not "iOS will accept it"; revocation is not checked; evaluation uses the signing time
  attribute because the signing certificate is short-lived. Run on macOS only for the real profiles.
- A structurally valid profile is never promoted to trusted: self-signed fixtures return
  `signatureValidButUntrusted`; tampered content returns `invalid`.

Not yet wired into the import flow or UI. When it is, the UI must show the status explicitly.

## 9. Prototype results

Verified (macOS, Apple `codesign`):
- `codesign --verify --deep --strict` passes on the signed test app; nested framework and extension pass individually.
- Tampering with a sealed resource, the executable, a nested binary, or adding a file each fails verification.
- CMS signature verifies with an independent tool (`openssl cms -verify`), and fails against altered content.
- Signed app has `TeamIdentifier=FIXT123456`, entitlements and identifier per section 6.
- Control: the unsigned app fails verification.

Verified (iOS 27 simulator, app-hosted): the same engine signs the test app using a Keychain-resident key; each
Mach-O's CMS signature checks out against its CodeDirectory with `SecKeyVerifySignature`. That is a self-consistency
check, not Apple's verification.

Not verified: acceptance by a real device (AMFI, profile trust on device, entitlement approval); any
non-self-signed certificate chain; fat binaries; Mach-O without header padding; SHA-1 slots for old iOS;
on-device performance and memory for large IPAs.

## 10. Risks for the full engine

1. No device available in this environment: installation acceptance is the largest unverified item.
2. The designated requirement for non-Apple chains is emitted like `codesign` does for them; for Apple-issued
   certificates the standard `anchor apple generic and certificate leaf[...]` form must be generated instead.
3. Large IPAs: hashing and rewriting in memory; needs streaming and the zip writer.
4. Keys are extractable at OS level (section 3).
5. Third-party signed certificates and profiles can be revoked at any time by Apple; nothing here changes that,
   and no anti-revoke mechanism is in scope.


## 11. Per-bundle provisioning profiles (implemented, experimental)

`BundleSigner.sign(appDirectory:identity:certificateTeamID:profiles:options:)` takes a `ProfileSet`: a pool of
candidate profiles plus optional per-bundle pins (`"."` is the main app, otherwise the path relative to the app).
The older single-profile entry point remains and routes through the same selector; all 16 original signing tests
passed unchanged against the new code before anything was added.

For every application, extension and nested app (frameworks and dylibs take no profile):
1. Each candidate is checked, in order: lists the signing certificate; team equals the certificate's team; not
   expired at `options.now`; platform is iOS; application identifier permits the bundle's final identifier;
   (policy `.reject` only) grants every requested entitlement.
2. Among compatible candidates the engine prefers fewest unmet requested entitlements, then most specific
   application identifier (exact, then `TEAM.prefix.*`, then `TEAM.*`), then latest expiry, then UUID, so the choice
   is deterministic and independent of input order.
3. A pinned profile is checked and never replaced by another.
4. Failure raises a specific error before any file is modified: `appIdentifierMismatch`, `profileDoesNotListCertificate`,
   `profileTeamMismatch`, `profileRejected(bundle, profile, reason)` (single candidate), or
   `noCompatibleProfile(bundle, id, reasons)` listing one reason per candidate.
5. `SigningResult.profileSelections` records the choice and every rejected candidate with its reason.

Entitlements: identity keys come from the profile; a requested entitlement is kept only if the profile has the key
and every requested list member is permitted (exact or trailing `*`); booleans need the profile to be true; an entitlement
the profile grants but the app did not request is never added (tested). `keychain-access-groups` are moved onto the
profile team. Policy `.dropAndWarn` (default) removes what is not granted and reports it; `.reject` refuses the profile.

## 12. Known limitations (complete list)

Device and platform
- No real-device test has been run. Acceptance by AMFI, profile trust on device, entitlement approval and certificate
  revocation status are unknown. **Do not describe this engine as device-compatible.**
- No installation path exists (separate milestone, itms-services or other).

Signing format
- Thin 64-bit arm64 Mach-O only. Fat binaries are rejected (not signed per slice).
- SHA-256 CodeDirectory only. Apple's own App Store signatures carry SHA-1 and SHA-256 (`Hash choices=sha1,sha256`,
  CodeDirectory 0x20500 observed on a real App Store binary); current Xcode output for an iOS 15 target is
  SHA-256 only. Apple documents the dual-hash rule only for macOS (TN3126: deployment-target driven). The iOS cutoff is not
  documented; support for iOS versions before SHA-256 CodeDirectories is unverified.
- Requirements blob is emitted in the form `codesign` uses for non-Apple chains (`identifier ... and certificate root = H"..."`).
  For Apple-issued certificates Apple's own output is `anchor apple generic and certificate leaf[...] ...`; that
  form is not generated, and no Apple-issued development certificate was available to compare. Effect on
  device acceptance unknown.
- RSA keys only (PKCS#1 v1.5, SHA-256). No ECDSA identities.
- No timestamp, no `LC_CODE_SIGNATURE` placed when the header lacks 16 spare bytes (reported as an error),
  signature must already be last in the file.
- Resource rules are the default iOS rule set; custom `ResourceRules`/`CodeResources` rules in the original are ignored.
- No handling of `Info.plist` cross-references when rewriting identifiers (`WKCompanionAppBundleIdentifier`,
  `NSExtension` attributes, URL types, associated domains, app groups).
- Application bundles containing code outside the known container directories are not discovered.

Processing and scale
- Whole files are read into memory. Measured: a 450 MB synthetic app (300 MB resource, 150 MB padded binary) signed in
  7.6 s with ~613 MB peak resident memory (release build). Multi-gigabyte apps are not viable without streaming.
- Archive writing and extraction use system `zip`/`unzip` in the prototype CLI only. No native zip writer, no zip64,
  no preservation of POSIX permissions or symlinks through IPAKit.
- No cancellation, no progress reporting.

Verification
- macOS `codesign` is the only independent verifier. `SignatureVerifier` is a self-check that shares our understanding
  of the format; it agrees with `codesign` on the tested scenarios but is not a substitute.
- Profile signature checks use public APIs only (section 8) and cannot reproduce Apple's private policy.
- Key material: keys imported from `.p12` are extractable at OS level (section 3).

Input robustness
- Mach-O parser: a fuzz test (3000 corrupted headers, seeded) crashed the first version of the parser (trap on
  malformed segment commands); fixed with explicit size and range checks and now covered by regression tests.
  This is a bounded fuzz, not exhaustive: zip, plist and DER parsers were hardened earlier but are not fuzzed to the
  same depth.
- Plists and entitlement values of unusual types are rejected rather than coerced.

## 13. Investigation results for production readiness

| Topic | Finding | Status |
|---|---|---|
| Apple-issued chains / designated requirements | Real App Store binary: `anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.3] /* exists */ and identifier "..."`, chain Apple iPhone OS Application Signing > Apple iPhone Certification Authority > Apple Root CA, CodeDirectory 0x20500 with SHA-1 and SHA-256. Development-certificate form not observed. | Observed (distribution); development unverified |
| Fat Mach-O | Rejected cleanly (tested). Needs per-slice signing with the fat header's offsets and alignment rebuilt; slice order and `arm64e` handling to be designed. | Not implemented |
| Header padding | Missing room for the load command is detected and refused with a specific error (tested with a synthetic binary). Real-world frequency unknown. Mitigation would be repacking, risky. | Detected, not solved |
| SHA-1 | See limitations. Needed only if the minimum iOS version predates SHA-256 CodeDirectory support; not established for iOS. | Open |
| Large IPA / archive writing | Measured above. Needs streaming hash and a native zip writer (stored + deflate, zip64, modes, symlinks). | Open |
| Independent verification | `codesign` (macOS) and `openssl cms` verify; `SignatureVerifier` self-check (macOS and iOS simulator). | Done for prototype scope |
| Malformed input | Mach-O fuzzed, a real crash found and fixed. Zip/DER/plist paths covered by targeted tests. | Partial |

## 14. Separate results (restated)

Archive integrity (IPAKit), code-signature consistency (macOS `codesign`; self-check elsewhere), profile structure,
profile trust (`ProfileTrust`) and installation eligibility are independent results and are reported separately.
The last one is not determinable without a device.


## 15. Audit of b6d8f1d (2026-10-13): confirmed defects and fixes

Method: read the whole signing path, wrote a regression test for each suspected defect, ran them against the
unmodified code, then fixed. Every row below failed before the fix and passes after; the test names are in
`Tests/SigningKitTests/AuditRegressionTests.swift`.

| # | Defect (observed behaviour on the old code) | Fix |
|---|---|---|
| 1 | A symlinked `embedded.mobileprovision` was written through: a file outside the app grew from 12 to 4373 bytes | preflight refuses symlinks that leave the app or sit on files the signer writes |
| 2 | A symlinked executable was rewritten through the link (72544 to 75448 bytes outside the app) | same preflight |
| 3 | FairPlay-encrypted binary (cryptid 1) was signed without error, producing an app that cannot run | `LC_ENCRYPTION_INFO(_64)` detected; refused before any write |
| 4 | Bytes following the existing signature were silently deleted when `__LINKEDIT` happened to end at the signature | signature must end at end of file, else refuse |
| 5 | A Mach-O outside bundle executables and container dylibs was left unsigned and the run reported success | preflight refuses it, naming the path; verifier flags it |
| 6 | An expired or not-yet-valid signing certificate was not checked (only the profile was) | checked first, specific errors |
| 7 | Profile CMS signature status was not reported with the selection | `ProfileSelection.signatureStatus` (never promoted to trusted) |
| 8 | A requested entitlement of `false` produced a warning and needed a grant | `false` needs no grant |
| 9 | Renaming the main bundle id left `WKCompanionAppBundleIdentifier` and `WKAppBundleIdentifier` pointing at the old id | cross-references follow renames |
| 10 | Verifier accepted any container with extra, duplicate or out-of-range slots as long as the checked slots matched | only slots 0, 2, 5, 7, 0x10000, each once, each inside the signature |
| 11 | Verifier did not check CodeDirectory length, `execSeg` against `__TEXT`, `__LINKEDIT` coverage, signer identity | added; `expectedSignerSHA1` makes a wrong signer a failure |
| 12 | CLI printed the output path without checking what it wrote | CLI inspects the archive, re-extracts it, runs the self-check, exits non-zero on failure |

Verifier correctness review (items where it could have accepted a bad signature): 10 and 11 above were real gaps
in what it checked; nothing in the audit showed it accepting a tampered page, resource, nested binary or CMS
(those were already covered and cross-checked against `codesign`). It still cannot evaluate trust, revocation,
entitlement approval, or anything Apple's kernel enforces and we do not model. A signer identity is reported, not
judged, unless `expectedSignerSHA1` is supplied.

## 16. Real-device readiness

See `2026-10-13-real-device-test-plan.md`. Blockers and unknowns, none bypassed:
- No authorised development certificate and profile for this device are present; they must be created by the
  account owner (plan section 3).
- The device's developer disk image cannot be mounted by Xcode 27.0 against iOS 27.2 beta; effect on install
  and launch is unknown.
- Requirements-blob form for Apple-issued chains is untested against a real Apple development certificate.
- No real-device result exists. Device compatibility is not claimed.
