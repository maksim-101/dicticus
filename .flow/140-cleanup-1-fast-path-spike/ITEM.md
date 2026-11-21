---
id: 140
title: cleanup-1-fast-path-spike
status: idea
size:
assignee: none
created: 2026-11-21
why:
waiting_until:
shipped:
links: 61-lfm3-small-model-retry-spike
---

# A measurement says whether Spokenly's 0.6B cleanup model is a usable fast path next to Qwen3.5-4B

`spokenly/cleanup-1` (Hugging Face, Apache-2.0, updated 2026-11-04; CoreML 768 MB, GGUF 639 MB per the report) is trained for fillers and self-corrections and is said to run in about 200 ms on Apple Silicon, weaker in German. Measure on the spike-022 harness against Qwen's good cleanups, English first; spikes 015, 022 and slice 61 rejected other small models, so the same bars apply. Source: `.planning/research/competitors-2026-11-21/SUMMARY.md`.
