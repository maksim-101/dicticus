---
id: 142
title: dictation-starts-paused-media
status: idea
size:
assignee: none
created: 2026-11-21
why:
waiting_until:
shipped:
links: 99-media-pause-off-keydown, 121-media-fallback-signed-check
---

# A dictation never starts playback that the owner had paused

The owner, 2026-11-21: for about two weeks, now and then, after a video or music had been playing and the owner stopped it by hand, a later dictation (sometimes about three dictations later), with no audio playing at all, starts playback while dictating. A bug to investigate. Likely area: the media auto-pause's MediaRemote toggle path (tier 2b), which sends a play/pause toggle rather than an explicit pause and resumes with a second toggle; the 2026-11-21 audit counted 5 tier-2b events with a resume toggle in 11 days (`.planning/debug/audit-2026-11-21/lens-fixes.md`, media section). Logs: `mediapause-*.jsonl` in the debug recordings.
