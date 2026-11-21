# Plan: 52-dictionary-ux

## Route

**Where the grouping lives.** Chosen: a pure grouping function and the group operations in `Shared/Services/DictionaryService.swift`, next to `renameEntry`, tested in `Shared/DicticusTests/`. Item 65 (iOS screens) then reuses them unchanged. Rejected: grouping inside the Mac view only; it cannot be tested without a UI host and item 65 would have to write it again.

**What makes two entries one row.** Chosen: the exact replacement string. On the owner's dictionary this gives 183 rows from 306 entries (counted 2026-11-14). Rejected: case-insensitive grouping; "claude" and "Claude" are different outputs, and renaming a merged row would silently change one of them.

**Storage.** Unchanged (`[heard form: DictionaryMetadata]` under `customDictionaryMetadata`); every group operation is a set of key-level edits followed by one `save()`. Rejected: a canonical-plus-aliases format, which needs a migration on a store with three data-loss incidents (brief, Not in this slice).

**The grouped list (mockup `dictionary-rows`, variant A).** Chosen: a SwiftUI `List` with alternating row backgrounds and a two-column header, each row a spelling cell and a wrapping row of chips. Rejected: keeping SwiftUI `Table`; its rows are sized for one line, and chips that wrap onto a second line (Gemini's five forms in the mockup) are the case the chosen variant shows. Both keep multi-selection for Delete Selected.

**Picking words in History (mockup `history-pick`, variant A).** Chosen: the raw text split into whitespace tokens, each a small view in a custom wrapping `Layout`, with hover highlight, click to pick and shift-click to extend (`NSEvent.modifierFlags` read in the tap handler). The token logic (which tokens, what text a pick yields, punctuation trimmed at the ends) is a pure function in `Shared/` with tests. Rejected: one `Text` with a link per word (`AttributedString` + `openURL`); it keeps native line breaking but cannot show the hover background, and links take the accent colour.

**Thinking ahead.** The group operations and the pick function are the shared base item 65 builds on. Nothing changes in matching (`applyExactPass`, fuzzy pass, guards), so the pipeline and the EditGuard tests are untouched; the earliest signal that the storage promise breaks is task 1's round-trip test through `loadGuarded`.

## Tasks

### Task 1: group model and group operations in the shared dictionary service
- **Goal:** `DictionaryService` can list groups and change them by group, without a new storage format. New: `struct DictionaryGroup` (spelling, heard forms sorted case-insensitively, newest `createdAt`, highest-priority `source`, `everydayForms`); `nonisolated static func groups(of:)` over an entries map; `addHeardForm(_:to:)` (a form that already exists as a key, compared case-insensitively, has that entry's replacement changed instead of a second key being added; returns `.saved`, `.invalid`); `removeHeardForm(_:)`; `renameSpelling(from:to:)` (every entry of the row gets the new spelling, `createdAt` kept, `source` promoted to `.user` as in `renameEntry`; refused with `.invalid` when the new spelling is empty or equals one of the row's own forms; a spelling equal to another row's merges the two rows); `removeGroup(spelling:)`; `isEverydayWord(_:)` (single token, NFC-lowercased, in `commonWords` or `lexiconWords`, the same sets Guard A uses). Every guard runs before any mutation; each operation ends in one `save()`.
- **Files:** `Shared/Services/DictionaryService.swift`; new `Shared/DicticusTests/DictionaryGroupTests.swift`.
- **Affects:** only new API; `apply`, `applyWithTrace`, `renameEntry` and import/export unchanged. The iOS target compiles `Shared/` and `Shared/DicticusTests/`, so the iOS suite runs the new tests too. Existing tests touching the same calls: `DictionaryEntryEditTests` (renameEntry contract, untouched), `DictionaryDataLossGuardTests` (loadGuarded, untouched).
- **Verify:** `cd macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:DicticusTests/DictionaryGroupTests -only-testing:DicticusTests/DictionaryEntryEditTests -only-testing:DicticusTests/DictionaryDataLossGuardTests test` prints `TEST SUCCEEDED`. The new tests cover: grouping of a fixture (several forms per spelling, two spellings differing only by case stay two rows, a spelling that is also another entry's key); each operation's effect and its refusals leave the dictionary unchanged; after every operation the persisted blob decodes through `loadGuarded` to the same map (criterion 3); `isEverydayWord("cloud")` true, an invented brand false; a form added through `addHeardForm` is rewritten by `applyWithTrace` on the next call (criterion 6). One test, `testLiveDictionaryGroupCount`, decodes a read-only copy of the owner's blob when `TEST_RUNNER_DICT_BLOB` names a file and prints the group and entry counts; it skips without it. Run once with the copy in the session scratchpad (never in the repo): expect `groups 183 entries 306`, unless the owner has edited the dictionary since, in which case the printed counts are compared with the same count taken by the exporting command.
- **Status:** done 095b336 (the plan's `everydayForms` field became the per-form `isEverydayWord` call; `existingKey` and `restoreEntry` added for task 3)
- **Depends on:** none

### Task 2: grouped Manage Dictionary window (mockup `dictionary-rows`, variant A)
- **Goal:** the Manage Dictionary window lists `groups(of:)` as rows: spelling column, "Heard as" chips with ×, a "+" chip that opens a small inline field to add a form, double-click on the spelling (and the Edit button) to rename the row, everyday-word chips outlined in the `warning` token colour, Delete Selected removing the selected rows, toolbar count "N words · M heard forms", sort Recent (source priority, then newest) and A–Z (by spelling). The footer's Add Entry form stays (heard form → spelling); an added entry whose spelling exists joins that row by construction.
- **Files:** `macOS/Dicticus/Views/DictionaryView.swift`; new `macOS/Dicticus/Views/DictionaryGroupRow.swift` (row and chip views).
- **Affects:** the window only. The menu-bar popover's `DictionaryPane` shows the entry count and an add form; unchanged. Import/Export, Starter Packs, Spoken Punctuation and Voice Commands sections unchanged.
- **Verify:** the macOS build and the dictionary tests: `cd macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:DicticusTests/DictionaryGroupTests test` prints `TEST SUCCEEDED`. The on-screen check is task 4.
- **Status:** done fd640b6 (plus `macOS/Dicticus/Views/WrappingLayout.swift`, shared with task 3)
- **Depends on:** task 1

### Task 3: pick words in History and add them from a sheet (mockup `history-pick`, variant A)
- **Goal:** in the History window's expanded row, the Raw view shows the raw text as pickable words (hover highlight, click picks, shift-click extends to the run between anchor and click); "Add to Dictionary…" appears under the text with the picked text; the Polished view is not pickable and shows the hint to switch to Raw. The sheet has "Heard as" (prefilled, editable) and "Correct spelling" (with the existing spellings offered), the note "Joins X, which has N heard forms" or "New word in the dictionary", the two non-blocking warnings (everyday word; form already in the dictionary pointing elsewhere), Add disabled while either field is empty or both are equal. Add calls `addHeardForm`; the row then shows "✓ Added: … Applies from your next dictation." with Undo, which restores the previous state of that one key.
- **Files:** new `Shared/Utilities/WordPick.swift` (tokens of a raw text, text of a pick with end punctuation trimmed); new `Shared/DicticusTests/WordPickTests.swift`; new `macOS/Dicticus/Views/AddToDictionarySheet.swift` (sheet and its small model: note, warnings, save, undo); new `macOS/DicticusTests/AddToDictionarySheetModelTests.swift`; `macOS/Dicticus/Views/HistoryView.swift` (Raw view, wrapping layout, button, sheet).
- **Affects:** `HistoryRow` only; the Copy buttons, search highlight and Polished view keep their behaviour. The History window gets `DictionaryService.shared` as an environment object where it is created (`macOS/Dicticus/DicticusApp.swift`). Popover `HistoryPane` unchanged.
- **Verify:** `cd macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:DicticusTests/WordPickTests -only-testing:DicticusTests/AddToDictionarySheetModelTests -only-testing:DicticusTests/DictionaryGroupTests test` prints `TEST SUCCEEDED`. The tests cover: picks of one word, a shift-extended run, a reversed run, end punctuation trimmed and inner punctuation kept, German umlauts; the model's note for a joining and a new spelling; both warnings ("cloud" as everyday word, an existing key with a different spelling) and no warning for an invented word; save through `DictionaryService.shared` (isolated suite) makes `applyWithTrace` rewrite the form (criterion 6); Undo of a new key removes it and Undo of a changed key restores its old spelling.
- **Status:** done 6ab10f1
- **Depends on:** task 1

### Task 4: on-screen check in the Mac test VM
- **Goal:** both flows observed in the built app on `mac-space`, never on the owner's screen, with screenshots for criteria 4 and 8.
- **Files:** new `.flow/52-dictionary-ux/evidence/vm-seed.sh` (writes a fixture dictionary of invented words into the guest's `com.dicticus.app` defaults and three fixture dictations into the guest's `History.sqlite` after a first launch has created it), screenshots under `.flow/52-dictionary-ux/evidence/`.
- **Affects:** the guest only. `mac-space` was running on 2026-11-14 at plan time, probably for another session: before use, check with `ListAgents` that no session holds it, and stop it afterwards only if this slice started it.
- **Verify:** in the guest, the app built with the Dicticus scheme (Debug, unsigned, `-derivedDataPath build`), seeded, launched; screenshots: the Manage Dictionary window with grouped rows and an everyday-word chip; History with a picked two-word run; the sheet joining an existing spelling; the sheet with both warnings; the confirmation line. Then `defaults read com.dicticus.app customDictionaryMetadata` in the guest decodes to the fixture plus exactly the one added form. The script exits non-zero if the seed or the read-back fails.
- **Status:** done 2e48ccf by headless rendering on the host (owner's choice; see Departures); the VM part stopped at the microphone prompt after seeding (b84f04b)
- **Depends on:** tasks 2 and 3

## Coverage of the done criteria

| Criterion | Covered by |
|---|---|
| 1 grouped rows (chips) and the 183-row count | task 1 (grouping tests, live count), task 2 (window), task 4 (screenshot) |
| 2 add / remove / rename / delete by row, existing rules kept | task 1 (operations and refusals), task 2 (controls) |
| 3 stored format unchanged | task 1 (round trip through `loadGuarded`); review checks the diff has no migration |
| 4 pick in Raw, sheet, join an existing row | task 3 (pick and model tests), task 4 (screenshots) |
| 5 two warnings, non-blocking | task 3 (model tests), task 4 (screenshot) |
| 6 takes effect on the next dictation | task 1 and task 3 (`applyWithTrace` after save) |
| 7 all suites green, live dictionary unchanged | build step 3: full macOS Dicticus and Dicticus-Debug-Recorder suites, iOS simulator suite (`cd iOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build/DerivedData -destination 'platform=iOS Simulator,name=iPhone 18 Pro' CODE_SIGNING_ALLOWED=NO test`), `shasum ~/Library/Preferences/com.dicticus.app.plist` before and after, `scripts/check-running-copy.sh` OK, simulator shut down |
| 8 look and feel | `[judge]` at verify, on task 4's screenshots next to the chosen mockups |

## Project working rules that apply

Tests use invented words only (public repo; no dictation text from the logs); every `xcodebuild` passes `-derivedDataPath build`; `scripts/check-running-copy.sh` after test runs; no Spotlight calls; the simulator is shut down after the iOS suite; GUI checks only in `mac-space`.

## Amendment 1 (BRIEF.md Amendment 1, criteria 9-13; approved by the owner 2026-11-21)

Route: keep the stored format and the group API of task 1; one shared "fix a word" component (markable polished text plus inline field) used in two places; the dictionary window gets a tab container so the reference sections leave the entries view. Colours: only those the current UI uses (DESIGN.md Don't, criterion 13). Each task's Verify uses the slice's targeted-test command shape from tasks 1-3 (`-derivedDataPath build`, `CODE_SIGNING_ALLOWED=NO`) with the named test classes, then `scripts/check-running-copy.sh`; screenshots only in mac-space.

### Task 5: fixes from the VM walkthrough (FIX.md F1a, F1b, F1e, F1f, F1g)
- **Goal:** the popover quick-add refuses an empty or identical replacement (F1a); the popover keeps its size with the add form open (F1b); opening the dictionary or another window from the popover closes the popover (F1e); removing a heard form and Delete Selected offer Undo (F1f, a confirmation line with Undo like the History one); double-click on a spelling starts the rename, checked on real input in the VM first (F1g; fixed only if it fails there too).
- **Files:** `macOS/Dicticus/Views/DictionaryPane.swift`, `PopoverRoot.swift`, `DictionaryView.swift`, `DictionaryGroupRow.swift`; tests in `macOS/DicticusTests/`.
- **Verify:** regression test for F1a seen failing first; F1f undo restores the removed keys (test through an isolated `DictionaryService`); F1b, F1e, F1g by VM screenshots.
- **Status:** done 7f42bac, inline: UI fixes across five small views, each a few lines (F1a guard moved into `setReplacement` so every add path refuses an empty spelling; `closePopover` also called from History and Settings buttons). VM screenshots for F1b, F1e, F1g owed to the mac-space turn after task 6.
- **Depends on:** none

### Task 6: dictionary window with tabs and search (criterion 12; ends F1j)
- **Goal:** tabs at the top "Entries | Spoken Punctuation | Voice Commands", each filling the window and scrolling itself; on Entries a rounded search field with magnifier and clear button above the list, ⌘F focuses it, filtering by spelling or heard form (case-insensitive, diacritics-insensitive), count "N of M words" while filtering; footer "Add ▾" menu (Add Entry…, Import CSV…, Starter Packs ▸ three packs) next to Edit; the Starter Packs paragraph goes; the Case Sensitive toggle goes from the Mac window (the shared setting stays at its stored value, false for the owner; the iOS toggle stays until item 65).
- **Files:** `macOS/Dicticus/Views/DictionaryView.swift` (split into the tab container and an entries view); filter function in `Shared/Services/DictionaryService.swift` or a small helper; tests in `Shared/DicticusTests/DictionaryGroupTests.swift`.
- **Verify:** filter tests (spelling match, heard-form match, no match, umlaut); VM: each tab, a filtered list, and opening Spoken Punctuation with the window still responding (clicks reach the list after switching back).
- **Status:** done d7a2ab4, inline: one view restructured, each result reshaped the next edit. Same commit narrows 7f42bac's guard: identical pairs anchor the fuzzy pass, and five matching tests failed in the full macOS run (log kept in the session only). Import moved into the Add menu as "Import CSV…" (still reads JSON). VM part owed to the next mac-space turn.
- **Depends on:** none

### Task 7: shared fix-a-word component (criterion 9)
- **Goal:** a view that shows a dictation's polished text as markable words (click marks one, drag or shift-click marks a run; whole words, end punctuation trimmed, reusing `WordPick`), and on marking opens "Heard as" (the marked text) and "Correct spelling" (focused) inline; Return adds through `addHeardForm` (joins a known spelling), Escape cancels; everyday-word and clash warnings next to the field, non-blocking; then "Added: … Applies from your next dictation. Undo". The sheet's model is reused for note, warnings, save and undo; the sheet itself goes.
- **Files:** new `macOS/Dicticus/Views/FixWordView.swift`; `AddToDictionarySheet.swift` (model kept, view removed or renamed); `Shared/Utilities/WordPick.swift` if polished-text tokens need a change; tests `AddToDictionarySheetModelTests`, `WordPickTests`.
- **Verify:** model tests carried over (warnings, join note, save makes `applyWithTrace` rewrite, undo); a drag-run pick test on polished text.
- **Status:** done a927763, inline: a gesture and layout loop. The sheet view stays until task 9 removes its last caller (History).
- **Depends on:** none

### Task 8: popover Home card (criterion 10)
- **Goal:** the card is titled "Last dictation · time · language", its polished text uses task 7's component in place, "‹ earlier" / "›" step through recent dictations, Copy is the only button; "Revert to Raw" and its code path go.
- **Files:** `macOS/Dicticus/Views/HomePane.swift`; whatever only Revert to Raw used.
- **Verify:** build and the existing HomePane-related tests; VM screenshots of the three steps.
- **Status:** done e46d01d, inline: one view. No HomePane tests exist; RevertToRawTests keeps only its hotkey test. The Revert-to-Raw hotkey (Settings → Hotkeys) shares the paste function and stays. VM screenshots owed to task 10.
- **Depends on:** task 7

### Task 9: "Fix a word" window (criterion 11)
- **Goal:** a window with recent dictations on the left (last one preselected and highlighted) and the chosen one large on the right with task 7's component, even spacing; opened in one click from the popover (Home card and History tab). The History window's Raw-view pick and its sheet go; its rows keep Copy and search, and a row's "Fix a word…" opens this window on that dictation.
- **Files:** new `macOS/Dicticus/Views/FixWordWindow.swift`; `DicticusApp.swift` (window scene); `HistoryView.swift`, `HistoryPane.swift`.
- **Verify:** build; VM screenshots of the window in the three steps and of the route from the popover.
- **Depends on:** task 7

### Task 10: full check and VM evidence for criteria 4, 5, 8-13
- **Goal:** the three suites green, the owner's dictionary blob unchanged (checksum), and a VM walkthrough with screenshots of every new screen next to the round-2 boards for criterion 8.
- **Verify:** as criterion 7; screenshots under `evidence/` named after their criterion.
- **Depends on:** tasks 5-9

## Departures from the brief

- Criteria 4 and 8 name screenshots "in the Mac test VM". On 2026-11-14 a macOS microphone prompt blocked the app windows in mac-space and refused synthetic input; the owner chose "Render headless on this Mac": a test renders the windows off-screen on the host with invented data. These images show the real SwiftUI layout but no launched app and no click-through.
