# R2 — final IPA artifact integrity

Base: `ff50f001f8ee768b5fe3cbd5835377bc563fd2b9` (R1 squash merge). Scope: archive identity, streaming I/O, final artifact validation and atomic promotion. No signing algorithms or credentials changed.

## Confirmed defects in the base

* `Sources/IPAKit/IPAArchiver.swift:55–60,181–201`: equal size plus CRC32 permitted original compressed data to replace different edited contents. Large entries additionally used modification time to avoid another CRC read. The deterministic 16-byte witnesses `9c1fe18a5db4786f3c5393b11f1280ec` and `ac12aa68ced7e488bdab66d91f1b366e` both have CRC32 `3112fecd`. Appending the same 2,097,153 zero bytes produces 2,097,169-byte witnesses with CRC32 `4534d269`.
* `Sources/SigningKit/IPASigner.swift:62–76`: the bundle self-check preceded packaging; the subsequent inspector read archive metadata, not every packaged executable/resource. Neither check established identity of packaged bytes with verified bytes.
* `Sources/IPAKit/IPAArchiver.swift:34`: writer allowed 65,535 entries, which `ZipArchive` interpreted as a ZIP64 sentinel. Filename and compressed-size narrowing also needed checked limits.
* `Sources/IPAKit/IPAArchiver.swift:16,172–177,189–195`: missing/corrupt source and I/O errors could silently become fallback compression or EOF. The writer opened its output directly, truncating any previous archive before successful completion.
* `Sources/IPAKit/IPAArchiver.swift:241–247`: precompressed copy did not check the copied length. The ZIP decoder needed exact compressed-input consumption and data-descriptor consistency for the new final gate to be authoritative.

### Severity and regression mapping

All references below are to the base commit unless explicitly marked as fixes.

| Severity | Original location | Failure / structural witness | Fix | Regression |
|---|---|---|---|---|
| P0 | `IPAArchiver.swift:55–60,181–201` | The two colliding byte sequences above satisfy the old reuse predicate despite differing contents; both small and large edited assets can be replaced by old bytes. | `IPAArchiver.swift:39,157–166`; `ArchiveIntegrity.swift:30–57` | `ArchiveIntegrityTests.testSmallCRCCollisionDoesNotRestoreOldBytes`, `testLargeCRCCollisionDoesNotRestoreOldBytes`, stored and legacy-call variants |
| P0 | `IPASigner.swift:62–76` | Successful work-tree verification followed by unchecked packaging does not authenticate the published artifact. | `IPASigner.swift:61–73`; `ArchiveIntegrity.swift:131–156`; `IPAArchiver.swift:129–132` | `IPASignerTests.testMutationAfterSelfCheckCannotReachPublishedIPA` (executable and CodeResources); altered candidate, post-check and post-pack tree mutations |
| P1 | `IPAArchiver.swift:77–83` | Opening the requested destination before successful write/validation destroys its previous contents. | Sibling staging at `IPAArchiver.swift:70–79`, promotion at `ArchiveIntegrity.swift:178` | Candidate validation, promotion, corrupted/truncated source, and output-preservation regressions |
| P1 | `IPAArchiver.swift:34,155,226,241–247` | ZIP64 entry-count sentinel accepted by writer, unchecked narrowing and incomplete precompressed copies. | `ArchiveIntegrity.swift:159–174`; `IPAArchiver.swift:208–218` | `testClassicZIPBoundariesRejectSentinelsBeforeOutputMutation` reads a real 65,534-entry archive, rejects 65,535 and protects an existing output; integer/name boundary and short-read tests |
| P1 | `IPAArchiver.swift:16,172–177,189–195` | Errors in opening a specified original or hashing files can become fallback compression / apparent EOF. | Explicit throwing source open, `FileFingerprint.read`, checked raw copies | Missing original, unreadable file, injected read/write errors, file growth and short EOF |

Additional ZIP gate requirements are enforced by `ZipArchive.swift:93–149,230–264`: exact raw-DEFLATE input consumption, local/central flags and data-descriptor consistency. Tests construct a valid-length DEFLATE payload with an extra byte and a descriptor with a changed CRC, and require controlled rejection. These changes do not make claims about how every external extractor treats malformed ZIPs.

## Design and guarantees

`IPAArchiveSession` retains one open original archive across inspection, extraction and reuse. Extraction computes SHA-256 of both plaintext and compressed input during existing streaming reads. Opaque inventory provenance binds those fingerprints to that session and extraction directory. Replacing a source pathname cannot substitute a different inode; in-place compressed-byte changes are detected while copying reused entries. Legacy URL-only archiver calls validate and hash original entries before reuse. Missing/unreadable specified originals fail explicitly; a genuinely absent entry can safely be compressed from the working tree.

`IPAArchiveManifest` captures the exact Payload path set, regular-file SHA-256/size/CRC, file and directory permission bits, kinds and symlink targets. The signer captures it before its bundle self-check. Writer streams compute SHA-256 again while compressing or storing changed files; reused entries require matching cryptographic fingerprints. Dates are never evidence of identity.

Every candidate is written to a private sibling of the destination. After optional metadata inspection, a fresh ZIP reader streams every actual packaged entry and checks contents, metadata and exact path membership against the manifest. It then rechecks the current working tree against the same manifest. Only then does a same-directory POSIX rename atomically replace the destination. Any preceding failure removes the candidate and compression scratch files without deleting or truncating the previous output.

The ZIP decoder uses the platform system zlib API for exact raw-DEFLATE consumption (`Z_STREAM_END`, `avail_in`, `total_in`), checks CRC/size and rejects trailing compressed bytes. Both signed and unsigned classic data descriptors are checked against the central record. Existing extraction path/symlink protections remain in place. ZIP64 is deliberately unsupported: max entry count 65,534, max size/offset/archive length 4,294,967,294, filename length 65,535 bytes, and the existing 64 MiB central-directory cap.

## Compatibility and cost

Valid supported thin/fat signing behavior is unchanged. New controlled rejections include inconsistent ZIP descriptors, trailing raw-DEFLATE input, ZIP64 sentinels, unrepresentable metadata, special permission bits, changed verification snapshots and unreadable specified reuse sources. Previously accepted malformed or integrity-ambiguous inputs are intentionally rejected. Symlink permission metadata is normalized to conventional `0120777`; file/directory rwx bits are preserved.

No extra extracted copy of the output is needed. Hashing runs in bounded 256 KiB chunks, with per-entry digests and manifest records. Extraction adds two SHA streams during existing I/O. Normal signing adds an intended-tree hash pass, a final archive decode/hash pass, and a final tree hash pass. Unchanged assets avoid recompression and original re-inflation via the extraction inventory. Changed large files retain parallel compression and its existing scratch-space costs. A complete sibling candidate must fit on the output volume; the prior output remains until rename. Memory is proportional to entry metadata plus per-worker buffers, not total IPA size.

The private job directory and staging directory remain within Wax's sandbox trust boundary. This does not claim filesystem transactions against a malicious process with arbitrary same-UID write access, crash-durable fsync publication, Apple provisioning/trust approval, or physical-device installation/launch. An internal signature check remains distinct from Apple's installation decision.

## Verification

Implementation commit `c67f7678aee6150eca0eb7ce508dcda0dbf972d3` passed [macOS CI 39197766601](https://github.com/dylldev/wax-signer/actions/runs/39197766601):

| Actual command / check | Result |
|---|---|
| `swift test` on `macos-26` | 540 tests, 13 skipped, 0 failures (527 passed); includes all 23 new archive-integrity cases, the signing mutation regression and R1 regressions. |
| Re-extract + `/usr/bin/codesign --verify --deep --strict -vv` | `IPASignerTests.testOutputPassesAppleCodesignAfterNativeRepack` passed; this independently checks the re-extracted fixture with Apple's verifier. |
| Existing `/usr/bin/zip` / `/usr/bin/unzip -tq` interoperability fixtures | Passed in the package suite. |
| `python3 -m unittest discover -s Server/wax-ota -p 'test_*.py'` | 45 passed. |
| `python3 -m unittest discover -s Source -p 'test_*.py'` | 3 passed. |
| `bash scripts/test_make_install_cert.sh` and `bash scripts/test_publish_prep.sh` | Passed (11 and 8 script assertions). All certificate tests use temporary test material and fake ACME, with no production credential access. |
| `xcodegen generate`; `xcodebuild -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` | `BUILD SUCCEEDED`. |
| `xcodebuild test -project LocalIPASigner.xcodeproj -scheme LocalIPASigner -destination 'id=<available iPhone simulator>' CODE_SIGNING_ALLOWED=NO` | `TEST SUCCEEDED`: separate bundles of 74 tests / 8 skips and 166 tests / 3 skips, all with zero failures. This is the existing scheme's simulator coverage, not all 540 package cases. |

The 13 package skips are eight Keychain cases requiring entitlements unavailable to the test host, two optional real-profile cases (`PROFILE_PATH`), one optional real IPA (`IPA_PATH`), one configured live OTA server and one user-supplied large IPA performance case (`WAX_PERF_IPA`). No new integrity regression was skipped. Simulator skips likewise concern Keychain/environment-dependent fixtures. No physical iPhone installation or launch was observed.

Local Linux verification used the existing offline Docker image `swift:6.2.3-jammy`:

```sh
# Prefix Docker commands here with the session's local daemon socket:
env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
  docker --host=unix:///var/run/docker.sock run --rm --network none \
  -v /workspace:/workspace -w /workspace/wax-signer swift:6.2.3-jammy \
  python3 scripts/test_parser_safety.py
```

Result: **33 isolated portable Swift parser cases passed, 0 failed**. Swift frontend syntax parsing of changed source/test files also passed. This is not Apple-framework integration verification; Linux has no Xcode/Apple SDK/Simulator and does not supply the full package's Apple `Security`, `Compression` and `CryptoKit` modules. The full package/build/simulator evidence comes from macOS CI above.

The Python server/source commands also passed locally (45 + 3). `test_publish_prep.sh` passed all 8 assertions. The first local certificate-script run failed its account-creation assertion because this Linux image lacks `uuidgen`; rerunning with the equivalent exported shell utility `uuidgen() { python3 -c 'import uuid; print(uuid.uuid4())'; }; export -f uuidgen` passed all 11 assertions. No repository test was altered for that host limitation; macOS ran the original script with its native utility. `git diff --check` passed.

The follow-up commit strengthens the unchanged-compressed-entry fixture: a deterministic raw-DEFLATE stream made of stored blocks differs from Wax's normal encoder output. Byte equality therefore proves reuse, rather than allowing a deterministic recompression to pass accidentally. It also strengthens the writer's sentinel-error assertion and records these results. [PR #2](https://github.com/dylldev/wax-signer/pull/2) carries the CI result for that final head; the implementation behavior is unchanged by this test/report follow-up.

### Measured observation

One warm-cache, debug Swift package run on the macOS CI host, using the reproducibly generated **8 MiB mixed-compressibility** asset in `testArchiveTimingObservation`:

| Operation | Seconds |
|---|---:|
| Capture/hash intended manifest | 0.0525 |
| Compress + final archive/tree gates | 0.3568 |
| Extract + capture extraction fingerprints | 0.0598 |
| Reuse + final archive/tree gates | 0.1777 |

The archive was 2,159,571 bytes. These are single-run observations for this fixture, not a statistical benchmark, a comparison against pre-R2 performance, a measurement of large real-world IPAs, or an iPhone speed claim. Peak resident memory, energy, thermal impact and device latency were not measured. Buffer sizes and scratch-space costs above are code-derived estimates. Device testing should include small, medium and multi-gigabyte apps, unchanged and substantially edited assets, near-full storage and background expiration, while confirming final artifact hashes and installation/launch independently.

## Changed files

| Path | Purpose |
|---|---|
| `Sources/IPAKit/ArchiveIntegrity.swift` | Open archive sessions, opaque extraction provenance, streaming fingerprints, intended-tree manifests, final ZIP comparison and checked promotion/limits. |
| `Sources/IPAKit/IPAArchiver.swift` | SHA-based reuse, checked streaming writes/copies, validated sibling staging and atomic publication. |
| `Sources/IPAKit/IPAExtractor.swift` | Reuse the session reader and return extraction provenance; preserve the existing path, link and parallel extraction protections. |
| `Sources/IPAKit/IPAInspector.swift` | Inspect an already-open reader and expose an actionable artifact-integrity error. |
| `Sources/IPAKit/ZipArchive.swift` | Stream exact DEFLATE decoding and hashes, authenticate compressed copies, validate descriptors and metadata boundaries. |
| `Sources/SigningKit/IPASigner.swift` | Share the source session, snapshot before self-check and publish only through the final artifact gate. |
| `Tests/IPAKitTests/ArchiveIntegrityTests.swift` | 23 deterministic integrity, I/O, metadata, boundary, compatibility and timing tests. |
| `Tests/IPAKitTests/ArchiveRoundTripTests.swift` | Missing specified source now requires explicit failure and preservation, instead of silent fallback. |
| `Tests/IPAKitTests/ZipFixture.swift` | Allow deliberate external-attribute inconsistencies and deterministic raw-DEFLATE streams in adversarial/reuse fixtures. |
| `Tests/SigningKitTests/IPASignerTests.swift` | Reject executable and CodeResources changes after self-check without replacing the previous signed IPA. |
| `docs/audits/2026-10-19/R2-IMPLEMENTATION.md` | Evidence, design, verification and limitations. |

## CI correction

The first macOS run, [39197546029](https://github.com/dylldev/wax-signer/actions/runs/39197546029), compiled but exposed a new manifest traversal defect: Foundation enumeration returned `/private/var/...` paths while the containment comparison used another spelling of the temporary directory. The fix canonicalizes both parents while retaining each entry's own symlink name, following the previously working archiver's approach. The comparison is still mandatory. A symlinked-root regression and the existing normal temporary-directory fixtures cover this behavior. The subsequent complete macOS package/build/simulator run passed, as recorded above. No test or security check was disabled.
