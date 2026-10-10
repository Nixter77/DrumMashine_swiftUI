# GROK_BUILD_TASKS_6: Groove Quantize

Base commit: 06e33cf (130 tests green). Commit this file first, then one commit per task.
Test after every task:
`xcodebuild test -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI -destination 'platform=macOS' -derivedDataPath ./DerivedData -only-testing:DrumMashine_swistUITests`

## What DAWs do (model to copy)
- Ableton Groove Pool: a groove = per-step timing offsets + velocity accents taken from a reference (MPC, SP-1200, live drummer).
  Knobs: Base (grid), Quantize %, Timing %, Random %, Velocity %. Applied non-destructively at playback; "Commit" bakes it.
- Logic / Cubase: "Groove Templates" / "Groove Quantize": any region can be extracted as a template; strength 0-100%.
- MPC: Swing 50-75% on 1/16 (50 = straight; 54/58/62/66 = classic settings). Swing% = position of the off-step
  inside a pair of 16ths: offset = (swing - 50)/50 × one step.

## Rules
- "Чистый" (Off) = exactly today's behaviour; existing Swing + Humanize keep working and stack after the groove.
- Groove is NON-destructive: steps in the pattern are never changed, only the playback time/velocity. A separate
  "Bake" command writes the result into step velocities (undoable); timing is not baked (grid has no sub-steps).
- No allocation, locks or ObjC on the render thread. Groove math happens in SequencerScheduler on its queue
  (it already applies swing at SequencerScheduler.swift ~L247-259). Precompute tables when the snapshot changes.
- Negative (early) offsets: allowed down to -0.25 step. The scheduler must decide with `grid + offset` against the
  horizon (as swing does now) and clamp the final time to >= `now` so nothing is scheduled in the past.
- Dark and Studio Light themes must both look right.

## G-1 Model: `GrooveTemplate` + factory grooves
- `struct GrooveTemplate: Codable, Identifiable, Equatable { id, name, resolution (steps per pattern: 16),
  timing: [Double]  // per step, in fractions of a step, -0.25...+0.5
  velocity: [Double] // per step multiplier 0.5...1.2 }`
- Factory set (`FactoryGrooves.swift`), each 16 steps:
  - Clean (all 0 / 1.0) = Off
  - MPC 54%, MPC 58%, MPC 62%, MPC 66% (odd steps offset (s-50)/50; velocity accent 1.0 on beats, 0.9 off-beats)
  - SP-1200 (MPC 60 + slight -0.02 rush on steps 4,12; harder accents)
  - Dilla (late snare/backbeat steps 4,12 +0.12; odd 16ths +0.18; hats loose; ghost velocities 0.7)
  - Shuffle 1/8 (triplet feel: steps 2,6,10,14 +0.33)
  - Bossa (slight push on 3,7,11 -0.05; accents on clave positions)
  - Afrobeat (odd 16ths +0.10, accents on 0,3,6,10,12)
  - Reggae One Drop (steps 2,6,10,14 +0.25 lazy, accent on step 8)
- Tests: count, IDs stable, arrays length 16, ranges valid, Clean is all zero/one.

## G-2 Engine settings + scheduler
- `GrooveSettings: Codable, Equatable { grooveID: String = "clean", amount 0...100 = 100 (Quantize/strength),
  timing 0...100 = 100, velocity 0...100 = 100, random 0...100 = 0, perTrack: [Bool] (8, all true) }`
  stored in SequencerEngine, the session file and the `.drumproj` (decodeIfPresent -> defaults, so old files load).
- Pass the resolved template + settings into `PatternSnapshot`. For a pattern of N steps, use template step `i % 16`.
- Offset for step i, track t (only if perTrack[t]):
  `timingOffset = template.timing[i%16] × amount% × timing% × samplesPerStep`
  `vel = baseVel × lerp(1, template.velocity[i%16], amount% × velocity%)`, clamp 0...1
  `random`: extra ± (random% × 0.05 step) using the existing RNG.
- Since today's offset is per step (all tracks together), move per-track offsets into `fire`: tracks whose groove is
  off fire on the plain grid (+swing/humanize). Keep it allocation-free.
- Tests: Clean == current timing bit-for-bit; MPC 66 at 100% puts odd steps +0.32 step later; amount 0 == Clean;
  perTrack off keeps that track straight; early offsets never schedule before `now`; old session JSON decodes.

## G-3 Extract groove from a pattern
- "Извлечь грув" builds a user template from the CURRENT pattern: velocity per step = mean velocity of active
  hits on that step normalised to max 1.0; timing = 0 (we have no sub-step data) unless the pattern has
  swing/humanize, then use the swing offset. Saved to `user_grooves.json` (same atomic store pattern as presets).
- Tests: round-trip, name uniqueness.

## G-4 UI
- In the transport next to SWING: a "GROOVE" pill menu (Clean + factory + user grooves) and a small popover with
  four knobs: STRENGTH, TIMING, VELOCITY, RANDOM, a per-track on/off row (8 small toggles with pad colours),
  buttons "Извлечь из паттерна" and "Запечь в паттерн" (Bake, undoable).
- Visual: when a groove is active, step numbers in the sequencer header show a tiny offset tick (purely visual).
- Undo for every change. All controls work in both themes.

## G-5 progress.md
- Section "Groove Quantize": what each knob does, list of grooves, how to extract/bake. Commit.
