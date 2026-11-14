---
id: 50.1
title: editguard-run-on-split-recovery
status: dropped
size: standard
assignee: agent
created: 2026-11-08
waiting_until:
shipped:
links:
---

# long dictations keep the LLM's interior sentence splits: measured, not shipped

Dropped on 2026-11-14 with the owner's sign-off. Spike 017 round 2 took its one pre-registered verdict on 1293 dictations (2026-10-11 to 2026-11-09): both frozen release rules fail the zero-REGRESSION bar. `b1` (isolated periods and commas) has 15 bad hunks of 304, two of the period hunks rated bad by both labellers. `c1` (commas only) has at least 7 bad hunks of 271: it releases one comma of a pair and splits a clause, with the opening half as well as the closing half. No gate code changed. By the pre-registration there is no third round without new evidence from a different source; a comma rule that knows about pairs would be a new candidate with its own round on fresh data.

Records: BRIEF.md, PLAN.md, REVIEW.md, VERIFY.md, evidence/verdict-summary.md (counts only). The full verdict with the passages is in the gitignored `.planning/spikes/017-runon-split-recovery/ROUND2-VERDICT.md`.
