# Roadmap

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
| 50.1 | editguard-run-on-split-recovery | long dictations keep the LLM's interior sentence splits; spike 017 round 2 verdict due 2026-11-09 | planned |
| 52 | dictionary-ux | voice-teachable corrections and heard-form aliases (DICTUX-01/02) | planned |
