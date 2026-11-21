---
id: 137
title: ios-keyboard-retest-full-access
status: planned
size:
assignee: none
created: 2026-11-21
why: the owner approved the re-test (2026-11-21); if a keyboard can open the app with Full Access on, iPhone dictation can land at the cursor like Granola, Wispr Flow and KeyVox do, instead of the clipboard
waiting_until:
shipped:
links:
---

# A device test shows whether a Dicticus keyboard can open its app on iOS 27 with "Allow Full Access" on

The April 2026 keyboard (removed) failed to open the containing app with five methods on iOS 26 (memory note on the keyboard decision). KeyVox, open source on the same FluidAudio/Parakeet stack, ships a keyboard that opens its app with the same responder-chain `openURL:options:completionHandler:` call (checked: `iOS/KeyVox Keyboard/App/KeyboardContainingAppLauncher.swift`), and KeyboardKit reports URL opening from keyboards needs Full Access since iOS 26; whether Full Access was on in April is not recorded. Every shipping dictation keyboard (Granola included) opens its app once per session, keeps the audio session alive in the background, and records in place afterwards. A newer route (Raycast, 2026-11-19, `stephancill/ios-keyboard-dictation`) captures the mic in a hidden WKWebView inside the keyboard with App Review risk. Research: `.planning/research/mobile-and-noise-2026-11-21/SUMMARY.md` sections 2-3 and `keyboard-competitors.md`; reusable MIT code from KeyVox, Dictus and Talkit in `.planning/research/competitors-2026-11-21/open-source.md`.
