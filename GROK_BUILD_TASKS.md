# GROK_BUILD_TASKS — план исправлений DrumMashine_swistUI

> Составлено 07.10.2026 по ревью кода на коммите `21b5172 fix1` (07.10.2026, 23:22 IDT). В нём зафиксированы правки `AudioEngineManager`, `SamplerNode`, `SequencerEngine`, `AudioVisualizerView` и новые файлы `DrumSynthesizer`, `DrumProject`, `Features/Modulation/`, `WaveformView`, `ToggleButtonView`, `HapticManager`. Предыдущая версия — `6db9e7a`.
> Номера строк ниже указаны по этому состоянию. После первых правок они сдвинутся, поэтому ищи по имени функции.

## Контекст

Это macOS-приложение на SwiftUI (SDK `macosx`, deployment target 15.6, Xcode 26.3, `SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, App Sandbox включён). Мак nixter: Mac mini 2018, Intel i7‑8700B с встроенной графикой. Выходы звука: LG UltraFine (44.1 kHz), динамики Mac mini (48 kHz), а также виртуальные устройства (Virtual Desktop, Immersed). Устройства с **разной** частотой дискретизации переключаются часто.

Звук синтезируется в `DrumSynthesizer`. Каждый из 8 треков играет через свою цепочку `AVAudioPlayerNode → AVAudioUnitTimePitch`, дальше идут subMixer → Reverb → Delay → Distortion → mainMixer. Секвенсор работает на `DispatchSourceTimer`, планирует ноты через `Task { @MainActor }` и передаёт в `scheduleBuffer(at:)` время из `mainMixerNode.lastRenderTime`.

Главные причины плохого звука:
1. Время нот считается не в той шкале: время микшера отдаётся плееру, у которого своя шкала времени.
2. Каждый трек может играть только одну ноту, а опция `.interrupts` и `stop()` обрывают хвосты нот.
3. Почти каждый синтезированный звук обрывается на 5–25 % амплитуды. Это даёт щелчок в конце.
4. Нет запаса по громкости и лимитера. 8 треков, каждый нормализован к 0.95, при сложении клипуют.
5. При смене аудиоустройства движок молча останавливается.
6. Главный поток перегружен: на каждый аудиобуфер публикуется около 35 `@Published`, и весь UI перерисовывается.

**Не верь `progress.md` и `QUICK_SUMMARY.md`**. Там написано «Zero clicks/pops», «sample-accurate» и «< 10 ms», но в коде этого нет.

## Правила работы (обязательно)

1. **Базовая точка** — коммит `21b5172 fix1`, он собирается. Перед началом убедись, что `git status` чистый: допускается только этот файл, его закоммить отдельно (`docs: add GROK_BUILD_TASKS`). Remote нет, ничего не пушь.
2. **Каждая задача = отдельный коммит.** Если задача большая, коммить её по шагам. Сообщение коммита начинай с ID задачи, например `P0-2: fade-out tails in DrumSynthesizer`. Не смешивай задачи в одном коммите.
3. **Сборка всегда зелёная.** После каждого коммита выполняй:
   ```bash
   cd . && \
   xcodebuild -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI \
     -destination 'platform=macOS' -derivedDataPath ./DerivedData build 2>&1 \
     | grep -E "warning:|error:|BUILD" | grep -v appintentsmetadataprocessor
   ```
   Ожидаемый результат: `** BUILD SUCCEEDED **`, и число предупреждений не растёт. К концу P1 предупреждений должно быть ноль.
4. **Исправь предупреждения Swift 6.** Сейчас их четыре: `AudioEngineManager.swift:84` (`setupAudioEngine()` вызывается вне MainActor), `:429` и `:453` (`generateSamplesForPreset` вызывается вне MainActor), `DrumProject.swift:204` (результат `save` не используется). Новых не добавляй. Не глуши их через `@preconcurrency`, `nonisolated(unsafe)` или `@unchecked Sendable`, если не можешь объяснить в комментарии, почему это безопасно.
5. Тесты (после задачи P0-0):
   ```bash
   xcodebuild -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI \
     -destination 'platform=macOS' -derivedDataPath ./DerivedData \
     test -only-testing:DrumMashine_swistUITests
   ```
6. Логи приложения смотри через `/usr/bin/log`. В zsh `log` — встроенная команда, поэтому нужен полный путь:
   `/usr/bin/log show --last 10m --style compact --predicate 'process BEGINSWITH "DrumMashine"' | grep -iE "overload|skipping cycle|error|fault|Hang Risk"`
7. Запуск собранного приложения: `open ./DerivedData/Build/Products/Debug/DrumMashine_swistUI.app`.
8. Сам ты звук не слышишь. Поэтому для каждой задачи есть **автопроверка** (тест или лог) и пункт **«на слух»** для nixter. Пункты «на слух» собери в отчёт в конце.
9. Делай задачи по порядку: P0-0 → P0-7 → P1 → P2. Задачи P0-3 и P0-4 заменяют `SamplerNode` и таймер секвенсора, поэтому не чини старый код точечно, если задача его выбрасывает.

---

## P0 — ломает звук

### P0-0. Тестовый стенд для офлайн-рендера звука
- **Файлы:** `DrumMashine_swistUITests/DrumMashine_swistUITests.swift`. Сейчас там только пустой `example()`.
- **Проблема:** автоматической проверки звука нет, а в документации заявлено то, чего нет в коде. Без стенда все остальные P0 придётся проверять только на слух.
- **Как исправить:**
  - Добавь тесты на Swift Testing (`import Testing`, `@testable import DrumMashine_swistUI`, тесты помечай `@MainActor`).
  - Хелпер `func analyze(_ s: [Float]) -> (peak: Float, tailPeak: Float, hasNaN: Bool)`. Здесь `tailPeak` — максимум модуля в последних 5 мс.
  - Хелпер офлайн-рендера: создать `AVAudioEngine`, вызвать `enableManualRenderingMode(.offline, format: <48 kHz stereo float>, maximumFrameCount: 4096)`, подключить узел-источник, вызвать `start()` и `renderOffline(...)` нужное число кадров, вернуть массив `[Float]` (левый канал).
  - Хелпер `onsets(_:threshold:)` возвращает индексы сэмплов, где сигнал впервые превысил порог после тишины длиной не меньше 2 мс.
  - Пока напиши тесты только для `DrumSynthesizer`: все пресеты из `SoundLibraryManager.shared.availableSounds` плюс 8 дефолтных звуков. Проверяй, что нет NaN и Inf, что `peak <= 0.9` и что `tailPeak < 0.001` (−60 dBFS). Сейчас тест на хвост **должен падать**, это ожидаемо, его чинит P0-2. Пометь его `.disabled("P0-2")`, чтобы сборка и тесты оставались зелёными, и сними метку в P0-2.
- **Проверка:** команда тестов из правила 5 проходит, отключённый тест виден в выводе.

### P0-1. Детерминированная инициализация движка, частота выхода, изоляция акторов
- **Файлы:** `Core/AudioEngine/AudioEngineManager.swift:79-87` (`init` с `Task.detached`), `:98-159` (`setupAudioEngine`), `:100` (жёстко заданы 44100 Гц и моно), `:283-321` (`generateAllSoundsAsync`, `44100` на `:302` и `:306`), `:425-466` (`previewSound` и `loadSound`), `:469` (`generateSamplesForPreset`). Также `Core/AudioEngine/DrumSynthesizer.swift:5`.
- **Проблема:**
  - Граф `AVAudioEngine` собирается и запускается из `Task.detached`. Это вызов MainActor-метода вне актора, отсюда предупреждение `:84`. Одновременно главный поток читает `samplerNodes` и `audioBuffers` (словари), то есть идёт гонка данных.
  - В логах Мака при каждом запуске (07.10, 22:51 и 23:13) есть `[Hang Risk] Thread running at User-interactive QoS waiting on a lower QoS thread`. Это инверсия приоритетов во время инициализации.
  - Из-за `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` и `DrumSynthesizer`, и `generateSamplesForPreset` неявно изолированы на `@MainActor`, но вызываются из detached-задач (предупреждения `:429` и `:453`). В режиме Swift 6 это ошибка компиляции.
  - Все буферы синтезируются на 44.1 kHz, а реальный выход часто 48 kHz (в логе `Output {BuiltInSpeakerDevice}`). Микшер на лету делает лишний ресемплинг. Кроме того, в секвенсоре на `SequencerEngine.swift:126` захардкожено `44100 / 10`.
- **Как исправить:**
  - Помечай `@MainActor` явно. Сборку графа (`attach`/`connect`) и `engine.prepare(); try engine.start()` делай синхронно на MainActor в `init` или в явном `start()`. Это занимает миллисекунды. В фон уходит только синтез сэмплов.
  - `DrumSynthesizer` объяви как `nonisolated enum DrumSynthesizer` (Swift 6.2 позволяет `nonisolated` на типе). Все генераторы сделай `static` и чистыми. Логику `generateSamplesForPreset` и `generateFXSamples` перенеси туда же как `nonisolated static func samples(for preset: SoundPreset, sampleRate: Double) -> [Float]`. Модели, которые передаются в фон (`SoundPreset`, `SequencerStep`, `SequencerTrack`, `EffectsChain`, `DrumPattern`), объяви `nonisolated struct ...: Sendable`.
  - Частоту бери из `engine.outputNode.outputFormat(forBus: 0).sampleRate`. Используй её и для синтеза, и для формата соединений. Нигде больше не пиши литерал `44100`, проверка: `rg -n "44100" DrumMashine_swistUI` должна вернуть пусто.
  - `isReady` выставляй на MainActor только после того, как готовы все 8 буферов. Ошибку `engine.start()` показывай через `errorMessage`. Сейчас баннер ошибки рисуется только при `isReady == true`, то есть ошибку не видно на экране загрузки. Исправь это в `MainLayoutView.swift:26-33`.
  - Песочница: для **вывода** звука никакой entitlement не нужен. Не обращайся к `engine.inputNode`, иначе приложение начнёт запрашивать микрофон и понадобится `com.apple.security.device.audio-input`.
- **Проверка:**
  - Сборка проходит, предупреждений `:84`, `:429` и `:453` больше нет.
  - `rg -n "Task.detached" Core/AudioEngine` даёт только синтез.
  - Запусти приложение и выполни команду из правила 6: `Hang Risk` больше нет.
  - Тест: `DrumSynthesizer.samples(for:sampleRate: 48000)` возвращает массив длиной `decay*48000` (с допуском).

### P0-2. Щелчки в конце звуков и запас по громкости в синтезе
- **Файлы:** `Core/AudioEngine/DrumSynthesizer.swift`. Длительность и огибающая: kick `:72` и `:105`, snare `:118` и `:142`, hi-hat `:153` и `:182-183`, clap `:193` и `:229-232`, tom `:245` и `:269`, crash `:279` и `:302`, ride `:340` и `:358-359`. Нормализация на `:10-21` (0.95). FX: `AudioEngineManager.swift:583-636` (нормализация 0.9).
- **Проблема:** длительность буфера равна `decay` или `max(min, decay)`, а огибающая `exp(-t/(decay*k))` к концу буфера ещё не затухла. Например:
  - kick (decay 0.35): в конце около 0.08 от пика (≈ −22 dB);
  - snare 808 (0.18 → 0.2 с): шум около 0.25;
  - HH Open (0.35 → 0.5 с): около 0.24;
  - tom: около 0.15;
  - ride: около 0.13;
  - Crash Dark: около 0.08.
  Буфер обрывается на ненулевом сигнале, и это даёт щелчок в конце **каждого** удара. Плюс каждый звук нормализован почти в 0 dBFS, поэтому при сумме 8 треков запаса нет.
- **Как исправить:**
  - Добавь общий хелпер `finalize(_:sampleRate:)`: нормализация к пику **0.5** (−6 dBFS, запас под сумму треков; общий уровень потом поднимет лимитер из P0-5), затем fade-out по половине косинуса на последних `min(10 мс, 10 % длины)` сэмплов, затем `DC = 0` в последнем сэмпле. Применяй его во всех генераторах и в FX.
  - Длину буфера считай от постоянной затухания: `duration = max(minDur, tau * ln(1000))`, где `tau` — самая длинная постоянная огибающей. Это ≈ 6.9·tau, то есть до −60 dB. Тогда fade-out работает только как страховка, а не режет звук.
  - Добавь короткую атаку 0.3–1 мс там, где сигнал стартует не с нуля (шумовой click у kick, snare, clap). Так убирается щелчок в начале без потери удара.
  - Сними `.disabled` с теста хвоста из P0-0 и поменяй порог пика на `<= 0.51`.
- **Проверка:** тесты P0-0 проходят для всех 68 звуков (60 библиотечных и 8 дефолтных). **На слух:** на одном пэде каждого трека (особенно SNARE, HIHAT, TOM, RIDE) щелчка в конце звука нет.

### P0-3. Новый голосовой движок для реального времени на `AVAudioSourceNode` (замена `SamplerNode` и `TimePitch`)
- **Файлы:** `Core/AudioEngine/SamplerNode.swift` (весь), `AudioEngineManager.swift:56-57`, `:71`, `:121-127`, `:345-376` (`trigger`), `:406-422` (`stop`, громкость и панорама трека). Новый файл `Core/AudioEngine/VoiceEngine.swift`.
- **Проблема (почему текущая схема ломает звук):**
  - Каждый трек — один `AVAudioPlayerNode`, то есть **монофония на трек**. `scheduleBuffer(..., options: .interrupts)` (`SamplerNode.swift:49`) обрывает звучащий буфер прямо в момент планирования, примерно за 100 мс до следующей ноты. Хвосты режутся, получаются щелчки, а частые хэты на соседних шагах звучат рвано.
  - При живом нажатии вызывается `playerNode.stop()` (`:45-47`). Он **удаляет все уже запланированные секвенсором ноты** этого трека и сбрасывает шкалу времени плеера.
  - Velocity задаётся через `playerNode.volume = velocity` (`:41`) в момент планирования, то есть за 100 мс до ноты. Это меняет громкость ещё звучащей предыдущей ноты и затирает громкость трека из `setTrackVolume` (`AudioEngineManager.swift:414-417`).
  - Choke (`AudioEngineManager.swift:363-372`) вызывает `stop()` **немедленно**, а не в момент ноты. Открытый хэт глушится раньше времени, и вместе с ним пропадают его будущие ноты.
  - `AVAudioUnitTimePitch` стоит в цепи всегда, хотя высота уже «запечена» в синтез (`:461` ставит `pitch = 0`). Это phase-vocoder: он смазывает атаку барабанов, добавляет задержку и тратит CPU (8 экземпляров).
  - `previewSound` играет на `samplerNodes[0]` и этим обрывает kick (это задача P1-6).
- **Как исправить (целевая схема):**
  - `nonisolated final class VoiceEngine`. Внутри один `AVAudioSourceNode` со стерео float-форматом на частоте выхода, режим не-interleaved.
  - Пул голосов: заранее выделенный `UnsafeMutablePointer<Voice>`, 32 голоса. Структура `Voice { active, track, sampleIndex, gainL, gainR, fadeRemaining, fadeStep, chokeGroup, startOrder }`.
  - Сэмплы трека хранятся в заранее выделенных `UnsafeMutableBufferPointer<Float>`, по слоту на трек плюс слот превью.
  - **Команды из UI и секвенсора в render** передаются через lock-free SPSC-кольцо фиксированной ёмкости (1024) на `Synchronization.Atomic` (macOS 15+, доступно при таргете 15.6). Команды: `trigger(track, velocity, atSample: Int64)`, `stopAll(fadeFrames)`, `setTrackGain(track, gain, pan)`, `swapSample(track, ptr, count)`.
  - Счётчик кадров движка `Atomic<Int64> renderedFrames` увеличивается в конце каждого render-вызова. Это **единственные аудиочасы** приложения.
  - Render-блок. Для каждой команды с `atSample` внутри текущего блока голос стартует **с точным смещением в кадрах**. Если команда опоздала, голос стартует со смещения 0, а счётчик `lateEvents` увеличивается.
  - Choke: при старте голоса группы `g` все остальные звучащие голоса группы `g` получают fade-out на 3 мс **с того же сэмпла**.
  - Voice stealing: на трек не больше 4 голосов. При переполнении самый старый голос трека получает fade 3 мс. Если весь пул занят, крадётся самый старый голос с fade 1 мс.
  - Громкость и панорама трека сглаживаются однополюсным фильтром примерно 5 мс, чтобы не было «zipper»-шума. Панорама с постоянной мощностью.
  - Velocity — это фиксированный gain голоса в момент старта.
  - **В render-блоке запрещено:** выделять память (Array/String/`print`), брать блокировки (`DispatchQueue.sync`, `NSLock`, `Mutex.withLock`), создавать ObjC-объекты (`AVAudioTime`, `AVAudioPCMBuffer`), обращаться к `@MainActor` и SwiftUI, вызывать `Task {}`. Замыкание render создавай внутри `nonisolated`-кода, иначе в режиме Swift 6 оно унаследует MainActor и упадёт на проверке очереди.
  - Замена сэмпла (`swapSample`): старый указатель render возвращает через второе SPSC-кольцо, а освобождает его MainActor, когда ни один голос уже не играет этот слот.
  - `AudioEngineManager.trigger(trackIndex:velocity:chokeGroup:at:)` переделай на `voiceEngine.trigger(..., atSample: 0 /* ASAP */)` для пэдов. `SamplerNode.swift` удали вместе с `AVAudioUnitTimePitch` и subMixer.
- **Проверка (тесты через офлайн-рендер из P0-0, частота 48 kHz):**
  1. Два удара crash с интервалом 125 мс: в окне 150–200 мс после первого удара энергия больше, чем у одиночного второго удара. Значит, первый не обрезан, полифония работает.
  2. Choke: открытый хэт в кадре 0, закрытый хэт в кадре 24000. Огибающая открытого хэта после кадра 24000+144 (3 мс) ниже −60 dB, а до кадра 24000 не тронута.
  3. `trigger(atSample: N)` даёт начало звука ровно в N (±0 кадров) для N = 1000, 4095, 4096, 4097 (граница блока).
  4. 64 одновременных триггера не падают, работают ровно 32 голоса, без NaN.
  5. `rg -n "AVAudioUnitTimePitch|SamplerNode|\.interrupts" DrumMashine_swistUI` возвращает пусто.
  6. Instruments → Allocations, 30 секунд воспроизведения, фильтр по потоку `com.apple.audio.IOThread.client`: 0 аллокаций.
- **На слух:** быстрые нажатия на один пэд дают наложение звуков, а не обрыв. Кик под хэтами не «заикается».

### P0-4. Сэмпл-точный секвенсор на аудиочасах (вместо Timer + `Task { @MainActor }`)
- **Файлы:** `Core/Sequencer/SequencerEngine.swift:74-78`, `:114-189` (`play`, `scheduleValues`, `stop`), `:193-238` (`triggerStep`), `:62-69` (`humanize` больше нигде не используется, регрессия коммита `fix1`).
- **Проблема:**
  - `AVAudioTime(sampleTime:atRate:)` строится из `mainMixerNode.lastRenderTime.sampleTime` (`:146-156`), то есть по шкале **выхода движка**. `AVAudioPlayerNode` трактует `sampleTime` в **своей шкале плеера**: она стартует с 0 при `play()` и сбрасывается при `stop()`. В итоге ноты звучат с задержкой, равной времени работы движка, или вообще не звучат. Треки, у которых плеер стартовал в разное время, расходятся между собой. Каждый choke или нажатие пэда ломает шкалу ещё раз.
  - Если `lastRenderTime` равен `nil`, то `nextSampleTime = 0` (`:128`). Тогда цикл `while` (`:155`) за один тик «догоняет» всё время работы движка и создаёт тысячи `Task`.
  - `stepIndex = self.currentStep` (`:159`) читается на фоновой очереди, а увеличивается асинхронно в отдельном `Task { @MainActor }` (`:175-177`). Если за тик планируется несколько шагов, они получают **один и тот же** индекс: шаги дублируются или пропускаются.
  - Каждая нота проходит через главный поток (`:162-164`). При загруженном UI (см. P1-1 и P1-2) нота приходит позже своего времени.
  - Свойства `@Observable` (`bpm`, `stepCount`, `tracks`) читаются с фоновой очереди. Это гонка данных.
  - Плейхед UI обгоняет звук на окно опережения (100 мс).
  - После `stop()` уже созданные `Task` продолжают триггерить ноты, а `currentStep` после сброса ещё раз увеличивается.
  - `setTrackPan` вызывается на каждую ноту (`:234`).
- **Как исправить:**
  - Новый `nonisolated final class SequencerScheduler`. Своя `DispatchQueue(qos: .userInteractive)` и `DispatchSourceTimer` с интервалом 5 мс и `leeway` 1 мс.
  - Снимок паттерна `PatternSnapshot` (Sendable-структура: шаги, velocity, probability, mute/solo, `stepCount`, `bpm`, `swing`, `humanize`, choke-группы) хранится в `Mutex<PatternSnapshot>` из `Synchronization`. Это поток планировщика, не render, поэтому мьютекс здесь допустим. MainActor обновляет снимок при каждом изменении `tracks`, `bpm` и других полей (через `didSet` или `onChange`).
  - Время шага считай в **абсолютных кадрах аудиочасов** `VoiceEngine.renderedFrames`, без накопления ошибки: `t(k) = anchor + round(k * samplesPerStep)`. При смене BPM переякорись: `anchor = t(текущий k)`, `k = 0`.
  - Swing: нечётные шаги сдвигаются на `swing/100 * samplesPerStep * 0.5`.
  - Humanize: ±`humanize/100 * 0.1 * samplesPerStep`, через детерминированный RNG.
  - Окно опережения: `lookahead = max(30 мс, 2 × размер IO-буфера)`. Каждый тик планировщик отправляет в `VoiceEngine` команды `trigger(..., atSample:)` для всех шагов, у которых `t < now + lookahead`.
  - `stop()`: `generation += 1` (опоздавшие команды отбрасываются), затем `voiceEngine.stopAll(fadeFrames: 5 мс)`.
  - Плейхед: `currentStep` вычисляется на MainActor из `renderedFrames - outputLatency` с частотой 30–60 Гц (через `TimelineView(.animation)` или таймер в `.common` runloop mode). Обновляй его, только когда шаг изменился. Никаких `Task` на каждый шаг.
  - Уровни громкости и панорамы треков передавай в `VoiceEngine.setTrackGain` при изменении, а не на каждую ноту.
- **Проверка (тесты через офлайн-рендер):**
  1. 120 BPM, 48 kHz, kick на всех 16 шагах, 2 такта: начала ударов на `k * 6000` (±1 кадр) для всех 32 ударов.
  2. Swing 50 %: нечётные шаги в `k*6000 + 1500` (±1).
  3. Смена BPM со 120 на 140 посреди такта: шаги до смены и после идут на правильной сетке, без двойных ударов.
  4. `stop()`, затем рендер ещё 200 мс: после fade 5 мс полная тишина (пик < 1e-5).
  5. Ни один шаг не продублирован и не пропущен за 1000 шагов, если шаг меняется каждые 7 мс (стресс-тест).
- **На слух (nixter):** 120 BPM, хэт на всех 16 шагах, кик на 1/5/9/13, слушать 1 минуту: ровно, без «плавания» и дублей. Сразу после запуска ноты звучат с первого шага, без паузы. Плейхед совпадает со звуком.

### P0-5. Гейн-стейджинг: мастер-лимитер и честный индикатор клипа
- **Файлы:** `AudioEngineManager.swift:132-135` (конец цепочки), `:507-509` (`setMasterVolume`), `Features/Visualizer/MasterControlView.swift:9-10` (`masterVolume = 0.85` в UI, а движок стоит на 1.0; кнопка `LIMITER` ни к чему не подключена), `:68-69` и `:108-116` (CLIP считается по RMS, а не по пику).
- **Проблема:** 8 треков по 0.95 плюс эффекты дают пики до 4–7, и на выходе цифровой клип (хрип). Кнопка LIMITER декоративная. Индикатор CLIP строится по сглаженному RMS и настоящие перегрузки почти не ловит.
- **Как исправить:**
  - В конец цепочки поставь `AVAudioUnitEffect` с `kAudioUnitSubType_PeakLimiter` (Apple): attack около 2 мс, decay около 50 мс, предусиление 0 dB, потолок примерно −1 dBFS (если потолок недоступен как параметр, ставь `mainMixer.outputVolume ≤ 0.89`). Кнопка LIMITER переключает его `bypass`.
  - Дополнительно в `VoiceEngine` поставь мягкий запас: сумма × 0.5 (уже сделано через −6 dB в P0-2).
  - Пиковый уровень считай прямо в render: максимум модуля за блок пиши в `Atomic<UInt32>` как биты Float. UI читает его 30 раз в секунду. CLIP загорается при пике ≥ 0.99 **до** лимитера.
  - При старте синхронизируй громкость из UI с движком (вызови `setMasterVolume(0.85)` в `onAppear` или храни громкость в модели).
- **Проверка:** офлайн-тест, где 8 треков играют все шаги с velocity 1.0 и включёнными reverb и delay: пик на выходе ≤ 0.9, NaN нет. **На слух:** нет хрипа на плотном паттерне (кнопка RANDOM, velocity 1).

### P0-6. Смена аудиоустройства и частоты дискретизации (`AVAudioEngineConfigurationChange`)
- **Файлы:** `AudioEngineManager.swift`, обработчика нет вообще.
- **Проблема:** на Маке nixter несколько выходов с разной частотой (LG 44.1k, динамики Mac mini 48k, виртуальные устройства). При смене выхода или подключении наушников AVAudioEngine **останавливается** и шлёт `AVAudioEngineConfigurationChange`. Код это не обрабатывает: звук пропадает до перезапуска приложения, а буферы остаются на старой частоте.
- **Как исправить:**
  - Подпишись на `NotificationCenter` с `.AVAudioEngineConfigurationChange` и `object: engine`. Обработчик выполняй на MainActor с дебаунсом 100 мс, потому что уведомление может прийти пачкой.
  - В обработчике: поставь планировщик на паузу и запомни позицию шага, вызови `engine.stop()`, прочитай новый `outputFormat`. Если частота изменилась, перегенерируй 8 буферов и превью на новой частоте (в фоне) и переподключи узлы с новым форматом. Затем `engine.prepare()`, `try engine.start()` (с повтором через 300 мс при ошибке) и продолжи воспроизведение с сохранённого шага.
  - Если старт не удался, покажи `errorMessage`.
- **Проверка:** запусти приложение, нажми Play, затем в «Системные настройки → Звук → Выход» переключи «LG ULTRAFINE» ↔ «Динамики Mac mini» 5 раз. Воспроизведение возобновляется в течение 1 секунды, высота звука не меняется (буфер на правильной частоте), в логе (правило 6) нет ошибок. В коде: `rg -n "AVAudioEngineConfigurationChange"` находит обработчик.

### P0-7. Цепочка эффектов: порядок, bypass, маппинг ручек
- **Файлы:** `AudioEngineManager.swift:63-65`, `:106-119`, `:129-135`, `:379-404` (`updateEffects`), `Core/AudioEngine/EffectsChain.swift`, `Features/EffectsRack/EffectsRackView.swift:20-97`, `:179-183`.
- **Проблема:**
  - Порядок Reverb → Delay → Distortion: дисторшн стоит **после** реверба и перегружает хвосты, звук получается грязным.
  - Выключенный эффект остаётся в цепи с `wetDryMix = 0`. Он всё равно тратит CPU и может окрашивать звук.
  - Ручка MIX 0..1 отображается в `wetDryMix * 100`. При 100 % reverb и delay **полностью убирают сухой сигнал**, и барабаны пропадают.
  - Feedback delay до 100 % даёт самовозбуждение и бесконечный рост.
  - Пресет `AVAudioUnitDistortion` не задан явно.
  - Параметры подаются в AU при каждом движении ручки без сглаживания, отсюда возможный «zipper».
- **Как исправить:**
  - Порядок: `VoiceEngine.sourceNode → Distortion → Delay → Reverb → Limiter → mainMixer`, все соединения в формате выхода.
  - Выключенный эффект ставь в `bypass = true`, а не в `wetDryMix = 0`.
  - Маппинг: reverb mix 0..1 → `wetDryMix` 0..50; delay mix 0..1 → 0..50; feedback 0..1 → 0..85 (клэмп); distortion: явно вызови `loadFactoryPreset(.multiDistortedCubed)` или другой выбранный пресет, затем `preGain` в диапазоне −20..+20 и `wetDryMix` 0..100.
  - Опционально: delay time по долям такта от BPM (1/8, 1/8 с точкой, 1/4).
- **Проверка:** офлайн-тест с delay feedback на максимуме и 10 секундами рендера: пик ≤ 0.9 (лимитер) и сигнал затухает после остановки нот. С reverb mix на максимуме RMS сухого удара в первые 5 мс не меньше 40 % от RMS без reverb. **На слух:** при включённом реверберации на максимуме кик остаётся слышен, дисторшн не хрипит на хвостах.

---

## P1 — стабильность и «хреново работает»

### P1-1. Визуализатор и метры: tap вне MainActor, без шторма `@Published`
- **Файлы:** `AudioEngineManager.swift:40-44` (`@Published` для amplitude и `spectrumData`), `:162-178` (`installVisualizerTap`), `:186-221` (`processAudioBuffer`), `:224-280` (`computeSpectrum`: аллокации на `:230` и `:262`). `Features/Visualizer/AudioVisualizerView.swift:84-126` (`AudioVisualizerData`: `Timer` 30 Гц, случайная «волна» на `:108`, лишний `DispatchQueue.main.async` на `:113`).
- **Проблема:**
  - Замыкание tap создаётся в неявно `@MainActor`-классе. В режиме Swift 6 (и при включённых runtime-проверках изоляции) оно будет помечено MainActor и **упадёт** (`_dispatch_assert_queue_fail`), потому что tap вызывается на фоновом аудиопотоке.
  - На каждый буфер tap идёт 3 присваивания amplitude и **32 отдельных** `spectrumData[i] = …`. Это около 35 `objectWillChange` у `AudioEngineManager`, а его наблюдают `MainLayoutView`, `EffectsRackView`, `SoundLibraryView` и `MasterControlView`. В результате весь экран перерисовывается десятки раз в секунду.
  - Состояние FFT (`fftRealBuffer` и т. п.) — это поля MainActor-класса, которые меняются на аудиопотоке.
  - Режим WAVEFORM показывает `Float.random`, а не сигнал.
- **Как исправить:**
  - Вынеси анализ в `nonisolated final class SpectrumAnalyzer`. Он владеет FFT-буферами, выделенными заранее, без аллокаций в цикле. Блок tap создавай в `nonisolated`-методе (`@Sendable`).
  - Результат (32 полосы, пик L/R, RMS L/R) пиши в структуру под `Mutex` или в атомики. Отдельная `@Observable @MainActor final class MeterModel` опрашивает её 30 раз в секунду и присваивает **один раз** (`bands = newBands`).
  - Пиковые уровни можно брать из `VoiceEngine` (P0-5) и не ставить отдельный tap для метров.
  - Из `AudioEngineManager` убери все `@Published`, которые относятся к визуализатору.
  - Waveform: либо настоящие сэмплы (децимированная огибающая последних N мс), либо удали режим.
- **Проверка:** сборка без предупреждений. `rg -n "@Published var (currentAmplitude|spectrumData)" DrumMashine_swistUI` возвращает пусто. В Instruments → SwiftUI (View Body) во время воспроизведения `MainLayoutView.body` не вызывается при каждом обновлении метра (максимум при смене isPlaying или ready). Загрузка CPU приложения в «Мониторинге системы» при Play заметно ниже, чем до правки (запиши цифры в коммит).

### P1-2. Лишние перерисовки UI и неправильное владение синглтонами
- **Файлы:** `UI/Layout/MainLayoutView.swift:9-10`, `Features/EffectsRack/EffectsRackView.swift:8`, `Features/SoundLibrary/SoundLibraryView.swift:8`, `Features/Visualizer/MasterControlView.swift:8`, `Features/Sequencer/PatternSlotsView.swift:9` (все используют `@StateObject private var x = Singleton.shared`). `Features/Sequencer/SequencerView.swift:69-75` и `:153` (все строки и шаги читают `sequencer.currentStep`).
- **Проблема:** `@StateObject` на чужом синглтоне — неверный паттерн: объектом владеет не view. Вместе с P1-1 это даёт полную перерисовку экрана. Каждая смена `currentStep` (8 раз в секунду при 120 BPM) перерисовывает все 8×16–32 `StepButtonView` с blur и shadow. На встроенной графике Intel это заметно тормозит.
- **Как исправить:**
  - Перейди на `@Observable` (`AudioEngineManager`, `PatternManager`) и внедряй их через `.environment(...)` или передавай параметром.
  - Подсветку текущего шага сделай отдельным оверлеем: одна колонка-«курсор», которая смещается по `currentStep`. Тогда `StepButtonView` не зависит от `currentStep`.
  - Строки секвенсора должны получать только свой `SequencerTrack`.
- **Проверка:** сборка. В Instruments → SwiftUI при воспроизведении количество вызовов `StepButtonView.body` за секунду меньше 10 при неизменном паттерне.

### P1-3. Swift 6 concurrency: ноль предупреждений, затем строгий режим
- **Файлы:** `DrumMashine_swistUI.xcodeproj/project.pbxproj:401-421` и `:434-454` (`SWIFT_VERSION = 5.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), `Core/Models/DrumProject.swift:204`, все места из P0-1, P0-4, P1-1.
- **Проблема:**
  - Сейчас 4 предупреждения, и это ошибки в режиме Swift 6.
  - `SequencerEngine` (`@Observable`, неявно MainActor) читается и пишется с `DispatchQueue` (`SequencerEngine.swift:142-178`).
  - `PatternManager` и `SoundLibraryManager` — синглтоны без явной изоляции.
  - `DrumProject.swift:204` — результат `try save(project:)` не используется.
- **Как исправить:**
  - После P0 и P1-1 включи `SWIFT_STRICT_CONCURRENCY = complete` (пока в режиме Swift 5) и исправь всё, что найдётся.
  - Аудиотипы (`VoiceEngine`, `SequencerScheduler`, `SpectrumAnalyzer`, `DrumSynthesizer`) объяви `nonisolated`. UI-модели оставь `@MainActor`.
  - На `:204` напиши `_ = try save(project: project)` или поставь `@discardableResult` на `save`.
  - Когда предупреждений станет 0, отдельным коммитом поставь `SWIFT_VERSION = 6.0`. Если появятся ошибки, которые нельзя аккуратно закрыть, откати этот коммит и опиши причину.
- **Проверка:** команда сборки из правила 3 выдаёт **0** строк `warning:` (кроме appintents). Приложение запускается в режиме Swift 6, Play и Stop работают, падений `dispatch_assert_queue` нет. Проверь `ls ~/Library/Logs/DiagnosticReports | grep -i drum`.

### P1-4. Паттерны: падение при записи, рассинхрон звука и названий
- **Файлы:** `Core/Models/PatternManager.swift:36-57` (`savePattern`), `:60-68` (`loadPattern`), `Core/Sequencer/SequencerEngine.swift:243-263` (`recordPadHit`), `:47-59` (`stepCount.didSet`).
- **Проблема:**
  - `loadPattern` присваивает `sequencer.tracks = pattern.tracks` (по 16 шагов) в обход `stepCount.didSet`. Если выбрано 32 шага, `recordPadHit` пишет в `tracks[i].steps[step]` с `step` до 31 и получается **выход за пределы массива, краш**. Сейчас `currentStep` к тому же обгоняет звук и может быть «не тем» шагом.
  - `loadPattern` не перезагружает звуки в движок: в треке написано «Kick Deep», а играет старый буфер. Громкость и панорама трека тоже не передаются в движок.
  - `stepCount` не сохраняется в паттерн.
- **Как исправить:**
  - Сделай единый метод `SequencerEngine.apply(pattern:)`. Он выравнивает число шагов у всех треков до `max(stepCount, 32)`, вызывает `loadSound` для каждого трека с его пресетом, отправляет `setTrackGain` и обновляет снимок для планировщика.
  - Сохраняй `stepCount` в `DrumPattern` (опциональное поле с дефолтом, чтобы старые данные декодировались).
  - В `recordPadHit` поставь `guard step < tracks[trackIndex].steps.count`, а шаг бери из аудиочасов (см. P1-7).
- **Проверка:** unit-тест: выставить `stepCount = .thirtyTwo`, загрузить слот с 16 шагами, вызвать `recordPadHit` для шагов 0…31, падения нет. Тест: после `apply(pattern:)` у всех треков `steps.count >= stepCount.rawValue`. **На слух:** загрузи слот B с другими звуками, звучат звуки слота B.

### P1-5. Редактор ADSR и Pitch ни на что не влияет
- **Файлы:** `Features/Pads/PadsGridView.swift:64-68` (binding на `tracks[idx].soundPreset`), `Features/SoundEditor/PadADSREditorView.swift:47-90`, `:105`, `:120`. `AudioEngineManager.swift:469-504` (`generateSamplesForPreset` использует только `decay` и `pitch`), `:512-544` (`applyEnvelope` нигде не вызывается).
- **Проблема:** ползунки ATK, DEC, SUS, REL и кнопки PITCH меняют модель, но буфер в движке не перегенерируется. Attack, sustain и release синтез вообще игнорирует. Для пользователя «редактор не работает». Pitch у hi-hat и тарелок тоже игнорируется.
- **Как исправить:**
  - Добавь `onChange(of: sequencer.tracks[idx].soundPreset)` с дебаунсом 150 мс, затем `loadSound(preset:forTrack:)` через `swapSample` из P0-3.
  - Огибающая ADSR накладывается в `DrumSynthesizer.samples(for:)` после генерации. Для барабанов sustain-фазы нет, поэтому трактуй ADSR как attack → decay до уровня sustain → release на хвосте. Учитывай fade-out из P0-2.
  - Сделай pitch для hihat, ride и crash (масштаб частот).
  - Удали мёртвый `applyEnvelope` из `AudioEngineManager`.
- **Проверка:** unit-тест: у пресета с `attack = 0.1` первые 50 мс по RMS тише, чем при `attack = 0`. При `pitch = +12` основная частота kick примерно в 2 раза выше (оценка по пересечениям нуля в первых 20 мс). **На слух:** долгое нажатие на пэд, сдвинуть ATK и DEC: звук меняется через долю секунды.

### P1-6. Превью в библиотеке звуков глушит KICK
- **Файлы:** `AudioEngineManager.swift:425-439` (`previewSound(preset:)` играет на `samplerNodes[0]`), `:442-446` (`previewSound(filename:)`, наследие), `Features/SoundLibrary/SoundLibraryView.swift:121`, `:164`.
- **Проблема:** превью играет на плеере трека 0. Оно обрывает kick и запланированные ноты kick, а также меняет громкость трека. Каждый клик пересинтезирует звук.
- **Как исправить:** выдели в `VoiceEngine` отдельный слот превью (`swapSample(previewSlot, …)` и `trigger(previewSlot, …)`). Сделай кэш сгенерированных превью по `preset.id` с LRU на 16 элементов. Удали `previewSound(filename:)`.
- **Проверка:** офлайн-тест: kick играет каждые 6000 кадров, посреди этого вызывается превью, все начала ударов kick на месте. `rg -n "previewSound\(filename" DrumMashine_swistUI` возвращает пусто.

### P1-7. Пэды: velocity, громкость трека, квантование записи
- **Файлы:** `Features/Pads/DrumPadView.swift:107-112` (`onTap(1.0)` всегда), `Features/Pads/PadsGridView.swift:34-42` (`trigger` без громкости трека, запись через `Task`), `SequencerEngine.swift:247`.
- **Проблема:**
  - Пэд всегда играет с velocity 1.0 и игнорирует громкость трека, поэтому он громче секвенсора.
  - При записи (OVERDUB или REPLACE) удар пишется в `currentStep`, который обгоняет звук на 100 мс и больше. Удары попадают на шаг позже.
- **Как исправить:**
  - Громкость трека применяй в движке (`setTrackGain`), одинаково для пэда и секвенсора.
  - Квантование записи: шаг = `round((renderedFrames - outputLatency - anchor) / samplesPerStep) mod stepCount`, то есть к **ближайшему** шагу по тому, что слышит пользователь.
  - Опционально: velocity от позиции клика по вертикали внутри пэда.
- **Проверка:** unit-тест функции квантования: время на 40 % шага даёт текущий шаг, на 60 % — следующий, на границе цикла 31 переходит в 0. **На слух:** режим REC OVERDUB, отстучать кик в долю: запись совпадает с метрономом паттерна.

---

## P2 — качество

### P2-1. Производительность UI на встроенной графике Intel
- **Файлы:**
  - `UI/Layout/MainLayoutView.swift:38-52` (два круга 400–500 pt с `blur(radius: 90–100)` на весь фон), `:61`, `:154-164` (невидимое кольцо `opacity(0)` с `repeatForever`);
  - `Features/Visualizer/AudioVisualizerView.swift:153-190` (32 столбца, у каждого `blur` и своя `.animation(.spring)`);
  - `Features/Sequencer/StepButtonView.swift:57-66` и `:86-89` (blur и shadow на шаге);
  - `Features/Pads/DrumPadView.swift:56-58`, `:105`;
  - `Features/Visualizer/MasterControlView.swift:94-116` (40 сегментов, каждый со своим `onChange` и `asyncAfter`);
  - `Features/EffectsRack/EffectsRackView.swift:205-209` (вечная пульсация LED).
- **Проблема:** большие blur и тени пересчитываются при каждой анимации. На Mac mini 2018 (UHD 630) это даёт просадки FPS и нагружает главный поток, а он нужен для отклика пэдов.
- **Как исправить:**
  - Фон с glow отрисуй один раз: статичное изображение или `.drawingGroup()` без анимации.
  - Спектр и метры рисуй в `Canvas` внутри `TimelineView(.animation(minimumInterval: 1/30))`, без spring-анимации на каждом столбце.
  - Glow на шаге делай через цвет и обводку, без `blur`.
  - CLIP: один флаг в `MeterModel` с таймером удержания 1 с.
  - Невидимое кольцо удали.
- **Проверка:** Instruments → Core Animation / SwiftUI: при воспроизведении FPS держится на 60, CPU приложения ниже, чем до правки (цифры в коммит).

### P2-2. Декоративные контролы без функции
- **Файлы:** `Features/EffectsRack/EffectsRackView.swift:28-35` (ROOM: `set: { _ in }`), `:110-144` (3-BAND EQ не подключён), `Features/Visualizer/MasterControlView.swift:10` (LIMITER, если P0-5 ещё не подключил), `Features/Sequencer/PatternSlotsView.swift:55-63` (кнопка Copy пустая), `MainLayoutView.swift:273` (захардкожен «808 CLASSIC»).
- **Проблема:** пользователь крутит ручки, а ничего не меняется. Это часть ощущения «хреново работает».
- **Как исправить:**
  - EQ: `AVAudioUnitEQ(numberOfBands: 3)` (lowShelf 120 Гц, parametric 1 кГц, highShelf 8 кГц, ±12 dB) в мастер-цепи перед лимитером, со своим bypass.
  - ROOM: `reverbNode.loadFactoryPreset(...)` из выбора smallRoom, mediumRoom, largeRoom, mediumHall, largeHall. Ручку замени на сегментный выбор.
  - Copy: копируй активный паттерн в следующий пустой слот или удали кнопку.
  - Подпись кита: имя или удалить.
- **Проверка:** сборка. `rg -n "set: \{ _ in \}" DrumMashine_swistUI` возвращает пусто. **На слух:** LOW +12 dB заметно добавляет низа, ROOM меняет хвост.

### P2-3. Качество синтеза и регрессия FX
- **Файлы:** `Core/AudioEngine/DrumSynthesizer.swift:152-189` (hi-hat: прямоугольные волны без ограничения полосы и однополюсный HPF), `:244-275` (tom: линейный спад высоты), `:26-28` (`Double.random` на каждый сэмпл). `AudioEngineManager.swift:596-621` (FX).
- **Проблема:**
  - Hi-hat собран из 6 «наивных» прямоугольников. Это алиасинг и жёсткий «цифровой» звон. Однополюсный HPF на 7 кГц слабый, и низ (263–845 Гц) просачивается.
  - У tom неестественный линейный спад высоты.
  - Коммит `fix1` **удалил** ветки `vinyl`, `reverse`, `impact`, `glitch` в FX: пресеты «Vinyl Crk», «Reverse», «Impact» и «Glitch» теперь звучат одинаково, как шум. Старые ветки есть в `6db9e7a`.
  - Денормалы: Мак на Intel, а на x86 денормализованные float в хвостах экспоненциальных фильтров резко замедляют расчёт.
- **Как исправить:**
  - Hi-hat: синтезируй на 2× частоте и децимируй, либо используй PolyBLEP-прямоугольники. Добавь биквадный bandpass и HPF второго порядка (≈ 7–10 кГц).
  - Tom: экспоненциальная огибающая высоты, как у kick.
  - Верни ветки FX из прошлой версии (`git show 6db9e7a:DrumMashine_swistUI/DrumMachine/Core/AudioEngine/AudioEngineManager.swift`), переложив их в `DrumSynthesizer`.
  - Быстрый детерминированный RNG (xorshift) с сидом. Заодно получится повторяемость в тестах.
  - В фильтрах и в render-сглаживании прибавляй `1e-20` или зануляй `|x| < 1e-15`.
- **Проверка:** тест: у 10 FX-пресетов попарно разные спектральные центроиды. Тест: у hi-hat энергия ниже 2 кГц меньше −30 dB от общей. **На слух:** хэт звучит «металлически», а не «пищит». Vinyl, Reverse и Impact отличаются.

### P2-4. Сохранение данных
- **Файлы:** `Core/Models/PatternManager.swift:86-101` (`try?` глушит ошибки, у формата нет версии), `Core/Models/DrumProject.swift:31` (`swing: Double = 0.5`, а в секвенсоре шкала 0…100), `:32` и `:308` (`masterVolume` всегда 1.0), `:109` (`appendingPathComponent("Exports/…", isDirectory: true)`: файл записывается по пути-«папке», и `write` падает). `DrumProjectManager` нигде не используется. `project.pbxproj:404` и `:437` (`ENABLE_USER_SELECTED_FILES = readonly`).
- **Как исправить:**
  - `PatternManager`: логируй ошибки через `Logger`, добавь поле `version` и миграцию, сохраняй с дебаунсом.
  - `DrumProject`: та же шкала swing (0…100), `masterVolume` бери из модели, исправь путь экспорта (`isDirectory: false`).
  - Если экспорт и импорт подключаются к UI, используй `NSSavePanel` или `.fileExporter`, а sandbox переведи на `ENABLE_USER_SELECTED_FILES = readwrite`. Если не подключаются, удали `DrumProjectManager` (см. P2-5).
- **Проверка:** unit-тест: туда-обратно `encode` → `decode` паттерна со `stepCount = 32` и `swing = 55` даёт те же данные. Повреждённые данные в UserDefaults приводят к 4 пустым слотам, без падения, ошибка в логе.

### P2-5. Мёртвый код, гигиена репозитория, документация
- **Файлы:**
  - `ContentView.swift` («Hello, world», не используется);
  - `Features/Modulation/ModulationView.swift`, `Utilities/HapticManager.swift`, `UI/Components/ToggleButtonView.swift`, `Features/Visualizer/WaveformView.swift` (новые, в основном UI не подключены; хаптика только под iOS);
  - ветки `#if canImport(UIKit)` по всему UI (в macOS-приложении это мёртвый код);
  - `firebase-debug.log` в корне;
  - нет `.gitignore`, поэтому в репозиторий попадают `xcuserdata`;
  - `progress.md`, `QUICK_SUMMARY.md`, `ANALYSIS_SUMMARY.md` с неверными заявлениями.
- **Как исправить:**
  - Удали или подключи неиспользуемые файлы. Хаптику на macOS можно делать через `NSHapticFeedbackManager` для трекпада, иначе удали.
  - Добавь `.gitignore`: `xcuserdata/`, `*.xcuserstate`, `.DS_Store`, `firebase-debug.log`, `DerivedData/`.
  - Перепиши `progress.md` по фактическому состоянию после P0 и P1.
- **Проверка:** сборка и тесты зелёные. `git status` чистый после коммита.

### P2-6. Мелкие баги и покрытие тестами
- **Файлы:** `SequencerEngine.swift:267-291` (tap tempo на `Date()`, то есть на системных часах, которые могут прыгать), `:32-41` (повторное присваивание `bpm` в `didSet`).
- **Как исправить:**
  - Tap tempo считай по монотонным часам (`ContinuousClock` или `ProcessInfo.processInfo.systemUptime`), бери медиану последних 4 интервалов.
  - BPM ограничивай в сеттере модели без рекурсивного `didSet`.
  - Добавь unit-тесты для планировщика (swing, humanize в пределах, смена stepCount на лету), для квантования записи и для туда-обратно сериализации.
- **Проверка:** команда тестов проходит. Покрытие логики `SequencerScheduler`, `DrumSynthesizer` и квантования не меньше 80 % (Xcode → Report Navigator → Coverage, с `-enableCodeCoverage YES`).

---

## Сводка

| Приоритет | Задачи |
|---|---|
| P0 (звук) | P0-0 … P0-7 — 8 задач |
| P1 (стабильность) | P1-1 … P1-7 — 7 задач |
| P2 (качество) | P2-1 … P2-6 — 6 задач |

В конце работы напиши в `progress.md` короткий отчёт: какие коммиты сделаны, какие тесты добавлены, какие цифры по CPU и FPS получились до и после, и список пунктов «на слух» для nixter.
