# Third-party notices

## Shipped code

None. The app and its modules (`IPAKit`, `CredentialKit`, signing prototype) depend only on
Apple system frameworks (Foundation, Security, CryptoKit, Compression, SwiftUI), which are not redistributed.

## Embedded data

- **Apple public certification authority certificates** (WWDR G3 and G6, Apple Root CA, Apple Root CA - G2 and G3)
  are embedded as data in `Sources/SigningKit/AppleCertificateAuthorities.swift` to complete signing
  certificate chains. They are public certificates issued by Apple Inc. and contain no private material.

## Not adopted

- **zsign** (MIT) and **OpenSSL** (Apache-2.0): reviewed in
  `docs/superpowers/specs/2026-10-11-ipa-signer-design.md`, not used. No zsign or OpenSSL code is present.
  zsign was read as a behavioural reference only; its `src/common/json.*` files were not used.

## Development-time tools (not distributed)

| Tool | Licence | Use |
|---|---|---|
| XcodeGen | MIT | generates the Xcode project from `project.yml` |
| Python `cryptography` | Apache-2.0 / BSD-3-Clause | `Tests/CredentialKitTests/generate_fixtures.py`, creates throwaway test credentials |
| OpenSSL CLI | Apache-2.0 | same script, creates a BER CMS test profile |
| Apple `codesign`, `security`, `unzip`, `zip` | Apple system tools | verification and archive handling in the prototype |

## Test fixtures

All certificates, keys and profiles under `Tests/` are generated, self-signed and throwaway.
They are not Apple-issued and carry no real credentials.
