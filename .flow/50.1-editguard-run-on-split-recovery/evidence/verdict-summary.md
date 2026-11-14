# Spike 017 round 2: verdict summary (2026-11-14, counts only)

The full verdict with the adjudicated passages is in the gitignored `.planning/spikes/017-runon-split-recovery/ROUND2-VERDICT.md` and `r4/adjudication.md`. Snapshot: 1293 records, 2026-10-11 to 2026-11-09 (cut-off chosen by the owner before any hunk was read), replayed on main 4a6ffd6 with the frozen patch (sha256 prefix 8bc83812a0f2e1bf).

Recomputed by `python3 -I …/r4/verdict_check.py` (exit 0, prints `verdict check ok`):

| figure | value |
|---|---|
| b1 REGRESSION hunks | 15 |
| c1 REGRESSION hunks | 7 |
| period hunks | 33 |
| lost periods | 61 |
| W1 percent | 54 |
| W2 records | 24 |
| comma hunks | 271 |
| German period hunks | 1 |
| German comma hunks | 8 |
| unexpected verdict changes | 0 |
| b1 verdict | CLOSED: measured, not shipped |
| c1 verdict | CLOSED: measured, not shipped |

## Constraints, as pre-registered

| constraint | b1 | c1 |
|---|---|---|
| H1 / H1c: zero REGRESSION among changed hunks | **fail**: 15 stand (8 period hunks, 2 of them rated bad by both labellers, and the 7 comma hunks) | **fail**: at least 7 stand (1 rated bad by agy and not overturned after reading the full record, 6 more of the same kind found by the independent review) |
| H2: pinned tests with the hook on | pass, 21 tests 0 failures | pass, 21 tests 0 failures |
| H3: boundary-casing hits a subset of main's | **fail**: 1 extra record (the same passage as one unanimous REGRESSION) | pass, 0 extra |
| H4: no token from neither source | pass, 0 | pass, 0 |
| H5 / H5c: German synthetic, zero REGRESSION | pass: 15 outputs byte-identical to the outputs labelled at the freeze | pass, same |
| German live | INSUFFICIENT-LIVE (1 period hunk, under 20) | INSUFFICIENT-LIVE (8 comma hunks, under 20) |
| Worth | W1 54 % (bar 30), W2 24 records (bar 15): met | floor and W1c 271 (bar 100): met |

## Labels

- The agent labelled all 304 changed hunks of b1 before agy ran: period hunks 27 good, 3 neutral, 3 bad; comma hunks 256 good, 15 neutral, 0 bad. c1's 271 comma hunks are the same hunks.
- agy ("Gemini 4 Argon (High)"; the round-1 model name no longer exists) labelled 94 items blind: all 33 period hunks (23 good, 3 neutral, 7 bad) and 61 comma hunks, 60 drawn with seed 20261114 plus the one the agent marked doubtful (28 good, 30 neutral, 3 bad).
- Flagged bad by either labeller: 9 period hunks and 3 comma hunks. Rulings: 2 comma hunks overturned (each is one comma of a pair whose other comma ships in the same record, which agy could not see); 1 comma hunk stands (half of a pair whose other half is not released, so the output gains an unpaired comma); the period hunks stand, 3 of them without an overturn attempt because b1 fails on the 2 unanimous ones either way.

- The independent review (REVIEW.md) then found 6 more comma hunks with the same defect as the standing one, outside agy's sample, all of which the agent's first pass had rated good or neutral. The agent's comma labels were too shallow; its "0 bad of 271" does not hold. The first labels are kept beside the revised ones. The review's scan is a heuristic, so 7 is a lower bound.

## Verdict, from the pre-registration's decision table

- **b1** (periods and commas): an H fails, so 50.1's split recovery closes as measured and not shipped. No third round without new evidence from a different source.
- **c1** (commas only): H1c fails on at least 7 hunks in 271 (2.6 %), so it closes. The failure is the rule's own behaviour: it releases a lone comma without knowing that it is half of a pair, and it happens with the opening half as well as the closing half.

For the owner (criterion 8): the two overturned comma rulings and the one agent-only period ruling, with the passages, are in `r4/adjudication.md`. Neither can change a verdict.
