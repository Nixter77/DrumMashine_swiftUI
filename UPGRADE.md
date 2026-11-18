# UPGRADE: акустика и динамика (velocity) — большое задание для Grok Build

> Автор задания: Grok Bot по просьбе nixter. Задание изучено на `main` @ `6cf321a`
> («perf/dsp/ux: optimize audio & analyzer…», 17.11.2026), 239 тестов зелёные по `progress.md`.
> Язык задания русский, идентификаторы, пути и команды на английском.
> Это файл-задание. Ниже всё, что нужно, чтобы выполнить его без вопросов. Где решение
> оставлено на тебя (Grok Build), так и написано: «решает исполнитель, записать в `progress.md`».

---

## 0. Жёсткие правила (читать первым)

1. **Ветка.** Вся работа на новой ветке `feat/acoustic-dynamics`, созданной от `main` @ `6cf321a`
   (проверь `git rev-parse main`; если `main` ушёл дальше — ответвись от актуального `main` и запиши SHA в отчёт).
   - Никогда не коммитить в `main`, не мержить в `main`, не делать `--force`/`--force-with-lease`, не переписывать историю (`rebase -i`, `amend` запушенного, `reset --hard` на запушенном).
   - Обычный `git push -u origin feat/acoustic-dynamics` после каждого зелёного пакета — можно.
   - Мерж в `main` только после явного «GO» от nixter.
   - В репо есть висящий коммит `3206c2b` («UI P3: @Observable ThemeStore…», 03.11) — он **не предок** `main` и не лежит ни на одной ветке. Не трогать, не черрипикать, не удалять.
2. **Коммиты.** Первый коммит ветки — сам этот файл (`UPGRADE.md`) без изменений. Потом один или несколько коммитов на каждый пакет, сообщение `AD-<N> <ID>: <что>` (например `AD-2 VL-1: VelocityCurve model`). Перед коммитом тесты зелёные.
3. **Тесты после каждого пакета** (DerivedData вне дерева, как в CUT_13/14):
   ```
   xcodebuild test -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI \
     -destination 'platform=macOS' -derivedDataPath ~/.drum_dd \
     -only-testing:DrumMashine_swistUITests
   ```
   Лог каждой фазы сохранить в `qa/ad<N>/test-YYYY-MM-DD-ad<N>.log` (по образцу `qa/cut14/`). Красный тест = пакет не готов.
4. **Никаких** платных CI, облачных раннеров, серверов, открытых портов, git worktree, соседних папок-клонов. `DerivedData` не коммитить.
5. **Реальное время.** В render-блоке `VoiceEngine` (`Mixer.render` и всё, что он зовёт) **нельзя**: аллоцировать (`Array`, `append`, замыкания с захватом, `String`), брать локи, звать ObjC/Swift runtime-тяжёлое, логировать, вызывать `DispatchQueue`. Всё тяжёлое — синтез буферов на фоновом `Task.detached`, как сейчас в `AudioEngineManager` (~L780).
6. **Существующий звук не ломать без разрешения.** Политика golden-тестов — раздел 6. Коротко: 60 legacy-буферов (`DrumMashine_swistUITests/Fixtures/factory_buffers_48k.txt`) **не меняются никогда** в этой работе.
7. **Сэмплы.** Только CC0 / public domain или сгенерированные самим кодом. Каждый файл с записью в `*_CREDITS.txt` (раздел 7). Если нет сети или лицензия не на 100 % ясна — пакет с сэмплами пропустить и написать в отчёте, синтез остаётся основным путём.
8. Обе темы (Dark и Studio Light) должны выглядеть нормально для каждого нового UI.
9. Пиши `progress.md` (секция `## AD-<N>`) после каждой фазы: что сделано, SHA, число тестов, что слушать.

---

## 1. Цели и не-цели

### Цели
- **G1. Сквозная динамика.** Velocity от любого источника (шаг секвенсора, пэд мышью/трекпадом, клавиатура, MIDI) доходит до движка одинаково, через одну кривую, и меняет **не только громкость, но и тембр**: яркость, атаку/транзиент, высоту, длину, долю шума, «проволоку» малого, «колокол» райда.
- **G2. Живость.** Round-robin (несколько вариантов одного удара), гуманизация velocity, акцент, ghost-ноты, чтобы 16 одинаковых шагов не звучали как пулемёт.
- **G3. Много акустики.** Новые/переписанные модели акустических барабанов и перкуссии (мембраны, малый с подструнником, томы, хэт closed/open/pedal/half, райд bow/bell, крэш/сплэш/чайна, rimshot/cross-stick, щётки, конги, бонго, кахон, шейкер, бубен, акустический хлопок и др.) и **не меньше 12 новых акустических китов** с характером.
- **G4. «Микрофоны».** У акустических китов есть ощущение комнаты: close / overhead / room микс, заложенный в буфер офлайн (без нагрузки на аудиопоток).
- **G5. Удобная правка velocity** в секвенсоре (лейн velocity, рисование, рампы, ghost/accent одним жестом).
- **G6. Вкус и уровни.** Иерархия громкости внутри кита, запас по пику, ровная громкость между китами, нет клипа на максимальной velocity.
- **G7. Совместимость.** Старые сессии, паттерны, пользовательские пресеты и киты открываются и звучат как раньше.

### Не-цели (не делать)
- Не делать AUv3/плагин, не трогать Synt, не добавлять сетевые функции, облако, аккаунты.
- Не менять число треков (8) и семейства треков (`kick, snare, closedHat/openHat, clap, tom, ride, crash, perc`) — новые звуки ложатся в эти семейства; артикуляции решают «больше звуков на трек» (пакет AR).
- Не переписывать эффект-цепочку (`EffectsChain`, AVAudioUnit-ноды) и Sidechain — только читать velocity как сейчас.
- Не менять 60 legacy-пресетов и их хэши.
- Не тащить большие сэмпл-библиотеки (лимит размера в разделе 7).
- Не делать физическое моделирование в реальном времени на аудиопотоке. Всё рендерится офлайн в буферы.

---

## 2. Ground truth: как устроено сейчас (проверено на `6cf321a`)

Корень кода: `DrumMashine_swistUI/DrumMachine/`.

### 2.1 Аудиодвижок
- `Core/AudioEngine/VoiceEngine.swift` (803 строки): 32 голоса (`voiceCount = 32`), 8 треков + трек превью (`slotCount = 9`), до 4 голосов на трек (`maxVoicesPerTrack = 4`), один стерео `AVAudioSourceNode`.
  - Управление идёт через SPSC-кольца `CommandRing`. Есть два лейна: `.control` (только main actor: пэды, гейны, свопы, превью) и `.sequencer` (только очередь планировщика). **В один лейн нельзя писать из двух потоков.**
  - **На каждый трек один моно-буфер** (`slotPtr[track]`, `slotCount[track]`). Буфер меняется командой `.swap`, старый уходит в retire-кольцо (`retireCapacity = 1024`).
  - **Velocity сейчас — только линейный множитель амплитуды**: `var sample = ptr[sampleIndex] * voices[index].velocity` (~L549). Тембр от velocity не зависит.
  - Choke: `choke(group:)` перед стартом голоса, линейный фейд `chokeLength`; steal-хвосты `tailPtr`.
  - Pan/gain по треку со сглаживанием (`smoothGain`, `panStepL`). Перед лимитером меряется пик (`consumePreLimiterPeak`).
- `Core/AudioEngine/AudioEngineManager.swift` (1043 строки): граф `voices → Distortion → Delay → Reverb → EQ → Compressor → Limiter → MainMixer` (`connectVoiceChain`, ~L399). Эффекты **глобальные** (инсерты на мастере), посылов по трекам нет. `trigger(trackIndex:velocity:chokeGroup:)` ~L804. Превью играет с velocity `0.85` (~L924). Ресинтез буферов на `Task.detached` (~L780), есть `PreviewSampleCache` (~L980) с ключом от `synthesisHash`.
- `Core/AudioEngine/DrumSynthesizer.swift` (1253 строки): чистые детерминированные генераторы, `Noise(seed:)` xorshift с фиксированными сидами на голос (`0xA11C_E001` кик, `0x5AA3_E001` малый, …).
  - Модели простые: кик — синус со свипом + клик + опц. шум/бита + `tanh`-драйв (с `6cf321a` — с полусэмпловым сглаживанием сатурации); малый — 2 синуса + HP-шум; хэт — шум + HP/BP; клэп — бёрсты шума; том — синус со свипом + «палочка»; райд — пинг + сизл; крэш — FM; perc — `fm | cowbell | noise`; FX.
  - `finalize` нормирует **пик к 0.5 (−6 dBFS)** и делает косинусный хвост 10 мс, последний сэмпл = 0. `applyToneAndLevel` (toneFilter + volume), `applyADSR` (для не-legacy кривая с `6cf321a`).
  - Точка входа: `DrumSynthesizer.samples(for:sampleRate:sampleRoot:)`; для `.bundled`/`.sample` читает файл через `SampleImporter.render` (макс. 10 с, `maxDuration`).
- `Core/AudioEngine/Sidechain.swift`: глубина дака зависит от velocity (`velocityScaling`).

### 2.2 Модель пресетов и китов
- `Core/Models/SoundPreset.swift`: `SoundPreset` (Codable, толерантный декод — каждое поле `decodeIfPresent`), поля `volume, pan, pitch, attack, decay, sustain, release, chokeGroup, origin, basedOn, voice: VoiceKind?, synth: SynthParams?, source: SoundSource, style: FactoryStyle?, toneFilter`. `SynthParams` — опциональные подструктуры `kick/snare/hat/clap/tom/ride/crash/perc/lofi`. `synthesisHash` — ключ кэша превью. `restored(fromFactory:users:)` — RESET.
  - `VoiceKind`: `kick, snare, closedHat, openHat, clap, tom, ride, crash, perc, fx`.
  - `FactoryStyle`: `classic808, style909, acoustic, lofi, trap, legacy`.
  - `SoundSource`: `.synth | .sample(fileName, originalName) | .bundled(fileName)`.
- `Core/Models/DrumKit.swift`: `DrumKit { id, name, sounds: [SoundPreset] }` — 8 копий пресетов.
- `SoundLibrary/SoundLibraryManager.swift`: 60 legacy-пресетов (`style = .legacy`), `factoryID(filename:)` = SHA-256 UUID v5 от `"factory.<filename>"` (стабильный id, **filename = вечный идентификатор**), `defaultPreset(forTrackIndex:)`.
- `SoundLibrary/FactoryPresets.swift`: 51 D-2 пресет (стили 808/909/acoustic/lofi/trap), числа «стартовые, ухо — за nixter».
- `SoundLibrary/AcousticKit.swift`: 13 реальных сэмплов (`Resources/AcousticKit/*.wav`, 44.1 кГц/16 бит/моно, пик −1 dBFS) из **«Big Rusty Drums» (Karoryfer Samples, CC0 1.0)**, **по одному velocity-слою и одному round-robin** на артикуляцию (см. `AcousticKit_CREDITS.txt`: kick vl11, snare vl8, ghost vl2 …). Ghost-нота сделана отдельным пресетом с `volume: 0.35`.
- `SoundLibrary/FactoryKits.swift`: 5 китов — `808, 909, Acoustic, Lo-Fi, Trap`. «Acoustic» сейчас синтетический (`kick_acoustic, snare_acoustic, ch_acoustic, clap_real, tom_acoustic_floor, ride_acoustic_dry, crash_acoustic_18, perc_tambourine`).
- `SoundLibrary/FactoryPatterns.swift`: символы паттернов `X`=1.0, `x`=0.75, `g`=0.4 (ghost), `-`=пауза. Паттерн может подменить звук трека (`[7: "oh_909"]`).
- Хранилища: `Core/Persistence/{KitStore, UserPresetStore, SessionStore, PersistenceStore, UserGrooveStore, EffectSceneStore}.swift`. Фикстуры старых форматов: `DrumMashine_swistUITests/Fixtures/legacy_*.json`.

### 2.3 Velocity сейчас — по источникам
| Источник | Где | Что сейчас |
|---|---|---|
| Шаг секвенсора | `Core/Sequencer/SequencerStep.swift` | `velocity: Float = 0.8`, `probability`. Есть правка: long-press+drag и контекст-меню в `Features/Sequencer/StepButtonView.swift`, заливка = velocity, подпись `Int(v*127)`. |
| Groove | `Core/Sequencer/Groove.swift`, `SequencerScheduler.swift` ~L311-327 | множитель velocity по 16-м (0.5…1.2), Bake пишет в шаги. |
| Humanize | `SequencerScheduler.swift` ~L272 | **только тайминг**, velocity не гуманизируется. |
| Randomize | `SequencerEngine.swift` ~L626 | `Float.random(in: 0.5...1.0)` — недетерминированно. |
| Пэд | `Features/Pads/DrumPadView.swift` ~L155 | **всегда `onTap(1.0)`** — нет никакой динамики с пэда. `recordPadHit` пишет 1.0 в шаг. |
| MIDI | — | **MIDI нет вообще.** |
| Accent | — | Отдельного акцента нет (только `X` в фабричных паттернах). |
| Превью | `AudioEngineManager` ~L924 | фиксированно 0.85. |
| Движок | `VoiceEngine` ~L549 | velocity = линейный гейн (v=0.4 → −8 dB). |

### 2.4 Choke
- Хэты в `choke 1` (`FactoryPresets`, `AcousticKit`, с `6cf321a` все `.hihat` legacy тоже). CUT_12–14: UI choke, `Off`, живой choke с пэда (`Features/Pads/PadTriggerChoke.swift`, `LivePadChokeTests`). Это **работает и не должно сломаться**.

### 2.5 Тесты, которые сторожат звук
- `FactoryBufferTests.legacyFactoryBuffersMatchTheD0Hashes` — SHA-256 60 legacy-буферов при 48 кГц. **Священная корова.**
- `FactoryBufferTests.clapTrackUsesTheClapVoiceAfterLaunch` — стартовые filenames треков.
- `VoiceEngineSegmentRenderTests.offlineRenderBitIdenticalToBaseline` — офлайн-рендер движка бит-в-бит. Изменишь математику микса — он покраснеет (см. раздел 6).
- `AcousticKitTests`, `FactoryKitTests`, `FactoryLibraryTests`, `LibraryVoiceTests`, `SynthParameterTests`, `CrackleDiagnosticsTests`, `CodableToleranceTests`, `LegacyDecodeDefaultsTests`, `PersistenceCompatibilityTests`, `Cut7RoundTripTests`, `ChokeOffTests`, `LivePadChokeTests`, source-guard тесты (`StepFlashSourceGuardTests`, `ThemeToastSourceGuardTests`) — образец для новых guard-тестов.

---

## 3. Архитектурное решение (обязательное, до кода)

Сделай **AD-0 «Design note»**: файл `docs/design/acoustic_dynamics.md` (≤ 200 строк) с итоговыми типами и сигнатурами, прежде чем писать код. Ниже — рекомендуемая архитектура; отступать можно, но причину записать.

### 3.1 Velocity-слои вместо «одного буфера на трек»
Тембр от velocity нельзя получить множителем. Значит на трек нужен **набор буферов**:

```
LayerSet (immutable, создаётся вне аудиопотока, одна аллокация)
  articulations: [Articulation]        // 1..4 (например snare: center, rim, sidestick, ghost-brush)
    layers: [Layer]                    // 1..8 velocity-слоёв, отсортированы по velocity
      velocityHi: Float                // верхняя граница слоя 0..1
      rr: [UnsafeMutablePointer<Float>, count]   // 1..4 round-robin варианта
```

- Рендерится в `Task.detached` целиком, кладётся в одну непрерывную аллокацию (или массив указателей, но всё выделено **до** свопа). На аудиопоток уходит один указатель на заголовок через новую команду `CommandKind.swapLayers` (4). Старый `LayerSet` — в retire-кольцо целиком (сохранить текущую семантику «буфер не освобождается, пока его играет голос/хвост»: `retireIfOrphan` должен проверять принадлежность к set).
- `Voice` получает `layerA/layerB` + `crossfade: Float` (смешивание двух соседних слоёв, см. 3.3), `rrIndex`. Стоимость: два чтения и одно FMA на сэмпл на голос — допустимо.
- **Legacy-путь:** пресет без `dynamics` = `LayerSet` из 1 артикуляции × 1 слоя × 1 RR = **ровно сегодняшний буфер**, velocity = тот же линейный множитель. Так golden-хэши и `offlineRenderBitIdenticalToBaseline` не меняются. Проверь это тестом (раздел 8, T-COMPAT-3).
- `.swap` (старый) оставить как обёртку «single-layer set» или сохранить параллельно — решает исполнитель; главное не ломать `VoiceEngineSegmentRenderTests` и retire-тесты.

### 3.2 Модель данных (всё опционально — толерантный декод)
В `SoundPreset` добавить:
```swift
var dynamics: Dynamics? = nil          // nil = legacy поведение (линейный гейн, один буфер)
var articulations: [ArticulationSpec]? = nil   // nil = одна артикуляция из текущих полей
```
```swift
nonisolated struct Dynamics: Codable, Equatable, Sendable, Hashable {
    var curve: VelocityCurve?          // по умолчанию .db(range: 30, shape: 1.0)
    var layers: Int?                   // 1...8, по умолчанию 5 (синтез) / по числу файлов (сэмплы)
    var roundRobin: Int?               // 1...4, по умолчанию 3 для акустики
    // Насколько параметры генератора следуют за velocity (0 = не следуют). Единицы указаны.
    var brightness: Double?            // октавы сдвига LP/HP/полосы на полный диапазон v, 0...3
    var transient: Double?             // доля клика/атаки: множитель на v=1 относительно v=0.2, 1...6
    var pitch: Double?                 // полутоны прироста высоты при v=1 (натяжение мембраны), 0...2
    var decay: Double?                 // множитель длины при v=1 относительно v=0.2, 0.5...2.5
    var noise: Double?                 // прирост доли шума/подструнника, 0...1
    var humanize: Double?              // случайный разброс velocity ±, 0...0.15 (детерминированный)
    var rrDetune: Double?              // разброс высоты между RR, центы, 0...25
}
nonisolated enum VelocityCurve: Codable, Equatable, Sendable, Hashable {
    case linear                        // legacy: gain = v
    case db(range: Double, shape: Double) // gain_dB = -range * (1 - v)^shape
    case table([Double])               // 8..16 точек, монотонная
}
```
- В `SequencerStep`: `var accent: Bool? = nil`, `var articulation: Int? = nil`. Nil = как сейчас.
- В `DrumKit`: `var mic: MicMix? = nil` (close/overhead/room, раздел 4 RM), `var dynamicsDefault: Dynamics? = nil` (общий профиль кита), `var character: String? = nil` (описание для UI).
- Все новые поля — в `synthesisHash` (кроме чисто-плейбэк полей вроде `curve` — их **не** включать, кривая применяется в плейбэке, а не в буфере; решить и задокументировать).
- **Не добавлять новые case в `VoiceKind`, `FactoryStyle` (кроме одного) и `SoundCategory`** без необходимости: старый билд приложения упадёт в fallback. Допустим один новый `FactoryStyle` — `percussion` («PERC/WORLD») — с толерантным декодом (неизвестный raw → `nil`, как уже сделано для `style`).

### 3.3 Как velocity превращается в звук (единый путь)
```
источник (шаг / пэд / клавиша / MIDI)
  → v_raw ∈ [0,1]
  → + accent (если шаг accent: v = min(1, v + kitAccentAmount), по умолчанию +0.2)
  → + groove velMul (как сейчас)
  → + humanize velocity (детерминированный ГПСЧ планировщика, ±dynamics.humanize)
  → clamp [0.02, 1]
  → VoiceEngine.trigger(velocity: v)                // в кольцо уходит v, не гейн
  → render: слой = по v (velocityHi), crossfade между соседними слоями в зоне ±0.04 вокруг границы
           RR = следующий по кругу для (track, articulation, layer), без повтора подряд
           gain = curve(v) / curve(v_layerRef)      // компенсация: слой уже сделан на своей громкости
```
- Таблица кривой (`curve`) считается вне аудиопотока в 128 значений и передаётся вместе с `LayerSet`. На аудиопотоке — только lookup + линейная интерполяция.
- **Слой синтеза рендерится на своей velocity** (центр слоя), с параметрами генератора, подкрученными через `dynamics` (яркость, клик, питч, длина, шум). Нормализация: **не нормировать каждый слой к 0.5 отдельно** — иначе пропадёт разница громкости. Нормировать по самому громкому слою артикуляции, остальные — с тем же масштабом. Это ключевое место, покрыть тестом T-VEL-1.
- Кривая громкости поверх слоёв нужна только для «между слоями» (гладкость) — итоговая громкость = громкость слоя × поправка. Итоговый динамический диапазон кита: ghost (v≈0.25) на 18–26 dB тише accent (v=1) для малого; кик 12–18 dB; хэт 14–20 dB; тарелки 16–24 dB.

---

## 4. Пакеты работ

Формат каждого пакета: **ID, что сделать, файлы, тесты, критерий приёмки (AC) — в том числе «на слух»**.

### Фаза AD-0 — подготовка
**AD-0.1 Design note.** `docs/design/acoustic_dynamics.md`: типы, команды движка, бюджет памяти, решение по `.swap`, по `synthesisHash`, по хранению сидов RR. AC: файл есть, в `progress.md` ссылка.

**AD-0.2 Инструменты измерения (тест-хелперы, не прод-код).** В `DrumMashine_swistUITests/Support/AudioMetrics.swift`:
- `peak(_:)`, `rms(_:window:)`, `rmsDb`, `spectralCentroid(_:sampleRate:)` (vDSP FFT 2048, первые 80 мс), `attackTimeMs` (10→90 % огибающей), `decayT60` (оценка по огибающей), `pseudoLUFS` (K-weighting приблизительно: HP 60 Гц + shelf +4 dB @1.5 кГц, интегральный RMS по 400 мс окнам, гейт −70 dB).
- `renderKitGroove(kit:pattern:bars:)` — офлайн-рендер через `VoiceEngine` (как в `VoiceEngineSegmentRenderTests`) без AVAudioEngine.
- `writeWav(_:to:)` в `FileManager.default.temporaryDirectory` — для прослушки nixter (см. раздел 10).
AC: хелперы покрыты маленькими тестами на синусе/шуме с известными значениями (пик синуса 0.5 → −6.02 dB ±0.01, центроид синуса 1 кГц ≈ 1 кГц ±5 %).

**AD-0.3 Golden для «неприкосновенных не-legacy».** Новый фикстур `Fixtures/factory_buffers_d2_48k.txt` — SHA-256 текущих 51 D-2 + 13 bundled-буферов на `6cf321a` (тот же формат, что `factory_buffers_48k.txt`) и тест `FactoryBufferTests.d2AndBundledBuffersMatchBaseline`. Это нужно, чтобы видеть, **какие** из них ты осознанно меняешь (раздел 6). AC: тест зелёный на старте ветки.

### Фаза AD-1 — velocity-пайплайн (без изменения тембра)
**VL-1 `VelocityCurve` + `Dynamics` модель.** Файл `Core/Models/Dynamics.swift`. Толерантный декод, `Hashable`, `Sendable`. Таблица 128 точек `curveTable()`, монотонность гарантируется (`table` сортируется/клампится). Тесты T-DEC-1..3.

**VL-2 Акцент и артикуляция в шаге.** `SequencerStep.accent`, `SequencerStep.articulation` (опц.). `StepSnapshot` (в `SequencerEngine.swift` ~L324-335) несёт их в планировщик. В `SequencerScheduler` (~L327) применить accent → v. Kit-параметр `accentAmount` (по умолчанию 0.2, диапазон 0…0.4). AC: старый паттерн без полей звучит бит-в-бит (тест на офлайн-рендер).

**VL-3 Гуманизация velocity.** В `SequencerScheduler` рядом с humanize тайминга (~L272) — разброс velocity `±dynamics.humanize` (или глобальная ручка `humanizeVelocity` 0…100 % в `SessionStore` рядом с `humanize`). Использовать **тот же детерминированный ГПСЧ планировщика** (`nextUnitSigned()`), не `Float.random`. По умолчанию 0 → поведение не меняется. Также перевести `SequencerEngine` randomize (~L626) на сидируемый ГПСЧ (сид от id паттерна + счётчик) — тесты станут детерминированными.

**VL-4 Пэд: динамика с мыши/трекпада.** В `DrumPadView` (~L155) вместо `onTap(1.0)`:
- **Позиция по вертикали**: низ пэда = тихо, верх = громко (`v = 0.25 + 0.75 * (1 - y/height)`, кривая решает исполнитель).
- Режим `padVelocityMode: .fixed | .position | .pressure` хранится в `SessionStore`. **По умолчанию `.fixed` (1.0)**, чтобы поведение не изменилось неожиданно; переключатель в UI должен быть заметным (рядом с транспортом или в меню пэдов).
- **Force Touch**: `NSViewRepresentable` поверх пэда, `pressureChange(with:)` / `NSEvent.pressure` → velocity первого касания (берётся пик давления за первые 12 мс; если устройство без Force Touch — fallback на `.position`).
- **Модификаторы**: `⌥`-клик = ghost (0.35), `⇧`-клик = accent (1.0 + accent-флаг для записи), обычный = по режиму.
- **«Full level»** (как MPC): тумблер, все удары 1.0.
- `recordPadHit` пишет реальную velocity (и accent при `⇧`).
- Индикатор velocity на пэде (кольцо/заливка на 150 мс, яркость = v).
AC на слух: в режиме position тихий удар внизу пэда звучит как ghost (и после фазы AD-2 — темнее), удар вверху — как акцент.

**VL-5 Клавиатура.** Расширить `KeyShortcutMonitor` (`UI/Layout/MainLayoutView.swift`): клавиши `Z X C V / A S D F`… **не конфликтовать** с `Space` (play) и `F` (fill-once) — выбрать раскладку без `F`, например ряд `1–8` = пэды 1–8, с `⇧` = accent, с `⌥` = ghost. Повтор клавиши игнорировать (как сейчас). AC: клавиши работают, текстовые поля и модальные окна их не ловят (есть такие тесты для Space/F — расширить).

**VL-6 MIDI-вход (CoreMIDI).** Новый `Core/MIDI/MIDIInput.swift`:
- `MIDIClientCreateWithBlock`, вход со всех источников, Note On (velocity 1…127, Note On vel 0 = Note Off), CC 4 (педаль хэта) для pedal/half-open (пакет AR).
- Карта GM: 36/35 кик, 38/40 малый (40 = rimshot-артикуляция), 37 cross-stick, 42 closed hat, 44 pedal hat, 46 open hat, 39 clap, 41/43/45/47/48/50 томы (на трек tom: артикуляции/питч), 51/59 ride bow, 53 ride bell, 49/57 crash, 55 splash, 52 china, 54 tambourine, 56 cowbell, 60–64 бонго/конги, 69/70 cabasa/maracas, 75 claves, 76/77 woodblock, 81 triangle. Карта редактируется (`MIDIMap` в `SessionStore`), есть «Learn» для пэда (опционально, P2).
- **Потоки:** колбэк CoreMIDI приходит на своём потоке. **Нельзя писать в `.control`-кольцо из него** (лейн только для main actor). Сделать **третий лейн `.midi`** (отдельный SPSC `CommandRing`, единственный продюсер — поток MIDI-колбэка) и читать его в `render` наравне с двумя другими. Тайминг: `MIDITimeStamp` → hostTime → sample offset в следующем блоке (как минимум «сейчас», `atSample <= 0`).
- Запись в секвенсор при записи (`recordPadHit`) — через main actor (`Task { @MainActor … }`), звук — сразу из MIDI-лейна.
- Индикатор «MIDI ●» в транспорте мигает на входящую ноту.
- Песочница: macOS app sandbox — проверить entitlements (CoreMIDI в песочнице работает без доп. прав; если нет — записать и не расширять права без согласия nixter).
AC: подключённый MIDI-пэд/клавиатура играет треки с разной громкостью; тест на маппинг и на кривую (без реального устройства — через виртуальный источник `MIDISourceCreate` в тесте, если доступно; иначе юнит на парсер пакетов).

**VL-7 Velocity curve по умолчанию для не-legacy.** Для пресетов с `dynamics != nil` кривая по умолчанию `.db(range: 30, shape: 1.0)`; для legacy — `.linear`. Глобальная настройка «Чувствительность» (soft / medium / hard = shape 0.6 / 1.0 / 1.6) для входа с пэда/MIDI — в настройках. AC: T-VEL-2.

### Фаза AD-2 — движок слоёв и round-robin
**EN-1 `LayerSet` + команда `swapLayers`.** Как в 3.1. Retire целым набором. Бюджет памяти (раздел 9). Тесты: retire/leak (`leakedBufferCount == 0`), перегрузка retire-кольца (есть `retireCapacity` хук), своп во время звучания (голос доигрывает старый set).

**EN-2 Выбор слоя и crossfade.** На триггере: найти слой по v, при попадании в зону ±0.04 от границы — играть два слоя с весами (equal-power). Оба слоя одной длины не обязаны быть: короче — дополняется нулём (проверка индекса).

**EN-3 Round-robin.** Счётчик на (track, articulation, layer) в состоянии миксера (без аллокации, фикс. массив 9×4×8). Правило: «следующий по кругу»; при `roundRobin ≥ 3` — случайный без повтора предыдущего (ГПСЧ на аудиопотоке — простой xorshift в структуре, детерминированный от старта движка). Для офлайн-тестов — детерминированно.

**EN-4 Синтез слоёв и RR.** В `DrumSynthesizer` новая точка `layerSet(for preset:, sampleRate:) -> LayerSetSpec` (массивы `[[Float]]` вне аудиопотока), которая для каждой артикуляции × слоя × RR вызывает генератор с параметрами, промодулированными velocity центра слоя, и **сидом шума `baseSeed ^ (rr * 0x9E37) ^ (layer * 0x85EB)`**. RR кроме сида чуть детюнит (`rrDetune` центов) и меняет клик на ±1 dB. Нормализация — общая на артикуляцию (см. 3.3).
- Параллельный рендер слоёв (`TaskGroup`, ≤ ядра) — разрешено, но детерминизм результата обязателен (тест: два рендера → одинаковые хэши).
- Прогрессивная загрузка: сначала рендерится и свопается слой ближайший к v=0.8 (чтобы трек сразу звучал), потом полный set. AC: смена кита не даёт тишины > 150 мс.

**EN-5 Bundled-сэмплы со слоями.** `SoundSource.bundled` расширить: `bundledLayers(files: [[String]])` — **новый case не вводить** (сломает старый декод) — вместо этого `ArticulationSpec.layerFiles: [[String]]?` (слой → RR-файлы). Пресет с `source = .bundled(fileName:)` и без `layerFiles` = как сейчас.

### Фаза AD-3 — тембр от velocity (по голосам)
Для каждого генератора — **velocity-зависимые параметры** через `Dynamics` (и пер-голосовые override в `SynthParams`). Значения — «стартовые цели», подбирать по ушам и по метрикам (раздел 5).

**TV-1 Кик (мембрана).** Новая подструктура `SynthParams.Membrane` (используется киком и томами):
- Моды: фундаментальная `f0` + 2–4 моды мембраны с соотношениями круглой мембраны ≈ 1.59, 2.14, 2.30, 2.65 (затухание выше мод быстрее, `tauRatio` 0.3–0.6).
- Pitch-envelope «натяжения»: начальный подъём `+pitch * v` полутонов, падение за 15–40 мс.
- Бита (beater): шумовой/импульсный клик BP 2–5 кГц; уровень ∝ `v^1.5`, яркость клика растёт с v (felt/wood/plastic — `beater: .felt | .wood | .plastic`).
- Резонансная (front) голова: вторая мембрана с `f0 * 1.05–1.15`, порт (`port: Bool` — короче хвост).
- Демпфирование (подушка/полотенце): `damping 0…1` укорачивает и убирает верхние моды.
- AC на слух: тихий кик — мягкий «тум» без щелчка, громкий — с явной атакой битой и чуть выше по тону в первый момент. Метрика: центроид первых 30 мс растёт ≥ 1.6× от v=0.25 к v=1.

**TV-2 Малый барабан (оболочка + подструнник).** `SynthParams.SnareModel`:
- Мембрана сверху (моды как в TV-1, f0 160–260 Гц), оболочка (2 резонанса 400–900 Гц), **подструнник**: шум через BP 2–8 кГц, огибающая с собственной атакой 2–6 мс и затуханием, **порог включения**: доля проволоки `wires = clamp((v - 0.15)/0.6)^0.8` — ghost-ноты почти «сухие», акценты — с полным звоном.
- **Sympathetic buzz**: опциональный отдельный тихий слой шума, который можно потом возбуждать от кика/томов — **не делать в реальном времени**; вместо этого параметр `buzz` добавляет маленький хвост проволоки в буфер самого малого. (P2: настоящий sympathetic — отдельный пакет, не в этой работе.)
- Артикуляции малого (`ArticulationSpec`): `center` (0), `rimshot` (1: + металлический обод 600–1200 Гц, +4 dB, ярче), `crossStick` (2: только «клак» дерева/обода, 1–2 кГц, без проволоки), `ghost/brush` — щётки отдельной моделью (TV-9).
- AC на слух: при v 0.2 — «ту» без шипения, при v 1.0 — хлёсткий удар со звоном проволоки; rimshot явно громче и злее center на той же v.

**TV-3 Томы.** На `Membrane`: высокий 180–240 Гц, средний 130–170, напольный 80–110; pitch drop 1–3 полутона за 60–150 мс, глубина ∝ v; палочка — короткий клик. Артикуляции на трек tom: `high`, `mid`, `floor` (через `articulation` шага и MIDI 41–50) — **это даёт три тома на одном треке**.
- AC: на сбивке high→mid→floor ясно слышны три разных барабана, громкие удары с «нырком» высоты.

**TV-4 Хэт (металл + педаль).** `SynthParams.Metal` (общая для хэта/райда/крэша):
- 6 квадратных/импульсных осцилляторов с негармоничными соотношениями (классика 808: 205.3, 304.4, 369.6, 522.7, 540, 800 Гц × масштаб) **+** модальный набор (8–12 синусов 3–14 кГц с разбросом) + шум; HP 6–9 кГц, BP-«тело».
- Velocity: яркость (+1…+2 октавы полосы от v=0.2 к 1), острее атака, больше шума.
- Артикуляции на трек hat: `closed` (0, 30–90 мс), `open` (1, 0.5–1.5 с), `pedal` (2, «чик» 25–50 мс, мало верха, ниже уровень), `halfOpen` (3, 150–300 мс, «шипение»), `tipVsShank` — как разница яркости внутри closed по velocity.
- Choke: все артикуляции хэта — одна choke-группа (1), `pedal` и `closed` глушат `open/halfOpen`. **Не сломать** CUT_12–14: choke-группа берётся с трека как сейчас; артикуляция не меняет группу.
- AC: closed→open→pedal на одной дорожке; open глушится следующим closed/pedal без щелчка; громкие closed ярче тихих.

**TV-5 Райд (bow / bell / edge).** На `Metal`: длинные моды 2–8 кГц с медленным затуханием (2–5 с, кап буфера 4 с), «пинг» палки ∝ v, накопление «гула» (wash) ∝ v^1.3. Артикуляции: `bow` (0), `bell` (1: сильные моды 600–1500 Гц, ясный тон, +3 dB), `crash/edge` (2). Опция `rivets` (заклёпки — шум-сизл с медленной атакой, для джаза).
- AC: bell явно «колокол», не просто ярче; на громких bow растёт шум/wash, на тихих — чистый пинг.

**TV-6 Крэш / сплэш / чайна.** На `Metal` + FM, атака 1–3 мс, «расцвет» верхов (envelope яркости: верх растёт 30–80 мс, потом спадает) — **сильно зависит от v**: тихий крэш — мягкий «шшш», громкий — взрыв. Модели: `crash16/18/20`, `splash10` (короткий 0.4–0.8 с, высокий), `china18` (грязный, сильный FM, ring). Плюс `choke-grab` — артикуляция «крэш с захватом» (короткий 150 мс). Кап 4 с.

**TV-7 Rimshot / cross-stick / clap-слот.** Семейства треков не смешивать: rimshot и cross-stick живут на треке snare как артикуляции (и как отдельные пресеты семейства `snare`, как сейчас `Real Rimshot`). Трек clap (`VoiceKind.clap`) получает акустические хлопки и щелчки пальцами (TV-10).

**TV-8 Ghost-ноты как динамика, а не громкость.** Пресеты `* Ghost` (например `Real Snare Ghost` с `volume: 0.35`) оставить для совместимости, но в новых китах ghost = низкая velocity на обычном малом (с `dynamics`) + символ `g` в паттернах. В фабричных паттернах для новых китов использовать `g` чаще.

**TV-9 Щётки.** Отдельная модель малого «brush»: `tap` (короткий шум 5–8 кГц + мягкая мембрана), `swirl` (длинный 0.6–1.5 с фильтрованный шум с медленным LFO 1–3 Гц, громкость ∝ v), `slap` (хлопок щёткой, ярче). Артикуляции на трек snare в brush-китах. Для райда — `brushRide` (мягкий, без пинга).

**TV-10 Перкуссия (трек perc, семейство `perc`, и clap для хлопков).** Новая подструктура `SynthParams.HandDrum` / `Shaken` — решает исполнитель. Минимальный список (каждый — пресет; где есть — артикуляции):
| Инструмент | Артикуляции | Модель | Velocity → |
|---|---|---|---|
| Conga (quinto/conga/tumba, 3 пресета) | open, slap, mute, heel | мембрана f0 180–330 Гц, slap = шум+высокие моды | яркость, slap-доля |
| Bongo (macho/hembra) | open, slap | мембрана 300–500 Гц | яркость, питч |
| Cajon | bass, slap, tip | бас 70–90 Гц + щёлк проволок 3–6 кГц | проволока ∝ v |
| Djembe | bass, tone, slap | мембрана 70 / 330 / шум | slap-доля |
| Shaker (cabasa/egg) | forward, back | гранулярный шум: плотность гранул ∝ v, BP 5–9 кГц | плотность, яркость |
| Tambourine | hit, shake, thumb-roll(?) | 8–16 негармоничных джинглов 4–9 кГц | число звенящих джинглов |
| Acoustic Clap (на трек clap) | single, group (3–5 рук), room | 1…N бёрстов с разными спектрами и разбросом 3–12 мс | разброс/плотность |
| Finger snap (clap) | — | короткий шум 2–4 кГц + щелчок | — |
| Cowbell acoustic | open, mute | 2–3 моды 560/840 Гц негармонично + удар | яркость |
| Agogo | high, low | 2 колокола (квинта/кварта) | яркость |
| Timbale | open, rim (paila) | металл. оболочка + мембрана 350–500 Гц | rim-доля |
| Claves / Woodblock / Temple block | high, low | модальные резонаторы дерева 1–3 кГц | яркость |
| Guiro | short, long | серия щелчков по огибающей, 25–60 Гц частота щелчков | длина ∝ v |
| Triangle | open, mute | 6–8 мод 1.2–9 кГц, долгий хвост | яркость |
| Tabla-like (опционально P2) | na, tin | — | — |
| Orchestral bass drum (на kick) | hit, soft-mallet | мембрана 40–60 Гц, длинный хвост 1.5–3 с | атака |
| Timpani-like tom (на tom) | — | мембрана с выраженным тоном | — |
| Suspended cymbal / Tam-tam (на crash) | hit (только удар, без свелла) | `Metal`, длинный | расцвет верхов |
| Concert snare (на snare) | center, roll-stroke | плотная проволока | — |

AC: каждый инструмент узнаётся на слух без подписи (nixter проверяет 10 случайных — ≥ 8 угадал).

**TV-11 Room/overhead/«микрофоны» (RM).** Офлайн, в буфер, детерминированно:
- `MicMix { close: Double, overhead: Double, room: Double, roomSize: .small | .medium | .large | .hall, roomTone: Double /* -1 dark … +1 bright */ }` на уровне кита (`DrumKit.mic`), override на пресете.
- `overhead`: копия сигнала с HP 300–500 Гц, задержка 1.5–3 мс, лёгкий comb — даёт «воздух».
- `room`: свёртка с **синтезированным** IR (экспоненциально затухающий шум с ранними отражениями 6–8 тапов 5–40 мс, RT60 0.3–1.8 с по `roomSize`, сид фиксирован), LP по `roomTone`. Свёртка — `vDSP_conv` или FFT, **вне** аудиопотока. Хвост комнаты увеличивает длину буфера — учесть бюджет (кап 4 с).
- Velocity: громкие удары сильнее «возбуждают» комнату (room-send ∝ v^0.7), — встроено в слои.
- Глобальные эффекты (`Reverb` в `EffectsChain`) не трогать; RM — часть звука кита.
- AC: «Rock Big Room» в соло звучит в комнате без включённого Reverb; «Studio Dry» — сухо.

### Фаза AD-4 — новые акустические киты
**KT-1.** Новый файл `SoundLibrary/AcousticKits.swift` (или расширить `FactoryKits`): **минимум 12 новых китов**, все 8 слотов в порядке треков (`kick, snare, hat, clap, tom, ride, crash, perc`), все `dynamics != nil`, `style = .acoustic` (перкуссия — `.percussion`, если введён). id кита — `factoryID(filename: "kit.ac.<slug>")`, пресеты — новые filenames с префиксом `ac_<slug>_<voice>` (**вечные id, не переименовывать потом**). Старые 5 китов не менять.

Таблица китов и целевых параметров (стартовые значения, подбирать по ушам, итог — в отчёте):

| # | Кит (`name`) | Характер | Kick | Snare | Hat | Clap-слот | Tom (art.) | Ride | Crash | Perc | Mic (close/OH/room, size) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Studio Dry | современный поп/рок, сухо, близко | 22", f0 55 Гц, felt, damping 0.6, pitch +0.6 | 14×5.5, f0 200, wires 0.7 | 14" яркий closed 60 мс | Acoustic Clap group | 12/13/16" | 21" bow, сухой | 18" medium | Tambourine | 1.0/0.3/0.1 small |
| 2 | Jazz Club 60s | малый кик, открытые томы, мягко | 18", f0 70 Гц, damping 0.1, долгий тон, beater felt | 14×5, высокий 240 Гц, wires 0.5, ghost-friendly | тёмный 13" | Finger snap | 12/14 высоко настроены, долгие | 20" с rivets | 16" thin, тёмный | Shaker | 0.7/0.6/0.3 medium |
| 3 | Brushes Ballad | щётки везде | 20", мягкий, тихий клик | brush tap/swirl/slap | pedal-хэт громче | Snap | mallet-томы | brush ride | splash тихий | Shaker egg | 0.6/0.6/0.4 medium |
| 4 | Funk Tight 70s | сухой, мёртвый кик, высокий хлёсткий малый | 22", damping 0.9, короткий, wood beater | 13", f0 260, wires 0.9, сильный rimshot | плотный closed, много tip | Acoustic Clap single | 10/12 сухие | 20" ping | 16" short | Cowbell acoustic | 1.0/0.2/0.05 small |
| 5 | Rock Big Room | большой, громкий, комната | 24–26", f0 48 Гц, plastic beater, + resonant head | 14×6.5, f0 180, wires 1.0 | 15" | Group clap + room | 13/16/18" низко, длинный pitch drop | 22" heavy, сильный bell | 19–20" громкий | Tambourine hit | 0.8/0.6/0.9 large |
| 6 | Vintage 60s Soul | мало мид-баса, «бумажный» малый, моно-характер | 20", глухой, mid-heavy | 14", много проволоки, тёмный | тёмный, медленный | Group clap | 12/16 | тёмный ride | 18" тёмный | Tambourine shake | 0.6/0.7/0.4 medium, roomTone −0.5 |
| 7 | Vintage 70s Dead | полотенца, очень сухо | 22", damping 1.0 | 14", damping, мало звона | закрытый, глухой | Snap | concert toms, damping 0.8 | dry ride | 16" тёмный | Shaker | 1.0/0.1/0.0 small |
| 8 | Fusion Bright | яркий, высокий тюнинг, быстрые сбивки | 20", f0 62, plastic | 13", f0 280, crack | яркий, tip | — (Acoustic Clap single) | 10/12/14 яркие | 21" bell яркий | splash 10 + crash 17 | Agogo | 0.9/0.5/0.2 small |
| 9 | Hip-Hop Breaks | «запиленный» акустический брейк | 22", f0 52, мягкий + roomTone −0.6 | 14", толстый, pitch −1, wires 0.8 | грязноватый | Group clap | floor-тяжёлые | тёмный ride | trashy china-ish | Tambourine | 0.7/0.5/0.6 medium, лёгкий `lofi.saturation` |
| 10 | Latin Percussion | конги/бонго/тимбалес | (кик — Cajon bass) | Timbale (open/paila) | Shaker | Clap group | Conga quinto/conga/tumba (3 арт.) | Cowbell acoustic | Crash thin | Bongo (macho/hembra), Guiro, Claves (артикуляции) | 0.8/0.5/0.3 medium |
| 11 | Cajon Unplugged | акустика «у костра» | Cajon bass | Cajon slap | Shaker egg | Finger snap | Djembe bass/tone/slap | Tambourine shake | Splash тихий | Claves/Woodblock | 0.8/0.4/0.4 small |
| 12 | Orchestral | концертная перкуссия | Orchestral bass drum (soft-mallet) | Concert snare | тихий «sizzle» (тонкий закрытый хэт) | Finger snap (или Temple block high, если исполнитель сделает его в семействе clap — записать) | Timpani-like (3 арт.) | Suspended cymbal | Crash cymbals pair (длинный) | Triangle open/mute | 0.4/0.8/0.9 hall |
| 13 | Real Rusty Multi | сэмплы Big Rusty Drums, **мультислойные** (EN-5) | kick_24, 4–5 слоёв×2 RR | snare_14 center/rim/sidestick/brush | hihat_14 tc/open (+ pedal, если есть в источнике) | Acoustic Clap (синтез) | tom_14/15/22 | ride_22 (+ bell, если есть) | crash_17 | Tambourine (синтез) | сэмплы уже содержат OH; mic room 0.2 |
| 14 | Afro / World (P2, если хватит ресурса) | джембе, шейкеры, колокол | Djembe bass | Djembe slap | Shaker | Clap group | Djembe tone + talking-drum-ish | Agogo | — | Bell pattern | 0.7/0.6/0.4 medium |

- Для каждого кита задать `character` (1 строка по-русски для UI), `accentAmount`, `dynamicsDefault`.
- **KT-2. Фабричные паттерны для новых китов** — по 1–2 на кит в `FactoryPatterns.swift` (те же правила, новый `kitID`): jazz swing ride + ghost-snare `g`, funk 16-е хэты с акцентами и ghost, rock 8-е с open hat, brushes ballad (swirl на сильные доли), latin tumbao/songo, cajon groove, orchestral roll-like (быстрые 16-е с crescendo velocity), boom-bap break. Где нужны артикуляции — расширить DSL паттернов: после символа опционально `r`=rimshot, `s`=sidestick, `o`=open hat, `p`=pedal, `b`=bell, `1/2/3`=том high/mid/floor (решает исполнитель, с парсер-тестом). Акцент — `X` + флаг accent у шага (символ `A`).
- **KT-3. UI библиотеки.** В `SoundLibraryView` фильтр «ACOUSTIC» показывает новые пресеты; для китов — список с `character`. Кнопка «Слушать кит» играет короткую демо-фразу кита (из его фабричного паттерна) через превью-трек — **без** изменения текущего паттерна пользователя.

### Фаза AD-5 — правка velocity в секвенсоре
**UI-1 Velocity-лейн.** Под рядом шагов выбранного трека — полоска столбиков (высота = v, цвет ярче для accent, точка для ghost < 0.45). Рисование мышью: протянуть — задать v всем шагам под курсором; `⌥`-протяжка — только активные шаги. Двойной клик по столбику — 0.8 (дефолт).
**UI-2 Быстрые действия трека** (контекст-меню заголовка трека): «Ramp up / Ramp down» (crescendo/decrescendo по выделению), «Humanize ±10 %» (детерминированно, undo), «Все ghost», «Все accent», «Сбросить velocity к 0.8», «Масштаб ×0.8 / ×1.2».
**UI-3 Шаг.** Существующие long-press-drag и контекст-меню (`StepButtonView`) сохранить; добавить в меню: Accent on/off, Articulation (список артикуляций пресета трека), Ghost (0.35). Визуально: accent — рамка/⚡ (в `instructions.md` есть идея ⚡ для v>0.9 — использовать для accent), артикуляция — маленькая буква (`r/s/o/p/b/1/2/3`).
**UI-4 Undo.** Все массовые правки velocity — одним шагом undo (как Bake грува).
**UI-5 Доступность/темы.** Обе темы, accessibilityIdentifier для новых контролов (`seq.velocityLane.<track>.<step>`), UI-тест на рисование лейна (если UI-тесты гоняются локально; если нет — юнит на модель правки).
AC на слух/глаз: нарисовать crescendo на хэтах за 2 секунды; в плейбэке хэты плавно растут по громкости **и** яркости.

### Фаза AD-6 — вкус, уровни, миграция, производительность
**TQ-1 Иерархия громкости (pseudo-LUFS на одиночных ударах при v=0.8, относительно малого):**
| Голос | Цель относительно snare | Допуск |
|---|---|---|
| Kick | −1 … +1 dB | ±1.5 |
| Snare | 0 (опорный) | — |
| Closed hat | −9 … −6 dB | ±2 |
| Open hat | −7 … −4 dB | ±2 |
| Clap-слот | −4 … −1 dB | ±2 |
| Tom | −3 … 0 dB | ±2 |
| Ride bow | −10 … −7 dB | ±2 |
| Crash | −5 … −2 dB (пик выше, RMS ниже) | ±2 |
| Perc (shaker/tamb) | −12 … −8 dB | ±2 |
| Perc (conga/bongo/cowbell) | −6 … −2 dB | ±2 |

**TQ-2 Запас:** пик каждого буфера ≤ 0.5 (как `finalize`), на v=1 + accent пик голоса ≤ 0.5 × gain(1) ≤ 0.5. Сумма «все 8 треков ударили одновременно на v=1» перед лимитером ≤ 0.95 (`consumePreLimiterPeak`). Нет NaN/Inf, последний сэмпл = 0, нет DC (среднее |mean| < 1e-3).
**TQ-3 Ровность китов:** офлайн-рендер одного и того же референс-грува (8 тактов, kick/snare/hat + ghost + 1 crash) на каждом новом ките → pseudo-LUFS в пределах **±1.5 dB** между китами (кроме Orchestral/Brushes — допуск −6…0 dB, они тише по замыслу; записать).
**TQ-4 Монотонность:** для всех новых пресетов RMS и пик **не убывают** с v (шаг 0.05), центроид не убывает для пресетов с `brightness > 0` (допуск 2 % на шум).
**TQ-5 Гладкость слоёв:** соседние слои отличаются по громкости ≤ 4 dB, по центроиду ≤ 35 %; crossfade без «ступеньки» (тест на 21 точке v вокруг границы — RMS кривая монотонна).
**TQ-6 Различимость RR:** RR-варианты одного слоя имеют разные хэши, разница RMS ≤ 0.7 dB, корреляция первых 50 мс < 0.995 (то есть реально разные) и > 0.6 (тот же инструмент).

**MG-1 Обратная совместимость и миграция:**
- Все новые поля опциональны, `decodeIfPresent`, неизвестные enum-значения → безопасный fallback (как `SoundCategory.init(from:)`).
- Старая сессия/паттерн/кит/пользовательский пресет (фикстуры `legacy_*.json`) декодируются и **звучат бит-в-бит** (офлайн-рендер = baseline).
- Новые файлы, открытые **старым** билдом (с `6cf321a`), не падают: проверить, декодируя новые JSON старыми типами — сделать в тесте копию «старых» структур не нужно; достаточно правила «никаких новых case в существующих enum без fallback» + тест, что `SoundSource`, `VoiceKind`, `FactoryStyle` не получили новых case (кроме согласованного `percussion`, который в старом билде даст `style = nil` — проверить, что это безопасно).
- Пользовательский пресет, сделанный из старого акустического пресета, не получает `dynamics` автоматически. Кнопка «Сделать живым» (P2) в редакторе — добавляет `Dynamics` по умолчанию (явное действие пользователя).
- `restored(fromFactory:users:)` должен копировать `dynamics` и `articulations`.
- `synthesisHash` обновлён, `PreviewSampleCache` не отдаёт старый буфер для нового пресета.

**PF-1 Производительность и память (раздел 9).**

---

## 5. Метрики, которыми подбирать звук (а не только ухом)
- Для каждого нового пресета сгенерировать отчёт `qa/ad<N>/metrics-<preset>.txt` (тестом, который пишет в temp, а потом скопировать в qa — **или** просто лог теста): по каждому слою — peak dB, pseudo-LUFS, центроид 0–30 мс и 30–200 мс, attack ms, T60.
- Сводная таблица по китам — в отчёт фазы.
- Цифры — подсказка; финальное слово за ушами nixter (раздел 10).

---

## 6. Политика golden-тестов
1. `Fixtures/factory_buffers_48k.txt` (60 legacy) — **не меняется**. Красный = откатить своё изменение, а не фикстуру.
2. `VoiceEngineSegmentRenderTests.offlineRenderBitIdenticalToBaseline` — должен остаться зелёным: legacy-путь (один слой, линейный гейн) обязан давать бит-в-бит тот же микс. Если меняешь порядок операций в `mix()`, сделай отдельную ветку кода для `LayerSet` с одним слоем, которая идентична старой арифметике.
3. `Fixtures/factory_buffers_d2_48k.txt` (AD-0.3, 51 D-2 + 13 bundled): **по умолчанию не меняется**. Разрешено осознанно изменить **только** пресеты стиля `.acoustic` из D-2 (`kick_acoustic, snare_acoustic, ch_acoustic, oh_acoustic, clap_real, clap_snap, tom_acoustic_floor, ride_acoustic_dry, crash_acoustic_18, perc_clave, perc_woodblock, perc_shaker, perc_tambourine, perc_triangle`) — и только если nixter не против; **рекомендация: не менять их вообще**, а сделать новые `ac_*` пресеты. Если всё же меняешь: регенерировать фикстуру отдельным коммитом `AD-<N> GOLDEN: regenerate d2 hashes for <список>`, в сообщении и в отчёте — список изменённых filenames, причина, до/после метрики.
4. Новые пресеты и киты получают свой фикстур `Fixtures/acoustic_layers_48k.txt` (хэш каждого слоя × RR × артикуляции) — фиксирует детерминизм. Регенерация — только отдельным коммитом с причиной.
5. Способ регенерации: тест пишет текущие хэши в `FileManager.default.temporaryDirectory` (как уже делает `FactoryBufferTests`), исполнитель копирует файл в `Fixtures/` руками. **Никаких** «автообновлений» фикстур из теста.
6. Стартовые звуки треков (`clapTrackUsesTheClapVoiceAfterLaunch`) и дефолтный кит при первом запуске — не менять.

---

## 7. Сэмплы и лицензии
- Разрешено: (а) звук, синтезированный этим кодом; (б) CC0 1.0 / public domain с проверяемой страницей лицензии. Не разрешено: «royalty-free», CC-BY (требует атрибуцию в UI — не сейчас), CC-BY-NC, «free for personal use», неизвестное.
- Уже используемый источник: **Karoryfer «Big Rusty Drums»**, CC0 1.0, `https://github.com/sfzinstruments/karoryfer.big-rusty-drums`. В нём много velocity-слоёв и round-robin — их можно добрать для кита «Real Rusty Multi» (EN-5). Перед скачиванием открыть LICENSE в репо и записать в CREDITS дату проверки и коммит источника.
- Обработка (как в текущем `AcousticKit_CREDITS.txt`): close+OH в моно, тишина в начале обрезана, длина ограничена (kick/snare/tom ≤ 1.5 с, hat closed ≤ 0.4 с, open ≤ 1.5 с, ride/crash ≤ 3 с), косинусный фейд, общий масштаб **на всю артикуляцию** (не нормировать каждый слой отдельно — сохранить разницу громкости!), 44.1 кГц, 16 бит, WAV.
- Лимит размера: все новые сэмплы вместе ≤ **20 МБ** в бандле. Слоёв ≤ 5, RR ≤ 2 на артикуляцию.
- Каждый файл — строка в `Resources/AcousticKit/AcousticKit_CREDITS.txt` (или новый `Resources/AcousticKitMulti/CREDITS.txt`): файл → исходный путь, слой, RR, обработка, лицензия.
- Тест `BundledSamplesLicenseTests`: каждый `.wav` в `Resources/**` упомянут в каком-то `*CREDITS*.txt`, и каждый CREDITS содержит строку `CC0`.
- Скрипт подготовки сэмплов (если нужен) — в `Supporting/tools/prepare_samples.swift` или `.py`, без внешних платных зависимостей; его вывод — детерминирован. Сырые исходники **не коммитить**.
- Нет сети / сомнение в лицензии → EN-5 и кит 13 пропустить, записать в отчёт.

---

## 8. Тесты, которые нужно добавить (минимум)
Swift Testing (`import Testing`, `@Test`, `#expect`), как в существующих файлах.

**Декод/совместимость**
- T-DEC-1 `Dynamics`/`VelocityCurve`/`MicMix`/`ArticulationSpec` round-trip + пустой JSON `{}` декодируется в дефолты.
- T-DEC-2 Старые фикстуры `legacy_*.json` декодируются, новые поля = nil.
- T-DEC-3 `SequencerStep` без `accent/articulation` = как раньше; с ними — round-trip.
- T-COMPAT-1 `factory_buffers_48k.txt` зелёный (существующий).
- T-COMPAT-2 `factory_buffers_d2_48k.txt` зелёный (или осознанно обновлён, раздел 6).
- T-COMPAT-3 legacy-пресет через `LayerSet` = тот же буфер, офлайн-микс бит-в-бит (существующий `offlineRenderBitIdenticalToBaseline` + новый с velocity 0.4/0.8/1.0).
- T-COMPAT-4 Нет новых case в `VoiceKind`/`SoundSource`/`SoundCategory` (guard по `allCases.count` / ручному списку).

**Velocity**
- T-VEL-1 Монотонность (TQ-4) для всех новых пресетов, v = 0.05…1.0 шаг 0.05.
- T-VEL-2 Кривые: `.linear` = v; `.db` монотонна, `curve(1) = 1`, `curve(0.25)` для range 30 ≈ −22.5 dB ±0.5.
- T-VEL-3 Accent: v + accentAmount, кламп 1; groove × accent порядок фиксирован тестом.
- T-VEL-4 Гуманизация velocity детерминирована (два запуска планировщика с одним сидом = одинаковые v), при 0 % — v не меняются.
- T-VEL-5 Пэд: маппинг позиции/давления/модификаторов в v (чистые функции, вынести из View).
- T-VEL-6 MIDI: парсер Note On/Off, vel 0 = off, GM-карта, CC4 → артикуляция хэта.
- T-VEL-7 Тембр: центроид первых 30 мс при v=1 ≥ 1.4× центроида при v=0.25 для kick/snare/hat/ride/crash новых китов; для snare доля энергии 3–8 кГц (проволока) при v=1 ≥ 3× чем при v=0.2.

**Движок / RT**
- T-RT-1 `swapLayers` во время игры: нет утечек (`leakedBufferCount == 0`), retire-кольцо переполнение → backlog, потом освобождение.
- T-RT-2 Crossfade на границе: 21 точка, RMS монотонна, нет щелчка (макс. разность соседних сэмплов в первые 2 мс не выше чем у одиночного слоя ×1.2).
- T-RT-3 RR: без повтора подряд при RR ≥ 2; распределение равномерное ±20 % на 300 ударах.
- T-RT-4 Source-guard: в `Mixer.render` и функциях, которые он зовёт, нет `Array(`, `.append(`, `[Float](`, `DispatchQueue`, `print(`, `AppLog`, `lock` (по образцу `StepFlashSourceGuardTests` — читать исходник как текст).
- T-RT-5 Три лейна: MIDI-лейн принимает команды, порядок по `atSample` соблюдён, generation-фильтр не трогает MIDI (как пэд).
- T-RT-6 Choke не сломан: `ChokeOffTests`, `LivePadChokeTests` зелёные + новый тест: pedal/closed глушат open/halfOpen той же группы на одном треке с артикуляциями.

**Уровни/вкус**
- T-LVL-1 Пик буфера ≤ 0.5, конец = 0, |DC| < 1e-3, нет NaN — все новые слои.
- T-LVL-2 Иерархия (TQ-1) по каждому новому киту.
- T-LVL-3 Ровность китов (TQ-3).
- T-LVL-4 Сумма 8 треков на v=1 перед лимитером ≤ 0.95.
- T-LVL-5 RR различимость (TQ-6), слои гладкие (TQ-5).

**Киты/паттерны**
- T-KIT-1 ≥ 12 новых китов, у каждого 8 звуков правильных семейств по треку, уникальные стабильные id, нет `filename`-коллизий с существующими 124 пресетами.
- T-KIT-2 Новые фабричные паттерны загружаются, артикуляции и accent из DSL попадают в шаги.
- T-KIT-3 `BundledSamplesLicenseTests` (раздел 7).

**Производительность**
- T-PERF-1 Рендер полного `LayerSet` любого нового кита при 48 кГц ≤ 2.5 с на Apple Silicon в Debug (мерить и записать; если Debug медленнее — порог для Release-эквивалента указать в отчёте). Первый слой (прогрессивный) ≤ 200 мс на трек.
- T-PERF-2 Память буферов всего кита ≤ 48 МБ (Float32), всего движка (8 треков + превью) ≤ 64 МБ.
- T-PERF-3 Офлайн-рендер 32 голосов с crossfade: время на блок 512 при 48 кГц ≤ 25 % от реального времени блока (10.7 мс) в Debug, записать фактическое.

---

## 9. Бюджеты производительности и реального времени
- Голоса: 32 общий пул без изменений; на трек до 4 (для ride/crash/open hat можно 6 — решение записать; общий пул не увеличивать без измерения).
- Crossfade-голос считается как **один** голос (два чтения внутри), не занимает два слота.
- Память: см. T-PERF-2. Если не влезает — уменьшить RR у тарелок до 2, слои тарелок до 4, кап длины тарелок 3 с.
- Синтез только вне аудиопотока; аудиопоток — только чтение указателей, lookup таблицы кривой, FMA.
- Никаких новых `@MainActor` hop'ов на пути пэд → звук (сейчас пэд пишет в `.control` с main actor — так и оставить).
- Задержка пэд→звук не хуже текущей (измерить офлайн: команда в кольце → первый ненулевой сэмпл ≤ 1 блок).
- `CrackleDiagnosticsTests` зелёные; новый прогон «смена кита 20 раз во время игры» без late-событий сверх текущего уровня (`lateEventCount`).

---

## 10. Порядок работ (фазы = cut'ы), коммиты, отчёты

| Фаза | Пакеты | Результат для nixter | Ориентир объёма |
|---|---|---|---|
| AD-0 | AD-0.1, 0.2, 0.3 | ничего не звучит по-новому; design note, метрики, golden d2 | малый |
| AD-1 | VL-1…VL-7 | пэд/клавиши/MIDI с динамикой, accent, humanize velocity (пока только громкость) | большой |
| AD-2 | EN-1…EN-5 | движок слоёв и RR (legacy бит-в-бит) | большой |
| AD-3 | TV-1…TV-11 | новые модели и тембр от velocity, комната | очень большой |
| AD-4 | KT-1…KT-3 | 12–14 акустических китов + паттерны | большой |
| AD-5 | UI-1…UI-5 | velocity-лейн и массовые правки | средний |
| AD-6 | TQ, MG, PF | выравнивание уровней, миграция, перф, финальный отчёт | средний |

- После каждой фазы: тесты зелёные → лог в `qa/ad<N>/` → секция в `progress.md` → коммит → обычный push ветки. Не ждать nixter между фазами, если всё зелёное и пакет не требует его решения; **остановиться и спросить** только если: нужно менять golden (раздел 6 п.3), нужна сеть/лицензия неясна, нужны новые entitlements, или пакет не влезает в бюджеты.
- Если ресурс (токены) кончается — закончить текущий пакет до зелёного состояния, закоммитить, написать в `progress.md`, что осталось. Лучше 4 законченные фазы, чем 7 начатых.
- Приоритет при нехватке ресурса: AD-0 → AD-1 (VL-1…VL-4) → AD-2 (EN-1…EN-4) → AD-3 (TV-1, TV-2, TV-4, TV-5, TV-11) → AD-4 (киты 1, 2, 4, 5, 10) → AD-5 (UI-1, UI-3) → остальное.

### Формат отчёта после каждой фазы (в `progress.md` и в ответе)
```
## AD-<N> — <название>  (ветка feat/acoustic-dynamics @ <SHA>)
Статус: DONE | PARTIAL (что не сделано и почему)
Тесты: <passed>/<failed>, лог qa/ad<N>/<file>.log
Golden: legacy 60 — без изменений; d2 — без изменений | изменены: <список> (коммит <SHA>)
Что сделано: 3–8 пунктов с файлами
Метрики: таблица (кит/голос: peak, pLUFS, центроид v0.25→v1, T60)
Бюджеты: рендер кита <s>, память <MB>, блок <ms>
Что слушать: 3–6 пунктов из раздела 11 с номерами
Риски/долги: …
```
### Финальный отчёт (AD-6)
Всё выше по всем фазам + список новых китов и пресетов (filename → name), таблица сравнения китов по pseudo-LUFS, что осталось P2, и **готовый к прослушке набор WAV**: тест `ListeningRenderTests` (помечен так, чтобы запускался только вручную, например `.enabled(if: ProcessInfo.processInfo.environment["DRUM_RENDER"] == "1")`) пишет в `~/Desktop/DrumMashine_listening/` (или temp, путь в отчёте) по каждому новому киту: `kit_<slug>_groove.wav` (8 тактов демо-паттерна), `kit_<slug>_velocity_ramp.wav` (каждый голос: 16 ударов v 0.1→1.0), `kit_<slug>_rr.wav` (8 одинаковых ударов v=0.8). Эти WAV **не коммитить**.

---

## 11. Чек-лист прослушки для nixter (приёмка на слух)
Ставь ✅/❌ и короткий комментарий. Каждый пункт — что сделать и что должно быть.

**Динамика**
1. Пэд в режиме «по позиции»: 8 ударов снизу вверх по малому — громкость растёт плавно, без скачка; нижние — «ту», верхние — «ТЩАХ» с проволокой.
2. То же на хэте: тихие — тёмные «тс», громкие — яркие «ц».
3. Force Touch (если трекпад умеет): лёгкое касание = тихо, сильное нажатие = громко.
4. `⌥`-клик = ghost, `⇧`-клик = акцент — разница очевидна.
5. MIDI-пэд/клавиатура (если есть): удары разной силы звучат разной громкостью **и** окраской.
6. `kit_*_velocity_ramp.wav`: на каждом голосе 16 ударов — нет «ступеньки» на границе слоёв.

**Живость**
7. `kit_*_rr.wav`: 8 одинаковых ударов звучат как живой барабанщик, а не копия; ни один не выпадает по громкости.
8. Humanize velocity 15 %: хэты «дышат», но ритм не разваливается.
9. Accent-шаги в паттерне слышны как акцент, а не просто громче — ярче/с атакой.

**Инструменты** (каждый узнаётся без подписи)
10. Кик: тихий мягкий, громкий с битой; «Rock Big Room» — большой, «Funk Tight» — сухой, «Jazz Club» — тональный маленький кик.
11. Малый: center / rimshot / cross-stick — три разных звука; ghost-ноты в «Funk Tight» шуршат, а не щёлкают.
12. Хэт: closed / open / pedal / half-open; open глушится closed или pedal без щелчка.
13. Томы high / mid / floor на одной дорожке — три разных барабана, громкие «ныряют» по высоте.
14. Райд: bow vs bell — bell это колокол; в «Jazz Club» слышны заклёпки.
15. Крэш: тихий — мягкий «шшш», громкий — взрыв; splash коротко и высоко; china грязно.
16. Щётки: tap, swirl (кругом, «шуршит»), slap; brush ride мягкий.
17. Перкуссия: конга open/slap/mute, бонго, кахон bass/slap, шейкер (тихо — редкий, громко — плотный), бубен, клавес, гуиро, треугольник open/mute, ковбел, агого, тимбалес — угадываешь ≥ 8 из 10 случайных.
18. Акустический хлопок: одиночный и «группа» — звучит как люди, а не как 808.

**Киты и микс**
19. Переключаю 12 новых китов на одном паттерне — громкость примерно одна (кроме Brushes/Orchestral, они тише специально), ничего не «выпрыгивает».
20. В каждом ките: кик и малый главные, хэты/шейкер тише, тарелки не режут уши.
21. «Studio Dry» сухой, «Rock Big Room» и «Orchestral» — в комнате/зале **без** включённого Reverb.
22. Максимальная velocity + accent на всех треках сразу — нет клипа и хруста; индикатор лимитера не горит постоянно.
23. Смена кита во время игры — нет тишины дольше мгновения, нет треска.

**Совместимость**
24. Мои старые паттерны и сессии открываются и звучат **так же**, как до обновления (808/909/Lo-Fi/Trap/старый Acoustic).
25. Choke хэтов с пэдов и из секвенсора работает как в CUT_14.
26. Velocity-лейн: рисую crescendo на хэтах — слышу рост громкости и яркости; undo возвращает всё одним шагом.
27. Обе темы (Dark и Studio Light) — новые элементы читаются.

---

## 12. Definition of Done (вся работа)
- Ветка `feat/acoustic-dynamics` запушена обычным push, `main` не тронут, истории не переписаны.
- Все тесты зелёные, legacy-golden и offline-baseline без изменений.
- ≥ 12 новых акустических китов, ≥ 30 новых акустических пресетов (с артикуляциями), velocity меняет тембр у всех новых пресетов.
- Пэд (позиция/давление/модификаторы), клавиатура, MIDI, шаги, accent, humanize — единый путь velocity.
- Метрики и бюджеты в отчёте, WAV для прослушки сгенерированы (не закоммичены), чек-лист раздела 11 приложен.
- Мерж — только после «GO» от nixter.
