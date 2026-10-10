# GROK_BUILD_TASKS_5 — alternative design "Studio Light"

Base commit: fee5d81. Reference image: `docs/design/studio_light_reference.jpg`
(from nixter's Grok Imagine page; brief was "stylish, light, new inventions + retro, room for animation").
Goal: a SECOND, switchable look. The current dark theme stays the default and must look exactly as now.
Commit this file + the reference image first, then one commit per task. Run the test command after every task:
`xcodebuild test -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:DrumMashine_swistUITests`

## What the reference shows
- Warm off-white background (~#F4EFE8), panels of frosted white glass (white 70–80% opacity, 1 px light border,
  soft long shadow ~ black 8%, radius 18), slight inner highlight at top edge.
- Pads: glossy "candy" 3D buttons, saturated colors (Kick red, Snare yellow, HiHat green, Clap light blue,
  Tom blue, Ride purple, Crash orange, Perc red-pink), white glyph (circle/triangle/square/star/diamond...)
  above white bold label, top gloss highlight, colored glow shadow under each pad.
- Sequencer grid: light grid lines on white; active steps are glossy rounded "jelly" blocks in the ROW's pad color
  with a soft colored glow. Inactive steps empty (just the grid). Step-number row on top.
- Transport: big round glossy green PLAY button with glow; BPM in large green LED/7-segment-like digits
  (retro touch) with − / + and an orange-blue "TAP TEMPO" pill; pattern slots A–D as small light keycaps,
  active slot orange; OFF / OVERDUB / REPLACE as a segmented light control.
- Knobs: brushed-metal silver knobs with a colored ring per effect (reverb purple, delay blue,
  distortion orange, EQ blue/green). Effect titles colored, with PRESET dropdown pills.
- Sound library: white cards with small orange dot + name; orange pill tabs; orange ASSIGN button.
- Text: dark graphite (#2B2B30), secondary #6E6E78. Accent orange #FF7A2F.

## H-1 Theme switching infrastructure (no visual change)
- `enum AppThemeStyle: String, CaseIterable { case dark, studioLight }`, persisted in UserDefaults key
  `appThemeStyle`, default `.dark`, held in an `@Observable`/ObservableObject `ThemeStore.shared`.
- Turn the `static let` colors/gradients in `AppTheme` into `static var` that read `ThemeStore.shared.style`
  and return the dark value (exactly today's values) or the light value. Keep every existing name so call
  sites do not change. Add new tokens only where needed (e.g. `panelFill`, `panelBorder`, `gridLine`,
  `stepInactive`, `glowOpacity`).
- Root view: `.id(ThemeStore.shared.style)` plus `.preferredColorScheme(style == .dark ? .dark : .light)`
  so the whole UI redraws on switch.
- Tests: default is dark; dark values equal the old hex values (spot-check background, accent, padColors);
  persistence round-trip.

## H-2 Studio Light palette + panels
- Fill the light values from "What the reference shows". `GlassmorphismModifier` and `ElevatedShadowModifier`
  get light variants (white frosted fill, light border, soft shadow) — branch on the style inside the modifier.
- Fix any hard-coded `Color.white` / `.black` text or fills found by `rg 'Color.white|Color.black|\.white\b'`
  in Features/ and UI/ that would be invisible on a light background; route them through AppTheme tokens.

## H-3 Candy pads + jelly steps
- `DrumPadView`: in studioLight draw a glossy pad: base gradient (color lighter top → color darker bottom),
  top gloss ellipse (white 45%→0%), inner border white 30%, colored glow shadow (color 45%, radius 10, y 6),
  pressed state scales 0.96 and darkens slightly. Add a per-pad SF Symbol glyph (circle.fill, circle.fill,
  triangle.fill, hand.wave.fill, square.fill, circle.grid.2x2.fill, star.fill, diamond.fill).
- `StepButtonView`: active step = glossy rounded block in the row's pad color with glow; inactive = clear with
  grid line. Playhead column = light tint. Dark theme unchanged.

## H-4 Retro transport touches
- Round glossy green PLAY (stop = red) with glow; BPM digits in a monospaced LED style (green, slight glow);
  TAP TEMPO pill; slot keycaps; segmented record mode. Only in studioLight.
- Knobs: in studioLight a silver brushed look (angular gradient greys) with a colored value ring passed by
  the effect (reverb purple, delay blue, distortion orange, EQ blue).

## H-5 Theme switch in the UI + animation hooks
- Add a small toggle (sun/moon icon) in the transport bar to switch dark ↔ Studio Light, with
  `withAnimation(.easeInOut(duration: 0.35))`. Also a menu item View ▸ Theme.
- Animation hooks (studioLight, subtle, respect "Reduce Motion"): pad press bounce (spring), active step pulse
  on playhead hit (glow flash 120 ms), PLAY button breathing glow while playing.

## H-6 progress.md
- Add a section "Studio Light design", list what changed and how to switch. Commit.

Rules: dark theme must stay pixel-equivalent; no audio/engine changes; one commit per task; all tests green.
