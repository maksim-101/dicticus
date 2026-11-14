# State
Slice: 60-pause-period-and-audio-retention
Carried: none

## Incoming
- 2026-11-08 from GSD HANDOFF.json (paused 2026-11-06, main at b8ab69c): owner checks on TestFlight build 18, none blocking: the 9c7 device checks (phone call, Siri, AirPods out/in mid-dictation, stop right after start, AI-cleanup model download and relaunch; built, not verified on a device); a tester with an iPhone 11-14 (Parakeet speed on A13-A15 unmeasured) and ideally an 8 GB iPhone 15 Pro/16 (confirm the AI Cleanup gate admits it) → ROADMAP row or owner list, as flow:next settles.
- 2026-11-08 from GSD HANDOFF.json: open owner questions: retry LFM3-1.7B for 6 GB phones (spike 022 failed as drop-in; asked 2026-11-04, unanswered); go/no-go for spike 020 Stage 3 (Nemotron 3.5 Transcribe pause phantoms; its 21 GB model cache is kept for it, disk is tight) → owner decisions.
- 2026-11-08 from GSD HANDOFF.json: optional follow-ups: "Delete model" for 6 GB iOS devices that downloaded the 2.7 GB model under build 17 or earlier; README still says "Parakeet TDT v3 ~1.2 GB" (iOS runs Parakeet Ultra, ~630 MB) and the IOSModelWarmupService.swift header says AI cleanup is excluded on iOS; HistoryServiceTests.testAppGroupAvailableFlagDefaultsTrue always skips in the simulator; check the r9g macOS download prompt and Settings rows on screen in the mac-space VM → ROADMAP rows if the owner schedules them.
