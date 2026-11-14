# Plan 61: LFM3-1.7B retry

## Route
The harness exists: spike 022's scripts (`build_items.py`, `generate.py`, `gate_arms.py`, `metrics.py`, `prep_labels.py`, `score.py`, `latency.py`, 299 lines together, read for this plan), its rubric and its gate build, in `.planning/spikes/022-lfm3-cleanup-model/`. This slice copies them to a new spike folder `.planning/spikes/025-lfm3-retry/` and changes three things: the stop list gains `</corrected_text>` (the app's list since 2026-10-31), LFM3 gets its own prompt arm, and the verdict is taken on a holdout.

Choices that shape the result:

- **Verdict data. Chosen: a fresh holdout, AI-cleanup dictations of 2026-10-30 to 2026-11-12** from the frozen log copies, none of them in spike 022's dev set. Counted today: English 300 (119 drawn with a seed), German 59 (all taken; above the brief's floor of 40). Rejected: scoring on the 238 dev items again, which is cheaper but lets a prompt written on those items grade itself. The two days after 2026-11-12 are left out because part of them was logged under this week's changed pipeline.
- **How LFM3's own prompt is written. Chosen: at most five hand-written variants, tried on the dev items only, the winner picked by a rule fixed in the protocol** (most items that ship a change through the gate, among variants whose 30-item blind label sample shows no more than 3 harmful). Rejected: an open-ended prompt search, which fits the dev set harder and costs labels for every round.
- **Which LFM3 arm gets the verdict. Chosen: one arm, named on the dev set before the holdout is decoded** (L2, the written prompt, unless it does worse on dev than L1, the production prompt with the fixed envelope). The other arm is decoded on the holdout too and reported, without a verdict. Rejected: picking the better arm on the holdout, which gives LFM3 two tries at one bar.

Early signal that the route is wrong: task 2. If LFM3 with the stop string and its own envelope still fails closed on more than 20 of the 238 dev items, or ships a change on fewer than 50 (spike 022: 45 failed closed, 36 shipped), the envelope is not the cause and the owner hears it before any prompt work.

What a pass commits to: a build slice with an LFM3 download for devices under the 6.5 GiB threshold, a model-family-aware envelope in `CleanupService`, and a memory and speed check on a real 6 GB iPhone. A fail leaves the standing decision (AI Cleanup needs 8 GB) as it is.

Runs: about 1400 dev requests and 540 holdout requests against a local `llama-server`, one model loaded at a time, through the host's resource gate on mains power. Spike 022 measured medians of 1 to 3 s per request and a p90 up to 12 s for LFM3, which gives an expected 1.5 hours of GPU time in total, ceiling 3 hours. The model download is about 1.1 GB. Labels: about 200 distinct texts, by a Sonnet subagent and agy.

All texts, prompts, outputs and labels stay in the gitignored spike folder; `.flow/61-…/evidence/` gets counts and hashes.

## Tasks

### 1. Harness, model and fidelity
- **Goal:** the spike folder holds the copied scripts with the app's current stop list; the gate is rebuilt from today's main; the LFM3 file is downloaded and its sha256 starts with `3793e1e6e2266919`; both models decode deterministically; Qwen at temperature 0 reproduces the dev outputs of spike 022.
- **Files:** `.planning/spikes/025-lfm3-retry/*` (untracked); `evidence/setup.md`.
- **Affects:** disk (1.1 GB), GPU. Nothing shipped.
- **Verify:** `shasum -a 256 <LFM3 file>` shows the prefix; `python3 -I generate.py Q dev determinism` and `… L dev determinism` print `True` three times each; `python3 -I check_q_repro.py` exits 0 when at least 95 % of Qwen's new dev outputs equal spike 022's `out-dev-Q.jsonl` after the stop-string cut (a lower rate is investigated before anything else runs).
- **Status:** todo
- **Depends on:** none

### 2. L1 on the dev set: the envelope alone
- **Goal:** LFM3 under the production prompt, with the stop string and its own envelope, is decoded and gated on the 238 dev items; the counts stand beside spike 022's.
- **Files:** `data/out-dev-L1.jsonl`, `data/gate-out-dev-L1.jsonl`; `evidence/dev-envelope.md`.
- **Affects:** nothing.
- **Verify:** `python3 -I metrics.py dev` exits 0 and prints, per language, failed closed, shipped change, gate pass and rejected edits for Q and L1; `python3 -I early_signal.py` exits 0 when failed closed is at most 20 and shipped changes are at least 50, and exits 1 with the numbers otherwise (then the owner is told before task 3).
- **Status:** todo
- **Depends on:** 1

### 3. L2: one prompt written for LFM3, frozen
- **Goal:** at most five prompt variants are decoded and gated on the dev items; a blind 30-item label sample per variant bounds harm; the selection rule names the winner and the verdict arm; the protocol (arms, holdout draw, labelling, the owner's pass rule, the latency rule) is written and hash-locked with the winning prompt's hash.
- **Files:** `prompts/L2-v*.txt`, `data/out-dev-L2-v*.jsonl`, `PROTOCOL.md`, `PROTOCOL.sha256`; `evidence/dev-prompt.md` (counts per variant, the choice, both hashes).
- **Affects:** nothing.
- **Verify:** `python3 -I select_arm.py` exits 0 and prints the variant table and the chosen verdict arm by the rule; `shasum -a 256 -c PROTOCOL.sha256` passes; `ls data/out-hold-*` finds nothing at that moment (recorded in `evidence/dev-prompt.md`).
- **Status:** todo
- **Depends on:** 2

### 4. Holdout: draw, decode, gate, fidelity
- **Goal:** the holdout items (German all 59, English 119 with seed 61) are built from the frozen logs of 2026-10-30 to 2026-11-12; Q, L1 and L2 are decoded and gated under one gate build; the gate replays the logged model output to the logged result on at least 99 % of holdout records.
- **Files:** `data/items-hold.jsonl` and its hash, `data/out-hold-{Q,L1,L2}.jsonl`, `data/gate-out-hold-*.jsonl`; `evidence/holdout.md`.
- **Affects:** nothing.
- **Verify:** `python3 -I build_items.py hold` prints the counts and asserts no key is in the dev set and every timestamp is in the window; `python3 -I gate_fidelity.py hold` exits 0 at 99 % or more; `python3 -I metrics.py hold` exits 0.
- **Status:** todo
- **Depends on:** 3

### 5. Blind labels, adjudication, third reader, latency
- **Goal:** every distinct shipped holdout text of the three arms is labelled blind by a Sonnet subagent and by agy with spike 022's rubric; every disagreement and every harm label is adjudicated in writing; a fresh third reader checks 40 agreed labels and any it disputes are adjudicated too; latency is measured for Q and the verdict arm on 30 items per language when the one-minute load is under 4, or recorded as not measured.
- **Files:** `data/labels-*.jsonl`, `data/adjudicate-hold.md`, `data/latency.json`; `evidence/labels.md`.
- **Affects:** dictation texts go to agy (Gemini), approved with the brief.
- **Verify:** `python3 -I score.py hold` exits 0 and prints good and harm per arm and language; it asserts one final label per distinct text and that every disagreement and every third-reader dispute has an adjudication entry.
- **Status:** todo
- **Depends on:** 4

### 6. Verdict, summary, items, the owner's sample
- **Goal:** the verdict per language follows the owner's rule (verdict arm: at least 60 % of Qwen's good edits, no more harm than Qwen); `evidence/verdict-summary.md` holds counts, hashes and the verdict; a pass creates a `planned` build item, a fail records the reason in this item; ten holdout dictations drawn with seed 61 are laid out side by side (raw, Qwen, LFM3) in an untracked file for the owner's judgment.
- **Files:** `VERDICT.md`, `owner-sample.md` in the spike folder; `evidence/verdict-summary.md`; `.flow/ROADMAP.md` and a new ITEM.md on a pass.
- **Affects:** ROADMAP order; the memory note on spike 022.
- **Verify:** `python3 -I verdict_check.py` exits 0: it recomputes good and harm from the final labels, applies the rule, and asserts the verdict and every figure in `evidence/verdict-summary.md`; `git status --short` shows nothing outside `.flow/`.
- **Status:** todo
- **Depends on:** 5

## Criteria to tasks
1 → task 3 (protocol, hash lock) and tasks 1-2 (arms). 2 → tasks 2 and 3. 3 → task 4. 4 → tasks 1 and 4. 5 → task 5. 6 → tasks 5 (latency) and 6. 7 → task 6. 8 `[judge]` → task 6 prepares the sample, verify hands it over.

## Departures from the brief
- The holdout window ends on 2026-11-12, two days before the brief's "after 2026-10-29" would allow, to keep one pipeline for all records.
- German has 59 holdout items, not up to 119; the brief's floor is 40.
- One LFM3 arm gets the verdict, chosen on dev; the brief's criterion 6 said "the better L arm" for latency, which is now that same arm.
