# GROK_BUILD_TASKS_10 — CUT (Binding PRD)

Дата: 2026-11-03 · База: origin/main `66126f2` (`66126f27ea60ede4fc97ecadbf36c84604824009`, проверено `git fetch` + `git rev-parse origin/main`) · Статус: **APPROVED-for-Eng** — nixter «Дальше» via Grok Bot (t318u), 2026-11-03.
Ветка: `cut/10-step-flash` от `66126f2`. Локальный `main` (3206c2b/divergent) НЕ использовать — `git switch -c cut/10-step-flash origin/main` или worktree.

## Decision needed
Нет. Выбран продуктовый кусок из `progress.md:233` («Not done yet: step flash when the playhead hits it», Studio Light design). Без звукового риска: только UI-слой поверх сетки, аудио/Sequencer не трогаем.
Почему не P3-2/P3-3: P3-2 (@Bindable ThemeStore в App) — CR оставил осознанно (нужен `$theme.style`), P3-3/AC-5 — ручной DEFER nixter. Оба косметика; в этот CUT не кладём.

## Outcome (одно предложение)
Во время Play активный шаг под плейхедом коротко вспыхивает цветом своей дорожки (Dark и Studio Light), при этом сетка шагов по-прежнему не читает `currentStep` (перерисовывается только оверлей).

## IN
- IN-1 Чистая модель вспышки (напр. `Features/Sequencer/StepFlash.swift`): `static func flashedRows(tracks: [SequencerTrack], step: Int) -> [Int]` — индексы дорожек, где `steps[step].isActive`, дорожка не muted (и с учётом solo, если в модели есть solo — тем же правилом, что слышимость в SequencerScheduler; без изменения Scheduler). Вне диапазона `step` → `[]`.
- IN-2 Якоря по строке: `StepColumnKey` (или новый ключ) должен давать `[column: [row: Anchor]]` (сейчас — массив без индекса строки). StepButtonView публикует `(column, trackIndex)`. Курсор колонки рисуется как раньше (пиксель-в-пиксель по тем же rect).
- IN-3 `PlayheadOverlay`/`PlayheadCursor`: поверх rect каждой строки из IN-1 — вспышка цветом дорожки (Dark: fill trackColor ~0.35 + glow; Light: белый блик/glow в духе CandyFill), затухание ~120–180 мс на смену `step`. Reduce Motion → статичная подсветка без анимации. `allowsHitTesting(false)`.
- IN-4 Инвариант производительности: `SequencerTracksView`/`SequencerRowView`/`StepButtonView` не читают `currentStep`/`isPlaying` (как сейчас). Добавить source-scan тест (паттерн CUT_9 IN-3): в этих трёх view нет `currentStep`.
- IN-5 Тесты `StepFlashTests`: (a) активный+немьют → в списке; (b) неактивный → нет; (c) muted → нет; (d) solo-правило (если есть); (e) step вне диапазона/stepCount 16/32 → корректно; (f) пустые дорожки → `[]`.
- IN-6 `progress.md`: строку «Not done yet: step flash…» заменить на краткое описание сделанного. DerivedData `~/.drum_dd`.

## OUT
- Аудио: VoiceEngine, Mixer, SequencerScheduler, EffectsChain, тайминг, Groove/Swing (CUT_7/8/CR fade — закрыты, не переоткрывать).
- Groove offset ticks в хедере (`progress.md:242`) — отдельный CUT.
- P3-2 @Bindable ThemeStore, P3-3/AC-5 theme redraw (DEFER nixter).
- Редизайн сетки/кнопок, новые темы, виджеты, анимации вне вспышки.
- merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly.

## AC
- AC-1 Все существующие тесты PASS (≥ ~204 на `66126f2`) + новые. Proof: лог `xcodebuild test -derivedDataPath ~/.drum_dd`. QA: 0 fail, число = база + новые.
- AC-2 IN-5 тесты есть и PASS, assert'ы реальные. Proof: имена + лог. QA: прочитать.
- AC-3 Инвариант IN-4: source-scan тест PASS; `grep -n currentStep` по трём view = 0. Proof: grep. QA: повторить.
- AC-4 Без звукового изменения: diff не трогает `Core/AudioEngine/**`, `Core/Sequencer/**`. Proof: `git diff --stat 66126f2..HEAD`. QA: проверить; golden/VoiceEngine тесты PASS.
- AC-5 Визуально (QA руками или скрин/запись в `qa/cut10/`): Play 16 и 32 шага, Dark и Light — вспыхивают только активные немьют шаги в текущей колонке цветом дорожки; курсор колонки на месте; Stop → вспышек нет; Reduce Motion → без анимации. Если запись невозможна — QA пишет DEFER с причиной (не soft-pass).
- AC-6 Diff только: `SequencerView.swift`, `StepButtonView.swift`, новый `StepFlash.swift`, тесты, `project.pbxproj`, `progress.md`, `qa/cut10/*`. Proof: diff --stat.
- AC-7 Нет merge в main, нет force-push. Proof: `origin/main` = `66126f2`. QA: проверить.

## STOP / KEEP ME IN
- STOP, если для вспышки нужно читать `currentStep` в сетке/строках (ломает перф-дизайн) — вернуть варианты Grok Bot.
- STOP, если затронуты аудио/Scheduler файлы или меняется golden.
- STOP, если per-row якоря требуют переписать layout сетки (дрейф HStack, см. NOTE в StepButtonView) — KEEP ME IN.
- Правило solo неочевидно из модели → реализовать только mute, отметить в отчёте.

## Unlock order
Eng ждёт этот файл; Grok Bot стартует Eng (PM — нет): ветка `cut/10-step-flash` от `66126f2` → IN-1+IN-5 → IN-2 → IN-3 → IN-4 → IN-6 → QA по AC-1..7 → Grok Bot роутит nixter для merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-03 — создан CUT_10 (PM), база `66126f2`, APPROVED-for-Eng (nixter «Дальше», t318u). Выбор: step flash из progress.md:233.
