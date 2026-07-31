---
version: alpha
name: Dicticus
colors:
  brand-primary: "#1F4231"
  brand-accent: "#2D6D4E"
  brand-surface: "#D8E8DC"
  recording: "#E5484D"
  ready: "#2BA471"
  warning: "#F5A524"
  text-primary: "#0B0F0D"
  text-secondary: "#5C6C64"
  background: "#FFFFFF"
  surface: "#F4F6F4"
  divider: "#E1E5E2"
  brand-primary-dark: "#1F4231"
  brand-accent-dark: "#7CC9A2"
  text-primary-dark: "#F2F5F2"
  text-secondary-dark: "#A8B5AD"
  background-dark: "#0E1311"
  surface-dark: "#172019"
  divider-dark: "#243029"
typography:
  display:
    fontFamily: "SF Pro Display"
    fontSize: 34
    fontWeight: 700
    lineHeight: 41
    swiftUI: ".largeTitle.bold()"
  title:
    fontFamily: "SF Pro Display"
    fontSize: 28
    fontWeight: 700
    lineHeight: 34
    swiftUI: ".title.bold()"
  headline:
    fontFamily: "SF Pro Text"
    fontSize: 17
    fontWeight: 600
    lineHeight: 22
    swiftUI: ".headline"
  body:
    fontFamily: "SF Pro Text"
    fontSize: 17
    fontWeight: 400
    lineHeight: 22
    swiftUI: ".body"
  subheadline:
    fontFamily: "SF Pro Text"
    fontSize: 15
    fontWeight: 400
    lineHeight: 20
    swiftUI: ".subheadline"
  caption:
    fontFamily: "SF Pro Text"
    fontSize: 12
    fontWeight: 400
    lineHeight: 16
    swiftUI: ".caption"
  caption2:
    fontFamily: "SF Pro Text"
    fontSize: 11
    fontWeight: 400
    lineHeight: 13
    swiftUI: ".caption2"
  mono-digits:
    fontFamily: "SF Mono"
    fontSize: 12
    fontWeight: 400
    swiftUI: ".caption.monospacedDigit()"
spacing:
  xs: 4
  sm: 8
  md: 16
  lg: 24
  xl: 32
  "2xl": 48
  "3xl": 64
rounded:
  xs: 4
  sm: 8
  md: 12
  lg: 16
  xl: 24
  pill: 999
motion:
  micro: 100
  fast: 180
  standard: 250
  expressive: 400
  spring-default: "response: 0.45, dampingFraction: 0.85"
components:
  mic-button-hero:
    diameter: 240
    iconSize: 96
    rounded: pill
    fillColor: brand-accent
    activeFillColor: recording
  mic-button-compact:
    diameter: 96
    iconSize: 40
    rounded: pill
    fillColor: brand-accent
    activeFillColor: recording
  primary-button:
    height: 50
    paddingHorizontal: lg
    rounded: md
    fontSize: 17
    fontWeight: 600
  status-pill:
    paddingHorizontal: sm
    paddingVertical: xs
    rounded: sm
    fontSize: 11
    fontWeight: 700
  history-row:
    paddingVertical: sm
    collapsedLineLimit: 3
    expandedLineLimit: null
  menu-bar-icon:
    size: 18
    style: template
---

## Overview

Dicticus is a privacy-first, on-device dictation utility for macOS, iPhone, and Windows. The visual identity should feel **calm, instant, and trustworthy** — the opposite of cloud-AI products that signal speed via blue gradients and motion. Forest green as the dominant brand color signals **privacy, locality, and quiet confidence**; the pale sage glyph on the icon reads as approachable rather than corporate. Every UI surface defers to platform conventions (Apple HIG on macOS/iOS, Fluent on Windows) and treats the brand color as an accent — not a wash. Motion is purposeful and short: state changes (listening, ready, error) are communicated through colour and shape, never through animation that delays the user's text appearing at the cursor.

## Colors

Dicticus uses a **forest-green brand pair** layered over Apple's semantic color system. Custom hex values appear only in two places: the `AccentColor` asset (drives `.tint`/`.accentColor` across the app) and onboarding/marketing surfaces. Everywhere else, prefer SwiftUI semantic colors (`.primary`, `.secondary`, `Color(.systemBackground)`) so the app inherits user dark-mode and accessibility settings.

| Token | Hex (light) | Hex (dark) | Role |
|-------|-------------|------------|------|
| `brand-primary` | `#1F4231` | `#1F4231` | Splash bg, onboarding hero, app-icon background |
| `brand-accent` | `#2D6D4E` | `#7CC9A2` | `AccentColor` asset; primary CTAs, mic-idle, links |
| `brand-surface` | `#D8E8DC` | — | Icon glyph; subtle highlight chips |
| `recording` | `#E5484D` | `#FF6369` | Active mic state; live activity indicator |
| `ready` | `#2BA471` | `#46C28C` | Success states, model-loaded badge |
| `warning` | `#F5A524` | `#FFB13B` | Permission-missing, model-not-cached, retry |
| `text-primary` | `#0B0F0D` | `#F2F5F2` | Body copy (use `.primary` in SwiftUI) |
| `text-secondary` | `#5C6C64` | `#A8B5AD` | Captions, helper text (use `.secondary`) |
| `background` | `#FFFFFF` | `#0E1311` | Window/page background |
| `surface` | `#F4F6F4` | `#172019` | Cards, history rows, settings group containers |

**Status colour conventions** (already used consistently in the codebase, locked here):

- `recording` for **active dictation only** — never for delete/destructive.
- `ready` for **operational success** (model loaded, permission granted) — not for general "go" CTAs.
- `warning` for **degraded but recoverable** states (microphone permission off, model not yet downloaded).
- Destructive actions (delete history, factory reset) use the system role color via `.role(.destructive)`, not the `recording` token.

## Typography

Two type families, both system-supplied: **SF Pro Display** for titles ≥28 pt and **SF Pro Text** for everything else. Code/numeric monospace uses **SF Mono** via `.monospacedDigit()` for download-progress and timer readouts. No custom fonts are bundled — Dicticus relies on Dynamic Type and trusts Apple's optical scale.

Hierarchy (named in DESIGN.md tokens but mapped to SwiftUI semantic styles in code):

- `display` → `.largeTitle.bold()` — onboarding hero, "What's New" banner.
- `title` → `.title.bold()` — section starts, settings group titles.
- `headline` → `.headline` — list-row titles, panel headers.
- `body` → `.body` — paragraphs, transcript content.
- `subheadline` → `.subheadline` — settings descriptions, secondary metadata.
- `caption` → `.caption` — helper text, status pill labels.
- `caption2` → `.caption2` — timestamps, language tags.
- `mono-digits` → `.caption.monospacedDigit()` — download MB counters, timers.

## Layout

**8-point grid** with a 4 px sub-base for tight clusters (icon + label gaps). All `padding`, `spacing`, and component dimensions resolve to one of: 4, 8, 16, 24, 32, 48, 64. Avoid 12 except for tight inline metadata (`HStack(spacing: 12)` between an icon, a label, and a chevron).

Default page padding: `lg` (24) on iPhone, `xl` (32) on iPad/macOS.
Default card/group spacing: `md` (16) between sibling groups, `sm` (8) within a group.

## Motion

Motion is **functional, not decorative**. Two principles:

1. **Never delay text appearing at the cursor.** Insertion is instantaneous; animations run in parallel, never block.
2. **Communicate state with one continuous shape.** Use `matchedGeometryEffect` for the home-screen mic-button morph (hero ↔ compact when clipboard state changes — UAT issue U3) so the same circle changes size rather than crossfading.

Durations:
- `micro` (100 ms) — pill toggles, checkbox.
- `fast` (180 ms) — color/opacity transitions (idle → recording flush).
- `standard` (250 ms) — geometry morph, sheet present, list reorder.
- `expressive` (400 ms) — onboarding step transitions, "What's New" reveal.

Default spring: `.spring(response: 0.45, dampingFraction: 0.85)` for non-modal geometry changes.

## Components

| Component | Tokens | Notes |
|-----------|--------|-------|
| **Mic button (hero)** | `mic-button-hero` | Home screen, empty clipboard. 240 pt diameter, dominant. |
| **Mic button (compact)** | `mic-button-compact` | Home screen, clipboard text present. 96 pt diameter, paired with cleanup-text panel above it. Same `id` as hero for `matchedGeometryEffect`. |
| **Primary CTA** | `primary-button` | "Start Dictation", "Download Model". Filled with `brand-accent`, 50 pt height. |
| **Secondary CTA** | inherit `.bordered` style | Settings actions, "Cancel". |
| **Status pill** | `status-pill` | Tiny SHORT/LONG-form labels in history rows; `brand-accent` opacity 0.1 background. |
| **History row** | `history-row` | 3-line collapsed by default; tap to expand and reveal full transcript. Highlight FTS5 search matches with `brand-accent` opacity 0.2 underline (UAT U6). |
| **Live transcript pane** | wrap content in `ScrollView` with `.defaultScrollAnchor(.bottom)` | Auto-scrolls to end during recording (UAT U4). |
| **Permission status row** *(macOS)* | platform-specific | Microphone, Accessibility, Input Monitoring — each shows ✓/⚠ and a Repair button when missing (UAT M3). |

## Do's and Don'ts

- **Do** use `AccentColor` (the asset) instead of hardcoding `brand-accent` hex in views — a single asset drives both `.tint` and macOS system-wide accent override.
- **Do** layer the brand pair (forest + sage) only on **brand surfaces**: app icon, onboarding hero, "What's New" splash. Standard chrome stays Apple-semantic.
- **Do** use `recording` (red) for the mic-active state only. Never for delete buttons.
- **Don't** introduce gradients or glassmorphism. Dicticus signals trust through restraint, not visual flair.
- **Don't** animate the actual text-insertion path. Animations are for state framing, never for content arrival.
- **Don't** override Dynamic Type. All typography respects user accessibility settings.
- **Don't** add a third typeface. SF Pro + SF Mono cover everything.

---

# 3. iOS-Specific

iPhone and iPad app shell. The most active design surface — Phase 19.6 polish (UAT U1–U6, D2) is scoped here.

## iOS Layout Specifics

- **TabView**: 3 tabs — Dictate / Dictionary / History. Settings is a route (Done-dismissable), not a tab. Dictionary was promoted from Settings → Transcriptions to a top-level tab in Phase 35.
- **Home screen** is **dynamic** based on clipboard state (UAT U3):
  - **Clipboard empty** → mic button rendered as `mic-button-hero` (240 pt), centered vertically, dominating the canvas. No text panel.
  - **Clipboard contains transcript** → mic button collapses to `mic-button-compact` (96 pt) at bottom-center, and a text panel appears above it showing the transcript with copy/edit/clear actions. Transition uses `matchedGeometryEffect(id: "micButton")` and `.spring(response: 0.45, dampingFraction: 0.85)`.
- **Settings** uses `Form` with `.insetGrouped` style. Sections in order: Transcriptions, AI Cleanup, History, Integration, Model Management, About. (Dictionary link removed from Transcriptions — Dictionary is now a top-level tab.)

## iOS Color Application

- The `AccentColor` asset in `iOS/Dicticus/Assets.xcassets/` should resolve to `brand-accent` (`#2D6D4E` light / `#7CC9A2` dark). Currently undefined — falls back to system blue. **Phase 19.6 task: define AccentColor.colorset.**
- Live Activity (Dynamic Island, lock screen): keep recording indicator at `recording` red — Live Activity has its own chrome, do not theme it.

## iOS Typography Specifics

All sizes inherit from the cross-platform tokens. Use `.dynamicTypeSize(...DynamicTypeSize.accessibility3)` as the cap to keep layouts intact while supporting accessibility scaling up to AX3.

## iOS Component Specifics

- **Mic button visual**: `Image(systemName: "mic.fill")` for idle and recording. Diameter and icon size from `mic-button-hero` / `mic-button-compact`. Long-press (0.5 s) cancels active dictation as escape hatch (D-30).
- **History rows**: 3-line collapsed body (`.lineLimit(3)`); tap expands to full transcript. When the user filters via search, highlight the matched FTS5 token span in the body using `AttributedString` + `brand-accent` underline (UAT U6).
- **Live dictation pane**: wrap the live-text view in `ScrollView { ... }.defaultScrollAnchor(.bottom)` so long dictations remain visible (UAT U4).
- **Auto-stop toggle** (Settings → Dictation): "Diktat automatisch beenden bei Stille" — default ON, but allow OFF for users who think aloud (UAT U5).
- **AI Cleanup banner** (Home, sticky): when `aiCleanupEnabled = true` AND `cachedModel = false`, show a yellow `warning` banner at top of Home: "AI Cleanup wartet — Modell laden →" tappable to Settings → AI Cleanup (UAT U1).
- **Restart prompt** after model download: replace plain text with a styled card containing a primary CTA "Jetzt neustarten" (UAT U2).

## iOS Asset Specifics

- App icon: `iOS/Dicticus/Assets.xcassets/AppIcon.appiconset/` (currently a single `AppIcon.png`; should be a multi-resolution set generated from a 1024×1024 master).
- iOS-specific: `AccentColor.colorset` (TBD — Phase 19.6).

---

# 4. macOS-Specific

Menu bar utility shell. Phase 19.7 hygiene work happens here (UAT M1–M3, D1).

## macOS Layout Specifics

- **MenuBarExtra**: 18×18 template SF Symbol (`mic.fill` or custom monochrome icon). Renders correctly in light/dark menu bar without explicit color.
- **Dropdown panel**: 348 pt wide; tabbed (Home / Dictionary / History); fixed-height, never scrolls; no config controls. Persistent header: "Dicticus" wordmark + a 40pt gear button that opens the Settings window.
- **Settings window**: `Settings { }` scene (⌘,). 4 panes: Hotkeys / AI Cleanup / General / About. ("Models" folds into AI Cleanup; "Dictionary" is NOT a Settings pane — it is a popover tab + the existing manager window.)

## macOS Color Application

- `NSColor.controlAccentColor` automatically follows the user's system accent — Dicticus does **not** override this on macOS. The `AccentColor` asset in `macOS/Dicticus/Assets.xcassets/` is provided as a fallback only.
- Status colors (`recording`, `ready`, `warning`) apply equally on macOS for permission badges in the dropdown.

## macOS Component Specifics

- **Permission Status Row** (UAT M3): rendered in the menu-bar dropdown. Shows three rows — Microphone, Accessibility, Input Monitoring — each with state indicator (`ready` ✓ / `warning` ⚠) and an inline "Repair" button when any is missing. Repair opens the relevant `x-apple.systempreferences:` URL.
- **Hotkey row**: `KeyboardShortcuts.Recorder` with conflict detection. No custom styling needed.
- **Model download progress**: same `ProgressView` styling as iOS, but inline in the Models tab.

## macOS Distribution Specifics

- **Single canonical install path**: `/Applications/Dicticus.app`. The build script (`scripts/build-dmg.sh`) and any dev install must remove stale copies in `~/Applications/`, `~/Downloads/`, `~/Desktop/`, etc., before installing — TCC permissions are bound to the running binary's signature/path, and stale copies cause the M1 hotkey-regression class of bugs.
- **One-liner uninstaller** (UAT M2): `find ~ /Applications -maxdepth 4 -name "Dicticus.app" -exec rm -rf {} +` (developer-only; user-facing uninstall is drag-to-trash from `/Applications`).

## macOS Asset Specifics

- App icon: `macOS/Dicticus/Assets.xcassets/AppIcon.appiconset/` — full multi-resolution set already present, **but missing icon** in latest build (UAT D1) suggests `Contents.json` may have stale references. Audit during Phase 19.7.
- Menu bar template icon: TBD — needs to be 18×18 monochrome with transparent bg, marked as Template Image in asset settings.

---

# 5. Windows-Specific

Future repo (`~/code/dicticus-windows`). Tokens here apply when the Windows app is built; cross-platform tokens (color, typography spec, motion durations) carry over verbatim. Apple-specific component names are translated to their Fluent equivalents.

## Windows Mapping

- **Typography**: SF Pro Display/Text becomes **Segoe UI Variable** (Windows 11) or **Segoe UI** (Windows 10). Sizes and weights stay identical — same token values, different resolution.
- **System tray icon**: 16×16 monochrome ICO, equivalent role to macOS menu-bar template.
- **Settings window**: WinUI 3 `NavigationView` with the same logical sections as macOS Settings.
- **Permission/install hygiene**: not yet relevant — Windows doesn't have TCC pollution. Hotkey API is `RegisterHotKey` (Win32), text injection via `SendInput`.

## Windows Color Application

- Brand colors (`brand-primary`, `brand-accent`) carry over for the splash/about surfaces. The `AccentColor` asset becomes the `Color/AccentColorBrush` resource — Fluent already exposes a system accent that Windows users can override.
- Status colors map directly. Use Fluent's `InfoBar` for `warning` / `ready` callouts where the iOS/macOS app would use a custom card.

> Re-evaluate this section once a real Windows app exists. Keep it terse until then — one Windows-specific section in DESIGN.md beats fragmenting design across files.

---

# 6. Asset Inventory

| Asset | Path | Status |
|-------|------|--------|
| iOS App Icon | `iOS/Dicticus/Assets.xcassets/AppIcon.appiconset/AppIcon.png` | ✅ present (single 1024×1024) — should be multi-res set |
| macOS App Icon | `macOS/Dicticus/Assets.xcassets/AppIcon.appiconset/icon_*.png` | ⚠ multi-res present but **missing in latest build** (UAT D1) — audit `Contents.json` |
| iOS AccentColor | `iOS/Dicticus/Assets.xcassets/AccentColor.colorset/` | ❌ TBD — create in Phase 19.6 with `#2D6D4E` light / `#7CC9A2` dark |
| macOS AccentColor | `macOS/Dicticus/Assets.xcassets/AccentColor.colorset/` | ❌ TBD — create in Phase 19.7 (low priority; macOS users prefer system accent) |
| Menu bar icon (macOS) | `macOS/Dicticus/Assets.xcassets/MenuBarIcon.imageset/` | ❌ TBD — 18×18 monochrome template image |
| Onboarding hero (iOS) | TBD | ❌ Currently uses `Image(systemName: "mic.fill")` at 80 pt — consider custom illustration in 19.6 |
| What's New graphics | TBD | ❌ Per-feature illustrations referenced in `WhatsNewView` — currently `Image(systemName: ...)` placeholders |
| Empty state illustrations | TBD | ❌ History empty, search no-results — system images currently |
| Live Activity icon | inherited | ✅ Uses `mic.fill` system symbol — fine |
| Windows tray icon | TBD | ❌ Future Windows repo |
| Windows installer artwork | TBD | ❌ Future Windows repo |

## Open TBDs (Design Backlog)

1. **Refine brand hex values** against the actual icon source vector. The values in this file are sampled from `iOS/Dicticus/Assets.xcassets/AppIcon.appiconset/AppIcon.png` and may differ by 1–2 % from the original art.
2. **Create AccentColor.colorset** for both platforms (iOS prio, macOS optional).
3. **Custom monochrome menu bar icon** — current macOS app likely uses `mic.fill` system symbol, which is fine for v1 but a unique brand mark would strengthen recognition.
4. **Onboarding hero illustration** — replace the `Image(systemName: "mic.fill")` placeholders with custom art that uses `brand-primary` and `brand-surface`.
5. **Multi-resolution iOS icon set** — current `AppIcon.appiconset/` contains only a single `AppIcon.png`; should be regenerated for all required sizes.
