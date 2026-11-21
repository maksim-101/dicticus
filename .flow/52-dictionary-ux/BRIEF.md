# Brief: 52-dictionary-ux (approved by the owner 2026-11-14)

## Outcome

On the Mac, the owner sees the dictionary as one row per correct spelling with all its misheard forms on that row, and can turn a misheard word in a past dictation into a dictionary entry from History in a few clicks, without retyping the misheard form. On the owner's dictionary the list shrinks from 306 rows to 183.

## Problem

- The dictionary stores one entry per misheard form (key = what the recognizer wrote, value = the correct spelling). On the owner's live dictionary (read 2026-11-14, counts only): 306 entries, 183 distinct correct spellings; 59 spellings have between 2 and 9 misheard forms, and those take 182 of the 306 rows. The Mac list (`macOS/Dicticus/Views/DictionaryView.swift`) shows every entry as its own row, so the forms of one word are scattered, and changing a spelling means editing each entry.
- Adding an entry means reading the misheard form off a dictation and typing both sides by hand in Settings. History (`macOS/Dicticus/Views/HistoryView.swift`) shows the raw recognizer text of each dictation (`TranscriptionEntry.rawText`, the input of `TextProcessingService` before the dictionary runs), but it has no path into the dictionary. Its text is a SwiftUI `Text` with `.textSelection(.enabled)`, which lets the owner copy a selection but does not tell the app what was selected.
- Nothing warns when a misheard form is an everyday word: an entry `cloud → Claude` rewrites every "cloud" dictated afterwards. The bundled EN+DE lexicon (`BrandMatcher.shared.combinedLexicon`, 518k words) is already loaded and could say so.

## For whom

The owner, on the Mac, after noticing a recurring mishearing: either in the Dictionary settings while tidying entries, or in History right after a dictation came out wrong.

## Done criteria

1. `[check]` `new` The Manage Dictionary window lists one row per correct spelling, with its misheard forms shown on the row as chips (mockup `dictionary-rows`, variant A: a "Correct spelling" column and a "Heard as" column of chips, each chip with its own ×, a "+" chip to add a form, an everyday-word form outlined in the warning colour; the toolbar counts words and heard forms). Observed: a unit test of the grouping over a fixture (several forms per spelling, case variants of one spelling, a spelling that equals another entry's key), and a count over the owner's live dictionary read without writing: 183 groups from 306 entries.
2. `[check]` `adapt` From a row the owner can add a misheard form, remove one form, change the correct spelling for the whole row, and delete the row. Each is a `DictionaryService` operation covered by a test; rules of the existing `renameEntry` hold (`createdAt` kept, an edited entry becomes `source: .user`, a clash with an existing key is refused before anything changes).
3. `[check]` `exists` The stored format does not change: the persisted blob is still `[heard form: DictionaryMetadata]` under `customDictionaryMetadata`, decoded by the shipped decoder. Observed: a test that encodes after each group operation and decodes with `loadGuarded`; no migration code in the diff.
4. `[check]` `new` In History, in the Raw view of a dictation, the owner clicks a word to pick it, shift-clicks another to extend the pick to the run of words between them, and presses "Add to Dictionary…" under the text (mockup `history-pick`, variant A; whole words only, punctuation at the ends dropped; in the Polished view nothing is pickable and a hint says to switch to Raw). A sheet opens with the picked text as the misheard form; the owner types the correct spelling and saves. If that spelling already has a row, the form joins that row. Observed: a UI-level test of the sheet's save path into a test `DictionaryService`, and a screenshot of the flow in the Mac test VM.
5. `[check]` `new` The sheet warns, without blocking, when the misheard form is an everyday word in the EN/DE lexicon, and when the form is already an entry pointing to a different spelling. Observed: tests with "cloud" (lexicon word) and with an existing key.
6. `[check]` `exists` An entry added from History takes effect on the next dictation: `applyWithTrace` over the saved misheard form returns the correct spelling. Observed: a test through the same service the pipeline uses.
7. `[check]` `exists` The macOS test suites (Dicticus and Dicticus-Debug-Recorder schemes) and the iOS simulator suite pass (the dictionary code is shared), and the owner's live dictionary blob is byte-identical before and after the test runs (checksum).
8. `[judge]` `new` The grouped list and the add-from-History flow look and feel right, judged on screenshots of the built app in the Mac test VM with a fixture dictionary, next to the chosen mockups: `mockups/dictionary-rows.png` (variant A, left) and `mockups/history-pick-2-sheet-join.png` / `history-pick-4-warnings.png` (variant A, left window; the sheet is shared).

## Amendments (owner, 2026-11-21, at verify; mockup rounds 1-2)

Criterion 4 changes: picking works on the polished text, not on Raw; no Raw/Polished switch, no "Add to Dictionary…" button and no sheet. Criteria 5 and 6 keep their expectations for the inline field. Criterion 8 is judged against the round-2 boards below.

9. `[check]` `new` Fix a word inline (mockup `pointer-r2`, variants A and B together): marking one word, or a run of words by drag or shift-click, in the polished text fills "Heard as" and opens a "Correct spelling" field under the text with the cursor in it; Return adds (through the group-aware path, so a known spelling joins its row), Escape cancels, then the line "Added: … Applies from your next dictation. Undo". The everyday-word and clash warnings of criterion 5 show next to the field, without blocking. Observed: tests of the add path and the warnings; screenshots in the Mac test VM.
10. `[check]` `new` Variant A: the popover's Home card is titled with the dictation it shows ("Last dictation · time · language"), its polished text is markable in place, "‹ earlier" steps to older dictations, Copy is its only button; "Revert to Raw" is removed. Observed: VM screenshots of the three steps.
11. `[check]` `new` Variant B: a "Fix a word" window with recent dictations on the left (the last one preselected and highlighted) and the chosen dictation large on the right, reached in one click from the popover; even white space (owner: "not every space is being used ... the white space is uneven"). Observed: VM screenshots; owner judges the look.
12. `[check]` `new` Dictionary window (mockup `dictionary-window-r2`, variant B): a rounded search field with a magnifier and a clear button above the list filters rows by spelling or heard form, ⌘F focuses it, the count reads "N of M words"; tabs at the top "Entries | Spoken Punctuation | Voice Commands" each fill the whole window, with their own scrolling; Starter Packs and Import CSV sit in an "Add ▾" menu next to Add Entry; the Case Sensitive toggle is removed (matching stays case-insensitive except a single all-caps key, as today). Observed: a filter test; VM screenshots of each tab; opening Spoken Punctuation leaves the window responsive (F1j).
13. `[check]` `exists` No new colours: the views use the colours the current UI uses (system and semantic colours, the existing accent); the green of the mockups' sidebar and selection is not taken over (owner: "don't just add new colors if you feel like it").

## Not in this slice

- iPhone and iPad screens: item 65 (`.flow/65-dictionary-ux-ios/`), owner's choice "Mac first" (2026-11-14).
- A "say the word again" teaching panel and a spoken "add to dictionary" command: not chosen by the owner (2026-11-14). The spoken correct spelling would be misheard the same way, so the correct spelling is always typed.
- Suggested entries mined from the logs or from post-paste edits: item 58 and SEED-003.
- Any change to how matching works (exact pass, fuzzy pass, guards). Search in the dictionary window moved into the slice by amendment 12.
- A canonical-plus-aliases storage format.
- Free text selection with a right-click "Add to Dictionary…" in History (mockup `history-pick` variant B, not chosen), and picking parts of a word.

## Mockup choices (2026-11-14)

- `mockups/dictionary-rows.html`: variant A, table with chips (B list-and-detail and C expandable rows not chosen).
- `mockups/history-pick.html`: variant A, click words (B select and right-click not chosen).

## Constraints

- Mac only; `Shared/` changes must keep the iOS target building and its suite green (CLAUDE.md, Shared change: "verify both platforms build").
- Dictionary data has been lost three times before (memory `reference_dictionary_persistence`; the init data-loss guard of 2026-07-19 and the rolling backup in `save()`). Every write goes through `DictionaryService.save()`; tests use their own store and never the owner's (`DicticusDefaults.suite` is ephemeral under test since 260724-9v8); criterion 7 checks it.
- Dev builds compiled with `PERSONAL_LEXICON` re-seed a deleted entry whose key is in the personal lexicon on the next launch (documented limitation in `renameEntry`). Removing such a misheard form from a row has the same effect as today's delete; the brief does not fix it.
- "Dictation samples from the debug logs never enter a tracked file" (CLAUDE.md): fixtures use invented words; the live dictionary is read for counts only.
- GUI checks run in the Mac test VM (`agent-vm`), never on the owner's screen.

## Size and risk

Standard. No risk trigger: no migration and no new deletion path beyond what the owner triggers by hand. Expected tasks: grouping and group operations in `DictionaryService` with tests; the grouped Dictionary pane; the History pick-and-add sheet with its warnings; the full check. Four tasks, under the limit.

## Open

- Search in the Dictionary pane: later, if 183 rows are still too many.
