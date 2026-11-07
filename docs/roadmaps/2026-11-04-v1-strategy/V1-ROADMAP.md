# Qualify the core across four releases

Use milestone numbers to name decisions, not dates. Keep public main as the starting point, selectively reconcile reviewed local/draft changes, and freeze one candidate before device work. Efforts are ranges in engineer-days. Parallel ownership reduces elapsed time, while reviewer, device, CA or host waits remain external.

## 0.17 · Stabilize the candidate path

Give users truthful identity, save and trust state before adding features.

| Decision | Stage requirement |
|---|---|
| Features | Normal/Dev provenance contract, runtime fingerprint guard, copy repair, reproduce draft AX issue and select reviewed UI changes. |
| Defects and open gates | B01–B04 |
| Prerequisites | T01–T05. T02/T03/T04 can proceed after T01. |
| Security | Keep key labels and Dev probe out of normal Wax. Guard retained identity and reject altered probe. |
| Performance | Capture unoptimized baseline. Check high-work credential import stays responsive. |
| Tests and compatibility | Red/green standard and Dev fixtures, wrong leaf/password, AX audit and normal build. Test existing identity records. |
| Documentation | Publish channel identity, bootstrap, exclusions and dated draft disposition. |
| Exit criteria and release blockers | Known failures reproduced and repaired or excluded with reason. Do not call a synthetic candidate a releasable IPA. |
| Engineering effort and confidence | 4–10 d / medium-high |

## 0.18 · Finish the three journeys

Preserve original, sign once, export or retry the retained output; compare identity on renewal.

| Decision | Stage requirement |
|---|---|
| Features | Provider recovery, shelf state, cancel/retry, update warnings, HTTPS destination and safe fallback. Include scoped onboarding only if reviewed. |
| Defects and open gates | B05,B07,B08,B10 |
| Prerequisites | T06,T07,T10,T11 plus scoped I09–I12. Ship on reviewed stabilization base. |
| Security | Check migration with disposable items, authenticated redirect policy, scope and expiration of server downloads. |
| Performance | Bound scratch before preparation and measure delay to cancel. Keep background progress ownership explicit. |
| Tests and compatibility | Fault injection, duplicate digests, provider loss, host outage, stale generations and termination. Retest normal/Dev split and pre-existing library schema. |
| Documentation | Write exact support table, setup and export/server troubleshooting. Explain experimental hosts before use. |
| Exit criteria and release blockers | The three journeys run on normal Wax with fixture outputs. All failures preserve previous good bytes. Host operator and floor-device availability still gate RC. |
| Engineering effort and confidence | 5–12 d / medium |

## 0.19 and RC · Freeze and prove support

Let users read exactly which device, profile and install path worked for the candidate.

| Decision | Stage requirement |
|---|---|
| Features | Independent corpus, hostile negatives, two-device matrix, responsiveness and compatibility ledger. No broad feature additions. |
| Defects and open gates | B04,B06,B09,B10,B11 |
| Prerequisites | T08,T09,T12,T13. Exact staged candidate before physical sign-off. |
| Security | Review parsers, Keychain, transport, logs and packaging. Test certificate confusion, signatures and host trust controls. |
| Performance | Record phase wall/CPU, RSS, scratch, p95, cancellation, UI heartbeat and thermal state on floor/current hardware. |
| Tests and compatibility | Full CI plus independent output, CMS, two physical devices, extension invocation, launch/update sentinel, Dynamic Type and VoiceOver. |
| Documentation | Freeze tested tuples, evidence manifest, bootstrap and release candidate notes. |
| Exit criteria and release blockers | All prepublication gate observations green. Mismatch in bytes, missing devices or unresolved serious defects requires a new RC or narrower promise. |
| Engineering effort and confidence | 5–12 d plus device/reviewer access / medium |

## 1.0 · Promote the exact qualified bytes

A user can bootstrap, recover a failed delivery and find a supported route for the verified file.

| Decision | Stage requirement |
|---|---|
| Features | Promote only the reviewed standard/Dev pair with validated feed, checksum and rollback packet. |
| Defects and open gates | B10 and any reopened B01–B11 |
| Prerequisites | T14 after T13. Owner approval for outward publication. |
| Security | Check staged asset scans, protected refs, no private identifiers or credentials in public evidence. |
| Performance | Compare shipped digest with measured RC. No code changes during promotion. |
| Tests and compatibility | Rehearse rollback before release, verify post-publication asset bytes/feed/version and rerun affected checks if bytes differ. |
| Documentation | Publish support/compatibility matrix, known limits, issue template and release notes. |
| Exit criteria and release blockers | All eight gates reach 2, operator approves promotion, downloaded bytes match. Restore previous stage on mismatch. |
| Engineering effort and confidence | 1–2 d plus approval / high conditional on RC |

The critical path is T01 → T02/T03/T04 → core recovery and host qualification → independent checks → T12 freeze → T13 phone matrix → T14 promotion and rollback. Do not delay the core for a speculative format, host or analytics subsystem. [Task dependencies](PRIORITIZED-BACKLOG.md) · [Gate grading](RELEASE-READINESS.md)
