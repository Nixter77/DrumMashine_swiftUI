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
On trigger the render thread picks the layer (`v <= velocityHi`). Within ±0.04 of a boundary it stores a second pointer and linear weights (`1-t`, `t`). Brightness is harmonic level, not a per-layer biquad, so neighbors stay in phase. Equal-power would lift that pair about 3 dB mid-zone and the next 0.05 step would fall. A read past a shorter buffer is 0. Gain is `curve(v)` once at trigger (`useCurve`). Layers are peak-normalized, so dividing by `curve(vRef)` drops the level at the next boundary. A linear one-layer bank leaves `useCurve` at 0 and `layerB` nil, so the mix stays `ptr[i] * velocity`. Round-robin is a fixed `9×8` cursor: next index, so a count ≥ 2 never repeats and 300 hits stay uniform. Offline renders are deterministic. `samples()` on a dynamics preset returns only the layer nearest 0.8, peak-capped at 0.5; the bank replaces it.
Normalization is per articulation: one scale so the loudest layer peaks at 0.5. Layers are then forced so peak and RMS do not fall as velocity rises, and scaled back under 0.5. Each layer is rendered at its center velocity. The body seed is `0xA11CE001 ^ (rr * 0x9E37)` and omits the layer term so adjacent layers stay in phase. A 20 ms overlay uses `seed ^ (layer * 0x85EB) ^ 0x51`. Detune is `rrDetune`, click ±1 dB.
`samples(for:)` on a dynamics preset returns only the layer nearest 0.8 (progressive first buffer). The full set follows in `Task.detached`.

## Acoustic models and room

`AcousticSynthesizer` runs only when `dynamics != nil`, in place of the legacy generator. Recipes: membrane kick/tom, snare (center, rimshot, cross-stick, buzz tail), brush tap/swirl/slap, hat closed/open/pedal/half-open, ride bow/bell/edge, crash/splash/china, hand drums, shaker, tambourine, acoustic clap, snap, cowbell, agogo, timbale, wood, guiro, triangle, orchestral bass, timpani, concert snare, suspended cymbal. Tabla and realtime sympathetic buzz are out.
Mic mix is summed into the buffer: close, a short HP overhead, and a seeded early-reflection plus exponential room tail. It does not touch `EffectsChain`. Room send scales with `v^0.7`. The tail then passes a 20 Hz one-pole highpass: subtracting the mean left a DC pedestal that peak-normalize lifted into the last 5 %.
Choke stays the track's choke group. Articulation does not change it, so closed and pedal still choke open and half-open.

## Kits, patterns, lane

Twelve kits in `AcousticKits`, ids `factoryID("kit.ac.<slug>")`, filenames `ac_<slug>_<voice>`, eight tracks in family order, `dynamics != nil`. The original five kits are not edited. `FactoryPatterns.all()` stays the original 40 rows of `X x g -`. New grooves live in `FactoryPatterns.acoustic()` and use tokens (`A` accent, suffix `r s o p h b 1 2 3`).
The ACOUSTIC chip lists `.acoustic` and `.percussion`. Kit rows show `character`. «Слушать кит» renders that kit's demo to the preview track and does not write the user pattern.
Velocity-lane edits are pure functions. Each bulk edit is one undo step. Accessibility id `seq.velocityLane.<track>.<step>`.

## Budgets

Voices stay 32. A crossfade is one voice. Per kit ≤ 48 MB of Float32, engine (8 + preview) ≤ 64 MB. Cymbal cap 2.5 s, drums shorter, 4 layers, round-robin 2. Render-thread code in `Mixer.render` and its callees does not allocate, lock, log, or hop queues. The source guard treats `lock` as a token not preceded by a letter, so `block` and `clock` stay legal.

## Samples

No new wavs unless Karoryfer Big Rusty Drums is re-checked CC0 and the new files fit in 20 MB. Otherwise Real Rusty Multi is skipped and synthesis is the only new source. Every wav under `Resources/` stays named in a `*CREDITS*` file that contains `CC0`.
