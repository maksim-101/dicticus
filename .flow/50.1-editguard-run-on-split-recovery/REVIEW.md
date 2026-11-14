# Review 50.1

The branch's diff from 4a6ffd6 holds only `.flow/` records, so there is no code to review for correctness or minimality. The verdict rests on untracked work in `.planning/spikes/017-runon-split-recovery/r4/`, so the review was one fresh reader (opus, read-only) given the pre-registration, the scripts, the hunks, both label sets and the rulings, and asked five questions without the agent's conclusion. One round.

| # | Severity | Finding | Disposition |
|---|---|---|---|
| R1 | WARNING | c1's standing REGRESSION count was too low. Six more comma hunks (6, 67, 92, 112, 118, 141) have the defect the adjudication sustains for hunk 43: one half of a comma pair ships, the other does not, and a clause is split. None was in agy's sample; the agent had rated five good and one neutral. | Accepted. Two of the six confirmed by the agent from the hunk listing, four taken on the reviewer's reading. Labels revised with the first label kept, rulings added to `adjudication.md`, counts in `evidence/verdict-summary.md` and `ROUND2-VERDICT.md` corrected to c1 at least 7, b1 15. Verdicts unchanged. |
| R2 | WARNING | The agent's 304 labels were written within about three minutes of the hunk files: read them as shallow. | Accepted as a limitation and stated in the summary. No relabelling: both verdicts fail on hunks confirmed by a second reader, and more bad labels cannot change a closed verdict. |
| R3 | WARNING | A pair-aware comma rule would have to handle both directions (opening half and closing half). | Recorded in `ROUND2-VERDICT.md` as a note for any future candidate; not work for this slice. |
| R4 | NIT | b1's H3 failure is the same passage as REGRESSION hunk 30, not independent evidence. | Already stated in the summary; the verdict does not depend on it. |
| R5 | NIT | `verdict_check.py`: the ruling check accepts any bare number in the adjudication file; W1's numerator counts period hunks, not recovered inserts (equal here, 33); W1 and W2 count the bad period hunks as recoveries (without them 41 % and at least 16 records, both still met); it compares against the tracked summary only. | Won't fix: none changes a result on this data, and the script has no later use. |
| R6 | NIT | Three departures were not listed: the code base is main 4a6ffd6, not the pre-registration's commit; the 10-11 and 10-12 records are rebuilt from an audit dump (checked against 318 real records on 2026-10-29); two counts-only looks happened before the cap. | Added to the departures list in `ROUND2-VERDICT.md`. |

The reviewer's answers that confirm the result: both scripts exit 0; the overturns of hunks 13 and 252 are right (the partner comma ships in the same record); hunk 43 stands; the blind sample was drawn as required (the seed reproduces it, every period hunk and every doubtful hunk is in it); each stated verdict is the one the decision table gives.

No open BLOCKER or WARNING.
