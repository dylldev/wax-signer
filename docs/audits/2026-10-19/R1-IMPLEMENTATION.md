# R1 — Defensive binary parsing implementation

Date: 2026-10-19. Repository: `dylldev/wax-signer`.
Baseline inspected: `a620d9d5e268ed7d0ea292a0af63a4c948efc760`.
Task branch: `codex/r1-parser-hardening`.

**Status: Implemented but verification incomplete.** The Foundation-only production parsers pass executable Swift regressions on Linux. Full Apple-framework compilation, signing, independent verification, installation and launch have not been verified. The initial checkout matched the audit baseline. Existing untracked audit artifacts were left outside this implementation commit.

## Implementation summary

- Mach-O parsing validates the declared command region, aligned command sizes, consumed fixed records and strings, section/segment containment, VM overflow, explicit platform/CPU metadata, entry points and signature placement. Existing section-table and duplicate-signature checks are preserved. Known LINKEDIT payloads, symbol/relocation tables and sections cannot overlap the signature being removed. LINKEDIT must be the final file-backed segment.
- Header insertion requires bounded, zero-filled padding before known file data. A missing section table no longer implies unlimited padding. Signature preparation validates sizes, narrowing conversions, alignment and resulting VM extent before changing bytes. It commits a local candidate and its bookkeeping together. Attachment returns a controlled size/invariant error rather than trapping.
- Universal parsing validates the complete architecture table, every slice's containment/alignment, overlap and duplicate architectures. Selection remains arm64 before arm64e. The selected slice must parse successfully and match the outer CPU/subtype exactly. Tree thinning stages validated outputs on disk before replacing any input.
- Signature layout validation proves SuperBlob logical boundaries, unique/disjoint indices, complete blobs and CodeDirectory hash/string geometry before any hash-table read. BlobReader uses the same container validation. The verifier still reports local consistency only; it does not establish Apple trust or installability. CMS must occupy one complete DER SEQUENCE before the existing bounded ASN.1/CMS reader runs.
- Debian ar/TAR geometry is separated from Apple decompression into a small Foundation-only implementation. Decimal/octal fields reject signs and invalid encodings; BSD names, complete headers, member padding, TAR checksums/body padding/end markers and GNU long names are checked. Gzip checks optional-field boundaries, reserved flags, optional header CRC, output CRC and ISIZE. Inflation checks progress, consumption and output bounds.
- Library injection parses supported unencrypted library code before replacing libraries or modifying the host. No credentials, distribution feeds, infrastructure, UI or signing cryptography changed. No package dependencies were added.

## Entry paths and validation retained

`IPASigner` extracts into its workspace, then `BundleSigner` preflights code through `FatMachO.thin` and `MachO` before planning/signing. `signExecutable` prepares a probe, builds the signature size, prepares the final image, attaches the signature and writes it. The only attachment call site now propagates the controlled error.

`LibraryInjector` parses the host, validates supplied dylibs/framework executables or dylibs extracted from Debian packages, builds load commands in memory, then copies files and writes the host. `DebExtractor` parses the entire ar archive, decompresses the selected data member, parses the entire TAR, then creates/writes output files. `SignatureVerifier.verifyExecutable` parses the Mach-O and signature geometry before evaluating hashes/CMS.

Preserved checks include the 32-byte Mach-O header minimum, little-endian 64-bit magic, section count bounded by segment-command size, duplicate signature rejection, trailing-signature requirement for replacement, unsupported fat64/swapped formats, no encrypted app signing, existing decompression/file limits, and basename-only Debian output. Load-command counts already generally caused an eventual rejection in the original parser; the improvement is reading their headers inside `sizeofcmds`, not a claim that every excess count previously crashed.

## Verified defects and witnesses

Original line references below refer to the baseline commit, not the patched line numbers. Severity describes the confirmed impact; P0 is the roadmap's task priority. No arbitrary code execution or external file disclosure was demonstrated.

| Severity | Original location | Failure mechanism and evidence | Fix location | Regression |
|---|---|---|---|---|
| High | `Sources/SigningKit/MachO.swift:15`, `:183`, `:186`; library insertion `:140` | With no sections, padding bound remained `Int.max`. A 104-byte header plus sectionless LINKEDIT parsed, then insertion replaced `104..<120` outside the Data. Original production MachO compiled unchanged in an isolated Linux Swift process: exit 132 / signal 4. | `MachO.swift:51` parser, bounded padding helper and `prepareForSignature` | `ParserSafetyTests.testOriginalMinimalCrashWitnessesAreRejected`, `testSectionlessImageCannotInventHeaderPadding`, `testNonzeroHeaderPaddingAndBadSizesCannotMutateImage` |
| High | `Sources/SigningKit/MachO.swift:89`, `:175`, `:181`, `:197` | Signature placement was bounded only by file size. A 120-byte image with a signature covering bytes `0..<120` parsed, removed all bytes, then patched the deleted header. Original production MachO isolated process: exit 132 / signal 4. Negative/oversized API signature sizes also reached narrowing conversions; some later failures occurred after mutation. | MachO signature/data-overlap checks; transactional preparation and checked attachment | `testSignatureMustNotOverlapHeaderTextOrOtherLinkeditData`, `testOriginalMinimalCrashWitnessesAreRejected`, `testNonzeroHeaderPaddingAndBadSizesCannotMutateImage`, `testTrailingSignatureFailureLeavesDataIntact`, `testAttachSizeMismatchIsControlledAndDoesNotMutate` |
| High | `Sources/SigningKit/SignatureVerifier.swift:172`, `:187`, `:192` | Page geometry could fail yet special-slot evaluation continued. `hashOffset=0xffffffff`, `nSpecial=7` passed the special reader's lower-bound-only check and sliced far beyond an 88-byte CD. The original **unchanged special-reader function**, extracted into a Foundation harness, exits 132 / signal 4. This is not execution of the full Apple-dependent verifier. LINKEDIT addition also trusted unchecked UInt64 geometry. | `SignatureLayout.CodeDirectory`; verifier early rejection and upper-bound check; bounded Mach-O segment ranges | `testValidCodeDirectoryAndInvalidHashTables`; Apple integration test `SignatureVerifierMalformedTests.testInvalidCodeDirectoryTablesProduceFailedReports` |
| Medium | `Sources/SigningKit/SignatureVerifier.swift:131`, `:138`, `:142`; `BlobReader.swift:17` | Container length could be smaller than the index/blob structures while bounds were checked against the containing allocation. Blob overlap was not rejected; entitlement reading did not share container/duplicate checks. A declared 12-byte SuperBlob with indices physically present after byte 12 is a structural witness. | `SignatureLayout.slots`; both consumers use the same validated layout. Ranges are sorted before blob copies to avoid quadratic overlap checks or aliased allocation amplification. | `testEmbeddedSignatureDeclaredBoundaryIndicesAndBlobs`; `SignatureVerifierMalformedTests.testMalformedContainerIndicesAndBlobLengthsProduceFailedReports` |
| Medium | `Sources/SigningKit/FatMachO.swift:33`, `:36`, `:37`, `:41` | `align` was not even read, nonselected slices were not range-checked, and overlap/table aliasing or outer/inner CPU mismatch was accepted. Small table fixtures with alignment 32, overlapping aligned slices or arm64e outer/arm64 inner metadata demonstrate these missing checks. | `FatMachO.thin` | `testFatTableContainmentAlignmentOverlapAndMetadata`, `testValidUniversalArchitecturePreferenceAndArm64e` |
| Medium | `Sources/SigningKit/FatMachO.swift:58`, `:72`; `LibraryInjector.swift:69` | Tree prepass rejected only unsupported fat magic; a later malformed fat table could fail after earlier replacements. Imported libraries were accepted by four-byte magic before destination replacement. Supporting evidence is the original control flow; deterministic regression asserts both tree files and host stay unchanged. | `FatMachO.thinTree` stages all outputs; `LibraryInjector.requireMachO` fully parses the selected library | `testMalformedLaterFatFileDoesNotRewriteAnySource`; `LibraryInjectorTests.testMalformedImportedLibraryDoesNotMutateTheHost` |
| High | `Sources/SigningKit/DebExtractor.swift:47`, `:48` | BSD name `#1/-1`, zero-size member: `-1 <= 0` passes, producing range `68..<67`. The original **unchanged arMembers function**, extracted into a Foundation harness, terminates with “Range requires lowerBound <= upperBound,” exit 132. | `DebArchive.arMembers`, strict unsigned numeric fields and containment before slicing | `testArNegativeBSDLengthsAndMalformedMembersAreRejected`; `DebExtractorTests.testMalformedArAndTarNeverCreateOutput` |
| Medium | `Sources/SigningKit/DebExtractor.swift:40`, `:54`, `:121`, `:123`, `:140` | Partial trailing ar headers, missing odd-member padding, partial TAR tails and absent TAR terminators could be silently accepted. TAR checksums were ignored and body rounding was not validated against available padded bytes. Existing small numeric-field widths/caps make a 64-bit arithmetic trap here **unproven**; do not confuse the truncation bug with demonstrated overflow. | `DebArchive.arMembers`, `tarFiles`, checked subtraction/rounding after containment | `testArNegativeBSDLengthsAndMalformedMembersAreRejected`, `testTarChecksumNumbersPaddingAndTermination`, `testSystemArTarAndGzipWrappersAreAccepted` |
| Medium | `Sources/SigningKit/DebExtractor.swift:79`, `:85`, `:86`, `:103` | Gzip optional fields were not independently confined before the trailer, CRC/ISIZE were discarded, and decoder END ignored unconsumed input. CRC and size mutations are explicit corruption witnesses. An infinite decoder loop was **not reproduced**; the no-progress guard is defensive. | `DebGzip.parse`, `Member.validate`, `DebExtractor.inflate` | `testGzipWrapperOptionalFieldsCRCAndLength`; Apple backend test `DebExtractorTests.testGzipCorruptionAndTrailingCompressedBytesAreRejected` |

CPU/file-type/platform rejection, complete fixed records/strings, CMS exact outer length and rewrite VM-overflow checks are additional defensive constraints, covered by named parser tests. The prior reader's permissive handling of unknown CPU/platform metadata is evident in the baseline; no unsupported binary installation was attempted. The existing ASN.1 reader already bounds recursion/length fields; it was inspected and left unchanged.

## Files changed

| Path | Purpose |
|---|---|
| `Sources/SigningKit/CheckedBytes.swift` | Small subtraction-based containment and big-endian fixed-record helper. |
| `Sources/SigningKit/MachO.swift` | Structural validation, bounded padding and transactional rewrites. |
| `Sources/SigningKit/FatMachO.swift` | Full architecture geometry, selected-slice validation and staged tree changes. |
| `Sources/SigningKit/SignatureLayout.swift` | Foundation-only SuperBlob, CD and outer CMS geometry. |
| `Sources/SigningKit/SignatureVerifier.swift` | Reject bad layouts before hashing; preserve failed reports and self-check trust distinction. |
| `Sources/SigningKit/BlobReader.swift` | Reuse signature-container validation for entitlements. |
| `Sources/SigningKit/DebArchive.swift` | Foundation-only ar/TAR/gzip wrapper checks. |
| `Sources/SigningKit/DebExtractor.swift` | Use validated containers; enforce decoder progress, consumption and gzip integrity. |
| `Sources/SigningKit/LibraryInjector.swift` | Validate actual supported library images before host/destination writes. |
| `Sources/SigningKit/BundleSigner.swift` | Propagate the now-throwing internal attachment operation. |
| `Tests/SigningKitTests/ParserSafetyTests.swift` | Deterministic hostile structures, integer boundaries, filesystem nonmutation and valid fixture/tool compatibility. |
| `Tests/SigningKitTests/SignatureVerifierTests.swift` | Full failed-report tests for hostile CD, container and CMS inputs without signing identities. |
| `Tests/SigningKitTests/DebExtractorTests.swift` | Full malformed-package no-write and gzip backend corruption tests. |
| `Tests/SigningKitTests/LibraryInjectorTests.swift` | Malformed library no-write regression; invalid string commands now explicitly reject. |
| `Tests/SigningKitTests/FatMachOTests.swift` | Correct synthetic CPU metadata and use a real valid early slice in tree rejection test. |
| `Tests/SigningKitTests/AuditRegressionTests.swift` | Keep encryption fixture range inside its actual file, preserving its encryption-rejection purpose. |
| `scripts/test_parser_safety.py` | Limited, dependency-free portable Swift harness with one subprocess per XCTest case. |
| `docs/audits/2026-10-19/R1-IMPLEMENTATION.md` | This evidence, compatibility and verification record. |

## Test results and reproducibility

The host has no Swift/Xcode/Apple SDK. A temporary Docker Swift toolchain was used: `swift:6.2.3-jammy`, Swift 6.2.3, Linux x86_64. Image digest: `sha256:33c73fc133767cdaafde26f0f9967c96ab25ff77618b7df1eabf46140bf2b6e6`. Test containers had networking disabled. The image is tooling, not an application dependency.

| Check | Result |
|---|---|
| `python3 scripts/test_parser_safety.py` with Swift available | **32 XCTest cases passed, 0 failed, 0 skipped**, each isolated in its own Swift test subprocess. Includes 24 new parser safety cases and all 8 existing MachOMalformedTests, including 3,000 seeded mutations. |
| Production parser compilation in that harness | Actual `MachO`, `FatMachO`, `CheckedBytes`, `SignatureLayout` and `DebArchive` compile/typecheck and execute. The existing SigningError enum is extracted unchanged from its Security-dependent file. No crypto/compression/parser mocks are used. The full SigningKit target is NOT built by this harness. |
| Valid fixtures | App, extension and framework parse, inject a load command, prepare/attach a dummy signature and reparse; original body bytes remain intact. Dummy attachment is geometry testing, not signature verification. |
| Baseline/output comparison | Separately compiled baseline and patched MachO implementations: **3/3 fixture outputs byte-for-byte identical** after the same library insertion, preparation and 256-byte dummy attachment. |
| Real local tools | System ar and tar archives are accepted and recover exact bytes. A real system-gzip header/trailer validates against its original plaintext. Raw DEFLATE/XZ decoding is not exercised on Linux. |
| Original crash witnesses | Two full original MachO witnesses, the extracted original special-slot function and extracted original arMembers function all terminate with signal 4 in separate processes. Patched structural rejection tests pass. |
| `swiftc -frontend -parse Sources/SigningKit/*.swift Tests/SigningKitTests/*.swift` | Syntax parse succeeds. This is not Apple-framework typechecking. |
| Full `swift test` | **Build failed, 0 tests executed**: Linux has no module `CryptoKit`; Security and Compression are also Apple-only dependencies. No Apple tests were counted as passing or as XCTest skips. |
| `git diff --check` | Passed. |
| Xcode build/test, iOS Simulator, Apple codesign | Unavailable: Linux lacks macOS/Xcode/Apple SDKs. |
| Full CMS cryptographic verification, device install/launch | Not executed or claimed. Existing and new Apple integration suites remain required. |

Example Linux command used (Docker already has the toolchain image):

```sh
env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_TLS -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH \
  docker --host=unix:///var/run/docker.sock run --rm --network none \
  -v /workspace:/workspace -w /workspace/wax-signer swift:6.2.3-jammy \
  python3 scripts/test_parser_safety.py
```

On macOS, run `swift test` as the release gate, including SigningTests, SignatureVerifierTests, SignatureVerifierMalformedTests, FatMachOTests, LibraryInjectorTests, AuditRegressionTests and DebExtractorTests. The existing codesign comparison suite performs independent Apple verification. Run the repository's unsigned Xcode build and simulator checks, then device signing/install/launch tests with legitimate test credentials. None of those outcomes can be inferred from the Linux parser tests.

## Compatibility assessment

Public APIs are preserved. `MachO.attach` is internal and now throws; its production caller was updated. Supported little-endian arm64/arm64e execute/dylib/bundle images, nested iOS/watchOS code, arm64 preference, XML/DER signing output and two-pass signature sizing remain. A zero-size **internal preparation probe** is still permitted; an on-disk zero-size signature command is rejected. Binaries without platform metadata remain accepted for legacy compatibility; explicit simulator/macOS/tvOS/inconsistent platforms reject. Accepting watchOS metadata is not a new device-installation compatibility claim.

New controlled rejections include out-of-segment sections, overflowed VM ranges, non-final LINKEDIT, signature/data overlap, unsafe or nonzero padding, missing TEXT/LINKEDIT, unsupported CPU/subtype/type/platform, malformed fixed/string commands, malformed/nonaligned/overlapping universal slices and mismatched selected CPU metadata. Sectionless files can retain/replace a valid existing signature but cannot gain a command by assuming spare bytes exist.

The local verifier deliberately evaluates Wax's SHA-256 CD v0x20400 format, with no scatter table and matching 32/64-bit limits. It now rejects unsupported CD versions/layouts instead of interpreting them as v0x20400. This does not prevent replacing a different valid original signature; entitlement extraction validates the container without requiring its CD to use Wax's layout. Zero-filled space reserved after the SuperBlob remains allowed. CMS outer BER-indefinite encoding is not accepted by the Wax-output self-check; provisioning-profile BER parsing remains unchanged.

Incomplete ar/TAR, bad checksums, invalid numeric encodings, missing TAR end blocks, unsupported GNU ar name-table references and malformed gzip are newly rejected. POSIX ustar, ordinary/BSD ar names, GNU TAR long names, uncompressed TAR and existing gzip/XZ paths remain intended supported workflows. GNU long-name records are capped at 4096 bytes. No zstd/bzip2 or extended TAR numeric-format support was added.

## Remaining risks and required verification

1. **Essential Apple verification is incomplete.** New complete-verifier, decompression-backend and library-injection integration regressions were added but could not run. Typecheck/build the complete app and package on macOS before considering R1 release verified.
2. The new no-write guarantee covers malformed-input validation failures. A multi-file commit can still partially finish if an actual filesystem write/permission/disk error occurs during the final replacement phase. General filesystem transactions, symlink races and cancellation are outside R1.
3. No physical iPhone signing, trust decision, installation or launch was observed; arm64e and nested watchOS execution need the legitimate device matrix. Internal hash consistency cannot substitute for Apple verification.
4. The parser validates consumed structures and file regions used by these rewrites; it is not a complete implementation of every historical/future Mach-O command or TAR extension. PAX metadata and other unsupported extension semantics were not newly implemented. Remaining format compatibility needs corpus/device testing, not guesses that unknown input works.
5. Existing whole-file Data processing, archive memory amplification and broader per-operation quotas remain separate roadmap work. R1 adds bounded arithmetic and pre-copy signature overlap validation but does not claim a full resource-exhaustion solution.
6. No additional confirmed malformed-input trap remains among the reproduced witnesses. This is bounded regression evidence, not a proof against all hostile binaries. Parser fuzzing on Apple platforms and a larger legitimate binary corpus remain useful follow-up validation.
