# State of 50.1-editguard-run-on-split-recovery
Slice: 50.1-editguard-run-on-split-recovery (standard)
Step: done
Next: nothing for this slice. The item is dropped: measured, not shipped. The next item in ROADMAP.md is 52-dictionary-ux, briefed when the owner asks.
Waiting on: nothing
Started: 2026-11-14T08:01:00Z
Baseline: not rerun: this branch changes no file outside .flow/, and main 4a6ffd6 carries slice 60's close (macOS Dicticus 1960 tests 0 failures, Debug-Recorder 2042, iOS simulator 1780; 60 STATE.md History)
Base: branch point
Risk: none
Carried: none

## Decisions
- 2026-11-14 brief: approved by the owner ("Approve, cut at 9 Nov"): the snapshot holds dictations up to the end of 2026-11-09, as pre-registered; agy (Gemini) is the blind second labeller, as in round 1.
- 2026-11-14 plan: approved by the owner ("approved"); the approval is the go for the verdict run up to 60 minutes of compute.
- 2026-11-14 verify: the owner signed off ("signing off on the verdict"): both candidates closed, 50.1 measured and not shipped; no ruling reopened.

## History
- 2026-11-14 50.1 brief: branch flow/50.1-editguard-run-on-split-recovery from main 4a6ffd6. Root `## Incoming` (three GSD handover lines, each checked still open) settled into root `Carried:`. Found: the verdict run due 2026-11-09 never ran. Cleanup logs of 2026-11-02 to 11-14 (320 lines, 191 of them up to 11-09) copied unread to `.planning/spikes/017-runon-split-recovery/holdout-logs-2026-11-14/` before the 14-day retention deletes them from 2026-11-16. The gate code (Shared/Utilities/EditGuard.swift) has no commit since the 11-02 recount. The item's other two carried-in lines became BRIEF.md criteria 6 and 7 and its Constraints. BRIEF.md written, waiting for approval.
- 2026-11-14 50.1 build: task 1: snapshot of 1293 records built and replayed on main 4a6ffd6 in a throwaway worktree; the 2026-11-02 recount reproduced exactly (27/47/227, 0 differing records). Tasks 2-5: H2 passes for both candidates (21 tests, 0 failures), H4 0, synthetic outputs byte-identical to the frozen ones; b1 fails H3 (1 extra record) and H1 (9 REGRESSION hunks standing, 2 rated bad by both labellers); c1 fails H1c on 1 comma hunk of 271 (rated bad by agy; full record read, not overturned: an unpaired half of a comma pair); 2 other agy comma flags overturned as pairs that ship together. Worth bars met for both. Verdict by the decision table: both closed, measured and not shipped (evidence/verdict-summary.md; `verdict_check.py` exit 0). Departures: agy model "Gemini 4 Argon (High)" because the round-1 model no longer exists (first attempt failed on the name before sending anything); the plan's separate labels_check and agy_check are folded into verdict_check.py; evidence/hard-constraints.md and evidence/labels.md are folded into evidence/verdict-summary.md; task 2's Verify expected h34.py to exit 0, which was wrong for a measurement. Worktree removed; check-running-copy OK after the test run. No full check run: the branch changes nothing outside .flow/. Review diff start 4a6ffd6.
- 2026-11-14 50.1 review: one fresh read-only reviewer on the untracked verdict work; no BLOCKER; R1 WARNING accepted: six more comma REGRESSION hunks of the same kind as the standing one, missed by the agent's shallow first labels, so c1 fails on at least 7 of 271 and b1 on 15; verdicts unchanged (REVIEW.md).
- 2026-11-14 50.1 verify: criteria 1-6 pass, 7 owed at ship, 8 waits for the owner (VERIFY.md). (The two lines above and this one are newer than the line below.)
- 2026-11-14 50.1 brief: approved with the cut-off at the end of 2026-11-09; the harness feeds the gate the logged post-rules text, so slice 60's pause rule is not replayed (BRIEF.md Constraints).
- 2026-11-14 50.1 ship: closed as dropped (measured, not shipped) on the owner's sign-off; ITEM.md dropped, ROADMAP line removed, root file back to Slice: none, all three carried lines done (the run was approved with the plan, the item is dropped here, the Incoming settlement merges with this branch). No tag, no deploy, no smoke check: no code changed. Scorecard 2026-11-14T08:01:00Z to ship: wall-clock 1.0 h, active agent time 0.9 h, owner inputs 2 typed + 2 slash, 1 question, 1 subagent run. Lines added against 4a6ffd6: .flow 176 (evidence 74 separate), code 0, tests 0. No production bug or user report was fixed in this slice.
