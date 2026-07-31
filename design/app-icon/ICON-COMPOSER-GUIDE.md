# Dicticus App Icon — Icon Composer authoring guide

**Concept:** edge-to-edge audio waveform (crisp), "midnight + cyan" palette.
**Reference:** `preview-1024.png` (the target look).
**Source layers:** `background.svg`, `glyph-wave.svg` (gradient), `glyph-wave-mono.svg` (flat, for tinted/clear).

This is the layered `.icon` authored in **Apple Icon Composer** (the GUI app). The
files here are the source; Claude wires the exported `.icon` into both targets afterward.

## Palette (exact values)

| Token | Hex | Use |
|-------|-----|-----|
| midnight-top | `#0B1626` | background gradient, top |
| midnight-bottom | `#17283E` | background gradient, bottom |
| bg-glow | `#1E4E66` @ ~50% | soft radial bloom, centered ~42% height |
| cyan-high | `#8BE9F5` | waveform bar gradient, top |
| cyan-deep | `#2A93B5` | waveform bar gradient, bottom |

## Layer structure (back → front)

1. **Background** — import `background.svg`, OR set a Fill layer with a linear
   gradient `#0B1626` (top) → `#17283E` (bottom), full-bleed. Add a soft radial
   highlight (`#1E4E66`, ~50% opacity) centered horizontally, ~42% from the top,
   feathered out to transparent — this gives subtle depth behind the wave.
2. **Waveform glyph** — import `glyph-wave.svg`. It's 7 rounded bars with a vertical
   `#8BE9F5 → #2A93B5` gradient, sized to ~62% width / ~75% height, centered.
   - Apply Icon Composer's **glow/bloom** to this layer (the SVG ships with NO baked
     glow so the tool's Liquid-Glass treatment stays clean). Target a soft cyan bloom.
   - Optionally add a **specular/translucency** material so it catches light (Liquid Glass).
3. **Specular sheen** (optional, Icon Composer often adds its own) — a top-down
   white gradient, ~40% → 0% opacity over the top ~45%, for the glassy highlight.

## Appearance variants

- **Default / Dark:** as above (cyan on midnight).
- **Tinted / Clear / mono:** use `glyph-wave-mono.svg` (flat white bars); the system
  applies the tint. Background goes to the neutral/clear treatment Icon Composer
  generates.

## Geometry (if rebuilding bars by hand)

7 rounded bars, viewBox 0–200 (scale ×5.12 for 1024). Centers x = 25,50,75,100,125,150,175;
bar width 13 (rx 6.5); heights 40,78,118,150,118,70,38; vertically centered at y=104.

## Export & handoff back to Claude

1. Export the layered bundle as **`AppIcon.icon`**.
2. Drop it in `design/app-icon/AppIcon.icon` (or tell Claude where it is).
3. Claude wires it into `macOS/Dicticus/Assets.xcassets` and `iOS/Dicticus/Assets.xcassets`
   (replacing the current PNG `AppIcon.appiconset`), updates the target settings, and
   render-verifies across light/dark/tinted at small sizes.

## Notes

- Verify legibility at 16–32px (menu-bar / Dock) — the wave reads well at small sizes
  per the mockups, but confirm after the glass treatment.
- Keep the brand identity in root `DESIGN.md` in mind; if we adopt midnight+cyan as the
  product accent (not just the icon), update the `DESIGN.md` color tokens to match.
