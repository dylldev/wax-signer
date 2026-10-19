# R15 read-only signing-plan foundation

Status: partial original R15 milestone; implemented, macOS verification pending. This PR stacks on R6 (#7), preserving independent App ID prefixes.

`BundleSigner` already decided profile selection/identifier rewrites before mutation, but decisions were private and resolved entitlement grants only during signing. At R6 head `3ef32fe`, planning is `BundleSigner.swift:186–276`, private selection at 280–319, and entitlement resolution during mutation at 399–418. The new API exposes those actual decisions using the same planner/resolver, rather than simulating a second signer.

## Contract

`BundleSigner.plan` accepts only public certificate-chain bytes, profiles, options and an already edited app-owned scratch tree. It never receives or retains a private signing handle. Public immutable rows expose original/final bundle IDs, selected/rejected profiles, CMS validity/trust status and requested/signed entitlement XML with granted/rewritten/dropped/identity-added decisions. A default policy rejects invalid CMS; valid-but-untrusted remains distinct. Synthetic tests must explicitly choose `allowInvalidForTesting`, and that never relabels their trust. Bounded output: default 256 bundles (hard maximum4096), entitlement serialization256KiB, inherited classic-ZIP path/file-count bounds. This is not a general CPU/scratch budget.

Caller-owned Any/Objective-C containers are frozen by property-list serialization and immutable profile-byte reparsing. Plan captures R2's streaming SHA-256/path/mode/symlink manifest, checks it after read-only planning, then rechecks immediately before any mutation. `IPAArchiveManifest.verifyTree` is now public, with the existing R2 implementation unchanged. Execution uses the captured decisions, verifies the exact supplied signing chain and current certificate/profile expiry, and is once-only across plan copies under a small lock.

Normal direct signing retains its existing policy and mutation order; the shared entitlement resolver is the only execution refactor. This milestone does not silently switch current app production behavior or introduce new signing algorithms. Plan execution requires exclusive ownership of its unpacked scratch tree: snapshot validation is not a filesystem lock against arbitrary external concurrent writers. Post-write R2 final IPA verification remains independently mandatory when integrating into IPASigner.

## Tests and remaining original scope

15 macOS cases (14 cross-platform Apple-framework cases): read-only tree, profile/entitlement execution parity, dropped/strict entitlement behavior, resource/executable/mode/link changes, wrong certificate before key use, once-only attempts, expiry since planning, bounds, unknown override rejection, mutable-container isolation, explicit invalid-CMS fixture policy and independent codesign of planned output. Existing signing/R1/R2/prefix tests remain enabled. Offline Swift syntax parsing passed; CI execution will be recorded separately.

Not complete: app preflight UI/confirmation, AppEditor change preview (including deterministic randomization/injection), immutable IPA/configuration snapshot across that UI, advanced per-bundle assignment UI, explicit production profile policy adoption, usability/accessibility review and device conformance. API deliberately applies to an already edited unpacked tree; it does not claim to predict edits that have not yet happened. Planning hashes the tree twice and execution once; buffers remain bounded, but large-corpus/phone latency is unmeasured. No installation, trust acceptance or physical launch is claimed.
