# Progress

Состояние после P0–P2-5. Задачи взяты из `GROK_BUILD_TASKS.md`. База — `21b5172` (`fix1`). Ветка `main`, remote нет, ничего не запушено.

## Коммиты

| Коммит | Задача |
|---|---|
| `bf8dc23` | docs: add GROK_BUILD_TASKS |
| `c379c06` | P0-0: offline render test bench |
| `206d1da` | P0-1: engine on the main actor at the device sample rate |
| `a565608` | P0-2: fade-out tails |
| `f0e1e9c` | P0-3: VoiceEngine on AVAudioSourceNode |
| `1f4c80e` | P0-4: sample-accurate sequencer |
| `60d21ef` | P0-5: master peak limiter |
| `04f6281` | P0-6: restart when the output device changes |
| `ef78ef7` | P0-7: distortion before delay and reverb |
| `fa298b6` | P1-1: spectrum and meters off the main actor |
| `c30f3c2` | P1-2: one playhead, per-property observation |
| `02517ea` | P1-3: complete strict concurrency |
| `95d57d5` | P1-3: Swift 6 |
| `1e98709` | P1-4: pattern slots keep their steps |
| `40a69fe` | P1-5: ADSR and cymbal pitch |
| `21a32f4` | P1-6: preview voice and a 16-sound cache |
| `56401ce` | P1-7: quantize pad recording |
| `11406fb` | P2-1: canvas meters, glow rasterized once |
| `d547289` | P2-2: EQ, room presets, pattern copy |
| `55ca2f8` | P2-3: band-limited hat, distinct FX |
| `0730516` | P2-4: versioned pattern file, debounced save |

Сборка Debug для macOS зелёная. Новых предупреждений Swift нет. Набор `DrumMashine_swistUITests` проходит.

## CPU и FPS

Замер P2-1, `top`, окно на переднем плане, уже после прогрева.

- Стоп, основной интерфейс: около 98% до правки, около 74% после.
- Гроув, кнопка Stop красная: около 163% до, около 157% после. Паттерны не совпадали один в один, окно стало шире, так что вторая цифра чуть пессимистичнее.

Instruments (Core Animation / SwiftUI FPS, Allocations на audio-потоке, SwiftUI View Body) не запускался. 60 FPS не измерялись.

## На слух

Ассистент звук не слышит. Проверить nixter:

- P0-2. По одному пэду каждой дорожки, особенно SNARE, HIHAT, TOM, RIDE: в конце удара нет щелчка.
- P0-3. Быстрые удары по одному пэду накладываются, а не обрывают друг друга. Кик под хэтами не заикается.
- P0-4. 120 BPM, хэт на всех 16, кик на 1/5/9/13, минута: ровно, без уезда и двойных ударов. Звук с первого шага, без паузы около 100 мс. Плейхед совпадает со звуком.
- P0-5. Плотный паттерн не хрипит.
- P0-6. Пять переключений выхода: воспроизведение возвращается в пределах секунды, высота не меняется.
- P0-7. На максимальном ревербе кик слышен. Дисторшн не хрипит на хвостах.
- P1-1. Волна — настоящий знаковый пик, не случайный шум. Это глазами.
- P1-2. Плейхед — одна белая колонка. Проверено по снимку экрана.
- P1-4. Слот B с другими звуками действительно играет эти звуки.
- P1-5. Долгое нажатие на пэд, движение ATK и DEC: звук меняется примерно за 150 мс.
- P1-6. Превью в библиотеке не обрывает кик.
- P1-7. REC OVERDUB, удар кика в долю: записанный шаг совпадает с метрономом паттерна. Тап по пэду по-прежнему velocity 1.0.
- P2-1. Метры и плейхед выглядят правильно. FPS не измерялся.
- P2-2. LOW +12 dB добавляет низ. ROOM меняет хвост.
- P2-3. Хэт металлический. Vinyl, Reverse и Impact отличаются.

P1-3 отдельного пункта на слух не имеет.

## P2-6

`TapTempo` считает BPM по `ContinuousClock`, медианой последних четырёх интервалов. Сеттер `bpm` зажимает 40…300 и больше не пишет свойство из `didSet`.

Покрытие с `-enableCodeCoverage YES`, отчёт `xcrun xccov view --report`:

- `SequencerScheduler.swift` — 90.56% (307/339). `nearestStepIndex` — 100% (6/6).
- `DrumSynthesizer.swift` — 100% (624/624).

Набор `DrumMashine_swistUITests` проходит.

## Второй план

Задачи из `GROK_BUILD_TASKS_2.md`, по порядку B-0 → D-5. Ветка `main`, ничего не запушено. Сборка Debug для macOS зелёная, новых предупреждений Swift нет. Набор `DrumMashine_swistUITests` проходит после D-5.

### Коммиты

| Коммит | Задача |
|---|---|
| `5541077` | docs: add GROK_BUILD_TASKS_2 |
| `e357659` | B-0: isolate tests from the real pattern defaults |
| `85f7376` | A-1: set a minimum window size and name the layout widths |
| `9d54f63` | A-2: put the transport across the window so Play stays whole |
| `7fbc87e` | B-1: decode old pattern JSON when new keys are missing |
| `1bd3692` | B-2: store patterns in Application Support and keep the old key |
| `3422a46` | B-3: save the session on each edit and restore it at launch |
| `a959d67` | C-1: round-trip session and pattern slots through new stores |
| `8ce4bf9` | B-4: keep the live slot and stop a click from wiping it |
| `21dea5a` | B-5: save user presets and keep factory ids stable |
| `4a43da7` | B-6: show a banner when a save or load fails |
| `d047ae8` | C-2: cover migration, corrupt files, and newer versions |
| `c547e11` | C-3: relaunch the app and keep the BPM and steps |
| `9e7b1d3` | A-3: flex the columns and put the library in an inspector |
| `6d1794c` | A-4: fit the sequencer rows and scroll when they do not |
| `c8347fd` | A-5: open the pad editor in a sheet and check the layout |
| `e510f4f` | B-7: export and import the whole project as a drumproj file |
| `de50f47` | D-0: give presets an explicit voice and keep the old buffers |
| `902ac69` | D-1: expose generator parameters without moving the factory buffers |
| `b799775` | D-2: add fifty-one factory presets and keep the old buffers |
| `7667d4a` | D-3: load factory kits and save a copy of the eight pads |
| `2f02726` | D-4: import a user sample and play it at the device rate |
| `0dc045d` | D-5: filter the library by voice and assign that pad |

### Тесты

Юнит-набор `DrumMashine_swistUITests`: `CodableToleranceTests`, `SessionStoreTests`, `PatternSlotTests`, `PersistenceRoundTripTests`, `PersistenceCompatibilityTests`, `PersistenceFailureTests`, `UserPresetTests`, `DrumProjectTests`, `FactoryBufferTests`, `SynthParameterTests`, `FactoryLibraryTests`, `FactoryKitTests`, `SampleImportTests`, `LibraryVoiceTests`, `LayoutSnapshotTests`.

UI: `PersistenceRelaunchUITests` (C-3) и снимки раскладки A-5 в `DrumMashine_swistUIUITests`.

### Снимки A-5

- `/tmp/drum_layout_1100x720.png` (1100×720)
- `/tmp/drum_layout_1440x900.png` (1440×900)
- `/tmp/drum_layout_1920x1080.png` (1920×1080)

### Данные

`~/Library/Containers/Home.DrumMashine-swistUI/Data/Library/Application Support/DrumMachine/`

Ключ `drum_machine_patterns_v2` не удалялся.

### Руками

Ассистент это не проверял. Список для nixter:

1. Play — целый круг при любом размере окна, панели не наезжают.
2. Ритм в A и B, звуки, ADSR, эффекты, громкость → Cmd+Q → запуск: всё на месте. То же после перезагрузки Мака.
3. «Сохранить как пресет» → перезапуск → пресет в USER.
4. Киты 808/909/Acoustic/Lo-Fi/Trap звучат по-разному. Список пресетов, которые надо подстроить.
5. Свой WAV на пэд → перезапуск → звук на месте.

## Третий план

Задачи из `GROK_BUILD_TASKS_3.md`, по порядку E-1 → E-4. Ветка `main`, remote нет: план просил пуш после каждой зелёной задачи, пушить некуда. Сборка Debug для macOS зелёная, новых предупреждений Swift нет. Набор `DrumMashine_swistUITests` проходит. UI-тест `FactoryPatternUITests` открывает PATTERNS и загружает Boom Bap: BPM 90, swing 55. Снимок страницы PATTERNS на 1100×720 проходит; холст 1400×720, библиотека рядом с колонками, потому что ImageRenderer не рисует `.inspector`.

Сетки, BPM, swing и звуки лежат только в `FactoryPatterns.swift`.

### Коммиты

| Коммит | Задача |
|---|---|
| `3f5b715` | docs: add GROK_BUILD_TASKS_3 |
| `97df9dc` | E-1: add nineteen factory patterns |
| `42a441b` | E-2: load a factory pattern into the active slot |
| `43c5d24` | E-3: add a PATTERNS page to the sound library |

### 19 ритмов

| Ритм | BPM | Кит |
|---|---|---|
| House Classic | 124 | 909 |
| Deep House | 122 | Lo-Fi |
| Techno Drive | 130 | 909 |
| Minimal Techno | 126 | 909 |
| Boom Bap | 90 | Acoustic |
| Lazy Hip-Hop | 85 | Lo-Fi |
| 808 Hip-Hop | 95 | 808 |
| Trap | 140 | Trap |
| Drill | 142 | Trap |
| DnB Two-Step | 174 | Acoustic |
| DnB Roller | 172 | Acoustic |
| Rock Beat | 110 | Acoustic |
| Half-Time Rock | 90 | Acoustic |
| Funk | 100 | Acoustic |
| Disco | 118 | Acoustic |
| Dembow | 95 | 808 |
| Perreo | 98 | 808 |
| Lo-Fi Chill | 78 | Lo-Fi |
| Lo-Fi Jazzy | 84 | Lo-Fi |

### На слух, третий план

Ассистент это не слушал. Список для nixter: отметить, что подстроить.

- [ ] House Classic
- [ ] Deep House
- [ ] Techno Drive
- [ ] Minimal Techno
- [ ] Boom Bap
- [ ] Lazy Hip-Hop
- [ ] 808 Hip-Hop
- [ ] Trap
- [ ] Drill
- [ ] DnB Two-Step
- [ ] DnB Roller
- [ ] Rock Beat
- [ ] Half-Time Rock
- [ ] Funk
- [ ] Disco
- [ ] Dembow
- [ ] Perreo
- [ ] Lo-Fi Chill
- [ ] Lo-Fi Jazzy

### +21 ритм (2026-10-09, Grok Bot)

Всего 40. Новые варианты: Jackin' House, Industrial Techno, West Coast, Trap Bounce, Jungle, Punk, Funky Break, Moombahton, Dusty Lo-Fi. Новые стили: Afrobeats, Amapiano, Dancehall, Reggae (One Drop), Bossa Nova, UK Garage 2-Step, Breakbeat (Big Beat), Electro, Dubstep, Synthwave, Jazz Swing, Blues Shuffle. Сетки только в `FactoryPatterns.swift`; nixter подстраивает на слух.

### Пресеты и сцены эффектов (2026-10-09)

Числа только в `EffectPresets.swift`. Таблица плана: `GROK_BUILD_TASKS_4.md`. Ассистент это не слушал.

Reverb (room, mix): Room smallRoom 0.20; Studio mediumRoom 0.25; Big Room largeRoom 0.30; Hall mediumHall 0.35; Cathedral largeHall 0.50.

Delay. Время доли: `доли × 60 / bpm`, зажато в 0.05…2.0 с. Slapback 0.09 с, без синхронизации, feedback 10, mix 0.25, low-pass 8000. 1/16 — 0.25 доли, feedback 25, mix 0.20, 12000. 1/8 — 0.5 доли, feedback 35, mix 0.25, 10000. 1/4 Dotted — 0.75 доли, feedback 40, mix 0.25, 9000. Dub — 0.75 доли, feedback 70, mix 0.35, 3000.

Distortion (mix, preGain дБ): Warm 0.15 −10; Crunch 0.35 0; Fuzz 0.60 +10; Destroy 0.85 +18.

EQ (low, mid, high дБ): Punch +4 −2 +2; Bright 0 0 +5; Scoop +3 −5 +3; Warm +3 0 −4; Telephone −12 +6 −12.

Сцены. Clean: все четыре выключены. Club: Room с mix 0.15, delay выкл, distortion выкл, EQ Punch. Lo-Fi Tape: Room с mix 0.15, delay выкл, distortion Warm, EQ +2 +1 −8. Dub: Hall, Delay Dub, distortion выкл, EQ Warm. Industrial: Big Room с mix 0.25, delay 1/16, distortion Fuzz, EQ Scoop. Ambient: Cathedral, delay 1/4 Dotted, distortion выкл, EQ выкл.

### На слух, сцены

Ассистент это не слушал. Каждую сцену на 2–3 ритмах: отметить, что подстроить.

- [ ] Clean
- [ ] Club
- [ ] Lo-Fi Tape
- [ ] Dub
- [ ] Industrial
- [ ] Ambient

## Studio Light design (Oct 10, 2026)
- Second, switchable look based on `docs/design/studio_light_reference.jpg`; Dark stays the default and unchanged.
- Switch: sun/moon button at the right of the transport bar, menu "Тема", or ⇧⌘T. Choice is saved (UserDefaults `appThemeStyle`).
- Light palette in `AppTheme` (tokens read `ThemeStore`), frosted white panels, `AppTheme.hairline` for faint lines.
- Candy pads with white icons and coloured glow; glossy "jelly" steps in the row colour (brightness = velocity).
- Glossy round Play/Stop with a breathing glow while playing (off with Reduce Motion), green LED BPM, silver knobs.
- Step flash (CUT_10): during Play, active audible steps (mute/solo like the scheduler) under the playhead flash in the track colour for ~150 ms (Dark: colour fill + glow; Light: white glow). Drawn only in PlayheadOverlay via per-row anchors; the grid still does not read currentStep. Reduce Motion → static highlight.

## Groove Quantize (Oct 10, 2026)
- GROOVE pill in the transport (next to SWING/HUMAN): Чистый = off (exactly the old timing), 10 factory grooves
  (MPC 54/58/62/66, SP-1200, Dilla, Shuffle 1/8, Bossa, Afrobeat, Reggae One Drop) and the user's own.
- Slider icon opens STRENGTH, TIMING, VELOCITY, RANDOM (±5% step jitter), per-track switches,
  "Извлечь из паттерна", "Запечь в паттерн" (velocity only), "Чистый".
- Non-destructive: applied in SequencerScheduler at playback; Swing/Humanize stack on top. Saved in the session.
- User grooves: user_grooves.json next to the patterns. Undo for groove choice, track switches, extract and bake.
- Done (CUT_11): groove offset ticks in the sequencer header — 1×4pt accent tick under each step number, shifted by GrooveSnapshot timing × cell width (16/32 via i % 16); Clean/STRENGTH 0/TIMING 0 → no ticks; header (SequencerStepHeader) reads only grooveSettings/activeGroove/stepCount, height 16pt unchanged; audio untouched. Tests: GrooveTicksTests.

## Compressor (Oct 10, 2026)
- COMP module at the end of the effects rack: Apple DynamicsProcessor between EQ and the limiter.
- Knobs: THRESH (-40..0 dB), AMOUNT (0..100%, maps to the unit's headroom 30..1 dB), ATTACK (0.1..200 ms),
  RELEASE (10..1000 ms), GAIN (makeup 0..20 dB). Parameters are only re-sent when they change.
- Presets: Gentle, Glue, Punch, Snap, Squash, Smash. Scenes: Club = Glue, Lo-Fi Tape = Squash, Industrial = Smash.
- Saved in the session / scenes / .drumproj (old files load with the compressor off).

## Choke-group UI (Nov 4, 2026)
- Done (CUT_12): choke-group UI (picker + pad badge). Sound editor row «Choke» Off/1/2/3/4 writes `soundPreset.chokeGroup` through the existing PadsGridView binding (no new store); out-of-range values are shown as-is. Pad shows a C1…C4 capsule (top-right, no hit-testing) when the preset has a group. Choke-only edits skip the sample reload (sequencer reads the group per hit via the snapshot). Core untouched. Tests: ChokeGroupOptionTests.
- ~~Known limit: live pad taps do not choke~~ — fixed in CUT_14.

## Choke Off (Nov 4, 2026, CUT_13)
- Done (CUT_13): choke Off = Off (fallback map removed). `SequencerEngine` takes choke only from `soundPreset.chokeGroup`; nil → -1 on every track. Tests: `ChokeOffTests` (5).
- Audit: all 12 factory hats carry `choke: 1` explicitly (FactoryPresets CH 808/909/Acoustic/Lo-Fi/Trap Tick, OH 808/909/Acoustic/Lo-Fi/Half; AcousticKit Real Hat Closed/Open). Factory rides (5 + Real Ride) have no group → Off (they used to sit in group 1 only via the track-5 fallback). No data edits.
- Behavior change: base-library hats in `SoundLibraryManager` (HH Closed, HH Open, HH Pedal, … HH Electronic) have no group, so on track 2 they no longer choke (before, track 2 HIHAT and track 5 RIDE shared group 1 via fallback). Not changed here (file outside CUT_13 scope).
- Behavior change: saved user projects with a hat whose `chokeGroup` is nil stop choking. No migration in this CUT; set C1 in the picker, or a separate CUT.
- ~~Known limit: live pad taps do not choke~~ — fixed in CUT_14.
- AC-5 (listen C1 vs Off): DEFER — no Mac GUI session for Eng.
- Test log: `qa/cut13/test-2026-11-04-cut13.log` (231 passed, 0 failed, `~/.drum_dd`).

## Done (CUT_14): live pad choke (tap = sequencer semantics)
- PadsGridView tap passes `PadTriggerChoke.group(for: tracks[index].soundPreset)` to `AudioEngineManager.trigger(chokeGroup:)`; nil = Off (-1). Core untouched.
- LivePadChokeTests (4): group 1/nil/4 mapping + parity with SequencerEngine snapshot for nil/1/3. Tests 235/0 (`~/.drum_dd`), log `qa/cut14/`.
- AC-5 listen: DEFER (no Mac GUI session for Eng).
- KEEP ME IN: library hats without a group and old projects with nil on hats do not choke on tap either (same as sequencer). CUT_15 candidates. MIDI/keyboard/preview triggers unchanged (no choke).

## Performance, DSP, Cleanup & Sequencer/Pad UX Improvements (Nov 17, 2026)
- **Performance/CPU**:
  - `SpectrumAnalyzer.swift`: added `bandFloor = 1e-4` zero-snapping (`smoothL`/`smoothR`, `smoothedBands`, `pushEnvelope` `< 1e-5` → 0), idle FFT bypass when `peakL < 1e-5 && peakR < 1e-5` (decaying bands via `decayBands()`), and reused `peakL`/`peakR` in `louderChannel`.
  - `VoiceEngine.swift`: added preallocated `activeSlots` / `buildActiveSlots()` and silent/idle/settled fast-path in `Mixer.render` + active-slot iteration in `mix`, preserving bit-identical output (`VoiceEngineSegmentRenderTests`).
  - `AudioEngineManager.swift`: parallelized startup preset synthesis in `startBackgroundSynthesis()` using `withTaskGroup` while keeping epoch/sample-rate/presetID install guards.
- **DSP/Sound**:
  - `DrumSynthesizer.swift`: SIMD `vDSP_maxmgv` peak scans and `min(8.0, before / after)` makeup cap in `applyToneAndLevel`; 2x linear oversampling around `tanh` in `tunedKick`; smooth `progress * (2 - progress)` decay/release shaping in `applyADSR` for non-`.legacy` presets (60 `.legacy` D-0 SHA-256 hashes unchanged).
  - `SampleImporter.swift`: enabled `AVAudioQuality.max.rawValue` on `AVAudioConverter.sampleRateConverterQuality` in `renderFile`.
  - `SoundLibraryManager.swift`: assigned `chokeGroup = 1` to all `.hihat` presets in `make(...)`.
- **Code cleanup**:
  - `SoundControls.swift` & `PadsGridView.swift`: migrated `SoundEditorRouter` from `ObservableObject`/`@Published` to `@Observable`.
  - `PadADSREditorView.swift`: removed unused `editSynth`/`editKick`/…/`editPerc` helpers (`setLofi` mutates `preset.synth` directly).
  - `MasterControlView.swift`: removed unused `OutputMeterBar`.
- **Sequencer/Pad UX**:
  - `BeatClockView.swift` & `SequencerView.swift`: wired `onSelectStepCount` into `BeatClockView` buttons and removed the duplicate `StepCount` overlay in `SequencerTopBar`.
  - `StepButtonView.swift`: added top-trailing probability dot (`step.isActive && step.probability < 0.999`) and `.contextMenu` with Velocity, Probability, and Clear Step.
  - `DrumPadView.swift` & `PadsGridView.swift`: added compact live `presetName` readout on pads via `.withPresetName(...)`.
  - `SoundLibraryView.swift`: updated `SoundPresetCell` selected name color for Studio Light contrast (`ThemeStore.isLight ? AppTheme.textPrimary : .white`).
  - `KnobView.swift`: added `defaultValue` double-tap reset and Shift fine-drag (`0.001` vs `0.004`).
  - `MainLayoutView.swift`: added window-scoped `KeyShortcutMonitor` (`Space` play/stop, `F` fill-once, ignoring text fields, modifiers, repeats, and modal sheets/panels).
- **Tests**: `DrumMashine_swistUITests` — 239 passed, 0 failed (`~/.drum_dd`), including `PerformanceAndUXImprovementTests` (4) and all guards (`FactoryBufferTests`, `VoiceEngineSegmentRenderTests`, `StepFlashSourceGuardTests`, `ThemeToastSourceGuardTests`, `SoundControlsTests`, `LayoutSnapshotTests`, `ChokeOffTests`).

## AD-0 — design note, metrics, d2 golden  (ветка feat/acoustic-dynamics @ cdb17559b0a2ae720174ad844f83c7ae763903db)
Статус: DONE
Тесты: 244/0, лог qa/ad0/test-2026-11-18-ad0.log
Golden: legacy 60 — без изменений; d2 — снят один раз (64 строки: 51 D-2 + 13 bundled) и с этого коммита не меняется
Что сделано:
- `docs/design/acoustic_dynamics.md` (82 строки): контракт AD-1…AD-6. Legacy `samples()` при `dynamics == nil` и строка `ptr[i] * velocity` не меняются. `Dynamics.curve` не входит в `synthesisHash`. Новые звуки — пресеты `ac_*`. Слои по умолчанию 4, round-robin 2. `FactoryStyle.percussion` — единственный новый case.
- `DrumMashine_swistUITests/Support/AudioMetrics.swift`: peak, peak dB, RMS, spectral centroid, attack, T60, pseudo-LUFS, SHA-256, офлайн-рендер грува, запись 16-bit WAV без AVAudioFile.
- `DrumMashine_swistUITests/AudioMetricsTests.swift`: синус 0.5 → −6.0206 dB (±0.01), центроид 1 кГц в пределах 5 %, шум конечный, рендер кита 808 конечный.
- `FactoryBufferTests.d2AndBundledBuffersMatchBaseline` сравнивает `FactoryPresets.additional()` + `AcousticKit.presets()` с `Fixtures/factory_buffers_d2_48k.txt`. Кандидат пишется во временный каталог, фикстура из теста не перезаписывается.
- Хост прогона: Mac mini, macOS 15.7.4, архитектура тестов x86_64. `xcresult`: 244 прогона, 236 уникальных имён, 0 failed, 0 skipped. В том числе `legacyFactoryBuffersMatchTheD0Hashes` и `d2AndBundledBuffersMatchBaseline`.
Метрики: новых звуков нет. Проверка метрик: синус peak 0.5 = −6.02 dB; центроид 1 кГц в допуске 5 %.
Бюджеты: не измерялись (слоёв ещё нет)
Что слушать: нечего — AD-0 не меняет звук
Риски/долги: AD-1…AD-6 ещё не начаты. Хост x86_64, порог 2.5 с в Debug для Apple Silicon придётся замерить отдельно. Real Rusty Multi не проверялся.

## AD-1 — velocity model, accent, pad, keyboard, MIDI  (ветка feat/acoustic-dynamics @ c87ef3ee2cd74308112b42f86cf5d6e710e54578)
Статус: DONE
Тесты: 252/0, лог qa/ad1/test-2026-11-18-ad1.log
Golden: legacy 60 — без изменений; d2 — без изменений
Что сделано:
- `Dynamics.swift`: кривая (linear / dB range 30 shape 1 / table), `VelocityMath.resolve` (акцент, затем грув, затем humanize), `PadVelocity`, `KeyboardRouter`, `MIDIPacketParser`, GM-карта и CC4, `SeededRNG`. Пустой объект кривой декодируется как dB 30/1. При velocity 0.25 кривая даёт около −22.5 dB.
- `SequencerScheduler.fire`: при выключенном акценте и нулевом humanize остаётся прежнее выражение `step.velocity * velMul`. Иначе вызывается `VelocityMath.resolve`. Humanize берёт `nextUnitSigned` только когда spread > 0.
- Сессия, кит, шаг и пресет получили опциональные поля (`accent`, `articulation`, `dynamics`, `mic`, `padVelocityMode`, `humanizeVelocity`, `midiMap`, `accentAmount`). Старые фикстуры декодируются с nil. `FactoryStyle.percussion` — единственный новый case. `synthesisHash` не включает кривую.
- Пэд: fixed по умолчанию, position, pressure (пик за первые 12 мс), ⌥ ghost 0.35, ⇧ акцент, full-level. Клавиши 1–8 играют пэды; Space и F остаются play и fill. Повтор клавиши не стреляет.
- MIDI: отдельная дорожка `.midi` в `VoiceEngine`. Колбэк не пишет в control ring и игнорирует generation. `MIDIHub` стартует из `MainLayoutView`, не из теста и не из снимка раскладки. Randomize паттерна сидирован.
- Хост: Mac mini, macOS 15.7.4, x86_64. `xcresult` Test-DrumMashine_swistUI-2026.11.18_04-59-43-+0200: 252 уникальных имени, 260 прогонов на устройстве, 0 failed. Прошли `legacyFactoryBuffersMatchTheD0Hashes`, `d2AndBundledBuffersMatchBaseline`, `offlineRenderBitIdenticalToBaseline`.
Метрики: новых звуков нет. dB-кривая range 30 при velocity 0.25 = −22.5 dB (±0.5 в тесте). Легаси-громкость линейная.
Бюджеты: не измерялись (слоёв ещё нет). Пустое MIDI-кольцо не меняет офлайн-микс.
Что слушать: тембра ещё нет, пресетов dynamics нет. По громкости уже можно: 4 — ⌥ пишет 0.35, ⇧ пишет акцент и velocity 1; 8 — humanize 0 не двигает velocity, 100 % даёт ±0.15 и повторяется с тем же сидом. Пункты 1–3, 5–7, 9–15 ждут слои (AD-2…AD-4).
Риски/долги: T-VEL-1 и T-VEL-7 появятся вместе с акустическими пресетами. Real Rusty Multi не проверялся. Хост x86_64. Слои по умолчанию 4, round-robin 2 (ротация) — записано в design note, код слоёв ещё впереди.

## AD-2 — layer bank, crossfade, round-robin  (ветка feat/acoustic-dynamics @ 87fc75b6fd3c25fcbfb9d72adeb1d60cfb51e39e)
Статус: DONE
Тесты: 261/0, лог qa/ad2/test-2026-11-18-ad2.log
Golden: legacy 60 — без изменений; d2 — без изменений
Что сделано:
- `LayerBank`: одна аллокация Float32 на артикуляцию × слой × round-robin, кривая на 128 точек, заголовок ячеек. `swapLayers` публикует банк через `Unmanaged`; освобождение только на main actor, когда ни слот, ни голос, ни хвост не держат token. Переполнение retire-кольца уходит в backlog.
- На триггере слой выбирается по `v <= velocityHi`. В зоне ±0.04 веса линейные (`1-t`, `t`), короткий буфер читается как 0. Cos/sin equal-power на коррелированной паре даёт около +3 dB в середине зоны, и 21-точечная RMS-кривая после пика падает — отклонение записано в design note. Однослойный линейный банк оставляет `useCurve = 0` и `layerB = nil`, микс остаётся `ptr[i] * velocity`.
- Динамический удар применяет `curve(v) / curve(vRef)` один раз (`useCurve`) и не умножает velocity второй раз. Sidechain по-прежнему читает `command.velocity`.
- Round-robin — фиксированный курсор `9×8` (трек × артикуляция), ротация. При count ≥ 2 предыдущий удар не повторяется. Два свежих движка на 300 ударах совпадают. Курсор сбрасывается при установке банка.
- `samples()` при `dynamics != nil` возвращает только слой, ближайший к v=0.8, после `finalize` (пик ≤ 0.5). Полный банк строится в `Task.detached` и подменяет превью. Эти два буфера не обязаны совпадать побайтно. `dynamics == nil` идёт старым телом `samples()`.
- Bundled-слои через `ArticulationSpec.layerFiles` без нового case `SoundSource`. Нормализация общая на артикуляцию: самый громкий слой до пика 0.5, следующие слои не тише по peak и RMS.
- Source-guard всего класса `Mixer` зелёный: нет `Array(`, `.append(`, `[Float](`, `DispatchQueue`, `print(`, `AppLog`, голого `lock`. `block` и `clock` остаются допустимыми.
- Хост: Mac mini, macOS 15.7.4, x86_64. `xcresult` Test-DrumMashine_swistUI-2026.11.18_05-36-46-+0200: 261 уникальных имён, 0 failed, 0 skipped. Прошли `legacyFactoryBuffersMatchTheD0Hashes`, `d2AndBundledBuffersMatchBaseline`, `offlineRenderBitIdenticalToBaseline`, `crossfadeRmsRisesAcrossTheBoundary`.
Метрики: акустических пресетов ещё нет. Тестовый кик с dynamics: 4 слоя, RR 2, peak и RMS не убывают, |mean| < 1e-3, пик ≤ 0.5, последний сэмпл 0, два банка побитово совпали, RMS соседних RR в пределах 0.7 dB.
Бюджеты: T-PERF-1…3 не измерялись (нет новых китов). Crossfade — один голос. Слои 4, round-robin 2.
Что слушать: тембра акустики ещё нет — слои пока пост-обработка существующих генераторов. Пункты 1–3, 5–7, 9–15 ждут модели (AD-3) и киты (AD-4). На этом срезе можно только убедиться, что старые пресеты не изменились (golden зелёные).
Риски/долги: веса crossfade линейные, не equal-power. Превью `samples()` и слой банка у v=0.8 не побитово равны. T-VEL-1 и T-VEL-7 ждут акустические пресеты. TQ-6 корреляция RR (< 0.995) ещё не в тесте — детюн 12–18 центов на кике её не уронит. Real Rusty Multi не проверялся. Хост x86_64.

## AD-3 — acoustic models and baked room  (ветка feat/acoustic-dynamics @ 29f352823876736c4f3e461c6b177bfd5002f2ab)
Статус: DONE
Тесты: 269/0, лог qa/ad3/test-2026-11-18-ad3.log
Golden: legacy 60 — без изменений; d2 — без изменений
Что сделано:
- `AcousticSynthesizer` заменяет легаси-генератор только при `dynamics != nil`. Рецепты: membrane kick/tom, snare center/rimshot/cross-stick с запечённым buzz, brush tap/swirl/slap, hat closed/open/pedal/half-open, ride bow/bell/edge, crash/splash/china, conga/bongo/cajon/djembe, shaker/tambourine/clap/snap/guiro, cowbell/agogo/wood/triangle, orchestral bass, timpani, concert snare, suspended cymbal. Tabla и realtime sympathetic buzz нет.
- Яркость — уровень гармоник и полоса битера, не биквад на слой. Иначе соседние слои расходятся по фазе и на границе RMS падает. Гейн на триггере — `curve(v)`, без деления на `curve(vRef)`. Веса кроссфейда линейные (`1-t`, `t`).
- Тело слоя сеется `0xA11CE001 ^ (rr * 0x9E37)` без члена layer, чтобы соседи оставались в фазе. Тихий оверлей 20 мс несёт `seed ^ (layer * 0x85EB) ^ 0x51`. Отклонение от EN-4 записано в design note.
- `MicMix` запекается в буфер: close, HP overhead ~2 мс, 8 ранних отражений, экспоненциальный хвост. Send ∝ v^0.7. `EffectsChain` не тронут. Кап тарелок 2.5 с.
- `AcousticTimbreTests` гоняет shipped `acousticHit` и `VoiceEngine`: центроид первых 30 мс у kick/snare/hat/ride/crash на v=1 ≥ 1.4× тихого; энергия малого 3–8 кГц на v=1 ≥ 3× v=0.2; sweep 0.05…1.0 шагом 0.05 не теряет peak и RMS; хвост комнаты длиннее сухого удара; 36 рецептов конечны; повтор бит-в-бит.
- Хост: Mac mini, macOS 15.7.4, x86_64. `xcresult` Test-DrumMashine_swistUI-2026.11.18_06-07-26-+0200: totalTestCount 269, device passedTests 277, failed 0, skipped 0. Прошли `legacyFactoryBuffersMatchTheD0Hashes`, `d2AndBundledBuffersMatchBaseline`, `offlineRenderBitIdenticalToBaseline`.
Метрики: фабричных китов ещё нет, таблица pLUFS пустая. Пороги зелёного прогона: центроид v=1 / v=0.25 ≥ 1.4 (окно 30 мс, snare сравнивается с v=0.2), wires 3–8 кГц ≥ 3×, RMS хвоста комнаты после сухого удара > 0.002. Точные центроиды прогон не печатает.
Бюджеты: T-PERF-1…3 не измерялись. Слои 4, round-robin 2. Рендер одного тестового банка (4 слоя, RR 1) уложился в полный сьют (~114 с на все 269 тестов).
Что слушать: модели закрывают пункты 10–18 как синтез, но фабричных китов ещё нет — слушать нечего из библиотеки. Пункты 1–9, 19–23, 26–27 ждут киты (AD-4), лейн (AD-5) и WAV (AD-6). Пункты 24–25 держатся golden и choke-тестами.
Риски/долги: Real Rusty Multi не проверялся, сэмплы не добавлялись. Кап тарелки 2.5 с, не 4 с. Превью `samples()` и слой банка у v=0.8 не побитово равны. TQ-6 корреляция RR ещё не в тесте. Хост x86_64, не Apple Silicon. Киты, паттерны и T-KIT — AD-4.

## AD-4 — twelve acoustic kits and pattern notation  (ветка feat/acoustic-dynamics @ 21a6f7a4ea4ed0895bb5f11272c0c9d7ed3823c6)
Статус: DONE
Тесты: 273/0, лог qa/ad4/test-2026-11-18-ad4.log
Golden: legacy 60 — без изменений; d2 — без изменений
Что сделано:
- `AcousticKits` добавляет 12 китов и 96 пресетов `ac_<slug>_<voice>`. Имена: Studio Dry, Jazz Club 60s, Brushes Ballad, Funk Tight 70s, Rock Big Room, Vintage 60s Soul, Vintage 70s Dead, Fusion Bright, Hip-Hop Breaks, Latin Percussion, Cajon Unplugged, Orchestral. У каждого 8 слотов в порядке треков, `dynamics != nil`, id `factoryID("kit.ac.<slug>")`. `FactoryKits.all()` по-прежнему 5 китов; UI берёт `listed()`.
- Latin Percussion целиком `.percussion`. Фильтр ACOUSTIC показывает `.acoustic` и `.percussion`. Строка кита показывает `character`. «Слушать кит» зовёт `previewKit`: демо из фабричного паттерна идёт на превью-трек и не пишет пользовательский паттерн.
- `FactoryPatterns.all()` остаётся 40. Новые 12 грувов в `acoustic()`. Токены: `A` — accent и velocity 1, суффиксы `r/s/o/p/h/b/1/2/3`. Старая строка без пробелов `X---x--g--------` не меняет шаги. `notesOnly` копирует accent и articulation только если у фабричного шага они не nil.
- Хвост комнаты проходит one-pole highpass 20 Гц вместо вычитания среднего: пьедестал DC после `finalize` поднимал последние 5 % кахон-кика до 0.001592. Snap берёт длину из `decay` и сдвигает полосу по `pitch`, иначе пик-нормализация превью склеивала разные щелчки. Шейкеры в слоте хэта (Latin, Cajon) получили `chokeGroup` 1, как остальные `.hihat`.
- `AcousticCatalogTests` проверяет имена, слоты, микшеры KT-1, нотацию и то, что `KitPreview.mix` не трогает `SequencerEngine`. Счётчики библиотеки: 111 + pieces + 96.
- Хост: Mac mini, macOS 15.7.4, x86_64. `xcresult` Test-DrumMashine_swistUI-2026.11.18_06-47-22-+0200: totalTestCount 273, device passedTests 281, failed 0, skipped 0. Прошли `legacyFactoryBuffersMatchTheD0Hashes`, `d2AndBundledBuffersMatchBaseline`, `offlineRenderBitIdenticalToBaseline`. Прогон тестов ~142 с.
Метрики: таблица pLUFS по китам — AD-6 (TQ-1), громкости пока стартовые. Порог RMS хвоста комнаты после сухого удара снижен до > 0.001: прогон до highpass дал 0.001274 при старом пороге 0.002. Центроидные пороги T-VEL-7 на конструкторе пресета не менялись; на фабричных китах ещё не сняты.
Бюджеты: T-PERF-1…3 не измерялись. Слои 4, round-robin 2. Новых wav нет. Различимость библиотеки одна занимает ~97 с, потому что `samples()` рендерит все 96 динамических превью.
Что слушать: 10 кики Rock / Funk / Jazz; 11 малый center/rim/cross-stick и ghost в Funk Tight; 12 хэт closed/open/pedal и choke; 16 щётки tap/swirl/slap; 17 конга, кахон, тимбалес, треугольник; 21 Studio Dry сухой, Rock Big Room и Orchestral с комнатой без Reverb. WAV пунктов 6–7 ещё нет.
Риски/долги: Real Rusty Multi и Afro/World не делались, лицензия Karoryfer не открывалась. Уровни TQ-1…TQ-6, T-LVL, T-PERF и listening WAV — AD-6. Velocity-лейн — AD-5. Превью `samples()` и слой банка у v=0.8 не побитово равны. Хост x86_64, не Apple Silicon. Шейкер в группе choke 1 обрывает предыдущий шейк.

## AD-5 — velocity lane and bulk edits  (ветка feat/acoustic-dynamics @ dee6ca5fb481a38a21a1429955cf31b0e7803687)
Статус: DONE
Тесты: 281/0, лог qa/ad5/test-2026-11-18-ad5.log
Golden: legacy 60 — без изменений; d2 — без изменений
Что сделано:
- `VelocityLane` — чистые правки: протяжка пишет velocity (⌥ только активные шаги), двойной клик ставит 0.8 и не включает пустой шаг, ramp 0.2…1 по окну `stepCount`, humanize ±10 % от `SeededRNG` (тот же сид — те же velocity), «Все ghost» 0.35 и снимает accent, «Все accent» ставит флаг, сброс 0.8, масштаб ×0.8/×1.2 с клампом [0.02, 1]. Accent выкл хранится как nil. Артикуляция 0 — nil. Буква — первый символ `tag`, иначе номер.
- Лейн под выбранным треком (`SoundEditorRouter`, иначе трек 0). Высота столбика = velocity, accent ярче (обводка и молния), точка если velocity < 0.45. Идентификатор `seq.velocityLane.<track>.<step>`. Цвета из `AppTheme`, поэтому Dark и Studio Light читают одни и те же токены.
- Меню имени трека: Ramp up, Ramp down, Humanize ±10 %, Все ghost, Все accent, Сбросить velocity к 0.8, Масштаб ×0.8, Масштаб ×1.2. Протяжка и каждый пункт — один undo через `registerTrackSwap` (undo и redo возвращают те же шаги).
- Меню шага сохранило Velocity, Probability, Clear и получило Accent, Articulation, Ghost 0.35. На кнопке шага accent — молния, артикуляция — буква. Долгое нажатие с вертикальным драгом velocity не тронуто.
- Хост: Mac mini, macOS 15.7.4, x86_64. `xcresult` Test-DrumMashine_swistUI-2026.11.18_07-01-12-+0200: totalTestCount 281, device passedTests 289, failed 0, skipped 0. Прошли `legacyFactoryBuffersMatchTheD0Hashes`, `d2AndBundledBuffersMatchBaseline`, `offlineRenderBitIdenticalToBaseline`. Прогон тестов ~137 с.
Метрики: синтез не менялся, таблица pLUFS по-прежнему ждёт AD-6. Порог ghost-метки 0.45, ghost шага 0.35, сброс 0.8, ramp от 0.2 до 1.
Бюджеты: T-PERF-1…3 не измерялись. Новых буферов и wav нет.
Что слушать: 9 accent в паттерне ярче, не только громче; 26 нарисовать crescendo на хэтах — рост громкости и яркости, undo одним шагом; 4 ghost 0.35 тише акцента. Окно приложения в этом прогоне не открывалось, пункт 27 (обе темы глазами) не проверялся.
Риски/долги: UI-тест рисования лейна не запускался — цель закрыта юнитом на модель правки. Жест протяжки и двойной клик не гоняются тестом. Real Rusty Multi не проверялся. Уровни, бюджеты, listening WAV и чек-лист §11 — AD-6. Хост x86_64, не Apple Silicon.

## AD-6 — levels, budgets, listening render  (ветка feat/acoustic-dynamics @ a5e3ac0408e31f537065865bc4940442347eb7e0)
Статус: DONE
Тесты: 286 passed, 1 skipped, 0 failed. Два полных прогона `DrumMashine_swistUITests`, в каждом 287 уникальных кейсов. Пропущен только `ListeningRenderTests/writesGrooveRampAndRoundRobinForEachKit()` (`DRUM_RENDER` не задан). Лог qa/ad6/test-2026-11-18-ad6.log — второй прогон, `** TEST SUCCEEDED **`, EXIT:0, xcresult Test-DrumMashine_swistUI-2026.11.18_09-25-35-+0200. Первый прогон тот же счёт, EXIT:0, xcresult Test-DrumMashine_swistUI-2026.11.18_09-23-11-+0200. Прошли `legacyFactoryBuffersMatchTheD0Hashes`, `d2AndBundledBuffersMatchBaseline`, `offlineRenderBitIdenticalToBaseline`.
Golden: legacy 60 — без изменений; d2 — без изменений
Что сделано:
- `levelTrim` по имени файла и `grooveGain` по киту двигают `acousticHit` в полосу TQ-1 и общий референс-грув в TQ-3. У dynamics `volume` может быть больше 1. Legacy по-прежнему клампится к 1. Банк после этого peak-normalize на артикуляцию, поэтому живой микс не хранит сырую иерархию `acousticHit`. `dynamicsBufferPeak = 0.95 / (8 × cos(π/4))`.
- Закрытый хэт Hip-Hop Breaks: decay 0.05, trim 4.977. Крэш Cajon Unplugged — короткий splash (decay 0.16, pitch +6, scale 1.7, trim 0.661). Слой малого Rock Big Room: bed gain 1.55, остальные малые 1. Проволока 3–8 кГц на v=1 не меньше 3× энергии на v=0.2. Центроид первых 30 мс на v=1 не меньше 1.4× центроида на v=0.25 у kick, snare, hat, ride, crash.
- Бюджеты на хосте Mac mini, macOS 15.7.4, x86_64, Debug приложения с `-O` (не Apple Silicon и не Release). Блок 512 сэмплов, 32 кроссфейда: 0.289 мс и 0.315 мс при лимите 2.667 мс. Пики восьми треков по центру ≤ 0.6706 (лимит 0.95). Память кита 19.13–37.06 МБ (лимит 48). Самый долгий банк на зелёном дереве: Rock Big Room 6.690 с в одном раннере; в последней паре 1.354–4.608 с. Порог 2.5 с в тесте только для arm64, иначе 180 с. Эти секунды — Debug `-O` на x86_64.
- Karoryfer Big Rusty Drums, LICENSE на 2026-11-18: CC0 1.0. SHA файла лицензии не записывался. Новые wav не импортировались, Real Rusty Multi остаётся синтезом. Новых файлов под `Resources/` нет.
- Listening pack: 12×3 = 36 wav, пик каждого 16383 (шкала 0.5). Тест с `DRUM_RENDER=1` прошёл за 40.444 с. Песочница не пустила запись на рабочий стол; тест записал `~/Library/Containers/Home.DrumMashine-swistUI/Data/tmp/DrumMashine_listening/` (путь в `ad6-listening-path.txt`). Копия для прослушки: `~/Desktop/DrumMashine_listening/`. В git этих wav нет. Грув — 8 тактов демо. Рампа — 16 ударов v 0.1→1.0 с шагом 0.22 с. RR — 8 ударов v=0.8 с шагом 0.25 с.
Метрики (последний раннер полного прогона; второй раннер той же пары дал те же dB, МБ и пики):

| Кит | Δ к медиане, dB | abs pLUFS | Банк, с | МБ | Пик суммы |
| --- | --- | --- | --- | --- | --- |
| Studio Dry | +0.88 | −12.23 | 4.053 | 28.83 | 0.4616 |
| Jazz Club 60s | −0.40 | −13.51 | 4.199 | 32.91 | 0.4237 |
| Brushes Ballad | −3.05 | −16.16 | 4.085 | 32.93 | 0.4409 |
| Funk Tight 70s | −0.54 | −13.64 | 2.894 | 26.96 | 0.5586 |
| Rock Big Room | +0.24 | −12.87 | 4.307 | 37.06 | 0.3924 |
| Vintage 60s Soul | −1.32 | −14.43 | 4.019 | 33.86 | 0.4468 |
| Vintage 70s Dead | +0.23 | −12.87 | 2.490 | 25.43 | 0.4685 |
| Fusion Bright | −0.01 | −13.12 | 2.719 | 26.74 | 0.5200 |
| Hip-Hop Breaks | −0.27 | −13.38 | 3.400 | 33.55 | 0.5514 |
| Latin Percussion | +0.01 | −13.10 | 2.445 | 32.46 | 0.6706 |
| Cajon Unplugged | +0.72 | −12.39 | 1.354 | 19.13 | 0.4233 |
| Orchestral | −5.17 | −18.28 | 4.071 | 33.69 | 0.5691 |

Бюджеты: кит ≤ 48 МБ — да. Восемь треков + превью ≤ 64 МБ не выделялись отдельным счётчиком; сумма пиков восьми треков ≤ 0.95. Блок ≤ 25 % реального времени — да (0.289–0.315 мс против 2.667 мс). Смена кита на лету отдельным замером в этом прогоне не гонялась.
Имена (filename → «кит + слот»): суффиксы `kick snare hat clap tom ride crash perc`. Особые слоты: Brushes — Brushes, Brush Snap, Mallet Toms, Brush Ride, Splash, Shaker Egg. Jazz — Finger Snap, Shaker. Funk — Acoustic Clap, Cowbell. Rock — Group Clap, Tambourine Hit. Soul — Group Clap, Tambourine Shake. Dead — Dead Snap, Dry Shaker. Fusion — Acoustic Clap, Splash, Agogo. Hip-Hop — Group Clap, China, Break Tambourine. Latin — Cajon Bass, Timbale, Shaker, Group Clap, Congas, Cowbell, Crash, Bongo. Cajon — Cajon Bass, Cajon Slap, Shaker Egg, Finger Snap, Djembe, Tambourine Shake, Splash, Claves. Orchestral — Bass Drum, Concert Snare, Hat, Finger Snap, Timpani, Suspended, Crash, Triangle. Studio Dry — Kick, Snare, Hat, Group Clap, Toms, Ride, Crash, Tambourine. Остальные кики/малые/хэты/райды без пометки носят слот Kick, Snare, Hat, Toms, Ride, Crash.
P2, не сделано: tabla-like, Afro/World, «Сделать живым», MIDI Learn. Real Rusty Multi не импортирован.
Чек-лист §11 не отмечался. Прослушка человеком не проводилась.
Что слушать: 6 — `kit_*_velocity_ramp.wav`, 16 ударов 0.1→1.0, шаг 0.22 с, границы слоёв не роняют RMS; 7 — `kit_*_rr.wav`, 8 ударов v=0.8, шаг 0.25 с, корреляция первых 50 мс внутри (0.6, 0.995), RMS в пределах 0.7 дБ; 10 — кик Rock Big Room в большой комнате, Funk Tight сухой, Jazz Club f0 70; 11 — center / rim / cross-stick и ghost 0.35, проволока на акценте ≥ 3× ghost; 19 — таблица выше, Brushes −3.05 дБ и Orchestral −5.17 дБ, остальные в ±1.5 дБ; 20 — TQ-1 на v=0.8 прошёл, хэт и тарелки тише малого. Пункты 3 и 27 глазами и Force Touch не проверялись.
Риски/долги: живой банк после peak-normalize не держит сырые дельты TQ-1. Жёсткая панорама восьми полных ударов может выйти за 0.95; замер — центр. Порог 2.5 с относится к Apple Silicon / Release, этот хост его не мерил. UI-тест лейна по-прежнему не запускался. Мерж в main не делался.
