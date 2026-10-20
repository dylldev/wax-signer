# R7: source JSON complexity and processing budgets

Partial R7 milestone on main/R2, independent of the download/cache implementation PRs. No signing, release or source-subscription policy change. Final-head macOS verification pending at initial publication.

## Confirmed gap and scope

`8ad4b2e:Sources/SourcesKit/SourceParser.swift:42–44,85–91,111–119,128–137` immediately materializes Foundation JSON/Raw arrays, including every version before reduction. The network's64MiB file cap does not bound object count, nesting or reduction work usefully: tiny objects or ignored nested metadata can fit that cap. Failable app/field decoding intentionally swallows schema errors, so a resource check only inside those Decodable implementations would risk silently dropping a hostile field and reporting success.

SourceParser now performs a constant-space scan over the original Data before JSONDecoder:64MiB bytes,50,000 object/array containers,250,000 lexical tokens,64 nesting levels and1MiB encoded bytes per JSON string (keys and ignored values count too). SourceParser.Limits permits smaller budgets, not raising those ceilings. It counts structure outside strings and respects escaped quote/backslash parity; Foundation remains responsible for JSON/schema correctness. No second decoded JSON tree, generic parsing framework or external dependency.

A15-second monotonic processing budget (configurable up to60s) and task cancellation are checked before/during the scan (64KiB intervals), after Foundation decode, for each app and for each candidate version. A Foundation decode/date operation already in progress cannot be interrupted; the next checkpoint rejects an expired result. This is bounded input/observable deadline enforcement, not a promise of exact synchronous CPU preemption. Limit failures propagate as actionable SourceError.resourceLimit, outside lenient decoding. A rejected refresh never reaches existing cache publication.

## Compatibility

Both current versions[] and legacy app-level fields retain identical reduction, URL filtering, duplicate IDs and newest-version behavior under budget. A UTF-8 BOM is accepted; network JSON must be UTF-8 per RFC8259. UTF-16/32 input previously tolerated by Foundation is now rejected rather than scanned under the wrong encoding. Oversized/over-complex sources are explicitly refused, never truncated into a misleading partial catalog. Individual exceptionally long descriptions/URLs and massive catalogs may require publisher splitting. No third-party sources are preloaded.

Existing normalized on-disk SourceRepo cache/index decoding is not routed through this network JSON parser; bounded legacy/local cache loading remains separate unfinished R7/R14 scope. Source icon acquisition/decode, provider waits, packaging scratch and Mach-O/DEB worker memory also remain open. This milestone does not complete original R7.

## Tests and verification

12 SourceObjectBudgetTests cover exact byte boundaries, ignored containers/scalars, nested input, UTF-8 string byte limits, escaped punctuation, budget propagation despite malformed app fields, invalid/overflow budgets, malformed JSON/BOM/encoding, Task cancellation, monotonic version-reduction expiry and mid-string checkpoint interruption. SourceStoreTests adds an actual refresh regression preserving old cache/ETag/index when the default nesting cap rejects a response.

A temporary offline Swift6.2.3 Linux package compiles unmodified SourceParser/SourceJSONBudget and the actual12 new+10 existing parser tests:22 tests,0 failures. It does not include the URLSession cache integration case or Apple frameworks; macOS CI must run the full package/iOS build/Simulator suites. Local log `/tmp/wax-source-parser-portable.log`; no test exclusions or network dependencies were added to Wax.

Changed paths: Sources/SourcesKit/SourceParser.swift, SourceJSONBudget.swift; Tests/SourcesKitTests/SourceObjectBudgetTests.swift, SourceStoreTests.swift; this report.

## Performance

One extra linear read of already-owned source bytes, constant scanner state, no additional file copy or full-text string allocation. The existing decoded graph/reduced arrays are unchanged, but budgets now bound their input. A reproducible same-runner optimized Linux before/after5,000-app synthetic fixture measurement is recorded in the master checkpoint after completion; it is not an iPhone result or a complete peak codec/app-memory budget.

No physical source-ingestion/UI responsiveness result is claimed. Device gate: add representative supported current/legacy sources, large under-budget feeds and deliberately over-budget fixtures; verify responsive failure/retry, unchanged cached browsing after refresh refusal and no accidental deletion of source/library artifacts.
