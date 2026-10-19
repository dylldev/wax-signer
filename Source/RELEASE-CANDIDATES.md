# R11: Build a reviewable candidate without publication

This command builds from the bytes of an explicitly selected **annotated** source tag, not from a dirty working directory or local ignored configuration. HEAD must resolve to that tag. The owner must first independently review/protect that tag and integrate the required R4/R12 changes; this tool does not grant approval or create tags.

On a Mac with Xcode, Swift, XcodeGen, Python3.12+ and the selected tag checked out:

```sh
python3 Source/prepare_release.py --repo /path/wax-signer \
  --tag vVERSION --build BUILD --flavor no-feed --no-history \
  --icon /path/public-icon.png --base-url https://dylldev.github.io/wax \
  --date YYYY-MM-DD --out /path/new-candidate
```

Use `--history /path/previous-stage/apps.json` to retain compatible existing versions and their actual locally present IPA bytes. `--no-history` is a deliberate owner decision for a new distribution identity; it must not silently replace a site containing useful previous releases. R4 generation refuses unavailable/mismatched historical artifacts. The historical dev.localsigner.app identity cannot be relabeled as io.github.dylldev.wax; their migration remains explicit.

For a reviewed public default feed, use `--flavor configured-feed --feed https://…/feed.json --domain …`; credentials/query-bearing URLs and invalid DNS names fail. Only these public arguments reach the build settings. The child build environment is restricted; ignored/untracked secrets never enter the fresh Git archive. No certificates, Keychain material, local app library, signing profile or private configuration is consumed. The ordinary build script signs nothing and publishes nothing.

The candidate contains `stage/` (R4's strictly validated feed/site/IPA/checksums/license/notice) and `provenance.json` (source commit/annotated-tag object/export hash, measured Xcode/Swift/SDK/XcodeGen versions, public configuration, actual staged IPA/plist/hash/size and source-built probe evidence). Temporary build files stay outside the stage and are removed. An existing candidate is refused; failures do not replace it. Ordinary single-writer destination use is assumed, not hostile concurrent renames in the output parent.

The gate requires actual packaged probe metadata, nested-byte/executable digests and hashes of the exported public source/generated plist. R12 is therefore a real dependency: old opaque-resource builds fail instead of being mislabeled ready. The generated page conservatively uses signer-export copy even for a configured feed; configuration alone does not verify an install route.

No GitHub release/Pages workflow is run or created. Review the candidate, run independent Apple codesign/CMS and the physical matrix, retain their evidence, then approve promotion separately. The manifest explicitly records those observations as NOT_RECORDED and binary reproducibility as NOT_ESTABLISHED. It is local build provenance, not an Apple attestation, proof against a compromised compiler, or a complete protected release pipeline. Future work: pinned-tool/action policy, review-linked CI evidence, protected manual promotion/postdeploy byte checks and rollback rehearsal.
