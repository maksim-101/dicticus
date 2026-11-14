# Task 1: harness, models, fidelity (2026-11-14)

Work files are in the gitignored `.planning/spikes/025-lfm3-retry/`. Counts and hashes only.

- Scripts copied from spike 022; the stop list is now the app's nine entries (022's eight plus `</corrected_text>`, as in `CleanupService.swift` on main). Arms are named on the command line; a prompt variant is a small transform of the production system text under `prompts/`.
- Gate tool rebuilt from `git archive main -- Shared` at b5c1310 (same code as 4a6ffd6) with the working tree's `PersonalLexicon.swift`: `Build complete!`.
- Models: LFM3-1.7B Q4_K_M was still on disk in spike 021's folder, so nothing was downloaded; `shasum -a 256` gives `3793e1e6e2266919…`. Qwen3.5-4B Q4_K_M is the app's file, `00fe7986ff5f6b46…`. Both prefixes equal spike 022's protocol.
- Server: Homebrew `llama-server` 0.9.0 build 12110 (spike 022 used 0.8.0), `-c 4096 -ngl 99 --seed 16 -np 1`, one model at a time, each admitted by the host's resource gate (`serve.sh`); the decode script asks the gate every 20 items and pauses when told.
- Determinism, Qwen: `python3 -I generate.py Q dev determinism` printed `True` three times.
- Qwen reproduction: `python3 -I check_q_repro.py` → `Q dev outputs equal to spike 022 after the tag cut: 238 of 238 (100.0 %)`, exit 0. The newer server version changes nothing. Qwen's 238 dev decodes took 432 s.
- The resource gate held the first start back for about four minutes while another session's model job loaded and ran; that session confirmed it was done before the decode started.

- Gate fidelity on the dev set with today's gate: the logged model output replays to the logged result on 237 of 238 records (German 118 of 119, English 119 of 119), the same figure as spike 022.

LFM3's determinism line is recorded with task 2.
