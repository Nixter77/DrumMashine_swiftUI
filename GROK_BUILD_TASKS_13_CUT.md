# GROK_BUILD_TASKS_13 — CUT (Binding PRD)

Дата: 2026-11-04 · База: origin/main `e9efc55` (`e9efc5534833ba07ae4c45fd6630dab562a598c1`, проверено `git fetch` + `git rev-parse origin/main`; merge --no-ff cut/12-choke-ui, parents 0b1dac3 + a08b897) · Статус: **APPROVED-for-Eng**: nixter «Дальше» (t328u), 2026-11-04.
Ветка: `cut/13-choke-off` от `e9efc55`. Локальный `main` НЕ использовать: `git switch -c cut/13-choke-off origin/main` или worktree.

## Decision needed
Нет. Прямое продолжение CUT_12 (KEEP ME IN оттуда): «Off» в UI должен значить Off. Живые пады (choke на tap) — OUT, отдельный CUT.
Факты (read-only, на `e9efc55`):
- `Core/Sequencer/SequencerEngine.swift:193` — `private let chokeGroups: [Int: Int] = [2: 1, 5: 1]`; `:347` — `chokeGroup: track.soundPreset.chokeGroup ?? chokeGroups[index] ?? -1` → nil на HIHAT(2)/RIDE(5) всё равно группа 1.
- Factory hats ставят группу явно: `FactoryPresets.swift:34` (CH 808 `choke: 1`), `AcousticKit.swift:38-39,61` (hats `choke: 1`). Значит дефолтный чок хэтов живёт в пресетах, fallback не нужен для factory.
- `SoundPreset.chokeGroup: Int?` (1-4 или nil), Codable `decodeIfPresent`.

## Outcome (одно предложение)
`SequencerEngine` берёт choke только из `soundPreset.chokeGroup` (nil → -1, без fallback-map), так что Off в пикере реально отключает choke на любом треке, а factory hats продолжают чокаться через свою явную группу 1.

## IN
- IN-1 `SequencerEngine.swift`: удалить `chokeGroups` map; `:347` → `track.soundPreset.chokeGroup ?? -1`. Больше ничего в `Core/Sequencer/**` и ни одной строки в `Core/AudioEngine/**`.
- IN-2 Аудит: все factory/kit пресеты категории `.hihat` (и ride, если должен чокаться) имеют явный `choke`. Если какой-то factory hat без `choke` и раньше чокался через fallback — добавить `choke: 1` в `FactoryPresets.swift`/`AcousticKit.swift` (только данные). Список проверенных пресетов — в отчёт.
- IN-3 Тесты `ChokeOffTests`: (a) трек 2 с chokeGroup nil → scheduled event chokeGroup == -1; (b) трек 5 nil → -1; (c) трек 2 с группой 1 → 1; (d) любой трек с группой 3 → 3; (e) каждый factory hat пресет → chokeGroup == 1. Через публичный/internal путь снапшота, без новых хуков в Core сверх IN-1.
- IN-4 Обновить существующие тесты, которые assert'ят fallback (если есть) — только ожидание, с комментарием «CUT_13: nil = Off».
- IN-5 `progress.md`: «Done (CUT_13): choke Off = Off (fallback map removed)»; снять Known limit про fallback; оставить limit про живые пады. Лог тестов в `qa/cut13/`. DerivedData `~/.drum_dd`.

## OUT
- Choke для живых пэдов (`PadsGridView` → `trigger(chokeGroup:)`) — отдельное решение.
- `VoiceEngine`, `AudioEngineManager`, `SequencerScheduler`, fade 3 ms, группы >4, sentinel-значения, миграция сохранённых проектов.
- UI пикера/бейджа (CUT_12) — не трогать, кроме если тест требует.
- Song / pattern chain, P3-2 @Bindable, P3-3/theme (DEFER), CUT_7…12, CR fade, косметика.
- Merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly.

## AC
- AC-1 Все тесты PASS (CUT_12: 225 + новые; QA фиксирует фактическое число). Proof: log `xcodebuild test -derivedDataPath ~/.drum_dd` в `qa/cut13/`. 0 fail.
- AC-2 IN-3 тесты есть и PASS, assert'ы реальные. Proof: имена + log.
- AC-3 Core-дифф минимален: `git diff e9efc55..HEAD -- DrumMashine_swistUI/DrumMachine/Core` = только `SequencerEngine.swift` (удаление map + одна строка); `Core/AudioEngine/**` пусто. golden/Scheduler/VoiceEngine тесты PASS. Proof: diff.
- AC-4 `grep -n "chokeGroups" Core/Sequencer` пусто. Proof: grep.
- AC-5 На слух/визуально (`qa/cut13/`): HIHAT CH 808 (C1) — open hat глушится closed; поставить Off → open hat звенит; RIDE Off → не глушит хэт. Mac GUI недоступен → DEFER с причиной, не soft-pass.
- AC-6 Diff только: `SequencerEngine.swift`, (опц.) `FactoryPresets.swift`/`AcousticKit.swift`, тесты, `project.pbxproj`, `progress.md`, `qa/cut13/*`. Proof: diff --stat.
- AC-7 Нет merge/force-push. Proof: `origin/main` = `e9efc55`.

## STOP / KEEP ME IN
- STOP, если для IN-1 нужно трогать что-то кроме `SequencerEngine.swift` в Core (Scheduler, VoiceEngine, AudioEngineManager).
- STOP, если golden/render тесты меняют вывод из-за удаления fallback и это нельзя объяснить только треками 2/5 с nil — сообщить, не править golden.
- KEEP ME IN: сохранённые пользовательские проекты, где хэт без chokeGroup (nil) раньше чокался через fallback, после CUT_13 перестанут чокаться. Миграцию НЕ делать; описать в progress.md и отчёте. Если nixter захочет миграцию — отдельный CUT.
- KEEP ME IN: если найден factory hat/ride без явной группы и неясно, должен ли он чокаться — оставить nil, перечислить в отчёте.

## Unlock order
Eng ждёт этот файл; Eng стартует Grok Bot, не PM. Ветка `cut/13-choke-off` от `e9efc55` → IN-3 (красные) → IN-1 → IN-2 → IN-4 → IN-5 → QA по AC-1..7 → Grok Bot передаёт nixter решение о merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-04: PM создал CUT_13, база `e9efc55`, APPROVED-for-Eng (nixter «Дальше», t328u). Выбор: real choke Off (follow-up CUT_12 KEEP ME IN).
