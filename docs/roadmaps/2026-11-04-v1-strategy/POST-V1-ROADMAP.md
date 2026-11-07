# Fund expansion when its evidence improves

Spend 1.1 on explanations users can inspect. Spend 1.5 on one measured bottleneck. Give 2.0 a feasibility question and a stop condition before promising a new installation model. Each stage inherits the current security, accessibility, compatible-update and distribution gates.

## 1.1 · Explain signing decisions

Let a returning user understand which capabilities changed and what they actually observed.

| Decision | Stage requirement |
|---|---|
| Features | Local receipts, Passport explanations, nested profile map, renewal shortcuts and explicit diagnostic preview. Prioritize I13–I18. |
| Defects and open gates | Continue B02/B03/B06 watch; no assumed new defect. |
| Prerequisites | T15,T16 after 1.0. Retain old record decoding and performance baselines. |
| Security | Version bounded history, redact on export, require explicit sharing. Keep rules offline. |
| Performance | Measure receipt I/O, VoiceOver rendering and long nested plans against 1.0. |
| Tests and compatibility | Old schema fixtures, changed grants, unknown trust, receipt export and two-device support regression. |
| Documentation | Explain receipt fields, known versus unknown outcomes and privacy controls. |
| Exit criteria and release blockers | Old records remain readable; receipts bind to the signed bytes; a user can identify the changed grant. Stop if evidence increases false confidence. |
| Engineering effort and confidence | 5–12 d plus device access / medium-high |

## 1.5 · Reduce measured cost

A large permitted app consumes less memory or avoids demonstrated lost work after interruption.

| Decision | Stage requirement |
|---|---|
| Features | One measured file-backed signing bottleneck or one durable checkpoint. Optional corpus comparison and nonce-bound Dev probe after independent review. |
| Defects and open gates | B08/B09 regression guardrails |
| Prerequisites | T17 or T18 only after T09/T15 and workload evidence. Do one costly change at a time. |
| Security | Bound range reads, reject mutated data, bind checkpoint to input digest, preserve originals and stale-generation checks. |
| Performance | Aim for at least 20% lower peak RSS on selected workload for T17; T18 must save measured rework without increasing publication risk. |
| Tests and compatibility | Compare baseline/optimized final verification on malformed, nested and large fixtures. Kill every checkpoint transition. Two-device regression. |
| Documentation | Publish change, before/after distributions, supported limits and explicit fallback. |
| Exit criteria and release blockers | Selected experiment clears target and security review or retains baseline. No ZIP64/ECDSA commitment. |
| Engineering effort and confidence | 5–15 d per selected change plus device access / medium-low |

## 2.0 · Qualify one new capability

A new group of users gains one verified route or format while the 1.x contract remains reliable.

| Decision | Stage requirement |
|---|---|
| Features | Time-box private-domain TLS, pairing, ZIP64 or ECDSA separately. Select only one production candidate after feasibility review. |
| Defects and open gates | B07/B11 boundaries continue; experiment cannot waive gates. |
| Prerequisites | T19 or T20 after v1 evidence and approved fixtures, ownership and cost. Pairing is a separate decision. |
| Security | Keep issuer keys private, verify chain/hostname, bind device credentials to consent, enforce archive/crypto limits. |
| Performance | Record power, storage, CPU and peak RSS before/after against comparable workloads. |
| Tests and compatibility | Independent cryptographic checks, malformed controls, backward compatibility, renew/failure drills and physical install/launch if claiming support. |
| Documentation | Publish requirements, operator burden, stop conditions and support ownership. |
| Exit criteria and release blockers | A scoped design passes its proving case, maintenance cost is funded and old journeys still pass. Otherwise close the experiment and keep 1.x. |
| Engineering effort and confidence | 5–10 d per spike; production estimate after proof / low |

A 2.0 spike may end with a documented no-go. Revisit only when the missing prerequisite changes, such as access to an authorized identity family, suitable test devices, a private domain owner or representative workload. [Long-term shortlist and rejected ideas](INNOVATION-LAB.md)
