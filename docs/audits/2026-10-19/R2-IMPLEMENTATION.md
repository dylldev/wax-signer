# R2 — final IPA artifact integrity

Base: `ff50f001f8ee768b5fe3cbd5835377bc563fd2b9` (R1 squash merge). Scope: archive identity, streaming I/O, final artifact validation and atomic promotion. No signing algorithms or credentials changed.

## Confirmed defects in the base

* `Sources/IPAKit/IPAArchiver.swift:55–60,181–201`: equal size plus CRC32 permitted original compressed data to replace different edited contents. Large entries additionally used modification time to avoid another CRC read. The deterministic 16-byte witnesses `9c1fe18a5db4786f3c5393b11f1280ec` and `ac12aa68ced7e488bdab66d91f1b366e` both have CRC32 `3112fecd`. Appending the same 2,097,153 zero bytes produces 2,097,169-byte witnesses with CRC32 `4534d269`.
* `Sources/SigningKit/IPASigner.swift:62–76`: the bundle self-check preceded packaging; the subsequent inspector read archive metadata, not every packaged executable/resource. Neither check established identity of packaged bytes with verified bytes.
* `Sources/IPAKit/IPAArchiver.swift:34`: writer allowed 65,535 entries, which `ZipArchive` interpreted as a ZIP64 sentinel. Filename and compressed-size narrowing also needed checked limits.
* `Sources/IPAKit/IPAArchiver.swift:16,172–177,189–195`: missing/corrupt source and I/O errors could silently become fallback compression or EOF. The writer opened its output directly, truncating any previous archive before successful completion.
* `Sources/IPAKit/IPAArchiver.swift:241–247`: precompressed copy did not check the copied length. The ZIP decoder needed exact compressed-input consumption and data-descriptor consistency for the new final gate to be authoritative.

## Design and guarantees

`IPAArchiveSession` retains one open original archive across inspection, extraction and reuse. Extraction computes SHA-256 of both plaintext and compressed input during existing streaming reads. Opaque inventory provenance binds those fingerprints to that session and extraction directory. Replacing a source pathname cannot substitute a different inode; in-place compressed-byte changes are detected while copying reused entries. Legacy URL-only archiver calls validate and hash original entries before reuse. Missing/unreadable specified originals fail explicitly; a genuinely absent entry can safely be compressed from the working tree.

`IPAArchiveManifest` captures the exact Payload path set, regular-file SHA-256/size/CRC, file and directory permission bits, kinds and symlink targets. The signer captures it before its bundle self-check. Writer streams compute SHA-256 again while compressing or storing changed files; reused entries require matching cryptographic fingerprints. Dates are never evidence of identity.

Every candidate is written to a private sibling of the destination. After optional metadata inspection, an independent new ZIP reader streams every actual packaged entry and checks contents, metadata and exact path membership against the manifest. It then rechecks the current working tree against the same manifest. Only then does a same-directory POSIX rename atomically replace the destination. Any preceding failure removes the candidate and compression scratch files without deleting or truncating the previous output.

The ZIP decoder uses the platform system zlib API for exact raw-DEFLATE consumption (`Z_STREAM_END`, `avail_in`, `total_in`), checks CRC/size and rejects trailing compressed bytes. Both signed and unsigned classic data descriptors are checked against the central record. Existing extraction path/symlink protections remain in place. ZIP64 is deliberately unsupported: max entry count 65,534, max size/offset/archive length 4,294,967,294, filename length 65,535 bytes, and the existing 64 MiB central-directory cap.

## Compatibility and cost

Valid supported thin/fat signing behavior is unchanged. New controlled rejections include inconsistent ZIP descriptors, trailing raw-DEFLATE input, ZIP64 sentinels, unrepresentable metadata, special permission bits, changed verification snapshots and unreadable specified reuse sources. Previously accepted malformed or integrity-ambiguous inputs are intentionally rejected. Symlink permission metadata is normalized to conventional `0120777`; file/directory rwx bits are preserved.

No extra extracted copy of the output is needed. Hashing runs in bounded 256 KiB chunks, with per-entry digests and manifest records. Extraction adds two SHA streams during existing I/O. Normal signing adds an intended-tree hash pass, a final archive decode/hash pass, and a final tree hash pass. Unchanged assets avoid recompression and original re-inflation via the extraction inventory. Changed large files retain parallel compression and its existing scratch-space costs. A complete sibling candidate must fit on the output volume; the prior output remains until rename. Memory is proportional to entry metadata plus per-worker buffers, not total IPA size.

The private job directory and staging directory remain within Wax's sandbox trust boundary. This does not claim filesystem transactions against a malicious process with arbitrary same-UID write access, crash-durable fsync publication, Apple provisioning/trust approval, or physical-device installation/launch. An internal signature check remains distinct from Apple's installation decision.

## Verification

Pending the actual macOS CI run. Regression coverage includes both CRC collision sizes, stored/deflated changed files, byte-exact unchanged reuse, inventory/source isolation, corruption/truncation, mutations after self-check, altered final candidates, content/path/mode/link mismatches, read/write error propagation, classic-ZIP boundaries and previous-output preservation. Existing signing, system ZIP interoperability and independent Apple codesign tests remain enabled. Results and measured observations will be recorded after execution.
