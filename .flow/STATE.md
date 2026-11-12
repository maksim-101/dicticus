# State
Slice: 53-probe-test-isolation (quick)
Step: review
Next: flow:review for 53 (quick: code-review low, one round), diff from dee0299.
Waiting on: nothing
Started: 2026-11-11T07:47:37Z
Baseline: main dee0299: macOS scheme Dicticus 1947 tests, 8 skipped, 2 failed (DictionaryServiceK7AddsTests.testK7_DoesNotOverrideUserCustomization, EditGuardCompoundRepairTests.testR0_checkerSignalsOnThisMac); scheme Dicticus-Debug-Recorder 2023 tests, 10 skipped, 1 failed (testK7_DoesNotOverrideUserCustomization)
Base: branch point
Risk: none
Carried:
- 53 review: the config test command runs scheme Dicticus (Debug, no DEBUG_RECORDER), so no diagnostics probe or recorder canary is compiled in the standard check; only the Dicticus-Debug-Recorder scheme tests them.
- 50.1 brief: the GSD pre-approval of the 2026-11-09 verdict run lapsed with the migration (owner chose to migrate before the run, 2026-11-08); the run goes into the 50.1 plan for the owner's approval.
- 50.1 brief: owner corrections from the GSD discuss pass, to carry into the done criteria: the bar is measured evidence (zero REGRESSION), German is evaluated separately, option (a) only if the spike wins.
- 50.1 brief: any b1 REGRESSION closes 50.1 as measured, not shipped (ROADMAP status `dropped`, with the reason), no third round; the comma-only c1 release is a separate decision.

## Incoming
- 2026-11-08 from GSD HANDOFF.json (paused 2026-11-06, main at b8ab69c): owner checks on TestFlight build 18, none blocking: the 9c7 device checks (phone call, Siri, AirPods out/in mid-dictation, stop right after start, AI-cleanup model download and relaunch; built, not verified on a device); a tester with an iPhone 11-14 (Parakeet speed on A13-A15 unmeasured) and ideally an 8 GB iPhone 15 Pro/16 (confirm the AI Cleanup gate admits it) → ROADMAP row or owner list, as flow:next settles.
- 2026-11-08 from GSD HANDOFF.json: open owner questions: retry LFM3-1.7B for 6 GB phones (spike 022 failed as drop-in; asked 2026-11-04, unanswered); go/no-go for spike 020 Stage 3 (Nemotron 3.5 Transcribe pause phantoms; its 21 GB model cache is kept for it, disk is tight) → owner decisions.
- 2026-11-08 from GSD HANDOFF.json: optional follow-ups: "Delete model" for 6 GB iOS devices that downloaded the 2.7 GB model under build 17 or earlier; README still says "Parakeet TDT v3 ~1.2 GB" (iOS runs Parakeet Ultra, ~630 MB) and the IOSModelWarmupService.swift header says AI cleanup is excluded on iOS; HistoryServiceTests.testAppGroupAvailableFlagDefaultsTrue always skips in the simulator; check the r9g macOS download prompt and Settings rows on screen in the mac-space VM → ROADMAP rows if the owner schedules them.

## History
- 2026-11-08 migration: moved from GSD to flow on the owner's go ("migrate now", before the 50.1 verdict run). GSD records stay in the gitignored planning tree; ROADMAP seeded with every phase under its old number; 50.1 is the first slice, at brief.
- 2026-11-11 53 brief: owner asked to fix the debug-log test leak found by the 2026-11-10 audit ("address this"); quick slice 53 opened ahead of 50.1, which stays planned and unbriefed.
- 2026-11-11 53 brief: approved by the owner. Owner also scheduled, in this order after 53: automatic context detection (54); LLM timeout investigated and addressed (55); followed up and tested: pick before sending (56), LLM returns an edit list (57), learn from post-paste corrections (58). Clean-while-speaking, paste-now-improve-later and on-screen names not chosen.
- 2026-11-11 53 plan: one task, a shared resolver for all ten writers. The owner's "slice 53 is approved" is taken as covering this plan, which adds no choice the brief left open; stated in the reply.
- 2026-11-11 53 build: task 1 done (3898e38); its Verify uses scheme Dicticus-Debug-Recorder, since the Dicticus scheme compiles no probes (a change within the slice, plan wording fixed).
- 2026-11-12 53 build: closed. Branch: macOS Dicticus 1948 tests 0 failed (7 skipped), Dicticus-Debug-Recorder 2025 tests 0 failed (8 skipped), live folder unchanged across both; check-running-copy OK; iOS simulator 1775 tests 0 failed (10 skipped) on the rerun, the first run's test runner hung before connecting.
