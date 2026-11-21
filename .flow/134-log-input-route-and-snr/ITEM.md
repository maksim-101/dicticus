---
id: 134
title: log-input-route-and-snr
status: idea
size:
assignee: none
created: 2026-11-21
why:
waiting_until:
shipped:
links: 78-device-bound-capture
---

# Each debug record says which kind of microphone was used and how loud the room was

The owner asked whether loud rooms and weak microphones such as AirPods cost accuracy. The 2026-11-21 audit measured on 393 retained clips that dictations less than 15 dB above room noise were misheard 31 % of the time against 7-11 % above (`.planning/debug/audit-2026-11-21/SYNTHESIS.md` section 8), but had no AirPods dictation and no route information. Log per dictation: input transport type (built-in, Bluetooth, USB; `kAudioDevicePropertyTransportType` on macOS, `AVAudioSession.currentRoute` port type on iOS), Bluetooth profile or sample rate, a per-dictation SNR estimate (the gate already computes a noise floor), and input volume at key-down. Then a week of AirPods use answers the question. Research on routes and denoising: `.planning/research/mobile-and-noise-2026-11-21/SUMMARY.md` section 5 (record from the iPhone/Mac mic while AirPods play; AirPods high-quality recording not supported in the EU, check at runtime).
