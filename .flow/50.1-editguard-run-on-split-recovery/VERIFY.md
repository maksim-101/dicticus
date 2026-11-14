# Verify 50.1 (2026-11-14)

Outcome number: REGRESSION hunks among changed hunks, bar zero. Read: b1 15, c1 at least 7. Both candidates close.

| # | Criterion | Evidence | Verdict |
|---|---|---|---|
| 1 | snapshot input, cut-off, recount reproduced | evidence/snapshot-counts.md: 1324 lines, last record 2026-11-09T05:03:44Z, `repro.py` exit 0 with 27 / 47 / 227 and 0 differing records | pass |
| 2 | every hunk labelled, agy blind pass, rulings | evidence/verdict-summary.md, Labels; `verdict_check.py` asserts one label per hunk, one agy row per item, every flagged hunk ruled; the reviewer re-drew the sample from the seed. Limitation: the agent's first comma labels were shallow (REVIEW.md R1, R2) | pass, with the limitation stated |
| 3 | pinned tests on main with the frozen patch, hook on | patch hash in evidence/snapshot-counts.md; 21 tests, 0 failures for b1 and for c1. That the environment switch reaches the test process is inferred from round 1, where the same switch made a pinned test fail for two candidates; it was not shown again in this run | pass |
| 4 | H3, H4, German synthetic, German live separately | evidence/verdict-summary.md, Constraints: b1 H3 1 extra record, c1 0; H4 0; synthetic outputs byte-identical; German live INSUFFICIENT-LIVE for both | pass (evaluated and recorded; b1's H3 result is a fail of b1) |
| 5 | worth figures | W1 54 %, W2 24 records, comma floor and W1c 271, recomputed by `verdict_check.py` | pass |
| 6 | one verdict per candidate from the decision table, counts-only summary | `ROUND2-VERDICT.md` (untracked), evidence/verdict-summary.md; the reviewer confirmed each verdict is the table's | pass |
| 7 | items match the verdict; nothing changed outside `.flow/` and `.planning/` | `git diff --stat 4a6ffd6..HEAD` lists only `.flow/` files; the item is marked `dropped` at ship, after the owner's sign-off | owed at ship |
| 8 | `[judge]` the owner reads the overturned and disputed rulings | `r4/adjudication.md`: two comma flags overturned (13, 252), one agent-only period ruling (212), one standing comma ruling (43) plus the review's six | waits for the owner |

Departures from the brief read with the criteria: PLAN.md, Departures; the agy model name; three check scripts folded into one.
