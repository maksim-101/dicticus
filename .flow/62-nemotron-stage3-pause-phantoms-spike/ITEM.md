---
id: 62
title: nemotron-stage3-pause-phantoms-spike
status: planned
size:
assignee: none
created: 2026-11-14
waiting_until:
shipped:
links:
---

# measured: whether Nemotron 3.5 Transcribe invents speech in thinking pauses, the last open question of spike 020 before it can be an opt-in macOS engine

The owner gave the go on 2026-11-14 ("the Nemotron spike could also go ahead"). Stage 1 (2026-10-29) passed: runs on Metal, 19.5 GB footprint, 1.2 s for a 10 s clip. Stage 2 passed: German 3.74 against Whisper's 5.35 WER, English a tie, dictionary context terms help English; one 136 s clip was replaced by 198 invented words under the plain prompt. Stage 3 tests pauses and phantoms. The weights and build are in the spike's cache outside the repo (about 21 GB), kept for this. Loading the model pushed about 4.4 GB of other apps to swap on the 48 GB Mac, so the run needs the host's resource gate and mains power. Research: `.planning/spikes/020-nemotron-transcribe-macos/` (gitignored). Standing usage fact that bounds it: the owner holds the hotkey through pauses of one to several seconds at the start, in the middle and at the end of a dictation.
