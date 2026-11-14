# Task 1: snapshot input, replay, reproduction (2026-11-14)

Counts only; inputs, outputs and scripts are in the gitignored `.planning/spikes/017-runon-split-recovery/r4/`.

- Patch: `shasum -a 256 017-hook-b1c1.diff` → `8bc83812a0f2e1bf2a73af6b2eaf13b42ca4c3ecdfa158dfe04fb05f2cee2441`; applied cleanly to a detached worktree at main 4a6ffd6.
- Input (`build_input.py`): 1142 lines from the recount's input, 182 added from the 2026-11-14 freeze, 9 duplicates dropped, 129 lines after 2026-11-09T23:59:59Z dropped. 1324 lines on 30 days, first 2026-10-11T03:48:01Z, last 2026-11-09T05:03:44Z. The harness loaded 1293 records with a model output (EN 1095, DE 198).
- Reproduction (`python3 -I …/r4/repro.py`, exit 0):

```
b1 hunks {'comma-insert': 227, 'dot': 27} unexpected 0 records whose output differs from r3: 0
c1 hunks {'comma-insert': 227} unexpected 0 records whose output differs from r3: 0
w0 records whose output differs from r3: 0
repro ok: dot 27, lost-dot 47, comma 227, unexpected 0
```

- Whole snapshot (`tally4.py`):

| quantity | EN | DE | total |
|---|---|---|---|
| period inserts main loses | 57 (38 records) | 4 (4 records) | 61 |
| comma inserts main loses | 469 | 36 | 505 |
| b1 changed hunks, period / comma | 32 / 263 | 1 / 8 | 304 in 148 records |
| b1 records regaining a period | 23 | 1 | 24 |
| c1 changed hunks (all comma) | 263 | 8 | 271 in 143 records |
| unexpected verdict changes | | | 0 |

The protocol header of `ROUND2-VERDICT.md` (cut-off, the owner's choice and date, commit, patch hash, input) was written before any hunk was opened.
