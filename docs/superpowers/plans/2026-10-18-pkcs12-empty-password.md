# PKCS#12 Empty-Password Crash Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent a valid modern PKCS#12 file with an empty password from crashing Wax during PBES2 decryption.

**Architecture:** Add a committed, test-only modern PKCS#12 fixture encrypted with an empty password and exercise it through `ModernPKCS12.assess`. Replace the potentially nil empty-array pointer passed to CommonCrypto with the non-null C string pointer provided by Swift, preserving the explicit UTF-8 byte length. Keep all password verification and cryptographic choices unchanged.

**Tech Stack:** Swift, Swift Package Manager, XCTest, CommonCrypto, OpenSSL (fixture generation only).

---

### Task 1: Add an empty-password PBES2 regression fixture and failing test

**Files:**
- Create: `Tests/CredentialKitTests/Fixtures/empty-password-pbes2.p12`
- Modify: `Package.swift`
- Modify: `Tests/CredentialKitTests/PKCS12ModernTests.swift`

- [ ] **Step 1: Generate a test-only key, certificate, and PBES2 PKCS#12 fixture**

Run from the repository root:

```bash
fixture_dir="$(mktemp -d /tmp/wax-empty-p12.XXXXXX)"
mkdir -p Tests/CredentialKitTests/Fixtures
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -subj "/CN=Wax Test Empty Password" \
  -keyout "$fixture_dir/key.pem" \
  -out "$fixture_dir/cert.pem"
openssl pkcs12 -export \
  -inkey "$fixture_dir/key.pem" \
  -in "$fixture_dir/cert.pem" \
  -out Tests/CredentialKitTests/Fixtures/empty-password-pbes2.p12 \
  -passout pass: \
  -keypbe AES-256-CBC \
  -certpbe AES-256-CBC \
  -macalg sha256
openssl pkcs12 -info -noout \
  -in Tests/CredentialKitTests/Fixtures/empty-password-pbes2.p12 \
  -passin pass:
rm -rf "$fixture_dir"
```

Expected: OpenSSL reports PBES2/AES-256-CBC and MAC verification succeeds with the empty password. This command is only for creating the checked-in test fixture; tests do not invoke OpenSSL.

- [ ] **Step 2: Include the fixture in the CredentialKit test bundle**

In `Package.swift`, change the CredentialKit test target to:

```swift
.testTarget(name: "CredentialKitTests", dependencies: ["CredentialKit"],
            exclude: ["generate_fixtures.py"], resources: [.copy("Fixtures")]),
```

- [ ] **Step 3: Add the failing parser regression test**

Add this method to `PKCS12ModernTests`:

```swift
func testReencodesModernPBES2FixtureWithEmptyPassword() throws {
    let url = try XCTUnwrap(Bundle.module.url(
        forResource: "empty-password-pbes2", withExtension: "p12", subdirectory: "Fixtures"))
    let fixture = try Data(contentsOf: url)
    guard case .legacyEquivalent(let legacy) = ModernPKCS12.assess(fixture, password: "") else {
        return XCTFail("expected the empty-password fixture to be re-encoded")
    }
    XCTAssertFalse(legacy.isEmpty)
}
```

- [ ] **Step 4: Run the focused test and confirm the current crash**

Run: `swift test --filter PKCS12ModernTests/testReencodesModernPBES2FixtureWithEmptyPassword`

Expected before the fix: runtimes that provide a nil base address for an empty buffer may crash at the force unwrap. On this runner, Swift provides a non-null base address for an empty array, so the test may pass before the fix; record that actual result. The code change removes reliance on that runtime behavior.

### Task 2: Pass a valid pointer for empty and non-empty passwords

**Files:**
- Modify: `Sources/CredentialKit/PKCS12Modern.swift`
- Test: `Tests/CredentialKitTests/PKCS12ModernTests.swift`

- [ ] **Step 1: Replace the empty-array pointer force unwrap**

In the PBES2 branch of `decrypt`, replace the `pw.withUnsafeBufferPointer` wrapper with:

```swift
let passwordByteCount = password.utf8.count
let rc = password.withCString { passwordPointer in
    kp[0].content.withUnsafeBufferPointer { sp in
        key.withUnsafeMutableBufferPointer { kptr in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passwordPointer, passwordByteCount,
                                 sp.baseAddress, sp.count, prf, UInt32(iter), kptr.baseAddress, size)
        }
    }
}
```

Keep the existing `guard rc == kCCSuccess` and decryption logic. `withCString` supplies a valid pointer for the zero-length case; `passwordByteCount` ensures the terminating NUL is not included in the PBKDF2 password.

- [ ] **Step 2: Run the focused regression test**

Run: `swift test --filter PKCS12ModernTests/testReencodesModernPBES2FixtureWithEmptyPassword`

Expected: PASS; the valid empty-password fixture returns `.legacyEquivalent` instead of terminating the test process.

- [ ] **Step 3: Recheck the existing modern and wrong-password cases**

Run: `swift test --filter PKCS12ModernTests`

Expected: all `PKCS12ModernTests` pass, including the existing non-empty modern fixture and wrong-password tests.

### Task 3: Run full verification and commit the fix

**Files:**
- Verify: `Package.swift`
- Verify: `Sources/CredentialKit/PKCS12Modern.swift`
- Verify: `Tests/CredentialKitTests/PKCS12ModernTests.swift`
- Verify: `Tests/CredentialKitTests/Fixtures/empty-password-pbes2.p12`

- [ ] **Step 1: Run all package tests**

Run: `swift test`

Expected: all non-skipped tests pass with no failures.

- [ ] **Step 2: Build the unsigned iOS app**

Run: `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Review the diff and check for whitespace errors**

Run: `git diff --check && git diff --stat`

Expected: only the PKCS#12 implementation, its fixture/test wiring, and regression test are changed.

- [ ] **Step 4: Commit the verified fix**

```bash
git add Package.swift Sources/CredentialKit/PKCS12Modern.swift \
  Tests/CredentialKitTests/PKCS12ModernTests.swift \
  Tests/CredentialKitTests/Fixtures/empty-password-pbes2.p12
git commit -m "Fix empty-password PKCS12 import crash"
```

Do not build or publish a 0.14.1 release as part of this plan. Keep its real-iPhone install and timing test as a separate release gate.
