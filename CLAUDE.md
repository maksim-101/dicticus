## Project

**Dicticus** is a fully local, multi-platform dictation app that replaces native dictation on Mac, iPhone and Windows. It transcribes German and English speech with on-device ASR, offers optional on-device LLM cleanup, and is activated by system-wide hotkeys (Mac/Windows) or a Shortcut (iPhone).

**Core value:** press a key, speak, release, and accurate text appears at the cursor almost at once, fully private, with no cloud dependency.

## Method
This project uses the flow method: start and resume with `flow:next`; state lives in `.flow/`.
Sequence: brief (mockup for visual or logic questions) → plan → build → review → verify → ship; owner findings → fix → verify (or ship, when only `[check]` criteria were touched and the `[judge]` items are signed off). Sequence, branches and who does what (subagents, models): `references/files.md` in the flow plugin.

# Compact instructions
Keep from `.flow/STATE.md`: slice, step, `Next:`, `Carried:`; the current task block and the done criteria in play; every owner decision and open question. After the compaction, re-read `.flow/STATE.md` and every file about to be edited; the current step's flow skill counts as read if its whole text was re-supplied, and otherwise is invoked again before the next edit; at `Step: done`, start flow:next only when the owner asks for new work, and otherwise wait.

## Working rules

### Constraints
- **Privacy:** all processing happens on-device; no audio or text goes to any server.
- **Performance:** transcription must feel near-instant after the hotkey is released (under 2-3 s for typical utterances).
- **Local models:** ASR and LLM both run locally, with quality comparable to Parakeet V3.
- **System-wide:** works in any text field in any app.
- **Activation:** push-to-talk on Mac/Windows, toggle on iPhone; never always-listening.
- **Public repo:** no personal data in any tracked file, commit message or `.flow/` file (pii-scan enforces it). `.flow/` files say "the owner", never a name, and use repo-relative paths. Dictation samples from the debug logs never enter a tracked file. The planning tree (`.planning/`) stays gitignored.

### Current stack (as of 2026-11-08; `CHANGELOG.md` is authoritative)
- macOS ASR: WhisperKit (`argmaxinc/argmax-oss-swift`, `from: 1.0.0`) with Whisper large-v3-turbo, since GSD phase 41.
- iOS ASR: FluidAudio `from: 0.17.7` (`iOS/project.yml`) with Parakeet Ultra, since quick task 261017-qlv (Parakeet since phase 47.1).
- Cleanup LLM, both platforms: Qwen3.5-4B-Instruct Q4_K_M via llama.cpp Metal (`qwen3.5-4b-q4_k_m.gguf`, SHA-256 pinned in `ModelDownloadService` / `IOSModelDownloadService`; dev override `-llmModelFileOverride <name>.gguf`), strictly opt-in behind the EditGuard fidelity gate.
- Windows (separate repo): whisper.cpp + llama.cpp.
- The original v1 stack research, its rejected alternatives and the model history live in `.planning/research/STACK.md` and the milestone archives.

### Standing decisions
- iOS runs on every iPhone and iPad with iOS 26; no chip gate (owner, 2026-11-04).
- AI Cleanup on iOS needs 8 GB RAM: threshold 6.5 GiB of `ProcessInfo.physicalMemory` (owner, 2026-11-04).
- macOS downloads the AI-cleanup model only after the user agrees; "Download the model automatically" defaults off (owner, 2026-11-03).
- Cleanup pipeline changes ship on macOS and iOS together.

### Shell command shaping (fewer permission prompts)
- Prefer the Read, Grep and Glob tools over `cat`/`sed -n`/`head`, `grep … | head` and `find`/`ls` globbing.
- Don't bundle diagnostics into one command: no `cmd1 ; echo "---" ; cmd2` chains, `for` loops or `if` blocks; issue separate simple commands.
- Avoid `$(…)` command substitution in diagnostic commands.
- Allowlisted: `git log/diff/status`, `head`, `tail`, `grep`, `cat`, `printf`, `sleep`, `strings`, `cut`, `tr`, `uniq`, `comm`, `column`.

### History and research (read-only)
- GSD history up to 2026-11-08 (phases, decisions, UAT, milestone archives) stays in `.planning/`, gitignored. A slice worktree doesn't have it; read it from the main checkout. `.flow/ROADMAP.md` lists every GSD phase under its old number.
- Spikes (`.planning/spikes/`), seeds (`.planning/seeds/`), todos (`.planning/todos/`), backlog (`.planning/backlog/`, plus 999.x items in `.planning/ROADMAP.md`) and debug-log audits (`.planning/debug/`) stay there; one becomes a `.flow/ROADMAP.md` row only when the owner schedules it.
- Spike findings (implementation patterns, constraints, gotchas): `Skill("spike-findings-dicticus")`.

## Multi-Platform Strategy

Dicticus is a family of platform-native apps sharing the same goal, models, and (where possible) code.

### Repository Structure

```
dicticus/                    ← this repo (Apple platforms)
├── macOS/                   ← macOS menu bar app (Swift/SwiftUI, xcodegen)
│   ├── project.yml          ← xcodegen config
│   ├── Dicticus/            ← app sources
│   └── DicticusTests/       ← tests
├── Shared/                  ← shared Swift code (future: extracted services)
├── iOS/                     ← iOS keyboard extension + host app (future)
├── scripts/
│   ├── build-dmg.sh         ← macOS release pipeline
│   └── build-ipa.sh         ← iOS release pipeline (future)
├── .flow/                   ← flow state (STATE.md, ROADMAP.md, slice folders)
├── .planning/               ← GSD history, read-only, gitignored
└── CLAUDE.md

~/code/dicticus-windows/     ← separate repo, separate tech stack (C#/Rust)
```

### Platform Details

| | macOS | iOS/iPadOS | Windows |
|---|---|---|---|
| Repo | `dicticus` (this) | `dicticus` (this) | `dicticus-windows` (separate) |
| Language | Swift 6 | Swift 6 | C# or Rust |
| ASR | WhisperKit (Whisper large-v3-turbo) | FluidAudio (Parakeet Ultra) | whisper.cpp |
| LLM | llama.cpp (Metal) | llama.cpp (Metal) | llama.cpp (CPU/CUDA) |
| Distribution | Sparkle + GitHub Releases | TestFlight / Ad-hoc | TBD |
| Tags | `macos-vX.Y.Z` | `ios-vX.Y.Z` | own repo tags |
| Build script | `scripts/build-dmg.sh` | `scripts/build-ipa.sh` | own repo |

### Shared Code (macOS ↔ iOS)

When iOS work begins, extract platform-independent services into `Shared/`:
- `DictionaryService`, `ITNUtility`, `CleanupPrompt` — pure Swift, no platform deps
- `CleanupService` — llama.cpp via SPM (cross-platform)
- `HistoryService` — GRDB (cross-platform)
- `TextProcessingService` — orchestrator, depends on above

Platform-specific code stays in `macOS/` or `iOS/`:
- Hotkey management, text injection, audio capture, app lifecycle, UI views

### Working on a Single Platform

Branch and PR as normal. Scope changes to the platform directory:
- macOS-only change: edit `macOS/` files, PR targets `main`
- iOS-only change: edit `iOS/` files, PR targets `main`
- Shared change: edit `Shared/`, verify both platforms build

## Code Signing & Keychain

Signing identities, keychain locations and the key-restore recipe are machine- and owner-specific and live in the untracked `CLAUDE.local.md` (loaded automatically). Never click "Revoke Certificate" in Xcode when it reports a missing private key: cancel and restore the key per that file.
