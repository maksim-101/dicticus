---
id: 135
title: ios27-background-neural-engine-entitlement
status: idea
size:
assignee: none
created: 2026-11-21
why:
waiting_until:
shipped:
links:
---

# The iPhone app declares iOS 27's background Neural Engine entitlement, or it is shown not to need it

iOS 27 release notes (Core AI, 174796039 and 179282606) restrict background Neural Engine access and require `com.apple.developer.background-tasks.continued-processing.inference`; the entitlement page says it applies to any Neural Engine use in the background. `iOS/Dicticus/Dicticus.entitlements` has only the app group. The owner tested on 2026-11-21 on iOS 27: start a dictation, switch to another app, stop from the Live Activity, tap the Dynamic Island — it works without error. So either the stop path reaches the foreground before transcribing, or FluidAudio falls back off the Neural Engine. Open: which of the two (a log line naming the compute unit would settle it), and whether adding the entitlement is still right. Source: `.planning/research/mobile-and-noise-2026-11-21/SUMMARY.md` section 1.
