# 54 context-from-app-category: plan

## Route

**Where the category is read.** Chosen: `NSRunningApplication.bundleURL` → `Bundle(url:)?.infoDictionary?["LSApplicationCategoryType"]`, cached per bundle URL for the app's lifetime. One plist read per new app, none per key press after that. Rejected: Spotlight (`mdfind`, `MDItem`), which froze the popover here and is banned by CLAUDE.local.md; and `LSCopyApplicationURLsForBundleIdentifier`, which gives a URL but still needs the plist read.

**Where the rule lives.** Chosen: `ContextResolver.resolve` gains a `category: String?` argument and a `terminalFallback` map, and stays AppKit-free, so the precedence is one function with one test file, and iOS keeps compiling it. Rejected: deciding in `HotkeyManager` next to the frontmost-app read, which would put the precedence in macOS code and leave `ContextResolver` describing a rule the app no longer uses.

**How the replay builds its prompts.** Chosen: a small Swift executable compiled from main's `Shared/` sources (the spike 022 `gate` package pattern) calls `CleanupPrompt.build` with `context: .code` and `.default` on each logged `post_rules` text, and the same executable runs EditGuard on each arm's output. Both arms then use the exact prompt text the app would build at the slice's commit. Rejected: string-substituting the system body inside the logged prompt (spike 022's method), which needs the right body text per prompt date and breaks when the glossary or filler list changes; two such changes landed in the window (752ddab, 52db8cb). Early signal: task 4 checks that `build(context: .default)` reproduces the latest logged Warp prompts byte for byte before any generation runs.

**What the route commits to.** Apps that declare developer tools but are used for prose (Claude desktop) get the code prompt. The 2026-08-02 A/B said the code prompt does not hurt prose; criterion 4 and the owner's `[judge]` sample re-check this on current data. If the sample goes against it, the fix is an override for that app, not a change of rule.

**Fragile assumption.** The plan assumes Warp's and the other developer apps' Info.plist carry `LSApplicationCategoryType`, which was checked once for five apps on this Mac. An app without the key falls to `.default`, as today. Task 2's test covers a bundle without the key.

## Tasks

### Task 1: category and terminal fallback in the resolver
- **Goal:** `ContextResolver.resolve(bundleID:category:pin:disabled:overrides:)` follows the brief's order: disabled, pin, override, `public.app-category.developer-tools` → `.code`, terminal fallback (`com.apple.Terminal`, `com.googlecode.iterm2`, `com.mitchellh.ghostty` → `.code`), `.default`. `curatedMap` is replaced by `terminalFallback`; the constant `developerToolsCategory` is public so the Settings pane can show it.
- **Files:** `Shared/Services/ContextResolver.swift`, `Shared/DicticusTests/ContextResolverTests.swift`.
- **Affects:** `AiCleanupPane.swift:320-321` reads `curatedMap` (task 3 changes it); `HotkeyManager.swift:313` and `:485` call `resolve` without a category (task 2 adds it; a default of `nil` keeps them compiling meanwhile). Tests asserting on `curatedMap`: `ContextResolverTests` lines 12-40 (`testCuratedMapCodeApps`, `testCuratedMapDefaultApps`, `testCuratedMapProseApps`) are rewritten for the new order. No other test names `curatedMap` (grep over `*/DicticusTests`, `Shared/DicticusTests`).
- **Verify:** `cd macOS && xcodegen generate >/dev/null && xcodebuild -project Dicticus.xcodeproj -scheme Dicticus -derivedDataPath build -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' -only-testing:DicticusTests/ContextResolverTests test` prints `TEST SUCCEEDED`, with one new case per precedence step, including: developer-tools category with no override → `.code`; override `.default` on a developer-tools app → `.default`; Terminal with category `utilities` → `.code`; unknown category and nil category → `.default`.
- **Depends on:** none.

### Task 2: macOS reads the category at key-down and logs it
- **Goal:** a new `AppCategoryReader` (macOS) returns the category for an `NSRunningApplication`, cached by bundle URL. Both `HotkeyManager` call sites pass it to `resolve`. `TextProcessingService.process` gains `detectedAppCategory: String? = nil`, and `DebugCleanupRecord` gains `app_category: String?` with the same backward-compatible decoding as `detected_bundle_id`.
- **Files:** new `macOS/Dicticus/Services/AppCategoryReader.swift`; `macOS/Dicticus/Services/HotkeyManager.swift` (`:310-318`, `:477-490`, `:660-666`); `Shared/Services/TextProcessingService.swift` (`:113-120`, `:645-651`); `Shared/Diagnostics/DebugRecorder.swift` (`DebugCleanupRecord` fields, `CodingKeys`, init, decoder); new `macOS/DicticusTests/AppCategoryReaderTests.swift`; `macOS/project.yml` and `iOS/project.yml` regenerated projects committed if the new files need it.
- **Affects:** every `DebugCleanupRecord` decoder test (`DebugCleanupRecordCodableTests`) must still decode records without the field; `process` callers (5 test files, iOS) compile unchanged through the default. The second copy of the frontmost-app read at `HotkeyManager.swift:604-607` is the release-time read for paste and post-edit, not context; it stays.
- **Verify:** `AppCategoryReaderTests` builds two throwaway `.app` bundles in a temp dir, one with `LSApplicationCategoryType = public.app-category.developer-tools` and one without the key, and asserts the reader returns the category and nil; a third assertion reads the same bundle twice and checks the plist is read once (a counter on the loader). Command: the task 1 command with `-only-testing:DicticusTests/AppCategoryReaderTests -only-testing:DicticusTests/DebugCleanupRecordCodableTests`, printing `TEST SUCCEEDED`. Runtime check at verify: the installed Debug-Recorder build's cleanup log after the owner's next Warp dictations shows `app_category` and `resolved_context: code` (owner's first use, read back by the agent).
- **Depends on:** task 1.

### Task 3: Settings pane states the rule
- **Goal:** the "Built-in defaults (read-only)" disclosure says: apps that declare the developer-tools category get the Code context; then lists the three terminal fallbacks; overrides above it are unchanged.
- **Files:** `macOS/Dicticus/Views/AiCleanupPane.swift:318-326`.
- **Affects:** nothing else reads `curatedMap`.
- **Verify:** the macOS app builds (`xcodebuild … -scheme Dicticus build` exit 0), and a headless screenshot of the AI Cleanup pane with the disclosure open, taken in the `mac-space` agent VM through `agent-vm` + `cua-driver`, saved to `.flow/54-context-from-app-category/evidence/settings-builtin-defaults.png`, shows the rule text and the three bundle IDs.
- **Depends on:** task 1.

### Task 4: replay harness tracer
- **Goal:** `.planning/spikes/024-warp-code-prompt-replay/` (gitignored, like every spike) holds: `build_items.py`, which selects the English AI-cleanup Warp records of 2026-10-29 04:22Z to 2026-11-09 from the audit's frozen logs (`.planning/debug/audit-2026-11-10/logs/`), and a `gate` Swift package compiled from the slice's `Shared/` with two modes: `prompt` (emit `build(context:)` for both arms per item) and `gate` (run EditGuard on an arm's output). Then a timed sample.
- **Files:** the spike folder only.
- **Affects:** nothing tracked.
- **Verify:** three checks, each printed by the scripts: (a) item count equals the audit's count of Warp English AI records (318 by `lang_used`; the brief's 312 counted by `lang`), with a key-list sha256 written before generation; (b) for the items logged after 52db8cb (2026-11-01 onward), `build(context: .default)` equals the logged `llm_prompt.text` byte for byte, count printed as `identical N / N`; a mismatch stops the task and is reported; (c) a timed sample of 5 items per arm through `llama-server` 0.9.0 with `qwen3.5-4b-q4_k_m.gguf`, temperature 0, seed 16, printing mean wall ms per item and the projection for 318 × 2. Expected about 2.8 s per item (spike 022 measured mean 2.8 s on the same model), so about 30 min for the run; the ceiling is 45 min of generation time. A projection past the ceiling stops here (build step 6).
- **Depends on:** task 1 (the gate compiles the slice's `Shared/`).

### Task 5: replay run, report, judge sample
- **Goal:** both arms generated and gated; `report.md` in the spike folder gives, per arm: rejected-edit count and rate, dictations that shipped a change, failed-closed count, gate-pass count, prompt-token median; the slice's `evidence/replay-report.md` carries the same figures with no dictation text. A blind sample of 20 items where the two arms' gated text differs, drawn with `random.Random(54)`, written side by side to the spike folder's `data/judge-sample.md` with the arm labels in a separate key file.
- **Files:** the spike folder; `.flow/54-context-from-app-category/evidence/replay-report.md`.
- **Affects:** the host GPU for about 30 min. Starts through `~/.claude/scripts/heavy-gate acquire replay-54 --class model --mem 6 --pid $$ --wait 1800`; needs AC. `heavy-gate check` between items; the run pauses on exit 10.
- **Verify:** `python3 -I metrics.py` exits 0 and prints the table with `n = 318` for both arms; `evidence/replay-report.md` exists and `grep -c` of any `raw` text from `items.jsonl` in it is 0 (checked by a script that reads both files and prints only the count). Generation time compared with the 45 min ceiling at the end.
- **Depends on:** task 4.

## End-of-build gates (build step 3)
- Full macOS suite, both schemes (`Dicticus`, `Dicticus-Debug-Recorder`), `TEST SUCCEEDED`; live `DebugRecordings` snapshot unchanged (slice 53's check, repeated since this slice touches `DebugRecorder.swift`).
- iOS simulator suite on iPhone 18 Pro, `TEST SUCCEEDED`, simulator shut down afterwards.
- `scripts/check-running-copy.sh` prints OK.
- Install the Debug-Recorder build with `scripts/install-local.sh`, so the owner's next dictations produce the criterion 2 log evidence.

## Departures from the brief
- The replay counts 318 items, not 312: the audit's 312 counted records by Whisper's detected language, the harness by the language the pipeline used. Same window, same app, same mode.
