# Instruments pass — 2026-11-18

Host: Mac mini x86_64, macOS 15.7.4, Xcode Instruments 26.0 (`xcrun xctrace`). Build: Release from
`37cb742` (baseline, plus only the `-DMAutoPlay` flag) and from this branch. Traces are in
`/tmp/dm_perf/*.trace` on the Mac, not in git.

## Method

- `xctrace record --launch` does not profile the build you pass on this Mac. LaunchServices resolves
  the bundle ID `Home.DrumMashine-swistUI` to the old `~/.drum_dd/.../Debug` app, even when you pass
  the binary path. Every number below therefore comes from `--attach <pid>`. The app is started
  directly from its `Contents/MacOS` binary, the recording begins 10 s after launch, and it runs
  for 25 s. Time Profiler samples every 1 ms.
- Playback runs use `-DMAutoPlay`, a new opt-in launch flag that starts the sequencer once the
  sounds are loaded. Without the flag nothing changes.
- View updates were counted with a temporary `Self._printChanges()` probe, built only in a /tmp
  copy and never committed.

## Findings

| P | Finding | Evidence | Status |
| --- | --- | --- | --- |
| P0 | At idle the window updated at display rate forever. | ~37 % of a core on the main thread with nothing playing. Display-cycle bursts every 17.0 ms (median), 3–4 ms each, under `NSDisplayCycleFlush → NSHostingView layout → AG::Graph::UpdateStack::update`. A `TimelineView(.periodic(by: 0.05))` around the transport's 8 pt MIDI dot drove this. Removing only that view took idle CPU from 38 % to 2 %. | **Fixed** |
| P1 | During playback the main thread runs at 90 %+ of a core in SwiftUI/AppKit layout. | `updateConstraintsIfNeeded` takes 30 % and window `layoutIfNeeded` 34 %. Every update (StepFlash/BeatDot animations at 60 Hz, meters at 30 Hz, step changes) re-measures the whole window, about 10–15 ms per pass on this x86 host. Very few view bodies are involved: about 12/s for the meters and about 8/s for the playhead and flash. | **Open**, see below |
| P2 | `outputLatencyFrames` called `outputNode.presentationLatency`, a HAL query, every 16 ms from the playhead poll. | 1.2–1.7 % of main-thread samples during playback. | **Fixed**: cached for 500 ms, re-read when the rate changes or the configuration is rebuilt. |
| P3 | Leaks: 595 root leaks, 23.6 KB, all `ListenerMap::InsertEvent(XAudioUnitEvent…)` inside AudioToolbox. | `leaks` with MallocStackLogging. The stacks come from AVAudioUnit parameter writes in `AudioEngineManager.init`, `setupAudioEngine`, `updateEffects` and `masterVolume.didSet`. They happen once at launch and stay inside the framework. | Not fixable in app code. Noted. |
| — | Audio render thread (`com.apple.audio.IOThread.client`). | About 2 % of a core during playback, mostly in `Mixer.mix/add`. Across 535 samples there were no malloc/free, mutex or unfair-lock frames, and one `swift_retain`. | Clean |

## Before / after (Time Profiler, attach, 25 s)

| Scenario | Baseline 37cb742 | This branch | Change |
| --- | --- | --- | --- |
| Idle, all threads | 9 893 samples (≈ 39.6 % CPU) | 547 samples (≈ 2.2 %) | −94 % |
| Idle, main thread | 9 330 samples (≈ 37 %) | 25 samples (≈ 0.1 %) | −99.7 % |
| Idle, `top` | 25–38 % | 1.3–1.5 % | |
| Idle, final tip (re-run) | — | 492 samples (≈ 2.0 %), main 26 | |
| Playback, all threads | 23 920 (≈ 96 %) | 22 520 (MIDI fix) → 22 129 (≈ 88.5 %, + latency cache) | about −7 %; the P1 cost is still there |
| Playback, `outputLatencyFrames` | 1.2–1.7 % of samples | 0.1 % | |
| Leaks (`leaks`, MSL) | 595 / 23.6 KB (idle, 25 s) | 602 / 24.0 KB (playback, 30 s) | Same AudioToolbox stack, no growth, none from app code |

Tests: `xcodebuild test -only-testing:DrumMashine_swistUITests` from a /tmp copy of the tree:
303 passed, 1 skipped (`ListeningRenderTests`, as before), 0 failed, `** TEST SUCCEEDED **`.

## P1: what was tried, not shipped

All three were measured with `-DMAutoPlay` over 20 s.

- `.windowResizability(.automatic)`: `updateConstraints` stayed at 34.8 %. No gain.
- The meter canvases each in their own `NSHostingView` with `sizingOptions = []`: no gain, 98 % main thread.
- No StepFlash/BeatDot animations: 72 % main thread, bursts every 47 ms instead of 17 ms. Each pass still costs about 9.5 ms. This would change the visuals, so it was not shipped.

Next candidates (a UI refactor that needs a decision):

1. Remove the window-wide re-measure. The `ViewThatFits` alternatives in `TransportBarView` and `SequencerView.trackArea`, the `GeometryReader` + preference frames in `VelocityLaneStrip`, and the `drawingGroup` + blur(100) ambient background all re-run on each pass.
2. Draw the playhead and step flash in one `Canvas` instead of animated overlay views.
3. Measure again on Apple Silicon in Release. This host is x86 and about 3–5× slower per pass.
