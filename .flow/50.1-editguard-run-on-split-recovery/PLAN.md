# Plan 50.1: the round-2 verdict run

## Route
The run is pre-registered: `.planning/spikes/017-runon-split-recovery/PREREG-round2.md` (2026-10-11) fixes the candidates, the holdout, the constraints H1-H5, the worth bars and the decision table. Its pass rule is this plan's Verify. The frozen patch `017-hook-b1c1.diff` (sha256 prefix `8bc83812a0f2e1bf`) is checked before use. The spike folder is gitignored, so no commit can be cited; the 2026-11-02 recount verified the same prefix.

One choice is left: the commit the replay runs on.
- **Chosen: today's main (4a6ffd6), in a throwaway detached worktree.** The pre-registration says H2 runs "against that day's HEAD". The gate file has no commit since the recount's `ed4cb3e`, and the harness feeds the gate each record's logged post-rules text, so slice 60's pause rule is not replayed. Bet: main reproduces the recount on the recount's records.
- **Rejected: `ed4cb3e`.** It would reproduce the recount exactly by construction, but it is not the day's HEAD, and a pass there would say nothing about the code a build would start from.

Early signal that the route is wrong: task 1's reproduction check. Restricted to timestamps up to the recount's last record, main must give 27 changed period hunks, 47 lost periods and 227 comma hunks; a difference is traced to a named commit before any hunk is read, and an untraceable one stops the build and goes to the owner.

What the route commits to: a `b1` or `c1` pass opens a build item whose rule is the frozen patch, unchanged. A `b1` REGRESSION ends split recovery for good ("no third round without new evidence from a different source").

All work files (inputs, outputs, hunks, labels, scripts, the verdict document) live in `.planning/spikes/017-runon-split-recovery/r4/` and `ROUND2-VERDICT.md`, gitignored, because they hold dictation text. `.flow/50.1-…/evidence/` gets counts only. Every commit on this branch is `.flow/` bookkeeping.

Runs: three harness replays over about 1300 records, one test run of two test classes, one agy pass over about 90 items. Expected under 30 minutes of compute together, ceiling 60 minutes; no GPU model, no paid service beyond agy's existing quota.

## Tasks

### 1. Snapshot input, replay, reproduction check
- **Goal:** the snapshot exists once, cut at 2026-11-09T23:59:59Z, replayed under main (`w0`), `b1` and `c1`; the protocol header of `ROUND2-VERDICT.md` (cut-off, the owner's choice and its date, commit, patch hash, input file list with line counts) is written before any hunk is opened.
- **Files:** `r4/holdout-input/` (the 23 files of `r3/holdout-input/` plus `cleanup-2026-11-02..09` from `holdout-logs-2026-11-14/`, de-duplicated by `ts`), `r4/live-{w0,b1,c1}.json`, `r4/tally4.py`, `r4/hunks4.py` (copies of the r3 scripts with the path changed), `r4/repro.py`, `ROUND2-VERDICT.md` header; `evidence/snapshot-counts.md`.
- **Affects:** nothing shipped. The worktree `../dicticus-50.1-replay` (detached at main) gets the patch and a copy of the gitignored `Shared/Services/PersonalLexicon.swift`; the main checkout is untouched.
- **Verify:** `python3 -I .planning/spikes/017-runon-split-recovery/r4/repro.py` exits 0 and prints `repro ok: dot 27, lost-dot 47, comma 227, unexpected 0` (it filters the r4 outputs to ts ≤ the last ts of `r3/live-w0.json`, asserts those numbers and that no input record is later than the cut-off or earlier than 2026-10-10T23:59Z); `shasum -a 256 …/017-hook-b1c1.diff` starts with `8bc83812a0f2e1bf`.
- **Status:** done (evidence/snapshot-counts.md; no code commit, the work files are gitignored)
- **Depends on:** none

### 2. Hard constraints that need no labelling: H2, H3, H4, synthetic outputs
- **Goal:** the pinned tests pass with the hook on for `b1` and `c1`; boundary-casing hits are a subset of main's; no neither-source token; the synthetic outputs (13 cases plus 2 hazard cases) are byte-identical to the frozen `synthb1-*.json` and `synthc1-*.json`, whose labels at the freeze showed no REGRESSION (H5, H5c).
- **Files:** `r4/h2-{b1,c1}.log`, `r4/h34.py` (copy of the round-1 script, path changed), `r4/synth-{b1,c1}*.json`; `evidence/hard-constraints.md`.
- **Affects:** the test host runs from the worktree's own `macOS/build` (`-derivedDataPath build`); `scripts/check-running-copy.sh` must print OK afterwards.
- **Verify:** in the worktree's `macOS/`, for each of `b1`, `c1`: `TEST_RUNNER_SPIKE017=<c> nice -n 10 xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -destination 'platform=macOS,arch=arm64' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" -only-testing:DicticusTests/EditGuardCoupledRevertTests -only-testing:DicticusTests/EditGuardGrammarRegressionTests test` ends `** TEST SUCCEEDED **` with 0 failures; `python3 -I …/r4/h34.py b1 c1` exits 0 (subset holds, 0 neither-source tokens); `cmp` of each synthetic output against its frozen file exits 0.
- **Status:** done: H2 pass for both (21 tests, 0 failures each), H4 0, synthetic outputs byte-identical; H3 fails for b1 with 1 extra record, which is a measured result and not a build failure (the Verify line wrongly expected exit 0); evidence/verdict-summary.md
- **Depends on:** 1

### 3. The agent's labels
- **Goal:** every changed hunk of `b1` (periods and commas) carries GOOD, NEUTRAL or BAD from the agent, with the round-1 definitions (`agy-prompt.md`); BAD is a REGRESSION. `c1`'s hunks are `b1`'s comma hunks and are labelled once. Doubtful ones are marked. The labels are written before agy's output exists.
- **Files:** `r4/hunks-{b1,c1}.json`, `r4/my-labels.json`; `evidence/labels.md` (counts per candidate, kind, language and label).
- **Affects:** nothing.
- **Verify:** `python3 -I …/r4/labels_check.py` exits 0 and prints the counts: every hunk id of both hunk files has exactly one label from the allowed set, and the comma hunk sets of `b1` and `c1` are identical.
- **Status:** done: 304 hunks labelled before agy ran; evidence/verdict-summary.md, Labels
- **Depends on:** 1

### 4. agy blind pass and adjudication
- **Goal:** agy has labelled, without candidate names or the agent's labels, every period hunk, a seeded random 60 comma hunks and every hunk the agent marked doubtful. Each disagreement and each BAD from either side is adjudicated after reading the full record, with the reasoning written into `ROUND2-VERDICT.md`.
- **Files:** `r4/agy-sample.jsonl`, `r4/agy-key.json`, `r4/agy-prompt.md`, `r4/agy-labels.md`, `r4/adjudication.md`; `evidence/labels.md` extended with agy's counts and the number of disagreements.
- **Affects:** dictation passages go to agy (Gemini), approved with the brief.
- **Verify:** `python3 -I …/r4/agy_check.py` exits 0: one agy row per sample item, every period hunk in the sample, 60 seeded comma hunks present, and every item where either label is BAD or the two differ between BAD and not-BAD has an entry in `adjudication.md`.
- **Status:** done: 94 items, agy model "Gemini 4 Argon (High)"; 12 flagged hunks ruled on; evidence/verdict-summary.md
- **Depends on:** 3

### 5. Worth figures, verdict, items
- **Goal:** `ROUND2-VERDICT.md` gives H1-H5 and W1-W2 for `b1`, H1c, floor and W1c for `c1`, German live separately, and one verdict per candidate from the decision table. The items match: a passing candidate gets a new `planned` item and ROADMAP line (for `b1` with the owner's 2026-10-11 corrections), neither passing marks 50.1 `dropped` with the reason. The worktree is removed.
- **Files:** `ROUND2-VERDICT.md`; `evidence/verdict-summary.md` (counts and verdicts, no dictation text); `.flow/ROADMAP.md` and a new `.flow/NN-<slug>/ITEM.md` per passing candidate, or 50.1's ITEM.md.
- **Affects:** ROADMAP order; the memory note on the holdout round.
- **Verify:** `python3 -I …/r4/verdict_check.py` exits 0: it recomputes W1, W2, the comma floor and W1c from `r4/live-*.json`, reads the final REGRESSION counts from `adjudication.md` and `my-labels.json`, derives the verdicts from the decision table and asserts they equal the ones stated in `evidence/verdict-summary.md`; `git status --short` shows nothing outside `.flow/`; `git worktree list` shows one line.
- **Status:** done: both candidates closed by the decision table; `verdict_check.py` (which also covers the labels and agy checks) exits 0; worktree removed. The item status change waits for the owner's reading of the rulings (criterion 8)
- **Depends on:** 2, 4

## Criteria to tasks
1 → task 1. 2 → tasks 3 and 4. 3 → task 2. 4 → task 2 (H3, H4, synthetic) and task 5 (German live). 5 → task 5. 6 → tasks 1 (header) and 5. 7 → task 5. 8 `[judge]` → verify hands the owner `adjudication.md`.

## Departures from the brief
- One seeded sample of 60 comma hunks serves both candidates. The pre-registration asks 40 random comma hunks for `b1` and 60 for `c1`; the comma hunks of the two are the same set, so the 60 contain a valid 40.
- The German synthetic check (H5) is met by byte-identity with the frozen outputs, which were labelled at the freeze, as the 2026-10-29 run did. If an output differs, that case is labelled anew.
