---
id: 141
title: tests-without-microphone-prompt
status: idea
size:
assignee: none
created: 2026-11-21
why:
waiting_until:
shipped:
links: 126-test-host-exit-crash, 68-test-suite-leftovers
---

# A local test run puts no microphone-permission prompt on the owner's screen

The owner, 2026-11-21: "I keep getting these allow microphone access on my screen!" during slice 52's test runs. Each `xcodebuild test` (and `scripts/pre-push`'s clean-checkout run) launches an unsigned Debug `Dicticus.app` as the test host; macOS treats every build as a new app and shows "Allow Dicticus to access your microphone?". The app's own request is `PermissionManager.requestMicrophone()` (called from onboarding and the Home pane); which test path triggers it, or whether the test host's startup touches audio input, is not yet known. Direction: find the trigger and keep the test host away from microphone access (skip audio-input setup when running under XCTest, or a stable signing identity for the test host so one grant holds). Until then, "Don't Allow" on the prompt is safe; it affects only the test copy.
