---
id: 126
title: test-host-exit-crash
status: idea
size:
assignee: none
created: 2026-11-15
why:
waiting_until:
shipped:
links: 59-check-both-schemes
---

# A local macOS test run ends without a "Dicticus quit unexpectedly" dialog

The macOS test host (com.dicticus.app.xctest) aborts at exit in llama.cpp's Metal teardown (ggml_abort in ggml_metal_rsets_free), so local test runs can put crash dialogs on the owner's screen. Reports since at least 2026-11-13 (6 that day, several on 2026-11-14, including the slice 52 baseline). Converted from an unscheduled root `Carried:` line of slice 52 at the adoption of 2026-11-15.
