# Criterion 1: the pause-period rule over this week's raw transcripts (2026-11-14, task 1)

Input: the raw ASR text of every AI-cleanup record with an LLM pass in `cleanup-2026-11-07.jsonl` to `cleanup-2026-11-14.jsonl` of the owner's live DebugRecordings folder (read at 06:10Z on 11-14; the folder grows during the day). Rule: a Python mirror of `RulesCleanupService.joinPausePeriods` (same regex `(\S+)\. ` before a lowercase letter, same abbreviation list, same digit, ellipsis and two-letter conditions); the Swift rule itself is covered by `RulesCleanupServiceTests` (11 tests, 0 failures; the four new tests fail with the rule removed: 3 failures in that run). Counts only; no transcript text leaves the folder.

| figure | count |
|---|---|
| AI-cleanup records with an LLM pass | 170 |
| records where the rule converts a pause period | 8 |
| legitimate period-plus-lowercase cases in the same texts (`bzw.`, `etc.`, `e.g.`, a number, an ellipsis) | 8 |
| of those changed by the rule | **0** |

Correction to the brief's figure: the "14 of 154" counted every period, question or exclamation mark followed by a lowercase word in the raw text, legitimate cases included; the ordinary-word pause periods among them, which the rule is for, were 6 at the time of the brief and are 8 in the 170 records of this run. The 7 shipped cases the brief counted include an ellipsis and a question mark that the rule leaves alone by design.
