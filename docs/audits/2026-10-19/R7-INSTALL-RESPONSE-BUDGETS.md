# R7 install response budgets

Status: implementation prepared; macOS CI pending. Stacked on PR #14 to preserve and exercise its confirmed, destination-bound bucket cleanup.

## Confirmed gaps

At R2 baseline `8ad4b2e`, `Sources/InstallKit/InstallTransport.swift:6,11`, `OTA.swift:173` and `S3Host.swift:73,86` materialized complete host responses before any size check. `CertificateFeed.swift:113–122` checked its body deadline only when a byte arrived; a silent body could never reach that check. Its catch path could turn cancellation into cached success, and its local cache was read without a byte cap. At bucket head `0760cf5`, `S3Host.delete` still materialized DELETE bodies in full despite the new cleanup ledger.

## Change

Small InstallKit-local data delegate retains at most 1 MiB of decoded control/upload response body (certificate feed explicitly 64 KiB). Actual chunks are authoritative; advertised length is only early refusal. A monotonic dispatch timer includes connection/headers/silent body, with 20-second control defaults and 30-minute total upload default. Cancellation completes once, invalidates/cancels the underlying session, and handles cancellation before task registration. Upload source files remain file-streamed by URLSession.

A configuration-cloned foreground session preserves protocol classes/cookies/TLS configuration. Custom session delegates/background sessions are explicitly rejected rather than silently dropping trust/lifecycle policies. HTTPS-only redirects have a five-hop cap; authenticated requests cannot cross origin. DELETE redirects are always refused, retaining R14's original non-redirection guarantee and its actual delegate-callback regression. Setup checks, S3 listing, manifest checks, upload replies and confirmed cleanup all use the bounded transport.

Certificate cache reads are bounded in chunks to 64 KiB+1. Cancellation is checked before cache use and propagated rather than falling back; ordinary network failure still permits a verified, nonexpired cached certificate. Existing chain/name/expiry validation is unchanged.

## Tests and limits

13 deterministic `InstallResponseBudgetTests`: exact cap, no/lying length, declared oversize, silent headers/body deadlines, parent/pre-registration cancellation, upload reply cap/source preservation, invalid budget/URL, custom trust delegate refusal, cached-feed cancellation and oversized cache replacement. Existing feed/server/S3 and R14 ledger tests stay enabled. Offline Swift syntax parsing passed; full Apple CI results will be recorded after execution.

Memory overhead: retained response cap plus URLSession's transient chunk; no whole IPA buffering or additional IPA disk copy. Per-request delegate/session/timer allocation is intentional for lifecycle ownership. Throughput/phone energy not measured. These controls do not complete original R7's extraction/scratch/object/image/worker-memory budgets, which remain open. No deployment, paid dependency, new TLS trust bypass or physical-device claim.

CI correction: initial runs39316253718/39316935167 each executed601 package tests with one failure in the unfinished short URLProtocol early-header fixture (deadline instead of size error); other response regressions and all existing package cases passed. The fixture now completes an empty body, so a size rejection can only come from headers. Header policy is additionally tested directly before any body, including numeric overflow. Silent/no-body response deadline tests remain unchanged; no limit or rejection was removed. Raw Content-Length is an advisory check alongside expectedContentLength, not an authority for actual decoded bytes.
