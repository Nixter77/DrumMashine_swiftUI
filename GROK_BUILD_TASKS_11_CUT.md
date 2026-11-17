# GROK_BUILD_TASKS_11 — CUT (Binding PRD)

Дата: 2026-11-03 · База: origin/main `60fe003` (`60fe00373aa46183f59db826cf9d92644613ecb5`, проверено `git fetch` + `git rev-parse origin/main`) · Статус: **APPROVED-for-Eng**: nixter написал «дальше» через Grok Bot (t321u), 2026-11-03.
Ветка: `cut/11-groove-ticks` от `60fe003`. Локальный `main` (3206c2b, разошёлся с origin) НЕ использовать: `git switch -c cut/11-groove-ticks origin/main` или worktree.

## Decision needed
Нет. Взят открытый продуктовый пункт `progress.md:242`: «Not done: groove offset ticks in the sequencer header». Это только UI. Звук не меняется: GrooveSnapshot и SequencerScheduler только читаем, не правим.
Почему не P3-2/P3-3: P3-2 CR оставил осознанно, P3-3/AC-5 nixter отложил (DEFER). Оба косметика.

## Outcome (одно предложение)
Когда выбран не «Чистый» groove, под номерами шагов в хедере секвенсора видны тики сдвига: смещение влево или вправо пропорционально timing-offset шага (с учётом STRENGTH×TIMING). При «Чистый» тиков нет, хедер выглядит как раньше.

## IN
- IN-1 Чистая модель (напр. `Features/Sequencer/GrooveTicks.swift`): `static func offsets(template: GrooveTemplate?, settings: GrooveSettings, stepCount: Int) -> [Double]`. Длина = stepCount (16/32; для 32 шаблон повторяется по `i % GrooveTemplate.length`, тем же правилом, что в scheduler: сверить со `SequencerScheduler`/`SequencerEngine+Groove`). Значения в долях шага, как `GrooveSnapshot(template:settings:).timing`, переиспользовать этот init, формулу не дублировать. Clean / nil / inactive → все 0 (или `[]`, а view тики не рисует).
- IN-2 Хедер в `SequencerView.swift` (блок «Step Number Header», `HStack` с `ForEach(beatCount)`): под каждой цифрой тонкий тик (≈1×4 pt) в `.overlay`, сдвиг по X = offset × ширина ячейки шага (`GeometryReader` внутри ячейки или `alignmentGuide`). Высоту хедера 16 pt не менять или увеличить максимум до ~20, без сдвига сетки и плейхеда. Цвет: `AppTheme.accent` (Dark и Light). Тик при |offset| < 0.01 не рисовать.
- IN-3 Хедер читает только `grooveSettings` и активный шаблон (`activeGroove` или эквивалент в `SequencerEngine+Groove`), а не `currentStep`/`isPlaying`. Инвариант CUT_10 (сетка не читает `currentStep`) сохранить: `StepFlashSourceGuardTests` PASS.
- IN-4 Тесты `GrooveTicksTests`: (a) Чистый → нет тиков; (b) MPC/Shuffle → ненулевые offset на нечётных 16-х, знак и величина = `GrooveSnapshot.timing`; (c) amount 50 → в два раза меньше; (d) timing 0 → все 0; (e) stepCount 32 → повтор шаблона; (f) перебор всех 10 factory grooves: длина = stepCount, значения в `timingRange`.
- IN-5 `progress.md`: строку «Not done: groove offset ticks…» заменить кратким описанием сделанного. Лог тестов положить в `qa/cut11/`. DerivedData `~/.drum_dd`.

## OUT
- Аудио, тайминг и scheduler: `Core/AudioEngine/**`, `Core/Sequencer/**` (Groove.swift, SequencerScheduler, SequencerEngine*) только читаем; правка = STOP.
- GrooveControlView, редактор шаблонов, запись/extract/bake, новые grooves.
- Тики в самих шагах сетки, перенос плейхеда по offset, анимации.
- P3-2 @Bindable ThemeStore, P3-3/AC-5 theme (DEFER). Повторно не трогать CUT_7/8/9/10 и CR fade.
- Merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly; виджеты.

## AC
- AC-1 Все существующие тесты PASS (на `60fe003` их 213) плюс новые. Proof: лог `xcodebuild test -derivedDataPath ~/.drum_dd` в `qa/cut11/`. QA: 0 fail, число = 213 + новые.
- AC-2 Тесты IN-4 есть и PASS, assert'ы реальные (сравнение с `GrooveSnapshot`, не тавтология). Proof: имена и лог. QA: прочитать.
- AC-3 Звук не меняется: `git diff --stat 60fe003..HEAD` не трогает `Core/AudioEngine/**`, `Core/Sequencer/**`; golden-тесты и GrooveTests PASS. QA: проверить.
- AC-4 Перф-инвариант: в хедере и `SequencerTracksView`/`SequencerRowView`/`StepButtonView` нет `currentStep` (кроме уже существующего TopBar/Overlay), source-guard PASS. Proof: grep. QA: повторить.
- AC-5 Визуально (QA руками или скрин в `qa/cut11/`): Чистый → тиков нет; MPC 58 / Shuffle → тики на офф-битах сдвинуты вправо; STRENGTH 0 → тики пропадают; 16 и 32 шага; Dark и Light; сетка и плейхед не сдвинулись. Если скрин сделать нельзя, QA пишет DEFER с причиной (не soft-pass).
- AC-6 Diff только: `SequencerView.swift`, новый `GrooveTicks.swift`, тесты, `project.pbxproj`, `progress.md`, `qa/cut11/*`. Proof: diff --stat.
- AC-7 Нет merge в main и force-push. Proof: `origin/main` = `60fe003`. QA: проверить.

## STOP / KEEP ME IN
- STOP, если для тиков нужно менять Groove.swift/scheduler/SequencerEngine (кроме чтения уже публичных свойств). Тогда вернуть Grok Bot варианты (напр. read-only computed var в расширении Features).
- STOP, если 32-шаговое правило применения шаблона в scheduler неочевидно или не `i % 16`. Тогда описать фактическое правило и KEEP ME IN.
- STOP, если тики требуют увеличить хедер больше ~20 pt или ломают выравнивание с колонками (HStack drift, NOTE в StepButtonView).
- Random jitter не визуализировать: он не детерминирован, это OUT.

## Unlock order
Eng ждёт этот файл; Eng стартует Grok Bot, не PM. Порядок: ветка `cut/11-groove-ticks` от `60fe003` → IN-1+IN-4 → IN-2+IN-3 → IN-5 → QA по AC-1..7 → Grok Bot передаёт nixter решение о merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-03: PM создал CUT_11, база `60fe003`, APPROVED-for-Eng (nixter «дальше», t321u). Выбор: groove offset ticks из progress.md:242.
