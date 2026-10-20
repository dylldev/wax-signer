# R14 milestone — Destination-bound bucket cleanup

Stacked on R3 `469a10e`; distinct from independent source-cache PR #8. These are separate reviewable persistence milestones, not a claim that all original R14 secret/backup migration work is complete.

## Evidence

Baseline R2 `App/OTAInstallModel.swift:178–195` stores only `[sessionID: timestamp]` and deletes using the **current** endpoint/bucket/keys. It forgets each record regardless of network/HTTP failure. `Sources/InstallKit/S3Host.swift:89–98` returns no deletion outcome and ignores HTTP status. A changed bucket could receive a deletion intended for the previous destination; a 403/timeout silently loses retry obligations.

## Design and transaction order

- `Sources/InstallKit/BucketCleanupStore.swift` stores version1 atomic JSON with session ID, normalized original HTTPS endpoint, bucket, region, public access-key SHA256 and expiry. It stores no access/secret key. Unique record IDs and remote routes prevent duplicate obligations from deleting an independently live session. Invalid/corrupt/oversized/unknown-version indexes remain intact and block new uploads, never becoming empty state. Regular-file validation, bounded journal size, mode0600 and backup exclusion apply to owned journal files.
- Before the first bucket PUT, a preparation record with nil expiry commits. While active, its record cannot be swept by this model. Termination before publication acknowledgment leaves a recoverable preparation record; installer links are never returned while it has nil expiry.
- After actual publication, its expiry must commit **before** returning the install link. If that local write fails, UI explicitly reports upload succeeded but installer was not opened; signed local IPA remains available. An interrupted unacknowledged publication can be cleaned on next launch. Live links wait for their recorded expiry.
- Sweeps use immutable credential snapshots and only records matching original endpoint/bucket/region/access-key digest. A record for changed settings/keys stays pending, requiring restored original configuration or operator bucket-expiry policy. No old credentials are retained to make cleanup convenient.
- `S3Host.cleanupConfirmed` checks both DELETE outcomes (2xx/404), attempts both even if one fails, has a20s request timeout and refuses redirects on destructive authenticated requests. Any failure retains the record; successful remote deletion plus failed local removal remains idempotently retryable. Existing best-effort `cleanup()` API stays compatible.
- Legacy UserDefaults `s3Pending` records lack destinations and are **left untouched**, with a visible explanation. Guessing that they belong to the currently selected bucket would recreate the defect. The settings pane gains Retry expired upload cleanup.

## Verification

Nine new journal unit tests, four S3 cleanup tests (including actual URLProtocol redirect callbacks), and eight app-model outcomes cover restart/preparation/expiry, exact destination/credential scoping, corrupt indexes, failed writes, concurrent updates, duplicate route rejection, removal of stale snapshots, HTTP failures/404/redirect refusal, failure/retry, legacy retention and unexpired links. Actual stubbed upload tests prove preparation precedes PUT, expiry precedes returning an installer link, and either index failure retains the local source with no installer handoff. Swift syntax parsed locally with offline Swift6.2.3; actual Apple framework and simulator execution is pending macOS CI. No physical bucket deployment or production credentials used.

## Limits

One app-owned store instance per file, not cross-process locking or power-cut/fsync durability. Atomic index replacement is not an atomic remote/local transaction; the prepared/acknowledged states and idempotent DELETE recover the gap. Bucket lifecycle rules remain a recommended backstop. Legacy records cannot be migrated automatically without unavailable original routing evidence. Removed/rotated access keys may require manual cleanup in their original bucket. This does not fix general OTA model operation ownership (R8), secret-store error APIs/migration or all network response budgets (R7). No hardware installation, launch or performance results claimed. Journal is small/bounded; hashing/file writes run off MainActor in app call sites.
