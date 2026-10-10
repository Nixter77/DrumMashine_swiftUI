# GROK_BUILD_TASKS_2 — раскладка окна, сохранение, тесты, библиотека звуков (DrumMashine_swistUI)

> Составлено 08.10.2026 (≈03:20 IDT) по коду на коммите `b7be7a9 P2-6: time tap tempo on a monotonic clock`, это HEAD ветки `main`, `git status` чистый. Сборка на этом коммите: `** BUILD SUCCEEDED **`.
> Первый план (`GROK_BUILD_TASKS.md`, задачи P0-0 … P2-6) выполнен. Звук, по словам nixter, теперь чистый. Этот файл — следующий этап.
> Номера строк указаны по `b7be7a9`. После первых правок они сдвинутся, поэтому ищи по имени функции или свойства.

## Контекст

macOS-приложение на SwiftUI: deployment target 15.6, `SWIFT_VERSION = 6.0`, App Sandbox включён (`project.pbxproj:401`, `:435`), `ENABLE_USER_SELECTED_FILES = readonly` (`:404`, `:438`), bundle id `Home.DrumMashine-swistUI`. Unit-тесты запускаются **внутри приложения** (`TEST_HOST`, `project.pbxproj:477`, `:498`), поэтому они видят тот же `UserDefaults`, что и живое приложение nixter.

nixter жалуется на две вещи:
1. **Раскладка сломана.** Большая зелёная кнопка Play слева в транспорте обрезана наполовину краем окна, правая панель (SWING/HUMAN, секвенсор) наезжает на транспорт, а дизайн в целом выглядит «странно».
2. **Ничего не сохраняется.** Готовые пресеты и паттерны после перезапуска пропадают, и программой почти невозможно пользоваться.

Плюс он хочет **библиотеку звуков побольше** (раздел D).

### Почему обрезан Play (найдено в коде)

- Левая колонка жёстко задана шириной **360 pt** (`UI/Layout/MainLayoutView.swift:113`). Транспорт внутри неё (`:137-273`) — это `HStack(spacing: 16)` из элементов **фиксированной** ширины: Play 68 (`:153`), блок BPM 30+4+68+4+30 = 136 (`:184-215`, число BPM `:202`), `Spacer(minLength: 8)` (`:242`), бейдж «кита» (`:246-264`) и `PatternSlotsView` ≈ 227 pt (`Features/Sequencer/PatternSlotsView.swift:9-56`: «PAT» + кнопка копирования 22 + 4 слота по 36 (`:113`) + отступы).
- Итого транспорт хочет ≈ **490 pt**, а места есть 360 − 2×14 (`:270`) = **332 pt**. SwiftUI не умеет сжать фиксированные `frame`, поэтому `HStack` становится шире своей колонки и **центрируется** в ней. Лишние ≈ 155 pt вылезают поровну в обе стороны, примерно по 75 pt. Слева их срезает край окна (отсюда половина кнопки Play), справа транспорт уходит **под** правую колонку (слот D и бейдж «KICK» спрятаны под панелью SWING/HUMAN). Расчёт сделан по коду, не замерен.
- Единственный гибкий элемент — кнопка `TAP TEMPO` с `.frame(maxWidth: .infinity)` (`:226-229`). При нехватке места она сжимается почти до нуля. Похоже, тонкая синяя полоска под «120» на скриншоте — это она и есть.
- Бейдж «кита» (`:246`) показывает имя звука **первого трека** («KICK»), а не имя кита. Он вводит в заблуждение и занимает место.
- Правая колонка тоже собрана из фиксированных ширин: `sequencerControlBar` (`:276-360`) со слайдерами 80 (`:285`, `:299`), подписями 32, пикером REC 190 (`:323`), кнопками CLEAR/RANDOM. Это ≈ 830 pt. У строк секвенсора фиксированные колонки 64+58+74+64 (`Features/Sequencer/SequencerView.swift:21`, `:46-48`), библиотека — 280 (`MainLayoutView.swift:127`). Минимальная ширина всего окна ≈ **1225 pt**.
- **Минимального размера окна нет**: `WindowGroup` в `DrumMashine_swistUIApp.swift:14-17` не задаёт ни `.defaultSize`, ни `.windowResizability`, а корневой view — ни `minWidth`, ни `minHeight`. Если окно уже ≈ 1225 pt, правая колонка тоже переполняется, центрируется и **наезжает на пэды** слева.
- По высоте: 8 строк по 42 pt (`SequencerView.swift:294`) без `ScrollView` (`:59`) плюс нижний ряд 220 pt (`MainLayoutView.swift:129`). Правой колонке нужно ≈ 770 pt, в окне ниже ≈ 800 pt строки обрезаются.
- Редактор ADSR открывается **оверлеем внутри панели пэдов** шириной 360 (`Features/Pads/PadsGridView.swift:51-78`), поэтому ему тесно.

### Почему не сохраняются пресеты и паттерны (найдено в коде)

- **Единственное, что вообще пишется на диск, — 4 слота паттернов A–D** (`Core/Models/PatternManager.swift`, ключ `drum_machine_patterns_v2` в `UserDefaults`, `:91`, `:193`). Больше ничего не сохраняется:
  - текущая сетка шагов, BPM, swing, humanize и длина паттерна живут только в памяти `SequencerEngine` (`Core/Sequencer/SequencerEngine.swift:63-116`);
  - выбранные звуки, ADSR и pitch пэдов лежат в `tracks[i].soundPreset` (`PadsGridView.swift:61-65`), тоже только в памяти;
  - эффекты (`AudioEngineManager.swift:99`, `effectsChain`), громкость мастера и лимитер (`Features/Visualizer/MasterControlView.swift:5-6`, это `@State`) сбрасываются при каждом запуске.
- **Слот сохраняется только долгим нажатием** (≥ 0.5 с) на A/B/C/D (`PatternSlotsView.swift:43-53`, `:117-121`) или кнопкой копирования. Подсказки нет. Изменения сетки **ничего не планируют на сохранение**: `scheduleSave()` вызывают только `savePattern` и `clearPattern(slot:)` (`PatternManager.swift:129`, `:159`). Поэтому сброс при уходе в фон или выходе (`:229-244`) сохраняет только то, что пользователь уже явно положил в слот.
- **При запуске ничего не загружается в секвенсор.** `SequencerEngine.init` (`SequencerEngine.swift:132-149`) создаёт 8 пустых треков с заглушками `"sound_0"…"sound_7"` (`:141-144`). Ни один слот не применяется, `activePatternIndex` не сохраняется.
- **Обычный клик по слоту стирает сетку.** Клик вызывает `loadPattern` (`PatternSlotsView.swift:39-42` → `PatternManager.swift:149-153`). Пустой слот всё равно существует (их всегда 4, `:224-226`), поэтому он загружается и затирает несохранённую сетку.
- **Пресеты получают новые UUID при каждом запуске.** `SoundLibraryManager.make` вызывает `UUID()` (`SoundLibrary/SoundLibraryManager.swift:123`), так что ссылка на заводской пресет по `id` после перезапуска ни на что не указывает. **Пользовательских пресетов в коде нет вообще**: нет модели, хранилища и кнопки «сохранить».
- **Ошибки проглатываются или не видны.**
  - `PatternManager.loadError` (`:100`) пишется, но **нигде в UI не показывается** (`rg loadError` находит только `PatternManager.swift`).
  - `UserDefaults.set` (`:193`) не сообщает об ошибке записи.
  - При ошибке чтения `patterns = []` (`:213-218`), то есть 4 пустых слота. Следующее же сохранение **перезаписывает** нечитаемые данные, без резервной копии.
- **Хрупкий Codable.** Синтезированный `Decodable` требует наличия ключа даже для свойства со значением по умолчанию (`SoundPreset.swift:4-22`, `SequencerTrack`, `SequencerStep`, `EffectsChain`). Добавишь новое поле в `SoundPreset` (а раздел D это делает), и все старые сохранения перестанут читаться и будут затёрты (см. предыдущий пункт).
- **Тесты трогают настоящие данные nixter.** Тест `corruptPatternSaveFallsBackToFourEmptySlots` (`DrumMashine_swistUITests/DrumMashine_swistUITests.swift:781-808`) записывает `"not-json"` в **настоящий** `UserDefaults.standard` приложения и восстанавливает его в `defer`. Если тест упадёт или процесс убьют между записью и `defer`, данные пропадут. Тест `loadingASixteenStepSlot…` (`:693-730`) меняет `PatternManager.shared.patterns` на живом синглтоне.
- **Sandbox не мешает.** `UserDefaults` и `Application Support` внутри контейнера (`~/Library/Containers/Home.DrumMashine-swistUI/Data/Library/…`) пишутся без дополнительных entitlement. `readonly` для user-selected files достаточно для импорта сэмплов (D-4). `readwrite` нужен только для экспорта (B-7).

### Что сейчас лежит на диске (проверено, только чтение)

`~/Library/Containers/Home.DrumMashine-swistUI/Data/Library/Preferences/Home.DrumMashine-swistUI.plist` → ключ `drum_machine_patterns_v2`, 58 157 байт, старый формат «голый массив» (до P2-4), 4 слота, **во всех 0 активных шагов**. В слотах есть поле `stepCount`, значит, их записала сборка между `1e98709 P1-4` (01:43) и `0730516 P2-4` (02:48) 08.10, скорее всего долгим нажатием на слот или кнопкой копирования: приложение записывает все 4 слота разом. Time Machine на Маке не настроен. **Восстановить старые паттерны и звуки неоткуда.** Миграция обязана сохранить и этот блок, но ценности в нём нет.

## Правила работы (обязательно)

1. **Базовая точка** — коммит `b7be7a9`, он собирается. Перед началом проверь, что `git status` чистый. Допускается только этот файл, закоммить его отдельно (`docs: add GROK_BUILD_TASKS_2`). Remote нет, ничего не пушь.
2. **Каждая задача = отдельный коммит** (большую задачу можно коммитить по шагам). Сообщение начинай с ID задачи, например `B-2: file store in Application Support with atomic writes`. Не смешивай задачи в одном коммите.
3. **Сборка всегда зелёная.** После каждого коммита выполняй:
   ```bash
   cd . && \
   xcodebuild -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI \
     -destination 'platform=macOS' -derivedDataPath ./DerivedData build 2>&1 \
     | grep -E "warning:|error:|BUILD" | grep -v appintentsmetadataprocessor
   ```
   Ожидаемый результат: `** BUILD SUCCEEDED **`, новых предупреждений нет. Не глуши Swift 6 через `@preconcurrency`, `nonisolated(unsafe)` или `@unchecked Sendable` без комментария, объясняющего безопасность.
4. **Тесты** — после каждого коммита, начиная с B-0:
   ```bash
   xcodebuild -project DrumMashine_swistUI.xcodeproj -scheme DrumMashine_swistUI \
     -destination 'platform=macOS' -derivedDataPath ./DerivedData \
     test -only-testing:DrumMashine_swistUITests
   ```
   UI-тесты (C-3, A-5) запускай отдельно: `-only-testing:DrumMashine_swistUIUITests`.
5. **Не трогай данные nixter.** До B-0 не запускай unit-тесты: они пишут в его настоящий `UserDefaults`. Никогда не удаляй ключ `drum_machine_patterns_v2` и файлы в контейнере приложения. Миграция только копирует.
6. Логи: `/usr/bin/log show --last 10m --style compact --predicate 'process BEGINSWITH "DrumMashine"' | grep -iE "persist|save|load|error|fault"`.
7. Запуск: `open ./DerivedData/Build/Products/Debug/DrumMashine_swistUI.app`.
8. Ты не видишь экран и не слышишь звук. Для каждой задачи есть **автопроверка** (тест, лог или снимок) и пункт **«руками»** для nixter. Собери пункты «руками» в отчёт в конце.
9. **Порядок:** B-0 → A-1 → A-2 → B-1 → B-2 → B-3 → C-1 → B-4 → B-5 → B-6 → C-2 → C-3 → A-3 → A-4 → A-5 → B-7 → D-0 → D-1 → D-2 → D-3 → D-4 → D-5. B-0 идёт первым, потому что без него тесты могут затереть данные. A-1 и A-2 — быстрые: nixter сразу увидит целую кнопку Play.
10. Для тестов и UI добавляй `accessibilityIdentifier` (сейчас их в проекте нет): `transport.play`, `transport.bpm`, `transport.bpm.plus`, `pattern.slot.A…D`, `seq.step.<track>.<step>`, `seq.panel`, `pads.panel`, `library.panel`.

---

## A — раскладка окна

### A-1. Минимальный и стартовый размер окна
- **Файлы:** `DrumMashine_swistUIApp.swift:14-17`, `UI/Layout/MainLayoutView.swift:7-31` (`body`).
- **Проблема:** у окна нет минимального размера, и его можно сжать так, что колонки переполняются и наезжают друг на друга (см. «Почему обрезан Play»).
- **Как исправить:**
  - В `WindowGroup` добавь `.defaultSize(width: 1440, height: 900)` и `.windowResizability(.contentMinSize)`.
  - В корне `MainLayoutView` поставь `.frame(minWidth: AppLayout.minWindow.width, minHeight: AppLayout.minWindow.height)`. Константы вынеси в `UI/Theme/AppLayout.swift`: стартовое значение 1100×720, финальное подгони после A-2…A-4 так, чтобы на минимуме ничего не обрезалось.
  - Магические числа ширин (360, 280, 220, 110, 44) тоже перенеси в `AppLayout`, чтобы правки были в одном месте.
- **Проверка:** сборка. Тест из A-5 (минимальный размер). **Руками:** окно нельзя сжать меньше минимума. Первый запуск после удаления сохранённого кадра окна открывает 1440×900.

### A-2. Транспорт на всю ширину окна, адаптивный, Play всегда целиком
- **Файлы:** `MainLayoutView.swift:98-134` (`mainContent`), `:137-273` (`transportBar`), `:276-360` (`sequencerControlBar`), `Features/Sequencer/PatternSlotsView.swift:9-56`.
- **Проблема:** транспорт ≈ 490 pt зажат в колонку 360 pt и центрируется с переполнением. Play срезан краем окна, слоты A–D уходят под правую панель, `TAP TEMPO` схлопнут.
- **Как исправить:**
  - Вынеси транспорт в отдельный `Features/Transport/TransportBarView.swift` и поставь его **над обеими колонками** на всю ширину окна: `VStack { TransportBarView; HStack { левая колонка; правая колонка } }`. Туда же перенеси элементы `sequencerControlBar` (SWING, HUMAN, REC, CLEAR, RANDOM). Получится одна верхняя панель, как у железных драм-машин.
  - Используй `ViewThatFits(in: .horizontal)` с двумя вариантами:
    - **широкий**, одна строка: `[Play] [− BPM + / TAP] [PAT A B C D ⧉] | [SWING] [HUMAN] [REC] … [CLEAR] [RANDOM]`;
    - **компактный**, две строки: в первой Play, BPM и слоты, во второй SWING, HUMAN, REC и кнопки.
  - У Play: `.fixedSize()`, `.layoutPriority(2)`, размер 56–64 pt. Никаких отрицательных `offset` и выхода за `padding`. Слайдерам SWING и HUMAN дай `.frame(minWidth: 70, idealWidth: 100, maxWidth: 140)` вместо жёстких 80. Пикеру REC — `minWidth 150`.
  - Бейдж «кита» (`:246-264`) удали. Имя кита вернётся в D-3, когда появятся настоящие киты.
  - У `TAP TEMPO` убери `maxWidth: .infinity` и задай нормальную минимальную ширину, чтобы надпись читалась.
- **Проверка:** сборка. Тест A-5: на минимальном размере окна кадр `transport.play` целиком внутри окна и не пересекается с `seq.panel` и `pads.panel`. **Руками:** Play — целый круг. BPM, TAP TEMPO и слоты A–D видны полностью при любом размере окна от минимального до полноэкранного.

### A-3. Гибкие колонки и библиотека звуков в инспекторе
- **Файлы:** `MainLayoutView.swift:101-115` (левая колонка `.frame(width: 360)`), `:118-132` (правая колонка), `:123-129` (эффекты + библиотека 280 × 220).
- **Проблема:** ширины колонок фиксированы, и при нехватке места панели переполняются и наезжают друг на друга.
- **Как исправить:**
  - Левая колонка (пэды, визуализатор, мастер): `.frame(minWidth: 300, idealWidth: 360, maxWidth: 440)`. Правая: `.frame(minWidth: 640, maxWidth: .infinity)`. `HStack(spacing: 12)` с одинаковыми внешними отступами 12.
  - Библиотеку звуков вынеси в `.inspector(isPresented:)` (macOS 14+, у нас 15.6) с кнопкой в тулбаре (`books.vertical`). Ширина инспектора 260–340. Нижний ряд справа тогда занимают только эффекты, у которых уже есть горизонтальный `ScrollView` (`EffectsRackView.swift:7`). Стартовое состояние: открыт, если ширина окна ≥ 1280, иначе закрыт. Состояние сохраняй (B-3).
  - Пэды: квадраты, вписанные в доступную высоту (`aspectRatio(1, contentMode: .fit)` у сетки целиком, а не только у ячейки).
- **Проверка:** сборка. Снимки из A-5 на 1100×720, 1440×900 и 1920×1080 без наложений. **Руками:** тяни окно от минимума до полного экрана, ничего не наезжает и не обрезается, библиотека открывается и закрывается кнопкой.

### A-4. Секвенсор по высоте
- **Файлы:** `Features/Sequencer/SequencerView.swift:59-64` (нет `ScrollView`), `:294` (`frame(height: 42)` у строки), `:21`, `:46-48` (фиксированные колонки-распорки).
- **Проблема:** 8 × 42 pt плюс заголовки плюс 220 pt эффектов не помещаются в окно ниже ≈ 800 pt, и нижние строки обрезаются.
- **Как исправить:**
  - Высоту строки считай из доступной высоты: `clamp(доступно / 8, 26…44)`. Если не помещается даже по 26, оберни строки в `ScrollView(.vertical)` через `ViewThatFits(in: .vertical)`. Плейхед-оверлей (`PlayheadOverlay`, `StepColumnKey`) должен оставаться внутри прокрутки.
  - Колонки M/S, VOL, PAN: общая константа из `AppLayout` для заголовка и строки, чтобы они не разъезжались.
  - Нижний ряд эффектов: `minHeight 170`, `idealHeight 220`.
- **Проверка:** снимок на 1100×720: видны все 8 строк (или прокрутка) и строка PERC не обрезана. **Руками:** в режиме 32 шагов шаги не сливаются, клики попадают в нужную клетку.

### A-5. Редактор пэда в окне-листе и автопроверка раскладки
- **Файлы:** `Features/Pads/PadsGridView.swift:51-78` (оверлей ADSR внутри панели), `DrumMashine_swistUIUITests/DrumMashine_swistUIUITests.swift` (сейчас шаблон).
- **Проблема:** редактор ADSR зажат в панели пэдов. Автопроверки раскладки нет.
- **Как исправить:**
  - Открывай `PadADSREditorView` через `.sheet` (или `.popover` у пэда) с шириной 420–520. Состояние редактирования не меняй.
  - Отладочный аргумент запуска `-DMWindowSize 1100x720`: при нём приложение в `onAppear` ставит размер окна (только в DEBUG).
  - UI-тест `testLayoutAtMinimumSize`: запуск с минимальным размером, затем проверка, что `app.buttons["transport.play"].frame` целиком внутри `app.windows.firstMatch.frame` и не пересекается с `seq.panel` и `pads.panel`, а `pattern.slot.D` хиттабелен. То же для 1440×900.
  - Снимки: `ImageRenderer(content: MainLayoutView().frame(width:height:))` на трёх размерах, PNG в `/tmp/drum_layout_<w>x<h>.png`. Пути выведи в лог теста, чтобы nixter мог посмотреть.
- **Проверка:** UI-тест зелёный, три PNG созданы. **Руками:** долгий клик по пэду открывает редактор поверх окна, а не внутри панели. Посмотри PNG.

---

## B — надёжное сохранение

### B-0. Изолировать тесты от настоящих данных и сделать резервную копию
- **Файлы:** `DrumMashine_swistUITests/DrumMashine_swistUITests.swift:693-730` и `:781-808`, `Core/Models/PatternManager.swift:86` (`static let shared`), `:205-227`.
- **Проблема:** unit-тесты работают внутри приложения и пишут в настоящий `UserDefaults.standard` nixter (`"not-json"`, `:798`). Падение посреди теста уничтожает его слоты.
- **Как исправить:**
  - Внедри зависимость: `PatternManager(defaults: UserDefaults, directory: URL)`. `shared` в обычном запуске использует `.standard` и папку приложения.
  - Если запущен под XCTest (`ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`), `shared` берёт `UserDefaults(suiteName: "DrumMachineTests-<uuid>")` и временную папку `FileManager.default.temporaryDirectory/DrumMachineTests-<uuid>`.
  - Тесты создают **свои** экземпляры менеджера со своим suite и папкой, а не трогают `shared`.
  - Перед любой миграцией (B-2) приложение один раз копирует сырые байты ключа `drum_machine_patterns_v2` в `Application Support/DrumMachine/Backups/legacy-patterns-<yyyyMMdd-HHmmss>.json`. Ключ не удаляет.
- **Проверка:** `rg -n "UserDefaults.standard" DrumMashine_swistUITests` пусто. Тест: после прогона всех тестов байты ключа в `.standard` не изменились (сравни SHA-256 до и после в фикстуре). **Руками:** ничего.

### B-1. Терпимый к старым данным Codable
- **Файлы:** `Core/Models/SoundPreset.swift:4-22`, `Core/Sequencer/SequencerTrack.swift`, `Core/Sequencer/SequencerStep.swift`, `Core/Models/PatternManager.swift:7-31` (`DrumPattern`), `Core/AudioEngine/EffectsChain.swift:4-54`, `Core/Models/DrumKit.swift`.
- **Проблема:** синтезированный `Decodable` падает, если в JSON нет ключа, даже когда у свойства есть значение по умолчанию. Любое новое поле (а D-0 их добавляет) сделает старые сохранения нечитаемыми, и они будут затёрты.
- **Как исправить:**
  - Напиши `init(from:)` с `decodeIfPresent(...) ?? default` для всех полей с умолчаниями. Обязательны только `id` (если нет — сгенерировать), `name` и `category`. `encode` оставь синтезированным.
  - Неизвестный `category` (`rawValue`) → `.percussion` вместо ошибки.
  - Все модели сделай `Equatable`: это нужно тестам C-1.
- **Проверка:** тест: JSON `SoundPreset` только с `id`, `name`, `filename`, `category` декодируется с умолчаниями. Тест: реальный блок из текущих данных nixter (4 пустых слота, старый массив; положи в `Tests/Fixtures/legacy_patterns_v2.json` — сгенерируй тем же кодом `PatternStore.encode` из 4 пустых паттернов) декодируется без ошибок.

### B-2. Файловое хранилище в Application Support, версии, атомарная запись, миграция
- **Файлы:** новый `Core/Persistence/PersistenceStore.swift`, `Core/Models/PatternManager.swift:33-80` (`PatternStore`), `:171-227`.
- **Проблема:**
  - `UserDefaults` не подходит для больших JSON (уже 58 KB, с 32 шагами и UUID у каждого шага будет больше).
  - Ошибки записи не видны.
  - При ошибке чтения данные затираются.
- **Как исправить:**
  - Папка `FileManager.default.url(for: .applicationSupportDirectory, …)/DrumMachine/` (в sandbox это `~/Library/Containers/Home.DrumMashine-swistUI/Data/Library/Application Support/DrumMachine/`). Файлы:
    - `session.json` — живое состояние (B-3);
    - `patterns.json` — слоты A–D;
    - `user_presets.json` — пользовательские пресеты (B-5);
    - `user_kits.json` — киты (D-3);
    - `Samples/` — импортированные сэмплы (D-4);
    - `Backups/`.
  - Каждый файл — `{ "version": N, "savedAt": ISO8601, "payload": … }`. Если версия больше известной, файл не трогаем и показываем ошибку.
  - Запись: `JSONEncoder` (`.sortedKeys`, `.prettyPrinted` в DEBUG) → `data.write(to: url, options: .atomic)`. Перед перезаписью старый файл копируется в `<name>.bak`, одна копия.
  - Чтение: если файл не читается, переименуй его в `<name>.corrupt-<timestamp>.json`, попробуй `.bak`, и только если и он не читается, начни с пустого. Ошибка всегда уходит в `lastError` (B-6). **Никогда не перезаписывай нечитаемый файл без копии.**
  - API бросает ошибки (`throws`), `try?` в слое хранения запрещён (проверка `rg -n "try\?" Core/Persistence` пуста).
  - Миграция при первом запуске: если `patterns.json` нет, а в `UserDefaults` есть `drum_machine_patterns_v2`, декодируй через существующий `PatternStore.decode` (он понимает и старый массив, и Document v1) и запиши `patterns.json`. Ключ в `UserDefaults` **не удаляй** минимум одну версию. Если ключ нечитаем, сырые байты уже лежат в `Backups/` (B-0), покажи ошибку и начни с пустых слотов, не трогая ключ.
  - Все операции хранилища — на `@MainActor`, запись файла можно унести в `Task.detached` с копией данных (значения `Sendable`).
- **Проверка:** тесты из C-2. **Руками:** после первого запуска в папке выше появились `patterns.json` и `Backups/legacy-patterns-….json`. Ключ в plist на месте (`defaults read Home.DrumMashine-swistUI drum_machine_patterns_v2 | head -c 80`).

### B-3. Автосохранение сессии при каждом изменении и при выходе, загрузка при запуске
- **Файлы:**
  - `Core/Sequencer/SequencerEngine.swift:63-116` (`tracks`, `bpm`, `stepCount`, `swing`, `humanize`), `:132-149` (`init` с заглушками);
  - `Core/AudioEngine/AudioEngineManager.swift:99` (`effectsChain`), `:106` (`trackPresets`), `:426` и `:467-486` (стартовые звуки), `:642-650` (master, limiter);
  - `Features/Visualizer/MasterControlView.swift:5-6` (`@State masterVolume`, `isLimiterOn`);
  - `Core/Models/PatternManager.swift:229-244` (наблюдатели);
  - `DrumMashine_swistUIApp.swift`.
- **Проблема:** сетка, звуки пэдов, ADSR, BPM, эффекты и мастер живут только в памяти, при запуске ничего не восстанавливается.
- **Как исправить:**
  - Модель `SessionState: Codable, Equatable` содержит `tracks` (с `soundPreset`, mute, solo, volume, pan), `bpm`, `swing`, `humanize`, `stepCount`, `activePatternIndex`, `effectsChain`, `masterVolume`, `limiterEnabled`, `libraryInspectorOpen`.
  - `SessionStore.scheduleSave()` с дебаунсом 0.5 с вызывается из `didSet`/сеттеров `SequencerEngine` и `AudioEngineManager`, а также из `updateEffects()`. `masterVolume` и `isLimiterOn` перенеси из `@State` в `AudioEngineManager` (как наблюдаемые свойства).
  - Сброс `flush()` синхронно вызывается на `NSApplication.willResignActiveNotification`, в `applicationShouldTerminate` через `@NSApplicationDelegateAdaptor` (вернуть `.terminateNow` после записи) и при закрытии окна (`onDisappear` корневого view). Закрытие последнего окна на macOS не завершает приложение, но данные должны быть уже на диске.
  - Загрузка при запуске: `SessionStore.load()` **до** создания `SequencerEngine`. `SequencerEngine(session:)` берёт треки из сессии, а `AudioEngineManager` синтезирует восстановленные пресеты вместо `startupSamples` (`:426`, `:476`). Без сессии используются пресеты библиотеки по умолчанию (D-0), а не заглушки `sound_N`.
  - Состояние воспроизведения не сохраняй: после запуска приложение всегда остановлено.
- **Проверка:** тесты C-1 и C-3. **Руками:** поставь шаги, BPM 133, поменяй звук и ADSR пэда, включи REVERB, громкость мастера 60 %, затем Cmd+Q. После запуска всё на месте. Повтори с «Завершить принудительно» через 2 с после правки: потеря не больше последних 0.5 с.

### B-4. Слоты A–D: активный слот сохраняется сам, клик больше не стирает работу
- **Файлы:** `Features/Sequencer/PatternSlotsView.swift:14-53` (клик загружает, долгое нажатие сохраняет), `:117-121`, `Core/Models/PatternManager.swift:108-160`, `:247-265` (`makeEmptyPattern` с заглушками).
- **Проблема:**
  - Сохранение в слот спрятано в долгое нажатие ≥ 0.5 с, а обычный клик по пустому слоту затирает несохранённую сетку.
  - Пустой слот содержит заглушки `sound_3`/`sound_4`, которые `DrumSynthesizer` рендерит **не тем** генератором: CLAP и TOM звучат как PERC, RIDE как CRASH (`DrumSynthesizer.swift:543-556` ищет `"tom"`/`"clap"`/`"ride"` в `filename`).
- **Как исправить:**
  - Модель «живого слота», как на железных драм-машинах: любые правки сетки, BPM, swing и звуков сразу пишутся в активный слот (`PatternManager.updateActive(from:)`, дебаунс общий с B-3). Переключение слота сначала сохраняет текущий, потом загружает выбранный.
  - Пустой слот при переключении получает **копию звуков текущего слота** с пустой сеткой, а не заглушки.
  - Долгое нажатие убери. Контекстное меню слота (правый клик): «Копировать в… A/B/C/D», «Очистить», «Переименовать». Подсказка `.help` на каждом слоте.
  - `activePatternIndex` хранится в `patterns.json`.
  - «Очистить» и «Случайно» (CLEAR/RANDOM) для непустого слота делают снимок для одного Undo (`UndoManager` окна, Cmd+Z).
- **Проверка:** тест: правка шага в слоте B, переключение на C и обратно на B — шаг на месте. Тест: переключение на пустой слот сохраняет звуки (`soundPreset.filename` не `sound_N`). **Руками:** напиши ритм в A, переключись на B, напиши другой, перезапусти приложение — A и B на месте, активен последний.

### B-5. Пользовательские пресеты звуков и стабильные id
- **Файлы:** `SoundLibrary/SoundLibraryManager.swift:113-130` (`make` с `UUID()` на `:123`), `:138-144` (`defaultPreset`: PERC → `.fx`, а у трека PERC категория `.percussion`), `Features/SoundEditor/PadADSREditorView.swift:131-140` (кнопка RESET ставит sustain 1.0 и decay 0.1, а не значения пресета), `Features/SoundLibrary/SoundLibraryView.swift:199-220` (назначение), `Core/AudioEngine/AudioEngineManager.swift:589`, `:600` (кэш превью по `preset.id`).
- **Проблема:** пользовательских пресетов нет. У заводских пресетов `id` меняется при каждом запуске. RESET в редакторе не возвращает исходный звук.
- **Как исправить:**
  - Стабильный `id` у заводских пресетов: детерминированный UUID из `filename` (например, первые 16 байт SHA-256 от `"factory." + filename`, с выставленными битами версии и варианта). Тот же `filename` даёт тот же `id`.
  - В пресет добавь `origin: .factory | .user` и `basedOn: UUID?` (с `decodeIfPresent` из B-1).
  - `UserPresetStore` (`user_presets.json`) с методами `save(_:)`, `rename`, `delete` и `duplicate`.
  - В редакторе пэда кнопка «Сохранить как пресет…» (имя, категория — инструмент). RESET возвращает значения пресета, из которого пэд был назначен (`basedOn`), а не захардкоженные числа.
  - В библиотеке вкладка **USER**: список, превью, двойной клик назначает на пэд, контекстное меню переименовать/удалить. Удаление пресета, который стоит на пэде, не ломает пэд: на пэде остаётся копия.
  - Кэш превью: ключ `(id, хэш параметров)`, чтобы правка пользовательского пресета не играла старый буфер.
- **Проверка:** тест: два создания `SoundLibraryManager` дают одинаковые `id` у пресета `kick_808`. Тест C-1 включает пользовательский пресет. **Руками:** настрой ADSR у SNARE, «Сохранить как пресет» → «Мой снейр», перезапусти, найди его в USER и назначь на другой пэд — звучит так же.

### B-6. Ошибки сохранения и загрузки видны пользователю
- **Файлы:** `Core/Models/PatternManager.swift:100`, `:194-198`, `:213-218`, `UI/Layout/MainLayoutView.swift:27-29` и `:78-95` (существующий `errorBanner` для аудио).
- **Проблема:** `loadError` нигде не отображается. Ошибка записи в `UserDefaults` вообще не видна.
- **Как исправить:**
  - `PersistenceStore.lastError: PersistenceError?` (наблюдаемое). Тип ошибки содержит операцию (чтение или запись), файл и `localizedDescription`.
  - Баннер в `MainLayoutView` (рядом с аудио-баннером, не перекрывая транспорт) с кнопками «Показать в Finder» (`NSWorkspace.shared.activateFileViewerSelecting`), «Повторить» и «Скрыть». Текст по-русски, например: «Не удалось сохранить паттерны: <причина>. Данные в памяти не потеряны, попробуйте ещё раз».
  - Каждая ошибка пишется в `Logger(subsystem: "Home.DrumMashine-swistUI", category: "persistence")`.
  - Если запись не удалась, `savePending` остаётся `true`, а следующая попытка идёт через 5 с и при выходе.
- **Проверка:** тест: папка хранилища только для чтения (`FileManager.setAttributes([.posixPermissions: 0o500])` на временной папке) → `lastError` установлен, данные в памяти не тронуты, после возврата прав следующий `flush()` успешен. **Руками:** баннер можно вызвать в DEBUG меню «Debug → Simulate save error».

### B-7. Экспорт и импорт всех данных в файл (резервная копия)
- **Файлы:** `Core/Models/DrumProject.swift` (только модель, сохранения нет, `:6` «File export is not wired to the UI»), `project.pbxproj:404`, `:438`.
- **Проблема:** всё хранится только в контейнере приложения. Если nixter удалит приложение, данные пропадут. Перенести их на другой Мак тоже нельзя.
- **Как исправить:**
  - Документ `.drumproj` (JSON, `UTType` экспортируется в Info) со всем содержимым: `SessionState`, слоты, пользовательские пресеты и киты, а сэмплы внутри как base64 или в папке-пакете.
  - Меню «Файл → Экспорт…» и «Импорт…» через `.fileExporter` и `.fileImporter`. Для экспорта переведи sandbox на `ENABLE_USER_SELECTED_FILES = readwrite`.
  - Импорт спрашивает: «Заменить» или «Добавить пресеты и слоты». Перед заменой текущее состояние автоматически копируется в `Backups/`.
  - `DrumProject` либо приведи к этому формату, либо удали, чтобы не было двух моделей.
- **Проверка:** тест: экспорт → импорт в пустое хранилище → `Equatable`-равенство. **Руками:** экспортируй на рабочий стол, удали `Application Support/DrumMachine` (предварительно скопировав), импортируй — всё вернулось.

---

## C — тест «сохранить → перезапустить → загрузить»

### C-1. Unit-тест полного круга через новый экземпляр хранилища
- **Файлы:** `DrumMashine_swistUITests/PersistenceRoundTripTests.swift` (новый).
- **Как сделать:**
  - Временная папка и `UserDefaults(suiteName:)` на каждый тест, удаление в `deinit` или `defer`.
  - Заполни состояние:
    - 32 шага, активны шаги 0, 7 и 31 у KICK, velocity 0.5;
    - swing 55, humanize 20, BPM 133;
    - у SNARE пресет с pitch +3 и ADSR (0.002, 0.25, 0, 0.12), трек HIHAT muted, у CLAP pan −0.4;
    - REVERB on, room `.largeHall`, mix 0.35; master 0.6, limiter off;
    - слоты A и B с разной сеткой, активен B;
    - один пользовательский пресет и (после D-3) один пользовательский кит;
    - (после D-4) один импортированный сэмпл.
  - `flush()`. Создай **новые** экземпляры `PersistenceStore`, `SessionStore`, `PatternManager` и `UserPresetStore` на той же папке, как будто приложение перезапустили. `load()` должен дать `==` по всем моделям.
  - Отдельный тест: изменение и сразу «выход» (`flush()` без ожидания дебаунса) → после «перезапуска» изменение на месте.
- **Проверка:** тест зелёный. Каждое новое поле в моделях обязано попасть в этот тест (комментарий в шапке файла).

### C-2. Миграция, повреждённые файлы, совместимость версий
- **Файлы:** тот же тестовый таргет, фикстуры в `DrumMashine_swistUITests/Fixtures/`.
- **Как сделать:** тест-кейсы:
  1. Старый массив в `UserDefaults` → `patterns.json` создан, данные равны, ключ в `UserDefaults` **на месте**, копия в `Backups/`.
  2. Document v1 в `UserDefaults` → то же самое.
  3. `patterns.json` содержит мусор → файл переименован в `.corrupt-…`, загружен `.bak`, `lastError` установлен, мусор не перезаписан.
  4. Версия файла 99 → файл не тронут, ошибка, пустое состояние в памяти, и при `flush()` файл **не** перезаписан.
  5. JSON без новых полей (D-0: `voice`, `synth`, `source`) читается, у пресетов умолчания.
  6. Запись при недоступной папке (см. B-6).
- **Проверка:** все кейсы зелёные.

### C-3. UI-тест настоящего перезапуска приложения
- **Файлы:** `DrumMashine_swistUIUITests/PersistenceRelaunchUITests.swift` (новый). В приложении — аргумент запуска `-DMDataDirectory <путь>` (только DEBUG), он подменяет папку хранилища.
- **Как сделать:**
  - Создай временную папку, запусти приложение с `-DMDataDirectory`, нажми `transport.bpm.plus` 13 раз (BPM 133), кликни `seq.step.0.0` и `seq.step.1.4`, подожди 1 с, затем `app.terminate()`.
  - Запусти снова с той же папкой. Ожидается: `transport.bpm` показывает «133», шаги включены (`accessibilityValue == "on"`).
  - Второй сценарий — выход через Cmd+Q **без** ожидания: `app.typeKey("q", modifierFlags: .command)` сразу после клика по шагу, затем перезапуск, и шаг на месте (проверяет сброс при выходе).
- **Проверка:** `-only-testing:DrumMashine_swistUIUITests/PersistenceRelaunchUITests` зелёный. **Руками (главная проверка для nixter):** поставь ритм в A и B, поменяй звуки пэдов, ADSR, эффекты и громкость, сохрани один пресет. Затем Cmd+Q и запуск: всё на месте. Перезагрузи Мак и запусти снова: всё на месте.

---

## D — библиотека звуков побольше

### Как библиотека устроена сейчас (проверено в коде)

- **Сэмплов нет, всё синтезируется.** `DrumSynthesizer` (`Core/AudioEngine/DrumSynthesizer.swift`) генерирует буфер на частоте выхода, `AudioEngineManager.loadSound` (`:614-629`) кладёт его в голосовой движок.
- **60 заводских пресетов**, по 10 на 6 категорий (`SoundLibrary/SoundLibraryManager.swift:17-102`): kick 10, snare 10, hihat 10, percussion 10 (clap 3, tom 3, conga, bongo, cowbell, shaker), cymbals 10 (ride 3, crash 4, splash, china, stack), fx 10.
- **Пресеты внутри категории почти одинаковые.** Генератор выбирается по категории и подстроке в `filename` (`DrumSynthesizer.swift:531-560`). Пресет меняет только `decay`, `pitch` и ADSR, а тембр задан константами внутри генераторов:
  - kick: 150→50 Гц за 0.08 с, щелчок 0.5, drive 1.5 (`:185-187`, `:209`, `:216`);
  - snare: тона 180/330 Гц, тело τ 0.15, шум HPF 1 кГц, 0.8 (`:234-256`);
  - hi-hat: 6 квадратов 263…845 Гц, HPF 8 кГц и BPF 10 кГц Q 0.8 (`:272-277`), открытый только если `decay > 0.15` (`:542`);
  - clap: 3 вспышки через 12 мс, 800…2500 Гц, хвост 0.4 (`:313-347`);
  - tom: 200→80 Гц за 0.07 с (`:368-377`);
  - crash: FM 300/412 Гц, индекс 5, HPF 2 кГц (`:402-417`);
  - perc: FM 800 Гц × 1.43, индекс 3 (`:440-448`). Conga, Bongo, Cowbell и Shaker — **один и тот же** FM-генератор с разной высотой;
  - ride: пинг 5 кГц, `decay` почти игнорируется (`:464`).
- **Привязка пэдов к категориям неровная:** CLAP, TOM и PERC все `.percussion`, RIDE и CRASH — `.cymbals`, а `defaultPreset` для трека 7 (PERC) берёт `.fx` (`SoundLibraryManager.swift:138-144`).

### Правило лицензий (обязательно)
- В приложение и в git попадают **только** звуки, синтезированные нашим кодом, или сэмплы с лицензией **CC0** (с файлом `DrumMashine_swistUI/Resources/Samples/LICENSES.md`: источник, автор, ссылка на CC0, дата).
- **Нельзя:** сэмплы Roland и других производителей, коммерческие паки, паки «free for personal use», CC-BY-NC, «найдено в интернете».
- Подписи «808», «909» в названиях — это описание стиля синтеза, а не сэмплы этих машин.
- Пользовательские импортированные сэмплы (D-4) лежат только в контейнере пользователя и в git не попадают (`.gitignore`). Ответственность за их лицензию на пользователе, об этом одна строка в окне импорта.
- Рекомендация этого плана: **заводские звуки только синтезированные**, без вложенных сэмплов.

### D-0. Модель пресета: явный тип голоса, параметры синтеза, источник
- **Файлы:** `Core/Models/SoundPreset.swift:4-22`, `Core/AudioEngine/DrumSynthesizer.swift:502-560`, `Core/Sequencer/SequencerEngine.swift:138-144` и `Core/Models/PatternManager.swift:247-265` (заглушки `sound_N`).
- **Проблема:**
  - Генератор угадывается по подстроке в `filename`, а заглушки `sound_N` рендерятся не тем генератором.
  - Тембр зашит в константы, поэтому новые варианты (909, акустика, lo-fi) нельзя выразить пресетом.
- **Как исправить:**
  - Добавь в `SoundPreset` поле `voice: VoiceKind` (`kick`, `snare`, `closedHat`, `openHat`, `clap`, `tom`, `ride`, `crash`, `perc`, `fx`). Для старых данных `voice` выводится из `category` и `filename` той же логикой, что сейчас в `renderedVoice`.
  - Добавь `synth: SynthParams?` — структура с опциональными полями на каждый генератор (D-1) и общий блок `lofi`.
  - Добавь `source: .synth | .sample(fileName:originalName:)` (D-4).
  - Всё через `decodeIfPresent` (B-1).
  - `renderedVoice` выбирает генератор по `voice`. Генераторы берут параметры из `synth ?? .default(for: voice)`, а **умолчания равны нынешним константам**.
  - Заглушки `sound_N` в `SequencerEngine.init` и `makeEmptyPattern` замени на `SoundLibraryManager.defaultPreset(forTrackIndex:)`. Маппинг: 0 kick, 1 snare, 2 closedHat, 3 clap, 4 tom, 5 ride, 6 crash, 7 perc (не fx).
- **Проверка:** тест на стенде P0-0: для всех 60 старых пресетов SHA-256 буфера на 48 kHz до и после **совпадает побитно**. Посчитай хэши до изменения и закоммить их как фикстуру. Тест: у трека CLAP после запуска генератор — clap.

### D-1. Параметры генераторов
- **Файлы:** `DrumSynthesizer.swift`: kick `:177-223`, snare `:226-262`, hi-hat `:265-303`, clap `:306-358`, tom `:361-393`, crash `:396-430`, perc `:433-459`, ride `:462-499`.
- **Как исправить:** в скобках умолчания, равные нынешним константам.
  - **Kick:** `startHz` (150), `endHz` (50), `sweep` (0.08 с), `click` (0.5), `clickMs` (10), `drive` (1.5), `noise` (0, новое: шум «колотушки» с BPF 3 кГц).
  - **Snare:** `tone1Hz` (180), `tone2Hz` (330), `tone1Level` (0.5), `tone2Level` (0.3), `bodyTau` (0.15), `noiseHPHz` (1000), `noiseLevel` (0.8).
  - **Hat:** `open: Bool?` (nil → старое правило `decay > 0.15`), `hpHz` (8000), `bandHz` (10000), `bandQ` (0.8), `noiseMix` (0, новое: доля белого шума к квадратам).
  - **Clap:** `bursts` (3), `spacing` (0.012), `hpHz` (800), `lpHz` (2500), `tailLevel` (0.4).
  - **Tom:** `startHz` (200), `endHz` (80), `sweep` (0.07), `stickNoise` (0, новое).
  - **Ride:** `pingHz` (5000), `pingModHz` (720), `pingLevel` (0.6), `sizzleLevel` (0.4), `sizzleTau` (0.5, теперь не константа), `hpHz` (3000), `lpHz` (6000).
  - **Crash:** `carrierHz` (300), `modHz` (412), `index` (5), `fmMix` (0.3), `hpHz` (2000).
  - **Perc:** `mode` (`fm` по умолчанию, `cowbell` — два PolyBLEP-квадрата + BPF, `noise` — полосовой шум для шейкера и тамбурина), `carrierHz` (800), `ratio` (1.43), `index` (3), `indexDecay` (20), `bandHz`, `bandQ`.
  - **Lo-fi (общий блок, после генератора, до `finalize`):** `bitDepth` (nil = без изменений; 12 или 8), `downsample` (1; 2–4 = sample-and-hold), `saturation` (0…1, tanh).
  - `pitch` (полутоны) по-прежнему умножает все частоты.
  - Редактор пэда показывает 3–4 главных параметра для своего `voice` («Тон», «Щелчок», «Шум», «Lo-fi»), а не все сразу.
- **Проверка:** хэши D-0 не изменились. Тест: для каждого `voice` изменение каждого параметра меняет буфер. Lo-fi с `bitDepth 8` даёт не больше 256 уровней (до нормализации).

### D-2. 51 новый заводской пресет (было 60, станет 111)

Все пресеты синтезированные. ADSR по умолчанию: attack 0.001, sustain 0, release ≈ 0.3 × decay. Числа ниже — **стартовые**: Grok Build проверяет их тестами, а финальную настройку на слух делает nixter. `filename` = ключ для стабильного `id` (B-5).

**Kick — 6**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Kick 909 | kick_909 | start 230, end 52, sweep 0.035, click 0.9, drive 2.2 | 0.30 |
| Kick 808 Long | kick_808_long | start 120, end 45, sweep 0.06, click 0.15, drive 1.2 | 0.90 |
| Kick Acoustic | kick_acoustic | start 110, end 62, sweep 0.025, click 0.7, noise 0.25, drive 1.1 | 0.22 |
| Kick Lo-Fi | kick_lofi | как 808 + lofi bit 8, downsample 3 | 0.35 |
| Kick Distorted | kick_dist | start 180, end 50, sweep 0.05, drive 4.0 | 0.40 |
| Kick Trap Sub | kick_trap_sub | start 90, end 38, sweep 0.12, click 0.1, drive 1.3, pitch −2 | 1.20 |

**Snare — 6**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Snare 909 | snare_909 | tone 190/340, bodyTau 0.07, noiseHP 1800, noise 1.0 | 0.20 |
| Snare 808 Snappy | snare_808_snappy | tone 238/476, bodyTau 0.12, noiseHP 2500, noise 0.9 | 0.15 |
| Snare Acoustic | snare_acoustic | tone 200/290, bodyTau 0.09, noiseHP 600, noise 0.7 | 0.30 |
| Snare Lo-Fi | snare_lofi | как 808 + lofi bit 8, downsample 2 | 0.18 |
| Snare Rimshot | snare_rimshot | tone 400/1700, bodyTau 0.02, noiseHP 3000, noise 0.25 | 0.06 |
| Snare Trap | snare_trap | tone 210/420, bodyTau 0.05, noiseHP 3500, noise 1.0, pitch +2 | 0.12 |

**Hi-hat закрытый — 5** (`voice = closedHat`, `open = false`)
| Название | filename | Параметры | decay |
|---|---|---|---|
| CH 808 | ch_808 | hp 7000, band 9000, Q 0.7 | 0.04 |
| CH 909 | ch_909 | hp 9000, band 11000, Q 1.2, noiseMix 0.4 | 0.035 |
| CH Acoustic | ch_acoustic | hp 6000, band 8000, Q 0.5, noiseMix 0.6 | 0.06 |
| CH Lo-Fi | ch_lofi | как 808 + bit 8, downsample 3 | 0.05 |
| CH Trap Tick | ch_trap_tick | hp 10000, band 12000, Q 1.0 | 0.02 |

**Hi-hat открытый — 5** (`voice = openHat`, `open = true`)
| Название | filename | Параметры | decay |
|---|---|---|---|
| OH 808 | oh_808 | hp 7000, band 9000, Q 0.7 | 0.45 |
| OH 909 | oh_909 | hp 9000, band 11000, Q 1.2, noiseMix 0.4 | 0.50 |
| OH Acoustic | oh_acoustic | hp 6000, band 8000, Q 0.5, noiseMix 0.6 | 0.70 |
| OH Lo-Fi | oh_lofi | как 808 + bit 8 | 0.40 |
| OH Half | oh_half | hp 8000, band 10000, Q 0.8 | 0.22 |

Открытый хэт глушится закрытым (общий choke group 1, как сейчас у трека 2).

**Clap — 5**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Clap 909 | clap_909 | bursts 4, spacing 0.010, hp 900, lp 3000, tail 0.5 | 0.20 |
| Clap 808 Wide | clap_808_wide | bursts 3, spacing 0.015, hp 700, lp 2200, tail 0.6 | 0.35 |
| Clap Real Hands | clap_real | bursts 2, spacing 0.008, hp 1000, lp 4000, tail 0.2 | 0.12 |
| Clap Lo-Fi | clap_lofi | как 808 Wide + bit 8, downsample 2 | 0.25 |
| Finger Snap | clap_snap | bursts 1, hp 2000, lp 6000, tail 0.1 | 0.05 |

**Tom — 6**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Tom 808 Low | tom_808_low | start 120, end 70, sweep 0.06 | 0.50 |
| Tom 808 Mid | tom_808_mid | start 180, end 105, sweep 0.06 | 0.40 |
| Tom 808 High | tom_808_high | start 260, end 150, sweep 0.06 | 0.35 |
| Tom 909 | tom_909 | start 260, end 120, sweep 0.03, stickNoise 0.3 | 0.30 |
| Tom Acoustic Floor | tom_acoustic_floor | start 110, end 82, sweep 0.02, stickNoise 0.15 | 0.60 |
| Tom Lo-Fi | tom_lofi | как 808 Mid + bit 8 | 0.40 |

**Ride — 5**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Ride 909 | ride_909 | ping 4200, mod 650, ping 0.5, sizzle 0.5, sizzleTau 1.2 | 1.5 |
| Ride 808 | ride_808 | ping 3500, mod 540, ping 0.6, sizzle 0.3, sizzleTau 0.7 | 1.0 |
| Ride Acoustic Dry | ride_acoustic_dry | ping 5200, ping 0.7, sizzle 0.3, sizzleTau 0.8 | 1.2 |
| Ride Bell Bright | ride_bell_bright | ping 6500, ping 0.9, sizzle 0.2, sizzleTau 0.6 | 1.0 |
| Ride Lo-Fi | ride_lofi | как 808 + bit 8, downsample 2 | 1.0 |

**Crash — 5**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Crash 909 | crash_909 | carrier 340, mod 470, index 6, fmMix 0.25, hp 3000 | 1.4 |
| Crash 808 | crash_808 | carrier 300, mod 412, index 4, fmMix 0.4, hp 2500 | 1.0 |
| Crash Acoustic 18" | crash_acoustic_18 | carrier 260, mod 388, index 7, fmMix 0.3, hp 1500 | 2.0 |
| Crash Short | crash_short | как 909 | 0.4 |
| Crash Lo-Fi | crash_lofi | как 808 + bit 8 | 1.0 |

**Perc — 8**
| Название | filename | Параметры | decay |
|---|---|---|---|
| Cowbell 808 | perc_cowbell_808 | mode cowbell, 540 + 800 Гц, BPF 2640 Q 1.5 | 0.35 |
| Rimshot 808 | perc_rim_808 | fm, carrier 1700, ratio 1.0, index 1 | 0.05 |
| Clave | perc_clave | fm, carrier 2500, ratio 1.0, index 0.5 | 0.06 |
| Woodblock | perc_woodblock | fm, carrier 1000, ratio 1.43, index 3 | 0.08 |
| Conga High 808 | perc_conga_808 | fm, carrier 370, ratio 1.0, index 0.8, indexDecay 40 | 0.20 |
| Shaker Real | perc_shaker | mode noise, band 6000, Q 1.5, attack 0.01 | 0.08 |
| Tambourine | perc_tambourine | mode noise, band 7500, Q 2.0, 2 вспышки через 15 мс | 0.18 |
| Triangle | perc_triangle | fm, carrier 4200, ratio 2.7, index 0.2 | 1.0 |

**Итого новых: 6 + 6 + 5 + 5 + 5 + 6 + 5 + 5 + 8 = 51.** Старые 60 пресетов (включая FX) не меняются.

- **Файлы:** `SoundLibrary/SoundLibraryManager.swift`. Вынеси список в `SoundLibrary/FactoryPresets.swift` (данные, а не код), с полем `style` (`.classic808`, `.style909`, `.acoustic`, `.lofi`, `.trap`, `.legacy`) для фильтра в D-5.
- **Проверка (на стенде P0-0) для каждого из 111 пресетов:**
  - нет NaN и Inf;
  - пик ≤ 0.5 + 1e-3 (как в `finalize`, −6 dBFS);
  - последний сэмпл = 0, `tailPeak < 0.001`;
  - длина ≤ 4 с.
- **Проверка различимости:** внутри каждого инструмента у любых двух пресетов отличается спектральный центроид более чем на 5 % **или** RMS-огибающая (по 10 мс) более чем на 1 dB в среднем.
- **Руками:** пролистай каждую вкладку и прослушай. Запиши, какие звучат плохо или одинаково, и какие числа поправить.

### D-3. Заводские и пользовательские киты
- **Файлы:** `Core/Models/DrumKit.swift` (модель есть, нигде не используется), новый `SoundLibrary/FactoryKits.swift`, `user_kits.json` (B-2).
- **Как сделать:**
  - 5 заводских китов по 8 пэдов (kick, snare, CH, clap, tom, ride, crash, perc):
    - **808:** kick_808_long, snare_808_snappy, ch_808, clap_808_wide, tom_808_mid, ride_808, crash_808, perc_cowbell_808;
    - **909:** kick_909, snare_909, ch_909, clap_909, tom_909, ride_909, crash_909, perc_rim_808;
    - **Acoustic:** kick_acoustic, snare_acoustic, ch_acoustic, clap_real, tom_acoustic_floor, ride_acoustic_dry, crash_acoustic_18, perc_tambourine;
    - **Lo-Fi:** kick_lofi, snare_lofi, ch_lofi, clap_lofi, tom_lofi, ride_lofi, crash_lofi, perc_woodblock;
    - **Trap:** kick_trap_sub, snare_trap, ch_trap_tick, clap_909, tom_808_low, ride_bell_bright, crash_short, perc_shaker.
  - «Загрузить кит» меняет звуки всех 8 пэдов одним действием (одно Undo), сетка не меняется.
  - «Сохранить кит как…» берёт текущие 8 пэдов (включая пользовательские пресеты и сэмплы) и пишет в `user_kits.json`. Пресет внутри кита хранится **копией**, а не ссылкой, чтобы удаление пресета не ломало кит.
  - Имя загруженного кита показывается в верхней панели (вместо удалённого в A-2 бейджа). После ручной правки пэда — «Имя кита*».
- **Проверка:** тест: загрузка кита 909 ставит 8 ожидаемых `filename`. Тест C-1 включает пользовательский кит. **Руками:** переключи 808 → 909 → Acoustic во время воспроизведения: звук меняется без щелчков и остановки.

### D-4. Импорт своих сэмплов (WAV/AIFF/CAF) перетаскиванием
- **Файлы:** новый `Core/Audio/SampleImporter.swift`, `Core/AudioEngine/DrumSynthesizer.swift:525-529` (`samples(for:)` — точка выбора источника), `Core/AudioEngine/AudioEngineManager.swift:490-520` (`resynthesizeInstalledBuffers` при смене частоты), `Features/Pads/DrumPadView.swift`, `Features/SoundLibrary/SoundLibraryView.swift`.
- **Как сделать:**
  - Перетаскивание файла на пэд (`.dropDestination(for: URL.self)`) или во вкладку USER, плюс кнопка «Импорт…» (`.fileImporter`, типы `.wav`, `.aiff`, `com.apple.coreaudio-format`).
  - Sandbox: перетаскивание и `fileImporter` дают доступ на чтение, `ENABLE_USER_SELECTED_FILES = readonly` достаточно. Файл **сразу копируется** в `Application Support/DrumMachine/Samples/<uuid>.<ext>`, закладки (security-scoped bookmarks) не нужны.
  - Ограничения: ≤ 10 с, ≤ 50 MB, иначе понятная ошибка в баннере (B-6).
  - Чтение через `AVAudioFile`, сведение в моно, `AVAudioConverter` в `outputSampleRate`. Pitch — ресемплинг с коэффициентом 2^(pitch/12). Затем тот же ADSR и `finalize` (−6 dBFS, затухание в конце).
  - При смене устройства и частоты буфер пересчитывается из исходного файла, а не из уже ресемплированного.
  - Создаётся пользовательский пресет: `source = .sample`, `voice` по пэду, имя = имя файла. Он сохраняется и восстанавливается как любой другой (B-5, C-1).
  - Если файл сэмпла пропал, пэд играет тишину, в библиотеке пометка «файл не найден», баннер. Без падения.
  - Удаление пресета-сэмпла удаляет файл только если на него не ссылается ни один пэд, слот или кит.
  - В окне импорта строка: «Импортируйте только звуки, на которые у вас есть права».
- **Проверка:** тест: сгенерируй во временной папке WAV 44.1 kHz стерео (синус 440 Гц, 0.5 с), импортируй → буфер моно на 48 kHz длиной ≈ 0.5 × 48000, пик 0.5, последний сэмпл 0. Тест: смена частоты на 44.1 kHz даёт длину ≈ 0.5 × 44100. Тест: после «перезапуска» (C-1) пресет-сэмпл на месте и играет. **Руками:** перетащи свой WAV на пэд PERC, проиграй, перезапусти приложение — звук на месте. Переключи выход LG ↔ динамики: высота звука не меняется.

### D-5. Библиотека: вкладки по инструментам, фильтр стиля, поиск
- **Файлы:** `Features/SoundLibrary/SoundLibraryView.swift:6-125` (вкладки категорий и список), `:199-220` (назначение «первому треку той же категории»: для TOM попадает на CLAP, потому что оба `.percussion`).
- **Проблема:** 6 категорий не совпадают с 8 пэдами. При 111 пресетах плюс пользовательских список без поиска неудобен.
- **Как сделать:**
  - Вкладки по `voice`: KICK, SNARE, HH CL, HH OP, CLAP, TOM, RIDE, CRASH, PERC, FX, плюс USER и KITS.
  - Фильтр стиля (чипсы 808 / 909 / ACOUSTIC / LO-FI / TRAP / ВСЕ) и поле поиска по имени.
  - Двойной клик назначает пресет на пэд **того же `voice`** (TOM → пэд TOM). Перетаскивание пресета на пэд назначает на этот пэд.
  - У каждого пресета в контекстном меню «Сохранить копию в USER», чтобы связать с B-5.
  - Библиотека живёт в инспекторе из A-3.
- **Проверка:** тест: двойной клик по `tom_909` меняет трек 4, а не 3. **Руками:** найди «909» поиском, назначь на пэды, сохрани как кит.

---

## Сводка

| Раздел | Задачи |
|---|---|
| A (раскладка) | A-1 … A-5 — 5 задач |
| B (сохранение) | B-0 … B-7 — 8 задач |
| C (тест полного круга) | C-1 … C-3 — 3 задачи |
| D (библиотека) | D-0 … D-5 — 6 задач, 51 новый пресет (60 → 111), 5 китов |
| **Всего** | **22 задачи** |

В конце работы допиши в `progress.md` короткий отчёт: список коммитов, добавленные тесты, пути к PNG-снимкам раскладки из A-5, где лежат файлы данных (`~/Library/Containers/Home.DrumMashine-swistUI/Data/Library/Application Support/DrumMachine/`), и список пунктов «руками» для nixter:
1. Play — целый круг при любом размере окна, панели не наезжают.
2. Ритм в A и B, звуки, ADSR, эффекты, громкость → Cmd+Q → запуск: всё на месте. То же после перезагрузки Мака.
3. «Сохранить как пресет» → перезапуск → пресет в USER.
4. Киты 808/909/Acoustic/Lo-Fi/Trap звучат по-разному. Список пресетов, которые надо подстроить.
5. Свой WAV на пэд → перезапуск → звук на месте.
