# GROK_BUILD_TASKS_14 — CUT (Binding PRD)

Дата: 2026-11-04 · База: origin/main `e0b7265` (`e0b72656aaadcdc498cb9eb155609eaaed7b62fc`, проверено `git fetch` + `git rev-parse origin/main`; merge --no-ff cut/13-choke-off, parents e9efc55 + 9c8f1d7) · Статус: **APPROVED-for-Eng**: nixter «дальше» (t331u), 2026-11-04.
Ветка: `cut/14-live-pad-choke` от `e0b7265`. Локальный `main` НЕ использовать: `git switch -c cut/14-live-pad-choke origin/main` или worktree.

## Decision needed
Нет. Продолжение CUT_13 KEEP ME IN: живые пады должны чокаться так же, как секвенсор. Проводка уже есть, нужен один аргумент.
Факты (read-only, на `e0b7265`):
- `Features/Pads/PadsGridView.swift:36` — `AudioEngineManager.shared.trigger(trackIndex: index, velocity: velocity)` → chokeGroup не передаётся → `-1` → тап по пэду никогда не чокает.
- `Core/AudioEngine/AudioEngineManager.swift:795` — `trigger(trackIndex:velocity:chokeGroup: Int? = nil)` уже принимает группу (`?? -1` → `VoiceEngine.trigger`). Core менять не нужно.
- `Core/Sequencer/SequencerEngine.swift:343` — секвенсор: `track.soundPreset.chokeGroup ?? -1` (эталон семантики после CUT_13).
- Это единственный вызов `trigger(trackIndex:` в `Features/**`.

## Outcome (одно предложение)
Тап по пэду передаёт `sequencer.tracks[index].soundPreset.chokeGroup` в `AudioEngineManager.trigger`, так что open hat глушится тапом closed hat той же группы, а Off (nil) не чокает — ровно как в секвенсоре.

## IN
- IN-1 `PadsGridView.swift:36`: передать `chokeGroup: sequencer.tracks[index].soundPreset.chokeGroup` (с тем же guard по индексу, что у `chokeBadge(track:)`). Ноль строк в `Core/**`.
- IN-2 Маленький чистый helper (напр. `PadTriggerChoke.group(for: SoundPreset) -> Int?` или static в `ChokeGroupOption`) в `Features/**`, чтобы тестировать маппинг без UI; PadsGridView использует его.
- IN-3 Тесты `LivePadChokeTests`: (a) preset с группой 1 → 1; (b) nil → nil (→ -1 в engine); (c) группа 4 → 4; (d) helper и `SequencerEngine` дают одинаковое итоговое значение для nil/1/3 (паритет; через существующий путь снапшота секвенсора, без новых хуков в Core).
- IN-4 `progress.md`: «Done (CUT_14): live pad choke (tap = sequencer semantics)»; снять Known limit про живые пады. Лог тестов в `qa/cut14/`. DerivedData `~/.drum_dd`.

## OUT
- Любые правки `Core/AudioEngine/**`, `Core/Sequencer/**` (VoiceEngine, AudioEngineManager, Scheduler, SequencerEngine), fade 3 ms, группы >4.
- MIDI/клавиатурный trigger, preview (`previewTrack`, chokeGroup -1) — не трогать.
- SoundLibraryManager hats без группы; миграция сохранённых проектов — отдельные CUT.
- UI пикера/бейджа (CUT_12), Song/chain, P3-2 @Bindable, P3-3/theme (DEFER), CUT_7…13, CR fade, косметика.
- Merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly.

## AC
- AC-1 Все тесты PASS (CUT_13: 231 + новые; QA фиксирует фактическое число). Proof: log `xcodebuild test -derivedDataPath ~/.drum_dd` в `qa/cut14/`. 0 fail.
- AC-2 IN-3 тесты есть и PASS, assert'ы реальные. Proof: имена + log.
- AC-3 `git diff e0b7265..HEAD -- DrumMashine_swistUI/DrumMachine/Core` пусто. Proof: diff.
- AC-4 `grep -n "trigger(trackIndex" Features` → единственный вызов содержит `chokeGroup:`. Proof: grep.
- AC-5 На слух (`qa/cut14/`): тап open hat → тап closed hat (обе C1) — open глушится; Off на open hat → звенит; тап во время playback чокает голос секвенсора той же группы. Mac GUI недоступен → DEFER с причиной, не soft-pass.
- AC-6 Diff только: `PadsGridView.swift`, helper-файл в `Features/**`, тесты, `project.pbxproj`, `progress.md`, `qa/cut14/*`. Proof: diff --stat.
- AC-7 Нет merge/force-push. Proof: `origin/main` = `e0b7265`.

## STOP / KEEP ME IN
- STOP, если для чока на тапе нужно менять что-либо в `Core/**` (сигнатура trigger, VoiceEngine, thread/ring) — сообщить, не править.
- STOP, если `sequencer.tracks[index]` недоступен в PadsGridView в момент тапа или index ≠ track index — сообщить маппинг, не изобретать.
- STOP, если golden/render/VoiceEngine тесты меняются.
- KEEP ME IN: library hats без группы и старые проекты с nil на хэтах на тапе тоже не чокаются (как в секвенсоре). Не чинить; отметить в progress.md/отчёте — кандидаты CUT_15.

## Unlock order
Eng ждёт этот файл; Eng стартует Grok Bot, не PM. Ветка `cut/14-live-pad-choke` от `e0b7265` → IN-3 (красные) → IN-2 → IN-1 → IN-4 → QA по AC-1..7 → Grok Bot передаёт nixter решение о merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-04: PM создал CUT_14, база `e0b7265`, APPROVED-for-Eng (nixter «дальше», t331u). Выбор: live pad choke (CUT_13 KEEP ME IN; проводка готова, Core не трогаем).
