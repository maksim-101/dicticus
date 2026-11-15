# Archive: rows and history from before the item folders; not the live roadmap

## Rows before the item folders

Migrated from GSD on 2026-11-08. Rows up to 51 are GSD phases under their old numbers; their records stay in the gitignored planning tree (`.planning/`, archives under `.planning/milestones/`). Main's history starts at the 1.0.0 public release (2026-07-31, fresh root), so phases before it have no commits on main. GSD backlog items (999.x), seeds, spikes and todos stay in the planning tree and become rows only when the owner schedules one. New slices take the next free number: 53. Since the adoption of 2026-11-15 (flow 0.10.5), every open entry of those lists is an item in `.flow/` or closed in the inventory below; spikes, research and debug audits stay in the planning tree as history.

| # | Slug | Outcome | Status |
|---|---|---|---|
| 01 | foundation-app-shell | macOS menu bar app shell (v1.0) | shipped |
| 02 | asr-pipeline | first push-to-talk ASR pipeline (v1.0) | shipped |
| 02.1 | asr-engine-swap | ASR engine swap inside v1.0 | shipped |
| 03 | system-wide-dictation | text at the cursor in any app (v1.0) | shipped |
| 04 | ai-cleanup | first local LLM cleanup mode (v1.0) | shipped |
| 05 | polish-distribution | v1.0 polish and DMG distribution | shipped |
| 06 | v1.1-phase-6 | v1.1 Cleanup Intelligence & Distribution, phase 6; name not recorded | shipped (no record) |
| 07 | v1.1-phase-7 | v1.1 phase 7; name not recorded | shipped (no record) |
| 08 | v1.1-phase-8 | v1.1 phase 8; name not recorded | shipped (no record) |
| 09 | v1.1-phase-9 | v1.1 phase 9; name not recorded | shipped (no record) |
| 10 | v1.1-phase-10 | v1.1 phase 10; name not recorded | shipped (no record) |
| 11 | v1.1-phase-11 | v1.1 phase 11; name not recorded | shipped (no record) |
| 12 | shared-code | macOS/iOS shared services extracted into Shared/ | shipped |
| 13 | app-intent-live-activity-core-dictation-pipeline | iOS App Intent + Live Activity dictation pipeline | shipped |
| 14 | settings-permission-onboarding | iOS settings and permission onboarding | shipped |
| 15 | custom-dictionary-post-processing | custom dictionary find-and-replace on both platforms | shipped |
| 16 | onboarding-universal-app-distribution | universal iOS app and distribution | shipped |
| 17 | keyboard-extension | iOS keyboard extension (later blocked on iOS 26, Shortcuts only) | shipped |
| 17.5 | inline-shortcut-dictation | inline Shortcut dictation | shipped |
| 18 | icloud-sync | CloudKit sync of dictionary and history; never started | dropped |
| 19 | ai-cleanup-ios | AI cleanup on iOS | shipped |
| 19.5 | ai-cleanup-ch-determinism | deterministic Swiss German cleanup | shipped |
| 19.6 | ios-ux-polish | iOS UX polish; deferred at v2.1 and never run as a phase | dropped |
| 19.7 | macos-hygiene | macOS hygiene pass | shipped |
| 20 | ai-cleanup-demotion-uat-visibility | AI cleanup demoted to opt-in, UAT visibility | shipped |
| 20.06 | ai-cleanup-behavioural-hotfix | AI cleanup behaviour hotfix | shipped |
| 20.08 | llm-swiss-ification-suppression | LLM Swiss-ification suppressed | shipped |
| 21 | adaptive-cleanup-stability | adaptive cleanup and stability | shipped |
| 22 | resolver-regression-hotfix | self-correction resolver regression hotfix | shipped |
| 23 | decimal-words-digit-grouping | decimal words and digit grouping; scope absorbed into 24 | dropped |
| 24 | ai-cleanup-quality-v2 | AI cleanup quality v2 | shipped |
| 25 | ai-cleanup-quality-v3-brand-acronym-recognition | brand and acronym recognition in cleanup | shipped |
| 25.1 | ai-cleanup-quality-v3b-remediation-telemetry | paper-driven remediation and telemetry | shipped |
| 26 | pipeline-quality-hardening | pipeline quality hardening | shipped |
| 27 | dictionary-hallucination-guard-recorder-enrichment | dictionary hallucination guard, debug recorder enrichment | shipped |
| 28 | v19d-prompt-iteration | cleanup prompt iteration (V19D) | shipped |
| 29 | asr-post-processing-acronym-collapse | spoken-letter acronym collapse after ASR | shipped |
| 30 | ptt-media-auto-pause-macos | media auto-pause during push-to-talk on macOS | shipped |
| 31 | dictionary-as-platform | dictionary as a platform (packages, import/export) | shipped |
| 32 | spoken-punctuation | spoken punctuation commands | shipped |
| 33 | ios-first-run-onboarding-polish | iOS first-run onboarding polish | shipped |
| 34 | v19e-r8-over-promotion-fix | V19E R8 over-promotion fix | shipped |
| 35 | ui-reorganization | UI reorganization | shipped |
| 36 | ios-background-dictation | iOS background dictation | shipped |
| 36.1 | cleanup-pipeline-quality | cleanup pipeline quality | shipped |
| 36.2 | macos-build-reliability-permission-ux | macOS local build signing, TCC reliability, permission UX | shipped |
| 36.3 | macos-app-group-removal-storage-migration | macOS App Group removed, storage migrated | shipped |
| 36.4 | post-asr-ai-cleanup-robustness | post-ASR and AI cleanup robustness | shipped |
| 36.5 | brand-name-matcher | brand-name matcher | shipped |
| 36.6 | cleanup-redesign-qwen2.5-3b | cleanup redesign on Qwen2.5-3B; held after failed on-device UAT, superseded by 44/45 | dropped |
| 37 | ios-distribution | iOS TestFlight distribution; build 12 cleared Beta App Review 2026-09-01 | shipped |
| 38 | context-aware-formatting | context-aware formatting | shipped |
| 39 | voice-edit-commands | voice edit commands; parked by owner decision after 2 data-loss defects, code ships disabled | dropped |
| 40 | windows-feasibility-spike | Windows feasibility spike; deferred to the Windows track | dropped |
| 41 | whisper-large-v3-turbo-asr | macOS ASR swapped to WhisperKit / Whisper large-v3-turbo | shipped |
| 42 | ai-cleanup-self-correction-consistency | self-correction consistency, German parity | shipped |
| 43 | comma-path-resolver-data-loss-fix | comma-path self-correction resolver no longer corrupts prose | shipped |
| 44 | cleanup-fidelity-guard | EditGuard fidelity gate on LLM cleanup; Qwen3.5-4B kept (D-10) | shipped |
| 45 | plain-cleanup-parity | plain path gets deterministic sentence capitalization (quick 260717-jfw) | shipped |
| 46 | ios-record-first-shortcut | iOS record-first Shortcut | shipped |
| 47 | ios-asr-engine-spike-parakeet-vs-whisper | iOS ASR decision: Parakeet | shipped |
| 47.1 | ios-parakeet-swap | iOS ASR swapped to FluidAudio / Parakeet | shipped |
| 48.5 | macos-asr-engine-decision | macOS stays on Whisper, decided on replay harness | shipped |
| 49 | v2.5-defect-hardening | v2.5 defect hardening, 12 quick tasks | shipped |
| 49.5 | editguard-atomic-punctuation-run-tokenization | EditGuard tokenizes punctuation runs atomically | shipped |
| 49.6 | editguard-coupled-edit-atomic-revert | EditGuard reverts coupled edits atomically, classifier rules | shipped |
| 49.7 | dictionary-brand-matcher-numeric-formatting | brand matcher, Swiss number formatting, ITN fixes | shipped |
| 50 | macos-reliability-hardening | macOS delivery-failure recovery, model integrity, idle unload, media guard | shipped |
| 51 | live-transcript-overlay | live transcript overlay while speaking | shipped |
| 66 | gsd-quick-tasks-after-v2.5 | GSD quick tasks from 2026-09-13 to 2026-11-04: 67 folders in `.planning/quick/`, 57 rows in the quick-task table of `.planning/STATE.md`; every row names a commit except 260923-sjc (superseded before execution) and 260924-8sw (measured, not shipped; its judge is item 90); added at the adoption of 2026-11-15 | shipped |

## State before the conversion

Slice: 54-context-from-app-category (standard)
Step: brief
Next: flow:brief for 54: dictation context follows the app's declared category (LSApplicationCategoryType; Warp, Orca, VS Code and Claude desktop declare developer-tools, checked 2026-11-11) instead of ContextResolver.curatedMap; overrides stay; the focused-field idea is a possible later step. Evidence: .planning/debug/audit-2026-11-10/SYNTHESIS.md (Warp 312 records on .default, 47 % rejected).
Waiting on: nothing
Started: not yet (set by flow:brief)
Baseline: not yet measured
Base: branch point
Risk: none
Carried:

## History before the item folders

- 2026-11-08 migration: moved from GSD to flow on the owner's go ("migrate now", before the 50.1 verdict run). GSD records stay in the gitignored planning tree; ROADMAP seeded with every phase under its old number; 50.1 is the first slice, at brief.
- 2026-11-11 53 brief: owner asked to fix the debug-log test leak found by the 2026-11-10 audit ("address this"); quick slice 53 opened ahead of 50.1, which stays planned and unbriefed.
- 2026-11-11 53 brief: approved by the owner. Owner also scheduled, in this order after 53: automatic context detection (54); LLM timeout investigated and addressed (55); followed up and tested: pick before sending (56), LLM returns an edit list (57), learn from post-paste corrections (58). Clean-while-speaking, paste-now-improve-later and on-screen names not chosen.
- 2026-11-11 53 plan: one task, a shared resolver for all ten writers. The owner's "slice 53 is approved" is taken as covering this plan, which adds no choice the brief left open; stated in the reply.
- 2026-11-11 53 build: task 1 done (3898e38); its Verify uses scheme Dicticus-Debug-Recorder, since the Dicticus scheme compiles no probes (a change within the slice, plan wording fixed).
- 2026-11-12 53 build: closed. Branch: macOS Dicticus 1948 tests 0 failed (7 skipped), Dicticus-Debug-Recorder 2025 tests 0 failed (8 skipped), live folder unchanged across both; check-running-copy OK; iOS simulator 1775 tests 0 failed (10 skipped) on the rerun, the first run's test runner hung before connecting.
- 2026-11-12 53 review: one round (quick). The reviewer covered the production path (no findings) and left three parts unchecked; the main loop checked two against the test runs (no finding). The carried scheme gap (R3, WARNING) was deferred to ROADMAP row 59.
- 2026-11-12 53 verify: criteria 1-4 pass with evidence; handed to the owner with the R3 deferral as the one decision.
- 2026-11-13 53 verify: signed off by the owner ("okay, go ahead"), R3 deferred to row 59.
- 2026-11-13 53 ship: merged to main, no tag (only the test host changes). Scorecard 2026-11-11T07:47Z to now: active agent time 1.1 h, owner inputs 2 typed + 1 slash, 0 questions, 2 subagent runs. Lines added: .flow 120 (+32 evidence), code 37, tests 19. Regression test: TestIsolationCanaryTests.testMacProbesRedirectedToTestDirectory plus the extended recorder canary.

## Inventory at adoption 2026-11-15

Steps 0 and 4 of flow's adoption, on the owner's go of 2026-11-15 ("migrate Dicticus from GSD Core to Flow"). Sources read: `.planning/backlog/` (42 files; `archived/` skipped, its README is the old triage), `.planning/seeds/` (4), `.planning/todos/pending/` (5), `.planning/ROADMAP.md`, `REQUIREMENTS.md`, `PROJECT.md`, `STATE.md`, `WINDOWS.md`, `notes/`, `quick-batches/`, the latest debug-log audit (`debug/audit-2026-11-10/SYNTHESIS.md`, which carries the open fixes of earlier audits), the open markers in every phase, quick-task and milestone-audit record, the root `Carried:` lines, the `.flow/` records, commit bodies on main since 2026-08-01, README and code TODOs, the agent's memory notes for this project and the owner's notes vault. Coverage: the memory notes were first screened by keyword (about 30 of about 115 read), then read in full in a second pass the same day; of nine vault matches for "Dicticus", one note concerned the app's plans, the rest are tooling hubs. Every entry that is still open arrived as an `idea`; a closure needs a commit, an archive row, an item or a recorded owner decision. Human-verification items dated before 2026-07-11 are closed by the owner's decision of that day (memory note 'Deferred human UATs closed'), about 19 records, not listed one by one.

| Source | Entry | Decision |
|---|---|---|
| root STATE.md Carried | TestFlight build 18 device checks | carried: 66 owner |
| root STATE.md Carried | testers with an iPhone 11-14 and an 8 GB iPhone | carried: 66 owner |
| root STATE.md Carried | delete the AI model on 6 GB iPhones that downloaded it | item 67 |
| root STATE.md Carried | README names the old iOS model and size; warm-up comment says no AI cleanup on iOS | done in the adoption commit |
| root STATE.md Carried | a history test always skips in the simulator | item 68 |
| root STATE.md Carried | check the macOS download prompt on screen in the VM | carried: 66 host |
| backlog/acronym-letter-number-spacing.md | letter after a letter-digit model code | item 69 |
| backlog/app-store-product-page-assets.md | App Store page assets | merged into 124 |
| backlog/asr-tech-term-mishearing-recovery.md | misheard technical terms recovered | item 70 |
| backlog/audio-ducking-during-dictation.md | ducking and calls left alone | item 71 |
| backlog/cleanup-prompt-prefix-kv-cache.md | reuse the encoded system prompt | item 72 |
| backlog/currency-spell-out-conversion.md | spelled-out currency amounts | item 73 |
| backlog/device-model-name-normalization.md | spoken device model names | item 74 |
| backlog/dictionary-entry-editing.md | edit a dictionary entry in place | done in 4da3d7c |
| backlog/dictionary-heard-form-aliases.md | heard forms as one dictionary row | merged into 52 |
| backlog/dictionary-import-dialog-safety.md | safe dictionary import dialog | done in 4da3d7c |
| backlog/editguard-punctuation-only-move-reversion.md | accept punctuation-only moves | done in 16a5458 |
| backlog/engine-agnostic-asr-abstraction.md | speech engine behind one interface | item 75 |
| backlog/history-correction-feedback.md | a history correction teaches the dictionary | merged into 52 (dictionary part) and 58 (hints) |
| backlog/idle-model-unload.md | free models after idle time | done in 50 |
| backlog/ios-testflight-distribution.md | iOS through TestFlight | done in 37 |
| backlog/ios-warmup-background-llm-load-indicator.md | show the cleanup model loading on iPhone | item 76 |
| backlog/live-activity-forcequit-staledate-mitigation.md | Live Activity after a force-quit | item 77 |
| backlog/live-transcript-overlay.md | live transcript overlay | done in 51 |
| backlog/macos-delivery-failure-recovery.md | recoverable transcript after a failed paste | done in 50 |
| backlog/macos-device-bound-capture-path.md | device-bound capture | item 78 |
| backlog/macos-input-pin-mid-hold-default-change.md | re-pin input on a mid-hold default change | dropped: not reproduced on build 17, the file's own record ("no fix needed") |
| backlog/macos-paste-at-cursor-intermittent-failure.md | intermittent paste no-op | done in 50 and 260920-9m8 |
| backlog/macos-recording-dies-on-input-device-change.md | recording survives an input device change | done in 16f56e8 |
| backlog/model-picker-asr-and-llm.md | choose speech and cleanup models | merged into 75 |
| backlog/parakeet-competitor-evidence-phase47.md | competitor evidence note | dropped: informational, fed phase 47 (shipped) |
| backlog/pasteboard-transient-marker.md | mark pasteboard writes transient | item 79 |
| backlog/release-checksums-model-integrity.md | DMG checksums, hashed model download | done in 50 (9989973) |
| backlog/rulescleanup-profanity-audit.md | remove swearing | item 80 |
| backlog/selfcorrection-gated-llm-integration.md | gated LLM self-correction pass | item 81 |
| backlog/speaker-l1-confusion-sizing.md | size native-language confusion | item 82 |
| backlog/spoken-currency-compound-formatting.md | "a dollar fifty" formatted | merged into 73 |
| backlog/spoken-digit-strings.md | spoken digit runs as codes | item 83 |
| backlog/spoken-parentheses-punctuation.md | spoken brackets | done in a8c4e8b |
| backlog/spoken-punctuation-commands.md | pipe and dash words | item 84 |
| backlog/ui-history-row-full-clickable.md | whole History row clickable | item 85 |
| backlog/v19e-r8-over-promotion-and-content-word-gate.md | capitalised word before a number not merged | done in 34 |
| backlog/v19e-supplementary-german-itn-number-corpus.md | German number corpus | item 86 |
| backlog/voice-edit-word-span-redesign.md | rebuilt "scratch that" command | item 87 |
| backlog/voice-teachable-corrections.md | spoken "add to dictionary" | dropped: not chosen by the owner, 52 BRIEF.md (2026-11-14) |
| backlog/whisper-bare-you-silent-hold.md | silent hold pastes nothing | item 88 |
| backlog/whisper-no-speech-prob-unavailable.md | real no-speech probability | item 89 |
| backlog/whisper-segment-seam-quality.md | words at decode-window seams | merged into 63 |
| seeds/SEED-001-realword-mishearing-judge.md | sentence-level judge | merged into 90 |
| seeds/SEED-001, "Monitor: unmarked self-corrections" | audits count unmarked self-corrections | CLAUDE.md |
| seeds/SEED-002-local-decision-model-arbiter.md | local decision model as arbiter | merged into 90 |
| seeds/SEED-003-dictionary-suggestion-miner.md | mishearings become dictionary suggestions | merged into 58 |
| seeds/SEED-004-ios-foundation-models-cleanup.md | iPhone cleanup on Apple's model | item 93 |
| todos/pending/asr-emits-digit-2-for-homophone-too.md | digit 2 for "too" | dropped: measured, no deterministic fix (about 1 in 545; a rule would corrupt 9), the file's own record |
| todos/pending/cloud-asr-option-assemblyai.md | optional cloud transcription | dropped: fully local is a hard requirement (PROJECT.md Out of Scope; CLAUDE.md Privacy; decision of 2026-08-31, memory note 'AssemblyAI cloud-ASR preconditions') |
| todos/pending/editguard-quote-role-restored-token-test.md | restored quote role test | merged into 94 |
| todos/pending/editguard-rejected-dash-substitute-vanishes.md | rejected dash substitute drops tokens | merged into 94 |
| todos/pending/llm-inserts-em-dash-at-restart-boundary.md | em-dash at a restart | item 95 |
| ROADMAP.md Phase 999.2 | voice enrollment, per-user calibration | merged into 82 |
| ROADMAP.md Phase 999.4 | light insertions over-reverted | merged into 90 |
| ROADMAP.md dictionary UX cluster; REQUIREMENTS DICTUX-01/02 | grouped dictionary rows, add from History | merged into 52 (Mac) and 65 (iPhone) |
| ROADMAP.md Phase 50.1 | run-on split recovery | done in 50.1 (dropped, measured) |
| ROADMAP.md Phase 39 | voice edit commands | dropped: archive row 39, parked by the owner |
| ROADMAP.md Phase 40; PROJECT.md Future Windows; WIN-01 | Windows | other project: dicticus-windows (archive row 40) |
| REQUIREMENTS RELY-02, RELY-03, MEDIA-01 | integrity, idle unload, media guard | done in 50 |
| PROJECT.md Future, iOS custom keyboard | keyboard extension | dropped: PROJECT.md Out of Scope; keyboard IPC removed (261101-f91) |
| PROJECT.md Future, iOS AI cleanup | AI cleanup on iPhone | done in 261103-9c7 |
| PROJECT.md Future, prompt customization | user-editable prompt | dropped: editor removed because cleanup never read it (52db8cb, 37cc63d) |
| PROJECT.md Future, heavier rewrite mode | heavier cleanup tier | item 97 |
| PROJECT.md Future, Swiss German ASR | dialect to Standard German | item 98 |
| STATE.md 49.6 W1 | stale doc comment | done (Shared/Utilities/FunctionWords.swift:225) |
| STATE.md 49.6 W2, W3 | kein/keine, adjacent-slot coupling | merged into 94 |
| STATE.md; phases/50 REVIEW WR-04 | key-down waits on media sampling | item 99 |
| STATE.md pending user decision | a German compound rule: keep or loosen | merged into 109 |
| STATE.md GSD housekeeping (branching, build 14, phase 37 hold, 10-24 audit) | old GSD housekeeping | dropped: superseded by flow, builds 17 and 18, and the audits of 10-29 and 11-10 |
| quick-batches/260930-s18/BATCH.json | nine batch tasks marked pending | done (each has a SUMMARY.md; STATE.md lists the batch merged) |
| WINDOWS.md entry 1 | replay harness test-host deadlock | item 104 |
| WINDOWS.md entry 2 | Swiss number formatting not idempotent | item 105 |
| notes/2026-09-23-new-asr-release-sweep.md | iPhone to Parakeet Ultra | done in 261017-qlv |
| notes/2026-11-01-codebase-audit.md, dead code and no-op settings | dead code removed | done in 261101-f91 and 261104-8k2 |
| notes/2026-11-01-codebase-audit.md, remaining cut candidates | cut inert pipeline parts | item 100 |
| notes/2026-11-01-codebase-audit.md, LLM value replay; deterministic-cleanup note Stage 1 | measure what the LLM output is worth | merged into 56 |
| notes/2026-11-01-deterministic-cleanup-and-dial.md Stage 2 | three-mode dial | item 101 |
| notes/2026-11-01-codebase-audit.md 3b | iPhone debug log channel | item 102 |
| notes/2026-11-01-codebase-audit.md, iOS pipeline copies | one iPhone pipeline | item 103 |
| notes/2026-11-01-codebase-audit.md, macOS loads the model at launch | no model load with cleanup off | item 106 |
| notes/2026-11-01-codebase-audit.md, test tidy-ups | test suite leftovers | merged into 68 |
| notes/2026-11-01-codebase-audit.md, four iOS defects, clean clone, Swiss default | iOS fixes, clean clone, default | done in 261101-f91, 261103-9c7, c2ccf89, 261103-8pj |
| notes/ housekeeping and evening runs | device checks; checklist | carried: 66 owner; done (ticked) |
| debug/audit-2026-11-10 fix 1 | Warp and Orca get the code prompt | done in 54 |
| debug/audit-2026-11-10 fix 2 | zero-audio holds discarded | merged into 88 |
| debug/audit-2026-11-10 fix 3 | log the cleanup outcome and LLM time | merged into 55 |
| debug/audit-2026-11-10 fix 4 | post-revert punctuation integrity | item 91 |
| debug/audit-2026-11-10 fix 5 | dot-cloud sibling variants | item 92 |
| debug/audit-2026-11-10 fix 6 | dictionary candidates on approval | merged into 58 |
| debug/audit-2026-11-10 fix 7 | remaining probes honour the test directory | done in 53 |
| debug/audit-2026-11-10 fix 8 | padded re-decode, short XLR holds | merged into 116 |
| phases/51 VERIFICATION and UAT | second display, full screen, accessibility, cleanup after idle | carried: 51 owner |
| phases/51 REVIEW WR-03, IN-03 to IN-06 | overlay code residues | item 107 |
| phases/50 REVIEW WR-01, 02, 05, 06 | reliability review leftovers | item 108 |
| quick/261019-87x, 261018-go0 | Bluetooth switch mid-hold loses audio | merged into 78 |
| quick/261002-6oh, 6oi, 261029-n8o, 261010-8dm, 261008-gb4, gb5, 261003-fiu, 261030-orz | owner judgment rows | item 109 |
| quick/261001-opz | contested seam spacings | merged into 94 |
| quick/261102-8q4; v2.5 44-14 | notice when cleanup is skipped | item 96 |
| v2.5 36.1, 36.4 VERIFICATION | NumberRevert and scaffold leftovers | item 110 |
| v2.5 46 REVIEW; 36 REVIEW-FIX | iPhone view-model housekeeping | item 111 |
| v2.5 44-14 | Mac and iPhone dictionaries drift | item 112 |
| v2.5 44-14 | prompt prefix cache deferred | merged into 72 |
| v2.5 37-04 | revoke a superseded App Store Connect key | carried: 37 owner (owner to confirm) |
| quick/261003-jvq | read the post-paste edit logs after a week | merged into 58 |
| runtime hand-offs of nine October quick tasks | built, not verified live | item 113 |
| quick/261010-8dn items 3 to 5 | fixture privacy remainder | item 114 |
| quick/260901-qyi review | restored ellipsis | done in 49.5 (49.5 VERIFICATION) |
| milestone audits v1.0, v2.3, v2.5 | listed tech debt | dropped: accepted by each audit (`tech_debt`, v2.5 acknowledged 2026-09-02) |
| .flow/60 SLICE.md Open | re-transcribe from retained audio; pause periods in plain mode; end of retention | item 115 |
| .flow/62 SLICE.md Open | repeat the engine comparison on a week of audio | merged into 64 |
| .flow/53 SLICE.md R3 | one check runs both schemes | merged into 59 |
| memory note 'Debug-log audit Oct 29-Nov 9' | zero-audio phantom; timeout logging; Warp and Orca | merged into 88; merged into 55; done in 54 |
| memory note 'Debug-log audit Oct 17-29' | short XLR holds | item 116 |
| memory note 'Spike 021: German particle prompt FAIL' | verb-second rule scope | item 117 |
| memory note 'Spike 022: LFM3 cleanup FAIL' | skip cleanup for German | item 118 |
| memory note 'Spike 019 live-preview quality' | flag a bad live preview | item 119 |
| memory note 'Spike 014: EditGuard over-blocking' | finer reverts, then a judge | merged into 90 |
| memory note 'Monitor unmarked self-corrections' | count them in every audit | CLAUDE.md |
| memory note 'Dictation transcripts are cross-project' | dictation text is often about other projects | CLAUDE.md |
| memory note 'Changelog & What's New' | What's New links to Releases | item 120 |
| memory note 'PTT media auto-pause' | send fallback in the signed app | item 121 |
| memory note 'Next: iOS Parakeet swap before TestFlight' | Shared/ as a Swift package | item 122 |
| memory notes 'Swiss German STT research', 'Swiss German datasets Oct 17' | dialect engine | merged into 98 |
| memory note 'Dictionary packages + brand matching' | shippable brand starter pack | done: README names bundled starter packs |
| memory note 'Speaker L1 confusion calibration' | calibration | merged into 82 |
| memory note 'Cleanup redesign (spike 010)' | trim degenerate German tails | item 123 |
| memory note 'V19D R8 kink/King bug' | a word before a number word merged into a code | done in 34 |
| memory note 'V28 K4 prose-number follow-on' | single-digit number words in prose stay words | item 127 (corrected 2026-11-15: phase 34 fixed the related over-promotion, not shown to fix this) |
| memory note 'Cleanup misses self-corrections' | gated self-correction | merged into 81 |
| memory note 'v2.5/v2.6 scope plan' | voice edit redesign | merged into 87 |
| memory note 'EditGuard materialize defect class' | conjunction carve-out todo | done (in `todos/done` or `todos/resolved`) |
| memory note 'Unpinned mic: Continuity wake + dead hotkey' | device-bound capture | merged into 78 |
| memory note 'Deterministic cleanup + dial (Fable)' | three-mode dial | merged into 101 |
| Shared/Utilities/NoSpeechDiscard.swift:28; Shared/Diagnostics/DiscardProbe.swift:52 | no-speech probability unavailable | merged into 89 |
| iOS/DicticusTests/IOSModelDownloadServiceTests.swift:23 | stale "Wave 2" TODO | merged into 68 |
| a private note of the owner | how Dicticus is distributed | item 124 (details stay private, the owner's word of 2026-11-15) |
| a private note of the owner | a second plan from the same note | dropped: removed from the public repo on the owner's word of 2026-11-15; number 125 stays unused |
| commit bodies on main since 2026-08-01 | device checks of 9c7 | carried: 66 owner |
| memory note 'Debug-log audit Oct 8-17' | a first name in the bundled word lists | merged into 114 |
| memory note 'Sim audio injection via BlackHole' | canned audio into the simulator's microphone | item 128 |
| memory note 'Whisper trailing-silence trim spike' | size trailing phantoms, retry a softer trim | item 129 |
| memory note 'Debug-log audit Sep 26-30' | three causes left open | item 130 |
| memory note 'Mixed-language cleanup limitation' | re-test mixed-language dictations | item 131 |
| memory note 'Release & publish process' | purge of old history and pull refs | done: checked 2026-11-15, no pull refs on the remote and the old commit is gone |
| memory note 'LaunchServices wrong-copy after install' | Spotlight reindex | done: checked 2026-11-15, the Spotlight query answers |
