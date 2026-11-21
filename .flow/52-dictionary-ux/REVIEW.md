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
