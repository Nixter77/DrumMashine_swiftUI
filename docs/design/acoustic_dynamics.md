# Acoustic dynamics — design note (AD-0)

Branch `feat/acoustic-dynamics` from `main` @ `6cf321aa0e9762c13fe3d4e57c63958683ede881`.
First commit is unmodified `UPGRADE.md`. This note is the contract for AD-1…AD-6.

## Legacy path stays bit-identical

`DrumSynthesizer.samples(for:)` is unchanged when `dynamics == nil`.
`VoiceEngine.swapSample` and the mix line `ptr[i] * velocity` stay the only path for that buffer.
A dynamics-free preset wrapped as a one-layer linear `LayerBank` uses that same buffer and the same multiply, so velocities 0.4, 0.8, and 1.0 match today's offline mix.
`synthesisHash` includes buffer-affecting fields only. `Dynamics.curve` is playback-only and is not part of the hash.
New sound is new `ac_*` presets. D-2 acoustic presets are not retuned. `factory_buffers_48k.txt` and `factory_buffers_d2_48k.txt` stay put.

## Types (`Core/Models/Dynamics.swift`)

```swift
struct Dynamics: Codable, Equatable, Sendable, Hashable {
    var curve: VelocityCurve?          // nil → .db(range: 30, shape: 1)
    var layers: Int?                   // nil → 4 (1…8)
    var roundRobin: Int?               // nil → 2 (1…4); cymbals stay at 2
    var brightness, transient, pitch, decay, noise, humanize, rrDetune: Double?
}
enum VelocityCurve {
    case linear                        // gain = v
    case db(range: Double, shape: Double) // dB = -range * (1-v)^shape; gain = 10^(dB/20)
    case table([Double])               // 8…16 points, sorted and clamped so the table rises
}
struct MicMix { var close, overhead, room, roomTone: Double; var roomSize: RoomSize }
enum RoomSize: String { case small, medium, large, hall }
struct ArticulationSpec { var name, tag: String; var recipe: AcousticRecipe?; var f0, decayScale, wires: Double?; var layerFiles: [[String]]? }
```

`SoundPreset` gains optional `dynamics`, `articulations`, `mic`. Nil decodes as nil.
`DrumKit` gains optional `mic`, `dynamicsDefault`, `character`, `accentAmount` (nil → 0.2).
`SequencerStep` gains optional `accent`, `articulation`. Nil is the old step.
`FactoryStyle.percussion` is the only new enum case. Unknown raw values still become nil.
`VoiceKind`, `SoundSource`, and `SoundCategory` gain no cases.

`VelocityCurve.curveTable()` is 128 monotonic gains, built off the audio thread and stored on the layer bank.

## One velocity (`VelocityMath.resolve`)

```
v_raw → if accent: min(1, v + accentAmount) → if groove on: v * velMul
      → if humanize spread > 0: v + spread * nextUnitSigned(), then clamp [0.02, 1]
      → else the exact expression the scheduler uses today
```

Spread is the session knob `humanizeVelocity` (0…100 → ±0…0.15) or `dynamics.humanize`, whichever is larger. Zero spread does not touch the scheduler RNG.
The engine receives velocity, not a baked gain. Pad and MIDI apply sensitivity shape 0.6 / 1.0 / 1.6 (`v^shape`) before that path. Steps do not.
Pad mapping is `PadVelocity.interpret` (fixed 1.0 by default, position `0.25 + 0.75 * (1 - y/height)` with y = 0 at the top, pressure peak over the first 12 ms or else position, ⌥ ghost 0.35, ⇧ accent at 1.0 plus the accent flag, full-level forces 1.0).
Keyboard: characters `1`…`8`, ⇧ accent, ⌥ ghost, repeats ignored. Space and `F` stay play and fill-once. Command and control are ignored. Text fields and sheets do not see the keys.
MIDI: `MIDIPacketParser` plus `MIDIMap.gm`. Note On 0 is Note Off. A third SPSC lane `.midi` is the only producer from the CoreMIDI callback. `checkGeneration` stays false, same as pads. CC4 ≥ 96 is hat pedal, ≥ 40 is half-open.
Pattern randomize uses a seeded xorshift (`pattern id` + counter), not `Float.random`.

## Layers (`LayerBank`)

Built off the audio thread in `LayerRender`. One float allocation holds every articulation × layer × round-robin. A small header (curve[128], cell offset/count/velocityHi/velocityRef/curveAtRef) is allocated beside it. `CommandKind.swapLayers` publishes both pointers. The old bank goes through the retire ring as one object and is freed on the main actor only when no voice, tail, or slot still points inside it.
`.swap` remains the single-buffer path and clears the slot's bank.
On trigger the render thread picks the layer (`v <= velocityHi`). Within ±0.04 of a boundary it stores a second pointer and linear weights (`1-t`, `t`). Brightness is harmonic level, not a per-layer biquad, so neighbors stay in phase. Equal-power would lift that pair about 3 dB mid-zone and the next 0.05 step would fall. A read past a shorter buffer is 0. Gain is `curve(v)` once at trigger (`useCurve`). Layers are peak-normalized, so dividing by `curve(vRef)` drops the level at the next boundary. A linear one-layer bank leaves `useCurve` at 0 and `layerB` nil, so the mix stays `ptr[i] * velocity`. Round-robin is a fixed `9×8` cursor: next index, so a count ≥ 2 never repeats and 300 hits stay uniform. Offline renders are deterministic. `samples()` on a dynamics preset returns only the layer nearest 0.8, peak-capped at `dynamicsBufferPeak`; the bank replaces it.
Normalization is per articulation: one scale so the loudest layer peaks at `dynamicsBufferPeak` (`0.95 / (8 × cos(π/4))`). Eight center-panned hits at velocity 1 then stay at or under 0.95 before the limiter. Layers are then forced so peak and RMS do not fall as velocity rises, and scaled back under that peak. Each layer is rendered at its center velocity. The body seed is the constant `0xA11CE001`, with no round-robin term, so a noisy hit stays one instrument and neighbors stay in phase. A 20 ms overlay uses `seed ^ (layer * 0x85EB) ^ 0x51`. Round-robin is a 50 ms noise at about 1.15× the window RMS, scaled by 0.75, seed `0xC0FFEE ^ (rr * 0x9E37) ^ 0x51`, the same waveform on every layer, applied after the mic bake. Snare noise then passes two one-poles near 1.1 kHz (makeup 1.8) so the 3–8 kHz wire band keeps its velocity shape. The bank adds a matching wire-band bed, stronger on quieter snare layers, so those centroids stay within 35 %. Rock Big Room uses bed gain 1.55; other snares stay at 1. Hip-Hop Breaks closed-hat decay is 0.05 so the peak-normalized preview stays more than 1 dB from the jazz and rock hats. Cajon Unplugged crash is a short splash (decay 0.16, pitch +6, scale 1.7). Kit `rrDetune` is 1 so a bright partial stays inside the 50 ms correlation band; the overlay carries the difference. Detune click is ±0.35 dB. After peak-normalize, a louder layer is scaled down so RMS rises at most about 4 dB. Wire, crash, brush, and beater velocity slopes are compressed so adjacent layers stay within 35 % centroid. The round-robin overlay gain does not track velocity. A short bright burst keeps the 30 ms accent test. Stored dynamics buffers are capped at 1.15 s before the cosine tail so a 4×2 bank stays under 48 MB. `grooveGain` multiplies volume after `levelTrim` so the shared reference groove meets TQ-3. Rock Big Room stays at 1, so its snare volume stays exactly 1.
A dynamics preset's `volume` may exceed 1. Legacy presets stay clamped to 1. `levelTrim` is a per-filename gain so `acousticHit` at velocity 0.8 sits in the TQ-1 band. The bank still peak-caps each articulation, then multiplies by `bankPlaybackGain` (at most 1) so the played hit keeps that hierarchy. A few curve ranges are narrower or wider so a ghost at velocity 0.25, mixed from the quieter layers, stays in its dB window. `acousticHit` stays the kit-preview mix and does not take the post-cap scale.
`samples(for:)` on a dynamics preset returns only the layer nearest 0.8 (progressive first buffer). The full set follows in `Task.detached`.

## Acoustic models and room

`AcousticSynthesizer` runs only when `dynamics != nil`, in place of the legacy generator. Recipes: membrane kick/tom, snare (center, rimshot, cross-stick, buzz tail), brush tap/swirl/slap, hat closed/open/pedal/half-open, ride bow/bell/edge, crash/splash/china, hand drums, shaker, tambourine, acoustic clap, snap, cowbell, agogo, timbale, wood, guiro, triangle, orchestral bass, timpani, concert snare, suspended cymbal. Tabla and realtime sympathetic buzz are out.
Mic mix is summed into the buffer: close, a short HP overhead, and a seeded early-reflection plus exponential room tail. It does not touch `EffectsChain`. Room send follows `v^0.7`, then is pulled toward the velocity-0.8 amount so adjacent layers stay closer. The value at 0.8 is unchanged. The tail then passes a 20 Hz one-pole highpass: subtracting the mean left a DC pedestal that peak-normalize lifted into the last 5 %.
Choke stays the track's choke group. Articulation does not change it, so closed and pedal still choke open and half-open.

## Kits, patterns, lane

Twelve kits in `AcousticKits`, ids `factoryID("kit.ac.<slug>")`, filenames `ac_<slug>_<voice>`, eight tracks in family order, `dynamics != nil`. The original five kits are not edited. `FactoryPatterns.all()` stays the original 40 rows of `X x g -`. New grooves live in `FactoryPatterns.acoustic()` and use tokens (`A` accent, suffix `r s o p h b 1 2 3`).
The ACOUSTIC chip lists `.acoustic` and `.percussion`. Kit rows show `character`. «Слушать кит» renders that kit's demo to the preview track and does not write the user pattern.
Velocity-lane edits are pure functions. Each bulk edit is one undo step. Accessibility id `seq.velocityLane.<track>.<step>`.

## Budgets

Voices stay 32. A crossfade is one voice. Per kit ≤ 48 MB of Float32, engine (8 + preview) ≤ 64 MB. Synthesis may run a cymbal out to 2.5 s; the stored buffer is then cut at 1.15 s. Drums are shorter. 4 layers, round-robin 2. Render-thread code in `Mixer.render` and its callees does not allocate, lock, log, or hop queues. The source guard treats `lock` as a token not preceded by a letter, so `block` and `clock` stay legal.

## Samples

No new wavs unless Karoryfer Big Rusty Drums is re-checked CC0 and the new files fit in 20 MB. Otherwise Real Rusty Multi is skipped and synthesis is the only new source. Every wav under `Resources/` stays named in a `*CREDITS*` file that contains `CC0`.
