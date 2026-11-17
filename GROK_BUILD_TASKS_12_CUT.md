# GROK_BUILD_TASKS_12 — CUT (Binding PRD)

Дата: 2026-11-04 · База: origin/main `0b1dac3` (`0b1dac334c2c58e2414902020a2186fda1522793`, проверено `git fetch` + `git rev-parse origin/main`) · Статус: **APPROVED-for-Eng**: nixter выбрал **A** через Grok Bot («Продолжай» / GO A, t325s1599), 2026-11-04.
Ветка: `cut/12-choke-ui` от `0b1dac3`. Локальный `main` (3206c2b, разошёлся с origin) НЕ использовать: `git switch -c cut/12-choke-ui origin/main` или worktree.

## Decision needed
Нет. Выбор A (choke-group UI). Пункта нет в progress.md — nixter подтвердил, что так можно. Это только UI поверх существующей модели. `Core/AudioEngine/**` и `Core/Sequencer/**` только читаем.
Как сейчас устроен choke (read-only факты):
- `Core/Models/SoundPreset.swift:145` — `var chokeGroup: Int? = nil  // 1-4 or nil`, Codable (`decodeIfPresent`), копируется в `:294`.
- `Core/Sequencer/SequencerEngine.swift:193,347` — `chokeGroup: track.soundPreset.chokeGroup ?? chokeGroups[index] ?? -1`, fallback-map `[2: 1, 5: 1]` (трек HIHAT=2 и RIDE=5 → группа 1, если в пресете nil).
- `SequencerScheduler` / `VoiceEngine.choke(group:)` — группа ≥0 глушит голоса той же группы (fade 3 ms).
- Factory hats (`FactoryPresets.swift`, `AcousticKit.swift`) ставят `choke: 1`.
- Пады: `PadsGridView.swift:36` вызывает `AudioEngineManager.trigger(trackIndex:velocity:)` БЕЗ chokeGroup → живой удар по паду сейчас не чокает (только секвенсор).

## Outcome (одно предложение)
В редакторе звука пада есть пикер choke-группы (Off / 1 / 2 / 3 / 4), значение пишется в `soundPreset.chokeGroup` и сохраняется; на паде в сетке маленький бейдж «C1…C4», если группа задана; секвенсор использует новое значение без изменений в Core.

## IN
- IN-1 Чистая модель `Features/SoundEditor/ChokeGroupOption.swift`: `enum ChokeGroupOption: CaseIterable { off, g1, g2, g3, g4 }` + `init(preset: Int?)`, `var presetValue: Int?`, `var badge: String?` («C1».. / nil). Диапазон 1…4 из комментария SoundPreset; значение вне диапазона → показывать как есть (не терять), не крашить.
- IN-2 Пикер в `PadADSREditorView.swift` (секция под ADSR/контролами, сегмент или `Menu`): bind к `preset.chokeGroup` через уже существующий binding из `PadsGridView.swift:90-97` (`sequencer?.tracks[idx].soundPreset`). Подпись «Choke». Без новых observable-сторов.
- IN-3 Бейдж на паде `DrumPadView.swift`: маленький капсульный бейдж в углу (≈ caption2), `AppTheme` цвета Dark/Light, только если группа задана. Источник — `sequencer.tracks[index].soundPreset.chokeGroup` (передать в `DrumPadView` как параметр `chokeBadge: String?` из `PadsGridView`). НЕ читать `currentStep`/`isPlaying`.
- IN-4 Тесты `ChokeGroupOptionTests`: (a) nil ↔ off; (b) 1…4 roundtrip; (c) badge строки; (d) Codable roundtrip `SoundPreset` с chokeGroup 3 и nil; (e) factory hats → `.g1`, бейдж «C1».
- IN-5 `progress.md`: добавить строку «Done: choke-group UI (picker + pad badge)» + известное ограничение про fallback/пады (см. STOP). Лог тестов в `qa/cut12/`. DerivedData `~/.drum_dd`.

## OUT
- Любые правки `Core/AudioEngine/**`, `Core/Sequencer/**` (VoiceEngine, AudioEngineManager, SequencerEngine fallback-map, SequencerScheduler) — правка = STOP.
- Смена семантики choke / scheduler: fade, приоритет fallback-map, новые группы >4, choke для живых пэдов (передача chokeGroup в trigger) — отдельное решение.
- Song / pattern chain mode, виджеты.
- P3-2 @Bindable ThemeStore, P3-3/AC-5 theme (DEFER). CUT_7…11 и CR fade не трогать.
- Merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly.

## AC
- AC-1 Все существующие тесты PASS + новые (CUT_11: 213 + новые; на `0b1dac3` grep находит ~225 test-деклараций — QA фиксирует фактическое число из лога). Proof: test log `xcodebuild test -derivedDataPath ~/.drum_dd` в `qa/cut12/`. QA: 0 fail.
- AC-2 Тесты IN-4 есть и PASS, assert'ы реальные. Proof: имена + test log.
- AC-3 Звук/Core не тронут: `git diff --stat 0b1dac3..HEAD` без `Core/AudioEngine/**`, `Core/Sequencer/**`; golden/Scheduler тесты PASS. Proof: SHA + diff --stat.
- AC-4 Перф: `DrumPadView`/бейдж не читают `currentStep`; `StepFlashSourceGuardTests` PASS. Proof: grep.
- AC-5 Визуально (screenshot в `qa/cut12/`): CH 808 на HIHAT → бейдж C1; сменить на Off → бейдж пропал; 2 → «C2»; перезапуск приложения → значение сохранилось; Dark и Light. Нельзя скрин → DEFER с причиной, не soft-pass.
- AC-6 Diff только: `ChokeGroupOption.swift`, `PadADSREditorView.swift`, `DrumPadView.swift`, `PadsGridView.swift`, тесты, `project.pbxproj`, `progress.md`, `qa/cut12/*`. Proof: diff --stat.
- AC-7 Нет merge/force-push. Proof: `origin/main` = `0b1dac3` (SHA).

## STOP / KEEP ME IN
- STOP, если для пикера/бейджа нужно менять что-то в `Core/AudioEngine/**` или `Core/Sequencer/**`.
- KEEP ME IN (известное): «Off» = nil, но на треках 2 (HIHAT) и 5 (RIDE) fallback-map `[2:1, 5:1]` в SequencerEngine всё равно даст группу 1. Eng НЕ чинит в Core; бейдж показывает только значение пресета; описать ограничение в progress.md и отчёте. Если nixter хочет настоящий Off — отдельный CUT (например, sentinel 0 / -1 или удаление fallback).
- KEEP ME IN: живые пады не чокают (`PadsGridView` не передаёт chokeGroup). Не чинить в этом CUT без решения Grok Bot/nixter.
- STOP, если binding из `PadsGridView` не доходит до `PadADSREditorView` без нового стора/синглтона, или изменение пресета вызывает перезагрузку сэмпла (`soundReloadTasks`, `onChange(of: soundPreset)` :108) с щелчком/задержкой — сообщить, не обходить.
- STOP, если бейдж ломает раскладку пада / hit-area.

## Unlock order
Eng ждёт этот файл; Eng стартует Grok Bot, не PM. Порядок: ветка `cut/12-choke-ui` от `0b1dac3` → IN-1+IN-4 → IN-2 → IN-3 → IN-5 → QA по AC-1..7 → Grok Bot передаёт nixter решение о merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-04: PM создал CUT_12, база `0b1dac3`, APPROVED-for-Eng (nixter GO A, t325s1599). Выбор: choke-group UI.
