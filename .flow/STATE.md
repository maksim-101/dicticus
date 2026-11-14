# State
Slice: 50.1-editguard-run-on-split-recovery
Carried:
- owner checks on TestFlight build 18 (still the current build on 2026-11-14), none blocking: the 9c7 device checks (phone call, Siri, AirPods out/in mid-dictation, stop right after start, AI-cleanup model download and relaunch; built, not verified on a device)
- owner: a tester with an iPhone 11-14 (Parakeet speed on A13-A15 unmeasured) and ideally an 8 GB iPhone 15 Pro/16 (confirm the AI Cleanup gate admits it)
- owner question, asked 2026-11-04 and again 2026-11-14, unanswered: retry LFM3-1.7B for 6 GB phones (spike 022 failed as drop-in)
- owner question, asked again 2026-11-14, unanswered: go/no-go for spike 020 Stage 3 (Nemotron 3.5 Transcribe pause phantoms; its 21 GB model cache is kept for it, disk is tight)
- unscheduled follow-up: "Delete model" for 6 GB iOS devices that downloaded the 2.7 GB model under build 17 or earlier
- unscheduled follow-up: README.md lines 14, 33 and 91 still say "Parakeet TDT v3" and "~1.2 GB" (iOS runs Parakeet Ultra, ~630 MB); iOS/Dicticus/Services/IOSModelWarmupService.swift line 10 says AI cleanup is excluded on iOS
- unscheduled follow-up: HistoryServiceTests.testAppGroupAvailableFlagDefaultsTrue always skips in the simulator
- unscheduled follow-up: check the r9g macOS download prompt and Settings rows on screen in the mac-space VM
