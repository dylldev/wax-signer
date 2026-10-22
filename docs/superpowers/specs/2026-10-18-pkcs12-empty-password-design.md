# Safe empty-password handling for modern PKCS#12 imports

Status: draft for review, 2026-10-18.

## Intent

Prevent Wax from crashing when it imports a supported modern PKCS#12 file whose password is empty. A certificate file selected by the person using Wax must not be able to trigger a force-unwrap crash in the password derivation path.

## Current behavior

`Sources/CredentialKit/PKCS12Modern.swift` verifies the file MAC before decrypting its contents. If the password is empty and the file uses PBES2, the PBKDF2 path creates an empty UTF-8 byte array and force-unwraps its optional `baseAddress`. An empty array may have no base address, so this input can terminate the process before Wax returns an import result.

## Proposed change

- Make the pointer passed to CommonCrypto valid for both empty and non-empty passwords while preserving the exact UTF-8 password byte count.
- Keep the existing accepted algorithms, iteration limits, password matching, import result, and error behavior unchanged.
- Add a small committed fixture containing a valid modern PBES2 PKCS#12 file with an empty password, then assert that parsing returns `.legacyEquivalent` with its certificate and key. Generate the fixture ahead of time; tests must not depend on OpenSSL being installed.

## Scope

Only the modern PKCS#12 password-to-PBKDF2 buffer handling and its regression coverage are included. No certificate/profile trust policy, key storage, user-facing import flow, other parsers, release metadata, or 0.14.1 release steps change.

## Verification

1. Add the empty-password PBES2 fixture and regression test first; confirm the test fails on the current force-unwrap path.
2. Run `swift test` and confirm all non-skipped tests pass.
3. Build the iOS app for the simulator.
4. Confirm the existing non-empty modern PKCS#12 fixture still matches its expected result.

The test and simulator build cannot prove that a certificate installs on a real iPhone. The separate 0.14.1 device-test gate remains in place.
