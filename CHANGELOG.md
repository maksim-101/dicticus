# Changelog

All notable changes to Dicticus (macOS + iOS). This is a high-level history — when things were added, changed, or fixed — consolidated from git history, tags, GitHub releases, and `.planning/` milestone records. Day-to-day fixes are rolled up into their release.

Dicticus is a fully local, on-device dictation app (ASR via FluidAudio/Parakeet TDT v3, AI cleanup via llama.cpp/Gemma) for macOS and iOS. Versioning note: the product milestone line (v1.0 → v2.3) and the macOS release-tag line (`v0.1.0` … `macos-v1.2.0`) evolved separately; both are shown where they apply.

---

## Unreleased

- **Starter packs expanded** — added brand and tech dictation corrections to the bundled starter packs (Dictionary → Starter Packs), macOS + iOS.

---

## 1.0.1 — Repo rename + cleanup fix — 2026-08-01

- **Project home renamed** to `github.com/maksim-101/dicticus` (was `dicticus-macos` — the repo hosts both the macOS and iOS apps). The Sparkle update feed moved to `maksim-101.github.io/dicticus/appcast.xml`; 1.0.0 installs carry the old feed URL and need this one manual update.
- **Fixed: AI-cleanup sentence glue** — when EditGuard (correctly) rejected an LLM merge of two sentences, the restored sentence break could lose its space ("labeled.So"). The rejected-edit restore path now keeps the original spacing. macOS + iOS.

---

## 1.0.0 — First public release — 2026-07-31

> **Versioning note:** 1.0.0 marks the first public release under a clean version line.
> The sections below it document earlier development milestones whose numbers (v1.x/v2.x
> and `macos-v1.x` tags) were internal counters; those tags and releases have been retired.

The first public Dicticus release, and a major engine generation:

- **New ASR engine** — Whisper large-v3-turbo via WhisperKit on the Apple Neural Engine, replacing Parakeet: better word accuracy and repair behavior in German and English, with clip-relative adaptive voice gating so quiet speech isn't dropped.
- **AI cleanup, rebuilt around fidelity** — cleanup (Qwen3.5-4B via llama.cpp) is strictly opt-in with its own hotkey, and every LLM edit now passes **EditGuard**, a deterministic edit-level guard that blocks the model from rewriting what you actually dictated (content-word deletions/insertions/identity changes, pronoun flips, phantom moves) while letting punctuation, casing, and safe grammar repairs through.
- **Context-aware formatting** — the active app is detected and the cleanup prompt adapts (code context keeps identifiers safe); per-app overrides and a session pin are configurable.
- **Plain dictation got smarter** — deterministic multi-sentence capitalization, spoken punctuation, acronym collapse, number/currency formatting, and the brand-matcher (phonetic recovery of misheard technical terms) all run without any LLM.
- **Custom dictionary platform** — user-owned corrections with CSV/JSON import/export and bundled starter packs.
- **Quality-of-life** — media auto-pause during push-to-talk (Music/Spotify pause, other audio muted only when actually playing), searchable local history (FTS5), menu-bar popover with Home/Dictionary/History tabs.
- **iOS app** — Shortcuts/Action-Button dictation with the same shared pipeline, deferred delivery for background recordings, and on-device models throughout.

Fully local as always: no audio or text ever leaves the device.

---

## v2.4 — Public-Release Readiness + Dictionary as Platform — shipped 2026-06-09 · tag `macos-v1.4.0`

Public-release prep: the dictionary becomes a user-owned platform, deterministic spoken-punctuation lands pre-cleanup, the iOS first-run experience gets an overhaul, and both apps are reorganized into a clean tabbed information architecture.

- **Phase 31 (2026-06-06)** — Dictionary as a platform: the public build ships an empty default dictionary (personal entries gated behind a local-only flag and kept out of the release binary), CSV/JSON import & export with three merge strategies and RFC-4180 validation, bundled offline starter packs with one-tap import, and docs for the CSV-author tech-term recovery workflow. macOS + iOS.
- **Phase 32 (2026-06-07)** — Spoken punctuation: saying "comma", "period", "new line", etc. is converted deterministically before AI cleanup, with an in-app reference table. macOS + iOS.
- **Phase 33 (2026-06-08)** — iOS first-run & onboarding overhaul: fixed the relaunch download-screen flash (including a follow-up where an already-downloaded model still showed a fake "Downloading" screen during warmup), download-screen label truncation at small widths, and a duplicate Action Button entry in Settings; added a 3-page guided onboarding tour that auto-presents after setup and is re-triggerable from Settings. Also removed a misleading dictation Live Activity that implied background recording the app couldn't actually do — leaving the app mid-dictation now finalizes and copies what you said instead. iOS.
- **Phase 34 (2026-06-08)** — AI cleanup R8 over-promotion fix (V19D → V19E): tightened the R8 EXCEPTION so AI cleanup no longer collapses real words next to number-words into identifier stems ("kink three" stays "kink three", "King Four" → "King four" — not K3/K4). The EXCEPTION now requires the preceding stem to be ALL-CAPS (e.g. GPT, E, API) or contain a non-letter character (e.g. iOS, E2), not just any capitalized word. Also added a deterministic content-word-preservation gate that falls back to pre-LLM text when a content word is dropped — a backstop for local word-loss invisible to the whole-text Levenshtein gate. Gap-closure (2026-06-08): the gate now runs on short utterances (≤3 words) instead of only on longer inputs, and legitimate number-word promotions ("M three" → "M3") are preserved by allowlisting spelled-out cardinals and ordinals. macOS + iOS.
- **Phase 35 (2026-06-09)** — UI reorganization (macOS + iOS): the macOS menu-bar popover is split into a fixed-height tabbed layout (Home / Dictionary / History) with a 4-pane ⌘, Settings window (Hotkeys / AI Cleanup / General / About) and all hotkey configuration consolidated into one pane; the popover Dictionary tab gains an inline add-entry form. iPhone gains a matching 3-tab layout (Dictate / Dictionary / History) with frequency-ordered Settings and Dictionary promoted out of Settings; on iPad the NavigationSplitView sidebar gains a Dictionary destination. Custom-dictionary entries you add now sort to the top of the list (above imported and default entries). Signed-build polish: full-width tab tap targets, a visible Quit button + hover tooltips in the popover header, and a Stage Manager fix so the Dictionary / History / Settings windows stay findable when switching apps. macOS + iOS.

---

## v2.3 — Live-Capture Quality Pass — shipped 2026-06-06 · tag `macos-v1.3.0`

Quality pass driven by analysis of real multi-day dictation logs (the DebugRecorder capture). Focus: stop the dictionary from corrupting text, and sharpen the AI cleanup prompt.

- **Phase 27 (2026-05-27)** — Dictionary hallucination guard (stops fuzzy-matching from mangling correct words), DebugRecorder enrichment, and a batch of brand/jargon dictionary additions.
- **Phase 28 (2026-05-27)** — "V19D" AI-cleanup prompt iteration: better clause handling, contraction handling, de-duplication, and number formatting.
- **Phase 29 (2026-05-29)** — Post-ASR fixes: spelled-out acronyms collapse (`N F S K` → `NFSK`), spoken letter names resolve inside acronyms (zed/zee → Z, etc.), and the Zed IDE (misheard as "set") is recovered via a period-anchored dictionary entry. Cross-platform (macOS + iOS).
- **Phase 30 (2026-06-06)** — Push-to-talk now pauses Apple Music / Spotify while you dictate and resumes on release; for other audio (browser/YouTube/podcasts) it mutes output during the hold and unmutes on release. Respects a system you muted yourself. macOS-only. (Note: output devices with hardware-only volume — some external USB DACs — can't be muted by macOS, so the mute fallback is a no-op there; the Music/Spotify pause is unaffected.)
- **Fix** — ASR model download now retries on a transient network drop instead of failing the whole download (the ~2.7 GB Parakeet download from HuggingFace would abort on a single "connection reset"). macOS + iOS.

_Shipped as macOS `1.3.0` (build 5) on 2026-06-06, tag `macos-v1.3.0` — the first installable update since `macos-v1.2.0`, so it delivers the v2.2 + v2.3 work together to anyone updating from 1.2.0._

---

## v2.2 — Adaptive Cleanup & Stability — shipped 2026-05-03 → 2026-05-22

Stability and correctness work on the cleanup pipeline, plus number/ITN handling.

- **Adaptive cleanup & stability (2026-05-03)** — Debounce fix, surgical completion, 6-token repair window.
- **Resolver regression hotfix (2026-05-08)** — Fixed self-correction regex (comma-prefix + word boundaries); locked behavior with cross-platform fixtures.
- **Pipeline quality hardening (2026-05-22)** — Inverse text normalization for spoken decimal markers (`Punkt`/`Komma`/`point`) and fixes for comma-separated digit words.

---

## v2.1 — AI Cleanup & Swiss-Ification Polish — shipped 2026-05-01  ·  tag `macos-v1.2.0`

Originally scoped as "keyboard extension + iCloud sync," but pivoted: the iOS keyboard extension was removed (iOS 26 blocked the URL-opening trick it relied on), and AI cleanup quality became the main work. Shipped as a notarized macOS release with auto-update.

- **AI cleanup overhaul** — Upgraded to Gemma 4 E2B; numbers/currencies/dates formatting; Swiss German orthography (ß→ss, dialect-aware); refined cleanup prompt with order-locking tests.
- **macOS distribution hardened** — Notarized DMG, Sparkle EdDSA-signed auto-update feed, full build→sign→notarize→staple pipeline.
- **Keyboard extension pivot** — Removed from shipping app; architecture preserved in history for possible future revival.
- **Repo hygiene** — Planning artifacts moved out of version control.

_Known limitations carried forward: non-reactive transcribing/cleaning menu-bar icon (cosmetic); occasional sentence-stitching by the LLM._

---

## v2.0 — iOS App (Shortcut Dictation) — shipped 2026-04-22

Dicticus became multi-platform with a native iOS app for iPhone and iPad.

- **Shared core pipeline** — Transcription/cleanup logic unified into a cross-platform `Shared/` module used by both macOS and iOS.
- **On-device iOS dictation** — FluidAudio on iOS with ~2.7 GB model provisioning and background warmup.
- **System integration** — "Start Dictation" Siri Shortcut / Action Button support and a Live Activity for real-time feedback.
- **Universal layout** — Adaptive SwiftUI UI (iPhone + iPad sidebar).
- **Local persistence** — History and dictionary stored via GRDB with full-text search.

---

## v1.1 — Cleanup Intelligence & Distribution — shipped 2026-04-20/21  ·  tags `v1.1.0`, `v1.1.1`

- **Smarter AI cleanup** — Upgraded the LLM to Gemma 4 E2B; redesigned prompt infers meaning from broken/non-native German rather than just fixing grammar.
- **Inverse text normalization** — Spelled-out numbers become digits, English and German ("one hundred twenty three" / "einhundertdreiundzwanzig" → "123").
- **Custom dictionary** — User-configurable find-and-replace for recurring ASR errors, pre-seeded with 35+ common fixes (pipeline: ASR → Dictionary → ITN → AI cleanup).
- **Transcription history** — Searchable full-text history of past dictations (GRDB + FTS5) with one-click copy.
- **Distribution** — Developer ID signed + Apple notarized (no Gatekeeper override); Sparkle auto-updates via EdDSA-signed appcast.
- **v1.1.1 patch (2026-04-21)** — Fixed default dictionary entries not populating on Sparkle updates (only fresh installs).

---

## v1.0 — MVP — shipped 2026-04-18  ·  tags `v1.0`, `v0.1.0`

First working release: a fully local macOS menu-bar dictation app.

- **System-wide push-to-talk** — Hold a hotkey, speak, release; text appears at the cursor in any app.
- **On-device ASR** — FluidAudio + Parakeet TDT v3 (German ~5% WER, English ~6% WER), ~200× realtime on the Apple Neural Engine.
- **Local AI cleanup** — Gemma (via llama.cpp) for grammar/punctuation; no cloud dependency.
- **Modifier-only hotkeys** — Fn+Shift / Fn+Control via a global event monitor.
- **Lightweight** — ~170 MB memory footprint.
- **DMG distribution** with a permissions onboarding flow.

---

_For deeper detail on any release, see the per-milestone records under `.planning/milestones/` and the phase summaries in `.planning/phases/` (local only — not tracked in git). GitHub Releases: https://github.com/maksim-101/dicticus/releases_
