# 54 review

Diff: `flow/54-context-from-app-category` from 3f084ce (`git merge-base main HEAD`), code files only (`Shared/`, `macOS/`, tests); `.flow/` bookkeeping excluded. Risk: none, so no security run. Reviewers: `code-review` at medium (correctness), `lean-review --no-fix --range 3f084ce..HEAD` (minimality, reviewer model sonnet), each with the data rule that dictation text from the debug logs and the gitignored planning tree never enters an output. Working rules checked against the diff by the main loop: no `mdfind` or Spotlight call (the reader goes through `Bundle(url:)`), no personal data or dictation text in tracked files, Shared change compiled by both platforms (iOS suite green at build close).

STATE.md `Carried:` holds three 50.1 brief items and nothing from this slice, so no carried row.

## Round 1

| id | severity | source | finding | disposition |
|---|---|---|---|---|
| R1 | NIT | lean `ask:scope` | Removing `curatedMap` drops Mail, Messages and Slack from `.prose` to `.default`. | **won't fix**, not an owner question: the brief records that `.prose` and `.default` build the same prompt (`CleanupPrompt.swift`, the `case .prose, .default:` branch), and the owner's scope decision of 2026-11-13 keeps a built-in list only for terminals. The only visible change is the local log's `resolved_context` reading `default` instead of `prose` for those apps. |
| R2 | NIT | lean `fix:auto` | `AppCategoryReader.plistReads` is a test-only counter in production code. | **won't fix**: PLAN.md task 2's Verify names "a counter on the loader" for the read-once assertion; it is a private-set integer with no behaviour. |
| R3 | NIT | lean `fix:confirm-intent` | The per-URL cache was not asked for by the goal. | **won't fix**: the brief's Constraints ("cached per bundle URL for the app's lifetime") and the plan's route choose it, so the press-time path reads one plist per new app. Known limit, recorded: an app updated in place keeps its cached category until Dicticus restarts; categories do not change in practice. |
| R4 | NIT | lean `fix:auto` | `liveResolvedContext()` and the press-time path repeat the frontmost → bundle ID → category → resolve sequence. | **won't fix** in this slice: the twin predates it and the plan named both sites; the global rule extracts a helper on real reuse, which a later change to both sites would be. |

| R5 | WARNING | code-review | `AppCategoryReader` cached a failed plist read (bundle missing or unreadable, e.g. mid-update) as "no category" for the process lifetime, so one transient failure demoted an app to the default prompt until restart; Xcode and VS Code had no I/O dependency before this slice. Claim checked: `Bundle(url:)` returns nil for a missing bundle and the old code wrote `.some(nil)` unconditionally. | **fix**: the plist is read as a dictionary from `Contents/Info.plist` and cached only when the read succeeds; regression test `testUnreadablePlistIsNotCached` (fails on the old reader: 3 failures, then passes). |
| R6 | WARNING | code-review | The developer-tools rule covers a class of prose-first apps, not one exception: on this Mac Linear, Hermes and Claude desktop declare `public.app-category.developer-tools` (reviewer checked with plutil); nothing tells the user which apps took the code prompt. | **won't fix** as a rule change, it is the brief's recorded decision ("the code prompt goes to every app that declares developer tools", Claude desktop named; the A/B of 2026-08-02 found the code prompt no worse on prose; criterion 4 and the `[judge]` sample re-check). The popover already shows the live resolution ("Current resolution: …", `PopoverHeader.swift`). Linear and Hermes go to the verify hand-over as further apps the rule covers, so the owner judges with the full list. |
| R7 | WARNING | code-review | No round-trip or tolerant-decode test for `app_category`, though the record has a hand-written decoder and CodingKeys; every earlier field got both. | **fix**: `testDebugCleanupRecordCodableRoundTrip_AppCategory` and `testDebugCleanupRecordDecode_TolerantToMissingAppCategory` added. |
| R8 | NIT | code-review | The per-URL cache never invalidates, so an app updated in place with a changed category is seen after a restart. | **won't fix**: same limit as R3, recorded there; a category change in place is rare and corrected by relaunching Dicticus. |
| R9 | NIT | code-review | Key-down does a synchronous plist read on the main actor for every first-seen app, and the popover render too. | **won't fix**: the brief's Constraints accept "one Info.plist read per key press, cached per bundle URL"; the plist belongs to the app that is running in front, so it sits on a volume that is already serving that app. |
| R10 | NIT | code-review | `Bundle(url:)` pins an `NSBundle` per app for the process lifetime. | **fix**, folded into R5: the reader uses `NSDictionary(contentsOf:)` on `Contents/Info.plist` and holds no bundle. |
| R11 | NIT | code-review | `plistReads` is a test-only counter in production code. | **won't fix**: duplicate of R2 (plan's Verify names the counter). |

Lean verdict: REVIEW (no BLOCKER or WARNING). Correctness review: 7 findings, 3 mapped WARNING (R5, R6, R7), 4 NIT.

## Round 2 (the fixes only: `git diff HEAD`, three files)

Slice checks rerun before the reviewer: the three touched test classes on scheme Dicticus-Debug-Recorder, 36 tests, 0 failures (AppCategoryReaderTests 5, ContextResolverTests 21, DebugCleanupRecordCodableTests 10); the full check on the working tree is recorded in STATE.md History with this round's commit.

`code-review` at medium on the working-tree diff: **R5 resolved yes** (the guard returns before the cache write; the regression test asserts two failed lookups cost two reads and a bundle created afterwards is seen on the third), **R7 resolved yes** (round-trip asserts the wire key and the decoded value; the legacy JSON decodes with a nil field). New findings inside the changed lines:

| id | severity | source | finding | disposition |
|---|---|---|---|---|
| R12 | WARNING | code-review r2 | Reading only `Contents/Info.plist` drops the flat-bundle layout `Bundle(url:)` handled: an iPhone or iPad app running on Apple Silicon keeps its Info.plist at the bundle root, so its declared category is now never read. Claim checked: iOS app bundles are flat. | **fix step** (review rule: an open WARNING after round 2 goes to `fix` with a regression test, no round 3): read `Contents/Info.plist`, then `Info.plist` at the root; test with a flat fixture bundle. |
| R13 | NIT | code-review r2 | A permanently unreadable plist is now re-read on every key press and popover render (no negative cache). | **won't fix**: with R12 fixed, a running app whose bundle has no readable plist is a broken install; the read is a local file stat and parse on the app's own volume, which is already serving that app. Recorded as a limit. |
| R14 | NIT | code-review r2 | The R5 test covers a missing bundle, not a present but corrupt plist. | **fix step**, with R12: one case writes garbage bytes to the plist and asserts nil and no caching. |
| R15 | NIT | code-review r2 | The round-trip test repeats the 25-line record literal a fifth time. | **won't fix**: the file's idiom; a shared fixture is a test-file cleanup outside this slice. |
| R16 | NIT | code-review r2 | `try!` in the new tests traps the host on a decode regression. | **won't fix**: the file's idiom, every earlier test uses it. |

Open after round 2: R12 (WARNING) and R14, both to `fix`. Everything else is fixed or `won't fix` with its reason; no `owner` row. Parts covered with `no findings`: DebugRecorder.swift, TextProcessingService.swift, the resolver's precedence, AiCleanupPane.swift, the HotkeyManager plumbing; the reviewer read the test files' stats, not their bodies (the correctness review covers them).
