# Brief 50.1: the verdict on recovering the LLM's sentence splits

## Outcome
The owner has a measured verdict, taken once by the rules written down on 2026-10-11, on whether the gate may keep the periods and commas the cleanup model inserts inside a long dictation: build candidate `b1` (periods and commas), build only `c1` (commas), or close 50.1 as measured and not shipped. The number read at verify is the count of REGRESSION hunks among all changed hunks of the snapshot; the bar is zero.

## Problem
In a long run-on dictation the cleanup model inserts sentence breaks, and the gate's rule `applySentenceCoupledRevert` throws them away together with a rejected edit elsewhere in the same sentence. On the dictations of 2026-10-11 to 11-02 (1114 records) the gate lost 47 inserted periods and 425 inserted commas this way. Round 1 of spike 017 failed four release rules, each on the same 3 bad hunks in 403. Round 2 froze two narrower candidates before any new log was read. Its single snapshot was due by the hard cap, 2026-11-09, and did not run: the project moved to flow on 2026-11-08 and the earlier approval lapsed. The 2026-11-02 recount (counts only) found 27 changed period hunks, above the cap rule's 20, so the snapshot takes a verdict.

## For whom
The owner, deciding whether a gate change is built. No user-facing change in this slice.

## Done criteria
1. `[check]` `new` The snapshot input is the union the recount names (rebuilt 10-11/10-12 records, the frozen copies of 10-29 and 11-02, and the copy frozen on 2026-11-14), de-duplicated by timestamp and cut at the owner's chosen end. Restricted to timestamps up to the recount's last record, the run reproduces the recount's numbers (27 changed period hunks, 47 lost periods, 227 comma hunks). Observed: the tally script's output in `evidence/`.
2. `[check]` `new` Every changed hunk of `b1` and `c1` carries a label from the agent; agy has blind-labelled every period hunk plus 40 random comma hunks for `b1` and 60 random comma hunks plus every doubtful one for `c1`. A REGRESSION from either labeller stands unless overturned in writing after reading the full record. Observed: label counts per candidate and labeller in `evidence/`.
3. `[check]` `adapt` The pinned tests (EditGuardCoupledRevertTests A-F, D15, Grammar Werden/Sind/Ist) pass on the day's main with the frozen patch applied (sha256 prefix `8bc83812a0f2e1bf` checked first) and the hook on, in a throwaway worktree. Observed: the test output.
4. `[check]` `adapt` The remaining hard constraints are evaluated and recorded: boundary-casing hits are a subset of main's, no token comes from neither source, the German synthetic set shows zero REGRESSION. German live hunks are reported separately, as `INSUFFICIENT-LIVE` below 20.
5. `[check]` `adapt` The worth figures are computed against their bars: share of lost periods `b1` recovers (30 %), records that regain a period (15), `c1` changed comma hunks (floor 100) and commas recovered (100).
6. `[check]` `new` `ROUND2-VERDICT.md` in the spike folder gives one verdict per candidate, read from the pre-registration's decision table with no change to either candidate. Any `b1` REGRESSION closes it as measured and not shipped, with no third round; `c1` is decided on its own. A counts-only summary, with no dictation text, goes to `evidence/verdict-summary.md`.
7. `[check]` `new` The items match the verdict: a passing candidate becomes a new `planned` item for its build (for `b1` with the owner's earlier corrections: zero REGRESSION as the bar, German evaluated separately, option (a) only on a win); if neither passes, 50.1 is `dropped` with the reason. No file outside `.flow/` and `.planning/` changes on this branch.
8. `[judge]` The owner reads every overturned REGRESSION and every hunk the two labellers disagreed on, with the full record beside it, and accepts or rejects the adjudication. With none of either, there is nothing to judge.

## Not in this slice
- Any change to shipped gate code. The hook stays a patch file in the spike folder.
- Tuning either candidate after seeing the snapshot, and any third round.
- The build of a winning candidate, on macOS and iOS together: a follow-on item.

## Constraints
- Pre-registration (`.planning/spikes/017-runon-split-recovery/PREREG-round2.md`): "Any edit to the rule after a holdout log has been opened voids the round." "Snapshot taken once."
- CLAUDE.md: "Dictation samples from the debug logs never enter a tracked file." Hunks, labels and the verdict document stay in the gitignored spike folder; `.flow/` gets counts only.
- The blind pass sends dictation hunks to agy (Gemini), as in round 1. It is the pre-registered second labeller; the app's own privacy rule concerns the shipped product, but the owner should know it at approval.
- The snapshot is five days late. The pre-registration says the cap snapshot is taken "with whatever exists" on 2026-11-09; the owner chooses the cut-off before any hunk is read, and the choice is written into the verdict document with its date.
- Slice 60 (merged 2026-11-14) turns a pause period into a comma before the gate. Whether the replay harness runs that step is checked in plan; it must act the same on main's output and both candidates.
- CLAUDE.md: "Cleanup pipeline changes ship on macOS and iOS together" (binds the follow-on build, not this slice).

## Size and risk
Standard: five or six tasks, no shipped code, no risk trigger. External: agy, already set up and used for round 1.

## Open
- What "option (a)" in the owner's 2026-10-11 correction refers to is not written down anywhere; it matters only if `b1` wins and is asked at the follow-on brief.
