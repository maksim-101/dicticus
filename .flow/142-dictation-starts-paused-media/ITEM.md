---
id: 142
title: dictation-starts-paused-media
status: planned
size:
assignee: none
created: 2026-11-21
why: a dictation restarts video or music the owner paused by hand, 7 times since 2026-11-14 by the logs; a daily annoyance with a located cause and a small fix
waiting_until:
shipped:
links: 99-media-pause-off-keydown, 121-media-fallback-signed-check
---

# A dictation never starts playback that the owner had paused

The owner, 2026-11-21: for about two weeks, now and then, after a video or music had been playing and the owner stopped it by hand, a later dictation (sometimes about three dictations later), with no audio playing at all, starts playback while dictating. A bug to investigate. Likely area: the media auto-pause's MediaRemote toggle path (tier 2b), which sends a play/pause toggle rather than an explicit pause and resumes with a second toggle; the 2026-11-21 audit counted 5 tier-2b events with a resume toggle in 11 days (`.planning/debug/audit-2026-11-21/lens-fixes.md`, media section). Logs: `mediapause-*.jsonl` in the debug recordings.

Investigation 2026-11-21 (read-only agent, `.planning/debug/audit-2026-11-21/media-autoplay.md`; the seven PLAY timestamps and the code lines checked by me): tier 2b sends a discrete PAUSE at key-down and a discrete PLAY at release (`MediaController.swift:707-722`), decided by one ~100 ms output-RMS sample above 1e-3 (`tier2bShouldFire`, line 310) that does not know which app made the sound. Seven release PLAYs since 11-14 (11-14, 11-16, 11-17, 11-20 ×2, 11-21 ×2), none 11-01..13. Four fit a short non-media sound at key-down (RMS 0.0027-0.0034, below the ~9.2e-3 the code's comment gives for playback) that ended by itself, which the verify step reads as a successful pause; one PLAY went out unverified because the key was released before verification. The PLAY then reaches the app that still holds media control (a paused video or Music), which explains "only now and then" and "several dictations later". Open: the owner reports playback starting while dictating; the code can only send PLAY at release. Deciding observation at the next incident: the time and whether the key was still held. Fix direction (not built): send PLAY only after a completed `stopped` verification, and send PAUSE only when a second sample ~0.3 s later is still above the threshold; two regression tests (weak short sound; early release) that fail today; `testEarlyRelease_CancelsVerificationBeforeSideEffects` and `testVerifyUnmeasurable_TreatedAsStopped` expectations change.
