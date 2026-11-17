# GROK_BUILD_TASKS_9 — CUT (Binding PRD)

Дата: 2026-11-03 · База: main `61f3bee` (`61f3beee3ccf277d66d6819db480d4e2f3c2bd20`, проверено `git rev-parse` = origin/main) · Статус: **APPROVED-for-Eng (D2)** — nixter D2 via Grok Bot, 2026-11-03.

## Decision needed
Нет — nixter выбрал **D2** (через Grok Bot, 2026-11-03). D1 закрыт (не выбран). IN/OUT/AC ниже — для узкого пути D2.

## ВАЖНО: аудит устарел — основной фикс уже на базе
Nightly-аудит снят на `ddc9da0`. Коммит `32694b4` «UI P3: @Observable ThemeStore instead of .id(theme.style), ForEach by track id, .task(id:) flash timers» — предок `61f3bee`. На базе проверено:
- `grep -rn '\.id(theme\|asyncAfter' DrumMachine/` → 0 совпадений.
- `ThemeStore` (`UI/Theme/ThemeStore.swift`) — `@Observable final class`, `static let shared`, `var style: AppThemeStyle`; `MainLayoutView` держит `private let theme = ThemeStore.shared`, `.id` нет.
- `PatternSlotsView.body`: `.task(id: flashToken)` → `Task.sleep(1.2 s)` → `guard !Task.isCancelled` → `showSaveConfirm = nil`; триггер `flashToken &+= 1` (~:88-90).
- `SoundLibraryView.body`: `.task(id: flashToken)` → тот же паттерн для `justAssigned` (~:42-47); триггер ~:446-448.
Остаток: устаревший doc-комментарий `MainLayoutView.swift:13-14` («…rebuilds the panels below via `.id`»), и **нет регресс-тестов / QA-доказательств**. Поэтому CUT_9 = «подтвердить + закрепить», без переписывания продукта.

## Outcome (одно предложение)
Смена темы не пересоздаёт дерево панелей (без `.id(theme.style)`), а тосты/подсветки в PatternSlotsView и SoundLibraryView гаснут через отменяемый `.task(id:)` без мигания — и это закреплено тестами/доказательствами QA.

## IN
- IN-1 `MainLayoutView.swift:13-14` — исправить устаревший комментарий (тема наблюдается через `@Observable ThemeStore`, `.id`-rebuild нет). Только комментарий.
- IN-2 Тест-гард P3-1 (напр. `ThemeStoreTests.swift`): `ThemeStore(defaults:)` на изолированном `UserDefaults(suiteName:)` — смена `style` сохраняется/восстанавливается; `withObservationTracking` на чтении `style` срабатывает onChange при переключении.
- IN-3 Тест/гард отсутствия регрессии: source-scan тест (или скрипт в `qa/`) — в `DrumMachine/**/*.swift` нет `.id(theme` / `.id(ThemeStore` и нет `DispatchQueue.main.asyncAfter` в `PatternSlotsView`/`SoundLibraryView`.
- IN-4 P3-5 — если тест на view-уровне сложен: вынести не нужно; достаточно QA-доказательства (AC-5). Допустимо (опционально) вынести 1.2 s в общий `static let flashDuration` без изменения поведения.
- IN-5 Если Eng найдёт реальный остаток P3-1/P3-5 (иной `.id(style)`, необменяемый таймер) — чинить в тех же 3 файлах тем же паттерном; иначе продукт не трогать. DerivedData `~/.drum_dd`; ветка от `61f3bee`.

## OUT
- P2-1 VoiceEngine (CUT_8 — смержен, не переоткрывать).
- Персистентность (CUT_7).
- Аудио/VoiceEngine/scheduler/Sequencer, groove, эффекты, звук/Init.
- Редизайн тем, новые темы, виджеты, прочий UI-polish вне 3 файлов + ThemeStore-тестов.
- merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly.

## AC
- AC-1 Все существующие тесты PASS (≥ числа на `61f3bee`). Proof: лог `xcodebuild test -derivedDataPath ~/.drum_dd`. QA: 0 fail, число = база + новые.
- AC-2 Тесты IN-2/IN-3 есть и PASS. Proof: имена + лог. QA: assert'ы реальные (не `XCTAssertNoThrow`).
- AC-3 P3-1: в коде нет `.id(theme…)`; комментарий `MainLayoutView:13-14` актуален. Proof: grep + diff. QA: повторить grep.
- AC-4 P3-5: оба тоста на `.task(id: flashToken)` с `Task.isCancelled`-guard, `asyncAfter` нет. Proof: grep. QA: прочитать оба `body`.
- AC-5 QA-доказательство руками (если тестами не покрыто): (a) переключение темы во время Play — звук не прерывается, состояние панелей (скролл/открытые попапы библиотеки) сохраняется; (b) двойной быстрый Save слота / Assign пресета — подсветка держится 1.2 s от последнего нажатия, без мигания; (c) закрыть библиотеку во время подсветки — нет ошибок/залипания. Proof: скриншоты/короткая запись в `qa/cut9/`.
- AC-6 Diff только: `MainLayoutView.swift` (комментарий/IN-5), `PatternSlotsView.swift`/`SoundLibraryView.swift` (только IN-4/IN-5), новые тесты (+ `project.pbxproj`). Proof: `git diff --stat 61f3bee..HEAD`.
- AC-7 Нет merge в main, нет force-push. Proof: `origin/main` = `61f3bee`. QA: проверить.

## Unlock order
Eng может стартовать по этому файлу. Grok Bot запускает Eng (PM — нет): ветка от `61f3bee` → IN-1 → IN-2/IN-3 → (IN-4/IN-5 при необходимости) → QA по AC-1..7 → Grok Bot роутит nixter для merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-03 — создан CUT_9 (PM), база `61f3bee`. Отмечено: основной фикс P3-1/P3-5 уже в `32694b4`; скоуп сужен до верификации + гардов.
- 2026-11-03 — статус APPROVED-for-Eng → DRAFT — KEEP ME IN; добавлен выбор D1 (закрыть как DONE) / D2 (узкий CUT_9).
- 2026-11-03 — финализация: nixter D2 via Grok Bot → статус **APPROVED-for-Eng (D2)**; Decision needed закрыт (D1 закрыт); Unlock: Grok Bot стартует Eng от `61f3bee`. IN/OUT/AC без изменений.
