# Archive: rows and history from before the item folders; not the live roadmap

## Rows before the item folders

Migrated from GSD on 2026-11-08. Rows up to 51 are GSD phases under their old numbers; their records stay in the gitignored planning tree (`.planning/`, archives under `.planning/milestones/`). Main's history starts at the 1.0.0 public release (2026-07-31, fresh root), so phases before it have no commits on main. GSD backlog items (999.x), seeds, spikes and todos stay in the planning tree and become rows only when the owner schedules one. New slices take the next free number: 53.

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
