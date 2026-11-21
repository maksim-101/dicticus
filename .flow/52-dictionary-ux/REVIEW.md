# Review of 52-dictionary-ux

Round 1 diff: d8f6410..c608f3e (merge-base with main; slice code unchanged since 2e48ccf).

Reviewers:
- Correctness: `code-review` skill at level medium on the branch against main; read the full diff and the touched services and views (DictionaryService, AddToDictionarySheet, HistoryView, DictionaryView, DictionaryGroupRow, WrappingLayout, the slice tests), no app or test run (data rules). 10 findings.
- Minimality: `lean-review-reviewer` (sonnet) over d8f6410..HEAD with the brief's outcome as goal; read BRIEF.md, PLAN.md excerpts, the non-test diff and call sites of `renameEntry` and `deleteSelected`. Verdict REVIEW, 3 findings, no `ask:scope`.
- Security: not run; standard slice, `Risk: none`, no risk trigger in the diff (local UI and the local dictionary store only).

Carried items: none.

| id | sev | summary | disposition |
|---|---|---|---|
| R1 | WARNING | `existingKey` matches case-insensitively, while the exact pass treats a single all-caps key and every key under the case-sensitive setting by case; adding "quib" can overwrite "QUIB" (checked: `DictionaryService.swift:538` vs `:380`) | fix (F1, regression test) |
| R2 | WARNING | a spelling can be saved that is another entry's heard form, so the exact pass replaces twice; own-forms clash check is exact-case (checked: `renameSpelling` / `addHeardForm`, sequential exact pass) | fix (F2, regression test) |
| R3 | WARNING | the sheet's typed Heard field is cut to letters and digits (`WordPick.trimmed`), so "C#" saves as "C" (checked: `AddToDictionarySheet.swift:19`) | fix (F3, regression test) |
| R4 | WARNING | the Raw view's words are pickable tokens, so a drag selection of Raw text no longer works; Copy still copies the whole text and Polished stays selectable | owner: a consequence of the chosen variant A (click words; variant B, free selection, not chosen); brief does not keep Raw selection. Question at verify: accept, or add selection back |
| R5 | WARNING | Undo restores the pre-sheet state even after a later edit of the same entry (checked: `undo()` restores without comparing) | fix (F4, regression test) |
| R6 | NIT | footer Add Entry accepts an empty replacement or one equal to the key (pre-existing) | fix (F5), one-line disable condition in a file the slice rewrote |
| R7 | NIT | row error messages share `duplicateWarning` and stay after Escape, disabling the footer Add | fix (F6) |
| R8 | NIT | confirming an unchanged rename rewrites the group's source to `.user` | fix (F7, regression test) |
| R9 | NIT | a token wider than the row overflows in `WrappingLayout` (long paths in Raw text) | fix (F8) |
| R10 | NIT | new views use `Color.orange` instead of the DESIGN.md `warning` token | won't fix: there is no Swift colour token for `warning`; the existing views use `.orange` (DictionaryView, AiCleanupPane) or a literal hex (HomePane), and introducing a token belongs to a design-token pass across all views |
| R11 | NIT | minimality: context-menu Delete duplicates `deleteSelected()` and skips `refreshEntries()` | fix (F9, one shared helper) |
| R12 | NIT | minimality: `removeHeardForm` is a thin wrapper over `removeReplacement` | won't fix: the guard skips a save of the live store when the form is already gone (a stale chip), which `removeReplacement` would write anyway |
| R13 | NIT | minimality: `HistoryRow.init` gains defaults used only by the render test | won't fix: the off-screen render (criterion 4 and 8 evidence) drives the row's pick and confirmation states through them; documented in the code |

Round 1 fixes: commit 6a32001 (mechanical-edit agent, sonnet; regression tests seen failing before each of F1-F4 and F7; slice tests 43 executed, 0 failures; iOS build succeeded). F3: `WordPick.text` already trims the pick, so only the model's whitespace trim changed.

## Round 2: c608f3e..6a32001

Reviewer: a fresh agent (opus), correctness rubric, given the range and the round-1 fix rows; read the diff, DictionaryService 320-640, the four views, the render test and the callers of `existingKey`, `addHeardForm`, `renameSpelling`, `undo`, `WrappingLayout`, `deleteGroups`, `restoreEntry`; ran nothing (the full check ran in parallel).

Round-1 rows resolved: R1 yes, R2 yes (over-broad, see R14/R15), R3 yes, R5 yes, R6 yes, R7 yes (gap R17), R8 yes, R9 yes in code (not render-checked), R11 yes.

| id | sev | summary | disposition |
|---|---|---|---|
| R14 | BLOCKER | `spellingClashReason` refuses a spelling whose case-variant key already maps to that same spelling ("github" → "GitHub": adding "git hub" to GitHub, picking GitHub in the sheet, or merging a row into GitHub is refused); checked `DictionaryService.swift:550-554` | fix step: return nil when the found key's replacement equals the spelling; regression test |
| R15 | WARNING | the own-forms check in `renameSpelling` became case-insensitive, refusing "Cloud" → "Claude" when the row holds "claude", which the exact pass handles idempotently; `addHeardForm` still accepts it, so the paths disagree; checked `:588` | fix step: back to exact equality; adjust the test at `DictionaryGroupTests.swift:116` |
| R16 | WARNING | the confirmation line now shows the failure style whenever `lastModel` is nil, so the off-screen render (built without a model) shows a failed confirmation; criterion 4/8 evidence `render-history-confirmation.png` changes; checked `HistoryView.swift:315-318` | fix step: a separate failed flag; re-render |
| R17 | NIT | Escape in a row's add-form field leaves the row warning showing | fix step |
| R18 | NIT | footer Add checks the untrimmed original, so a whitespace-only original enables Add | fix step |
| R19 | NIT | `fittedSize` measures each subview twice per layout pass | won't fix: two measurements per token on rows of at most a few hundred tokens |
| R20 | NIT | the footer Add Entry (`setReplacement`) and iOS `renameEntry` can still store a spelling that is another heard form; `Slice52RenderTests.swift:93` counts warnings against the shared store | defer: untouched code; noted in item 65 (iOS dictionary UX) and item 133 |
