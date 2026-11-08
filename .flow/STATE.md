# State
Slice: 50.1-editguard-run-on-split-recovery (standard)
Step: brief
Next: flow:brief for 50.1. Inputs, read-only from the main checkout's planning tree: ROADMAP.md row 50.1, phases/50.1-editguard-run-on-sentence-split-recovery/50.1-STATUS.md, spikes/017-runon-split-recovery/ (README.md, PREREG-round2.md, ROUND2-RECOUNT-2026-11-02.md "For the cap run"). The round-2 cap snapshot and verdict run (output ROUND2-VERDICT.md) is due 2026-11-09 and needs the owner's approval of the flow plan first.
Waiting on: nothing
Started: not yet (set by flow:brief)
Baseline: not yet measured
Base: branch point
Risk: none
Carried:
- brief: the GSD pre-approval of the 2026-11-09 verdict run lapsed with the migration (owner chose to migrate before the run, 2026-11-08); the run goes into the 50.1 plan for the owner's approval.
- brief: owner corrections from the GSD discuss pass, to carry into the done criteria: the bar is measured evidence (zero REGRESSION), German is evaluated separately, option (a) only if the spike wins.
- brief: any b1 REGRESSION closes 50.1 as measured, not shipped (ROADMAP status `dropped`, with the reason), no third round; the comma-only c1 release is a separate decision.

## Incoming
- 2026-11-08 from GSD HANDOFF.json (paused 2026-11-06, main at b8ab69c): owner checks on TestFlight build 18, none blocking: the 9c7 device checks (phone call, Siri, AirPods out/in mid-dictation, stop right after start, AI-cleanup model download and relaunch; built, not verified on a device); a tester with an iPhone 11-14 (Parakeet speed on A13-A15 unmeasured) and ideally an 8 GB iPhone 15 Pro/16 (confirm the AI Cleanup gate admits it) → ROADMAP row or owner list, as flow:next settles.
- 2026-11-08 from GSD HANDOFF.json: open owner questions: retry LFM3-1.7B for 6 GB phones (spike 022 failed as drop-in; asked 2026-11-04, unanswered); go/no-go for spike 020 Stage 3 (Nemotron 3.5 Transcribe pause phantoms; its 21 GB model cache is kept for it, disk is tight) → owner decisions.
- 2026-11-08 from GSD HANDOFF.json: optional follow-ups: "Delete model" for 6 GB iOS devices that downloaded the 2.7 GB model under build 17 or earlier; README still says "Parakeet TDT v3 ~1.2 GB" (iOS runs Parakeet Ultra, ~630 MB) and the IOSModelWarmupService.swift header says AI cleanup is excluded on iOS; HistoryServiceTests.testAppGroupAvailableFlagDefaultsTrue always skips in the simulator; check the r9g macOS download prompt and Settings rows on screen in the mac-space VM → ROADMAP rows if the owner schedules them.

## History
- 2026-11-08 migration: moved from GSD to flow on the owner's go ("migrate now", before the 50.1 verdict run). GSD records stay in the gitignored planning tree; ROADMAP seeded with every phase under its old number; 50.1 is the first slice, at brief.
