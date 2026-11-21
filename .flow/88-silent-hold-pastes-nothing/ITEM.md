---
id: 88
title: silent-hold-pastes-nothing
status: idea
size:
assignee: none
created: 2026-11-15
why:
waiting_until:
shipped:
links: 
---

# A silent hold or an all-zero input device pastes nothing and says so

Imported at the flow adoption of 2026-11-15 from the old GSD lists; inventory row in `.flow/ARCHIVE.md` under "Inventory at adoption 2026-11-15". The lone-word filter catches only holds under 1.5 s or without voice; the 11-10 audit found two 45 s zero-level holds shipped as a phantom.

Added 2026-11-21: the 11-09..21 audit had no zero-level hold, but two near-silent clips past the near-silent rule's 2.5 s limit shipped a phantom: #373 "You" (4.0 s, 1 of 40 voiced frames) and #403 "So" (3.2 s). Open-source peers gate on Silero VAD before ASR (KeyVox `VoiceActivityDetector.swift`, MIT) and drop transcripts that are only a known hallucination; any such gate must only decide "no speech at all" and never trim, because the owner pauses mid-dictation (`.planning/research/competitors-2026-11-21/SUMMARY.md`).

Sources: .planning/backlog/whisper-bare-you-silent-hold.md; .planning/debug/audit-2026-11-10/SYNTHESIS.md sections 2 and 10.2; memory note 'Debug-log audit Oct 29-Nov 9'
