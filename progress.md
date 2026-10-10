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
- Not done yet: step flash when the playhead hits it.

## Groove Quantize (Oct 10, 2026)
- GROOVE pill in the transport (next to SWING/HUMAN): Чистый = off (exactly the old timing), 10 factory grooves
  (MPC 54/58/62/66, SP-1200, Dilla, Shuffle 1/8, Bossa, Afrobeat, Reggae One Drop) and the user's own.
- Slider icon opens STRENGTH, TIMING, VELOCITY, RANDOM (±5% step jitter), per-track switches,
  "Извлечь из паттерна", "Запечь в паттерн" (velocity only), "Чистый".
- Non-destructive: applied in SequencerScheduler at playback; Swing/Humanize stack on top. Saved in the session.
- User grooves: user_grooves.json next to the patterns. Undo for groove choice, track switches, extract and bake.
- Not done: groove offset ticks in the sequencer header.

## Compressor (Oct 10, 2026)
- COMP module at the end of the effects rack: Apple DynamicsProcessor between EQ and the limiter.
- Knobs: THRESH (-40..0 dB), AMOUNT (0..100%, maps to the unit's headroom 30..1 dB), ATTACK (0.1..200 ms),
  RELEASE (10..1000 ms), GAIN (makeup 0..20 dB). Parameters are only re-sent when they change.
- Presets: Gentle, Glue, Punch, Snap, Squash, Smash. Scenes: Club = Glue, Lo-Fi Tape = Squash, Industrial = Smash.
- Saved in the session / scenes / .drumproj (old files load with the compressor off).
