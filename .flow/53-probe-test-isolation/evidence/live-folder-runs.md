# Live DebugRecordings folder around the full suites (2026-11-11, on AC, heavy-gate slot dicticus-tests)

Snapshot = `wc -l` of every live `*.jsonl` plus the `preview-flags/` file list (scratchpad snap.sh).

| Run | Code | Result | New rows in live folder |
|---|---|---|---|
| macOS, scheme Dicticus | main (dee0299), baseline worktree | 1947 tests, 8 skipped, 2 failed | 117 rows across the two runs: mediapause 75, overlay 22, paste 10, postedit 10, all with ts 08:17:04–08:17:21Z |
| macOS, scheme Dicticus-Debug-Recorder | main (dee0299), baseline worktree | 2023 tests, 10 skipped, 1 failed | (included above) |
| macOS, scheme Dicticus | slice branch | 1948 tests, 7 skipped, 0 failed | none (snapshot diff empty) |
| macOS, scheme Dicticus-Debug-Recorder | slice branch | 2025 tests, 8 skipped, 0 failed | none (snapshot diff empty) |

The baseline runs also purged the live files from 10-20 to 10-27. That is the probes' normal 14-day retention, run from the test host.
No capture or cleanup rows were written on 2026-11-11, so none of the 117 rows is a real dictation. They were moved out of the live folder after the run.
`scripts/check-running-copy.sh` printed OK after the macOS runs and again at the end.
