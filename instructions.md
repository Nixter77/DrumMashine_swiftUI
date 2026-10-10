# Инструкции по разработке Drum Machine для iOS (SwiftUI)

Ты — **Senior iOS Engineer** и **Sound Designer** с глубокой экспертизой в SwiftUI, AVFoundation, AudioKit и Apple HIG (Human Interface Guidelines). Твоя задача — спроектировать и написать полнофункциональный Drum Machine для iPad/iPhone, который выглядит как нативное приложение Apple уровня GarageBand — минималистично, мощно и красиво.

---

## Общая архитектура проекта

Проект должен быть строго модульным — каждый компонент в отдельном файле/папке:

```
DrumMachine/
├── App/
│   └── DrumMachineApp.swift
├── Core/
│   ├── AudioEngine/
│   │   ├── AudioEngineManager.swift       # AVAudioEngine singleton
│   │   ├── SamplerNode.swift              # AVAudioUnitSampler обёртка
│   │   └── EffectsChain.swift             # reverb, delay, distortion
│   ├── Sequencer/
│   │   ├── SequencerEngine.swift          # логика шагов, BPM, swing
│   │   ├── SequencerStep.swift            # модель одного шага (on/off, velocity)
│   │   └── SequencerTrack.swift           # трек = один инструмент + 16 шагов
│   └── Models/
│       ├── DrumKit.swift                  # набор звуков (Kit)
│       ├── DrumPad.swift                  # модель пэда
│       └── SoundPreset.swift              # пресет звука + эффекты
├── SoundLibrary/
│   ├── SoundLibraryManager.swift          # загрузка и управление звуками
│   └── Sounds/                            # .wav / .aiff файлы (10-15 звуков)
│       ├── kick_01.wav
│       ├── snare_01.wav
│       ├── hihat_closed.wav
│       └── ...
├── Features/
│   ├── Pads/
│   │   ├── PadsGridView.swift             # 8 пэдов в сетке
│   │   └── DrumPadView.swift              # один пэд с velocity-чувствительностью
│   ├── Sequencer/
│   │   ├── SequencerView.swift            # основная сетка секвенсера
│   │   ├── SequencerRowView.swift         # одна строка (трек)
│   │   └── StepButtonView.swift           # кнопка шага с velocity индикатором
│   ├── SoundEditor/
│   │   ├── SoundEditorView.swift          # Sheet/Panel редактора звука
│   │   ├── PitchTuneView.swift            # pitch, tune
│   │   └── EnvelopeView.swift             # ADSR envelope визуально
│   ├── EffectsRack/
│   │   ├── EffectsRackView.swift          # список подключённых эффектов
│   │   ├── ReverbView.swift
│   │   ├── DelayView.swift
│   │   └── DistortionView.swift
│   ├── Modulation/
│   │   └── ModulationView.swift           # LFO назначение на параметры
│   ├── SoundLibrary/
│   │   ├── SoundLibraryView.swift         # браузер звуков
│   │   └── SoundLibraryCell.swift
│   └── Visualizer/
│       ├── AudioVisualizerView.swift      # визуальный аудио-выход
│       └── WaveformView.swift             # осциллограф реального времени
├── UI/
│   ├── Components/
│   │   ├── KnobView.swift                 # кастомный круглый нобель
│   │   ├── SliderView.swift               # кастомный слайдер
│   │   ├── VUMeterView.swift              # VU-метр
│   │   └── ToggleButtonView.swift
│   ├── Theme/
│   │   ├── AppTheme.swift                 # цвета, радиусы, тени
│   │   └── Typography.swift              # шрифты SF Pro
│   └── Layout/
│       └── MainLayoutView.swift           # корневой layout
└── Utilities/
    ├── HapticManager.swift                # тактильная обратная связь
    └── Extensions/                        # Color+Ext, View+Ext и т.д.
```

---

## Дизайн — Apple Style

### Принципы
- **Тема:** Dark Mode как основная. Материалы `.ultraThinMaterial`, `.regularMaterial`.
- **Цветовая палитра:**
  - **Background:** `#0A0A0F` (почти чёрный)
  - **Surface:** `#1C1C1E` (системный Apple dark)
  - **Accent:** `#FF6B35` (оранжевый, как у Logic Pro X) + `#0A84FF` (Apple blue)
  - **Active step:** яркий accent glow
  - **Inactive step:** `#2C2C2E`
- **Типографика:** SF Pro Rounded для заголовков, SF Pro Text для данных, SF Mono для BPM/значений.
- **Форм-фактор:** оптимизировано под iPad landscape + iPhone portrait адаптация.
- **Анимации:** `withAnimation(.spring(response: 0.3, dampingFraction: 0.7))` для всех состояний.
- **Геометрия:** `cornerRadius(12)` для секций, `cornerRadius(8)` для кнопок.
- **Тени:** `shadow(color: .black.opacity(0.4), radius: 8, y: 4)`.

---

## Модули — детальные требования

### 1. 🎛 AudioEngineManager
- **Singleton** через `@MainActor`.
- **AVAudioEngine** с несколькими `AVAudioPlayerNode` (по одному на трек).
- Поддержка одновременного воспроизведения всех треков.
- Мастер-шина с `AVAudioUnitReverb` и `AVAudioUnitDelay`.
- **Методы:**
  - `func play(sound: SoundPreset, velocity: Float)`
  - `func stop()`
  - `func updateEffect(_ effect: AudioEffect, value: Float)`
- Использовать `AVAudioPCMBuffer` для низкой латентности.

### 2. ⏱ SequencerEngine
- `@Observable` class (Swift 5.9+).
- **BPM:** 60–200, по умолчанию 120.
- **Количество шагов:** 16 (с возможностью 8/16/32).
- **Swing:** 0–100%.
- **Метроном:** опциональный.
- Таймер на `DispatchQueue.global(qos: .userInteractive)` или AudioKit Clock.
- Для каждого шага хранить: `isActive: Bool`, `velocity: Float` (0.0–1.0), `probability: Float`.
- **Функции:** Play/Pause/Stop/Record.
- **Состояние:** Текущий активный шаг — `@Published currentStep: Int`.

### 3. 🎹 PadsGridView
- 8 пэдов в сетке 2×4 или 4×2.
- **DrumPadView:**
  - Pressure-чувствительный через `DragGesture` (симуляция velocity по скорости нажатия).
  - При тапе: haptic feedback (`.impactOccurred(intensity: velocity)`).
  - Glow-эффект при активации: `.shadow(color: padColor.opacity(0.8), radius: 12)`.
  - Отображение имени звука и иконки (SF Symbol).
  - Long press → открыть `SoundEditorView` как `.sheet`.
  - Каждый пэд можно перекрасить (8 предустановленных цветов).

### 4. 🎚 SoundEditorView (Sheet Panel)
- **Параметры редактирования для каждого пэда:**
  - **Pitch:** -24 до +24 полутонов (`KnobView`).
  - **Tune:** -100 до +100 центов (`KnobView`).
  - **Volume:** 0–100% (кастомный `SliderView`).
  - **Pan:** L-R (`SliderView`).
  - **ADSR Envelope:**
    - Attack: 0–2000ms
    - Decay: 0–2000ms
    - Sustain: 0–100%
    - Release: 0–5000ms
    - Визуальная ADSR кривая (Canvas рисование Path).
  - **Reverse:** Bool toggle.
  - **Choke Group:** 1-4 (нобель).

### 5. 🔊 EffectsRackView
- **Эффекты на каждый трек + мастер-шина:**
  - **Reverb:** Room Size, Damping, Wet/Dry.
  - **Delay:** Time (в долях: 1/4, 1/8, 1/16), Feedback, Mix.
  - **Distortion:** Drive, Tone, Mix (визуализация wave clipping на Canvas).
  - **Compressor:** Threshold, Ratio, Attack, Release.
  - **Filter (Low/High/Band pass):**
    - Cutoff frequency (логарифмическая шкала).
    - Resonance (Q).
    - Визуализация frequency response кривой.

### 6. 〰️ ModulationView
- **LFO модуляция:**
  - **LFO Shape:** Sine / Square / Triangle / Saw / Random.
  - **Rate:** 0.1–20 Hz (синхронизируется с BPM при включении Sync).
  - **Depth:** 0–100%.
  - **Destination:** Volume / Pan / Pitch / Filter Cutoff / Effect Param.
  - **Визуализация:** LFO волны в реальном времени (Canvas + TimelineView).
  - До 2 LFO на трек.

### 7. 📚 SoundLibraryView
- **Встроенная библиотека:**
  - **Категории:** Kicks, Snares, Hi-Hats, Percussion, FX, Cymbals.
  - **UI:** список с preview (тап = воспроизведение), drag-and-drop на пэд.
  - Поиск по имени.
  - Фильтр по категории (горизонтальный chip-скролл).

### 8. 📊 AudioVisualizerView
- **Визуальное представление аудио-выхода:**
  1. **Waveform (осциллограф):** обновление через `TimelineView` (60fps), `AVAudioEngine` tap на `mainMixerNode`, Canvas + Path.
  2. **Spectrum Analyzer:** FFT через Accelerate framework (`vDSP_fft_zrip`), 32 бара частот с анимацией falloff.
  3. **VU Meter (стерео):** вертикальные бары L/R, цвет: зелёный → жёлтый → красный, Clip индикатор.
  4. **Beat indicator:** пульсирует в такт BPM.

### 9. 🎯 Velocity в секвенсере
- **На каждом StepButtonView:**
  - Short tap → включить/выключить шаг (`velocity = 0.8` default).
  - Long press + drag up/down → изменить velocity.
  - **Визуализация:** высота заливки кнопки = velocity (снизу вверх).
  - Цвет яркости зависит от velocity (темнее = тише).
  - При `velocity > 0.9` — показывать маленький ⚡️ индикатор.
  - Tooltip при drag: "Vel: 87".

---

## Главный экран — Layout

```text
┌────────────────────────────────────────────────────────────┐
│  [◀ Kit Name ▶]     BPM: [120] ±    SWING [──●──]   [▶ ■] │
├──────────┬─────────────────────────────────────────────────┤
│  PADS    │              SEQUENCER GRID                      │
│  [K][S]  │  KICK  ○●○○ ○●○○ ○○○● ○○○○  [Vol][FX][MOD]    │
│  [H][C]  │  SNARE ○○○○ ●○○○ ○○○○ ●○○○  [Vol][FX][MOD]    │
│  [O][R]  │  HIHAT ●○●○ ●○●○ ●○●○ ●○●○  [Vol][FX][MOD]    │
│  [P][X]  │  CLAP  ○○○○ ●○○○ ○○○○ ○●○○  [Vol][FX][MOD]    │
│          │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ + (Add Track)   │
├──────────┴──────────────┬──────────────────────────────────┤
│   AUDIO VISUALIZER      │   MASTER FX  │  SOUND LIBRARY    │
│   ≋≋≋≋≋≋≋ waveform ≋≋≋ │  [REV][DLY]  │  [Browse Sounds]  │
│   ████▓▒░ VU meter      │  [COMP][EQ]  │                   │
└─────────────────────────┴──────────────┴───────────────────┘
```

---

## Технический стек

| Слой | Технология |
| :--- | :--- |
| **UI Framework** | SwiftUI 5.0+ |
| **State Management** | `@Observable` (Swift 5.9), `@StateObject`, `@EnvironmentObject` |
| **Audio Engine** | AVFoundation (`AVAudioEngine`, `AVAudioPlayerNode`) |
| **DSP / FFT** | `Accelerate.framework` (vDSP) |
| **Haptics** | `CoreHaptics` + `UIImpactFeedbackGenerator` |
| **Drawing** | Canvas API (SwiftUI) |
| **Animation** | `TimelineView`, `withAnimation`, `matchedGeometryEffect` |
| **Data** | Swift `Codable` + `UserDefaults` (сохранение паттернов) |
| **Concurrency** | Swift Concurrency (async/await, Actor) |
| **Min Target** | iOS 17.0 / iPadOS 17.0 |

---

## Кастомные UI-компоненты

### KnobView
- **Круглый регулятор в стиле Logic Pro:**
  - Жест: вертикальный drag (вверх = +, вниз = -).
  - Диапазон: любой через generic `Binding<Double>`.
  - Визуал: дуга прогресса на Canvas, метка значения под нобелем.
  - Double tap → сброс к дефолту.
  - Haptic tick каждые 10% поворота.
  - Размер: 44×44 (compact), 64×64 (regular).

### StepButtonView
- **Кнопка шага секвенсера:**
  - Состояния: off / on / active (текущий воспроизводимый).
  - Velocity fill: заливка снизу, высота = velocity * кнопки.
  - Active pulse: `@State animatingPulse` с `ScaleEffect` + `opacity`.
  - Цвет: accent при on, `.systemGray5 при off`, белый при active.

---

## Сохранение и загрузка

```swift
// Модель проекта DrumProject: Codable
struct DrumProject: Codable, Identifiable {
    var id: UUID
    var name: String
    var bpm: Double
    var swing: Double
    var tracks: [SequencerTrack]
    var masterEffects: EffectsChain
    var createdAt: Date
}
```

- Сохранение в Documents directory как JSON.
- Список проектов на стартовом экране (`NavigationSplitView`).
- Поддержка iOS Share Sheet для экспорта проекта.

---

## Инструкции по генерации

1. Начни с `AudioEngineManager.swift` — весь аудио-стек должен работать до UI.
2. Затем `SequencerEngine.swift` — логика без UI.
3. Затем базовые модели — `DrumPad`, `SequencerStep`, `SequencerTrack`.
4. Потом UI снизу вверх: `KnobView` → `StepButtonView` → `SequencerRowView` → `SequencerView` → `MainLayoutView`.
5. Каждый файл должен начинаться с комментария `// MARK: - [ModuleName]` и содержать `// MARK: - Preview` в конце.
6. Preview для каждого View с реалистичными mock-данными.
7. Не используй сторонние зависимости — только Apple frameworks.
8. Весь текст в UI через `LocalizedStringKey` (подготовка к локализации).
9. Пиши production-ready код: `guard let`, proper error handling, memory management.
10. Добавляй `// TODO: Phase 2` комментарии для расширений (MIDI, AUv3, Cloud sync).

---

## Дополнительные фичи (бонус)

- **Undo/Redo** через `UndoManager` для изменений в секвенсере.
- **Shake to randomize** — случайный паттерн через `CMMotionManager`.
- **Copy/Paste** паттернов между треками.
- **Mute / Solo** на каждом треке.
- Цветовая схема пэдов сохраняется с проектом.
- **Live Record mode:** тап по пэдам записывает шаги в реальном времени.
