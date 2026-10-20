# R13 measurement correctness milestone

The old PerfTests callback concurrently mutated captured Date/Array state and wrote every run to the same `perf-out.ipa`. It was not a reliable baseline. PerformanceRecorder now serializes progress-event timing with a lock and a monotonic system clock. Each run has unique owned scratch/output paths, with deferred cleanup on failures. `WAX_PERF_OUT=/path/to/samples` emits unique JSON raw event timing samples; previous runs are not overwritten. Three deterministic tests exercise 1,000 concurrent callbacks finalization against late callbacks, and raw-sample serialization.

These are progress-event intervals, not CPU time or independent execution duration of overlapping pipeline stages. No production performance optimization or speed gain is claimed. No real-input benchmark was executed in this milestone; the existing opt-in test still skips without WAX_PERF_IPA.

For a real baseline, record exact SHA/toolchain/OS, input SHA-256, compression option and filesystem; keep CPU/RSS/scratch instrumentation separate and account for its overhead. Use the same runner and input bytes for both revisions, one warm-up and at least five samples per setting. Report median and nearest-rank p95, not one warm-cache anecdote. Small/medium/large deterministic fixture corpora, RSS/scratch high-water sampling, TSan and physical-device thermal/battery observations remain outstanding original R13 requirements. This milestone fixes measurement races; it does not complete R13.

On macOS, for each authorized input and isolated output directory:

```sh
swift --version
xcodebuild -version
shasum -a 256 /path/input.ipa
WAX_PERF_IPA=/path/input.ipa WAX_PERF_OUT=/path/samples swift test --filter PerfTests.testStageTimings
# Repeat on the comparison revision with the same input/runner/configuration.
```

Fixture credentials are synthetic only. Do not commit user IPAs or raw device identifiers. The engine's self-check and R2 final artifact gate remain enabled. Test-source inspection is not a substitute for codesign or real device installation/launch.
