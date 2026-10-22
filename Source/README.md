# Prepare a distribution stage without publishing

Generate from the exact IPA selected for review, never `project.yml` alone:

```sh
python3 Source/make_source.py --ipa /path/Wax-VERSION.ipa \
  --icon /path/icon.png --capabilities signer-export --date YYYY-MM-DD \
  --base-url https://dylldev.github.io/wax --out /path/new-stage \
  --extra LICENSE --extra NOTICE
python3 Source/validate_source.py --dir /path/new-stage --expect-base https://dylldev.github.io/wax
```

Choose capabilities for that binary: `inspector` for historical inspector-only releases, `signer-export` for signing/export, or `signer-install` only after verifying the build's configured installation routes. This flag is a reviewed assertion, not automatic feature detection or device approval. No script uploads or deploys anything. Generate into an absent/empty destination; existing populated stages are never overwritten.

Version, build, bundle ID, minimum OS, size and SHA-256 are read from the actual IPA. Each copied IPA is hashed again before publication of the stage. Filename URLs and source deep links are percent-encoded. A fixed date makes feed/page generation repeatable for fixed input bytes. Missing icon, IPA or historical artifact fails before a feed is published. `--keep-versions path/apps.json` requires every retained IPA beside that feed; checks metadata/hash, copies it and rewrites its URL to the selected canonical base. It does not guess that an unavailable remote release exists. Public LICENSE/NOTICE are the only optional extras allowed by the generator; the strict stage validator requires them before promotion.

The validator checks all version records, legacy/newest field parity, actual ZIP/plist metadata, size, SHA-256, checksum sidecars, opaque icon dimensions, containment and the stage allowlist. It fails on malformed schema. It is not an Apple codesign/trust/install verifier. After a separately approved deployment, run `python3 Source/validate_source.py https://dylldev.github.io/wax/apps.json` and ingest the feed in AltStore/SideStore on an authorized device. No successful deployment/device ingestion is claimed by local staging.

A `dev.localsigner.app` historical IPA is a separate app identity from `io.github.dylldev.wax`; changing feed metadata cannot migrate the app container, credentials or library. Do not relabel the old IPA as a new build. The 0.3.2 distribution repair intentionally retains the old inspector binary and its limitations pending a separately reviewed, conformance-tested new release.
