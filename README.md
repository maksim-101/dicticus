# Dicticus

A fully local dictation app for macOS and iOS. Hold a key or trigger a shortcut, speak, release — accurate text appears instantly. Fully private, no cloud dependency.

<p align="center">
  <img src="assets/popover-home.png" width="348" alt="Dicticus menu-bar popover — Home tab, ready to dictate">
</p>

## Features

- **Multi-Platform** — Native apps for macOS (Menu Bar) and iOS (Universal App).
- **System-wide push-to-talk** — Works in any text field on macOS.
- **Siri Shortcuts & Action Button** — Trigger iOS dictation from anywhere, even when locked.
- **On-device ASR** — Whisper large-v3-turbo via WhisperKit on the Apple Neural Engine.
- **AI cleanup mode** — Grammar, punctuation, word-order, and filler-word correction via Qwen3.5-4B (llama.cpp), on both macOS and iOS. Optional and opt-in — triggered by its own shortcut, with a deterministic fidelity guard that blocks the model from rewriting what you actually dictated.
- **Spoken punctuation** — Say "comma", "new line", etc. and it's inserted deterministically before cleanup.
- **Auto language detection** — German and English, no manual switching.
- **Local History & Search** — Browse and search your past transcriptions with FTS5.
- **Custom Dictionary** — Define your own replacements for technical terms or names; import/export as CSV/JSON and add bundled starter packs.

## Requirements

### macOS
- macOS 15+ (Sequoia)
- Apple Silicon Mac (Intel Macs launch the universal binary, but transcription without the Neural Engine is too slow to recommend)
- ~1 GB disk for the ASR model, plus ~2.7 GB for the optional AI-cleanup model (downloaded only if you enable AI cleanup)

### iOS / iPadOS
- iOS 17+
- iPhone 15 or later (for Action Button optimization), or any modern iPhone/iPad. AI cleanup requires a device with ≥5 GB RAM.
- ~1 GB disk for the ASR model, plus ~2.7 GB for the optional AI-cleanup model.

## Installation

### macOS
1. Download `Dicticus.dmg` from [Releases](../../releases)
2. Open the DMG and drag Dicticus to Applications
3. Launch Dicticus — it's Developer ID signed and notarized, so it opens normally (no Gatekeeper override needed).
4. Grant Microphone and Accessibility permissions when prompted.

### iOS
1. Build from source using Xcode 26.
2. Grant Microphone permission during onboarding.
3. Download the ASR model (one-time setup).
4. Follow the in-app guides to setup the **Start Dictation** Siri Shortcut.

## Manual uninstall

Prefer the script: `./scripts/uninstall.sh` quits Dicticus, removes the app bundle, preference files, and the LaunchAtLogin entry, then prompts before deleting the ~3 GB model cache.

To uninstall by hand, remove these four locations:

1. `/Applications/Dicticus.app`
2. `~/Library/Preferences/com.dicticus.*.plist`
3. `~/Library/Application Support/Dicticus/` (contains the Qwen3.5 AI-cleanup model, the WhisperKit ASR cache, and `history.sqlite`)
4. `~/Library/LaunchAgents/com.dicticus.app.plist` (LaunchAtLogin entry; only present if you enabled "Start at login")

**TCC permission entries:** macOS does not let any app clean its own Privacy & Security entries. After uninstalling, open **System Settings > Privacy & Security** and remove **Dicticus** from **Microphone**, **Accessibility**, and **Input Monitoring** before reinstalling — otherwise stale TCC entries from previous bundle copies can block hotkeys.

## Updating the app icon

The app icon is generated from a single source: `assets/icon-master.png` (1024×1024 PNG, committed to the repo).

To change the icon:

1. Replace `assets/icon-master.png` with a new 1024×1024 PNG.
2. Run `./scripts/generate-icons.sh` to fan the master out to:
   - all ten macOS appiconset PNGs (16/32/128/256/512 × 1x and 2x)
   - the single iOS `AppIcon.png` (iOS 18 unified icon model)
3. Commit the regenerated PNGs along with your master change — generated outputs are tracked in git so PR reviewers can spot unintended icon changes visually.
4. Clean-build (`scripts/build-dmg.sh` or `xcodebuild -scheme Dicticus -configuration Release clean build`) before verifying in Finder; LaunchServices caches stale icons aggressively. If the new icon does not appear after a clean build, run `killall Dock Finder` and `sudo mdutil -E /` to nuke icon caches.

## Usage

- **macOS**: Hold a hotkey, speak, release. Two configurable hotkeys — plain dictation (default ⌃⇧S) and AI cleanup (default ⌃⇧D).
- **iOS**: Trigger the **Start Dictation** shortcut via voice, Action Button, or Back Tap.
- **Dictionary**: Manage replacements in Settings to improve accuracy for specific terms.
- **History**: Use the History tab on iOS or the Menu Bar on macOS to find past transcriptions.

## Privacy

All processing happens on-device. No audio or text is ever sent to any server. The app makes zero network calls during operation (model downloads happen once on first launch).

## Tech Stack

| Component | Technology |
|-----------|-----------|
| App shell | Swift 6 + SwiftUI, MenuBarExtra (macOS) |
| ASR | WhisperKit + Whisper large-v3-turbo (CoreML, Apple Neural Engine) |
| LLM | llama.cpp + Qwen3.5-4B Instruct Q4_K_M (Metal) — macOS + iOS |
| Database | GRDB + SQLite (FTS5) |
| Live Activity | ActivityKit (iOS) |
| Text injection | NSPasteboard (macOS) + UIPasteboard (iOS) |

## Building from Source

```bash
# Prerequisites: Xcode 26+, xcodegen
brew install xcodegen

# macOS
cd macOS
xcodegen generate
xcodebuild -scheme Dicticus -configuration Release build

# iOS
cd iOS
xcodegen generate
# Open Dicticus.xcodeproj in Xcode 26 and Run on Device/Simulator
```

## License

Private project. All rights reserved.
