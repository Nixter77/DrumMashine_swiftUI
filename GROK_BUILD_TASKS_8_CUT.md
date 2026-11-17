# GROK_BUILD_TASKS_8 — CUT (Binding PRD)

Дата: 2026-11-03 · База: main `26473ad` (`26473ada90e1d416de879ef71821e189e3aa4051`, проверено `git rev-parse`) · Статус: **APPROVED-for-Eng (P2-1 VoiceEngine)** — nixter: «GO P2-1 VoiceEngine», 2026-11-03.

## Decision needed (nixter)
Нет — утверждено (nixter GO P2-1). Новое решение нужно только при STOP по звуку (см. AC-5).

## Outcome (одно предложение)
`Mixer.render` в VoiceEngine перестаёт делать по два `drain` и `smooth()` по 9 дорожкам на каждый сэмпл, а звук остаётся бит-в-бит тем же (или изменение доказано и эскалировано).

## Контекст (Nightly `ddc9da0`, P2-1)
`DrumMashine_swistUI/DrumMachine/Core/AudioEngine/VoiceEngine.swift`, `Mixer.render(frameCount:audioBufferList:)` (~:306-357): цикл `for frame in 0..<frameCount` на каждом кадре вызывает `drain(controlRing, …)`, `drain(sequencerRing, …)`, `mix(frame:…)` и `smooth()` (~:557-562, one-pole по `smoothGain[track]` для `slotCount = 9`). `planPan(frameCount:)` уже работает раз на блок — образец.

## IN
- IN-1 Сегментный рендер: в начале блока и после каждого применённого события определить ближайший `atSample` в `controlRing`/`sequencerRing` (peek, без снятия); рендерить кадры отрезками `[cur, nextEvent)` без вызова `drain`; на границе — `drain` обоих колец с тем же `absolute`, что и сейчас. Порядок «control → sequencer», применение на том же кадре и `planPan` после команд кадра 0 — сохранить точно.
- IN-2 Удешевление `smooth()` **без изменения звука (приоритет)**: пропуск, когда все 9 дорожек сошлись (`smoothGain == targetGain`), флаг `gainSettled` сбрасывается при изменении `targetGain`. Это даёт бит-идентичность.
- IN-3 (только если IN-2 недостаточно и по согласованию) throttle `smooth()` раз в 16–32 кадра или рампа раз на блок как `planPan` — **меняет звук ⇒ STOP/KEEP ME IN** до решения nixter с before/after доказательством (AC-5).
- IN-4 Тесты (новый файл, напр. `VoiceEngineSegmentRenderTests.swift`): (a) trigger с `atSample` в середине блока стартует ровно на том же кадре, что и до фикса; (b) несколько событий в одном блоке + события на кадрах 0 и `frameCount-1`; (c) late-событие (`atSample < blockStart`) всё ещё считается в `lateCounter`; (d) gain-рампа после `setGain` совпадает с эталоном per-frame one-pole; (e) offline-рендер фиксированного паттерна: буфер до/после равен побитно (эталон снимается на `26473ad`).
- IN-5 DerivedData `~/.drum_dd`; ветка от `26473ad`.

## OUT
- Персистентность (CUT_7) — не трогать, даже если что-то открыто.
- P3-1 `.id(theme.style)`, P3-5 toast `asyncAfter`, любой UI/polish, виджеты.
- Groove/swing, scheduler/Sequencer, эффекты, sidechain-логика, дефолты звука/Init.
- Несвязанные рефакторинги VoiceEngine (кольца, voice pool, retire).
- merge в main, force-push, правка истории; Cloud Agents; wake CodeReviewer/Nightly.

## AC
- AC-1 Все существующие тесты PASS (база ≥ текущее число на `26473ad`, включая тесты CUT_7). Proof: лог `xcodebuild test -derivedDataPath ~/.drum_dd`. QA: 0 fail, число = база + новые.
- AC-2 Новые тесты IN-4 (a)–(e) есть и PASS. Proof: имена тестов + лог. QA: assert'ы сравнивают конкретные кадры/сэмплы, не `XCTAssertNoThrow`.
- AC-3 В горячем цикле нет per-frame `drain` и безусловного per-frame `smooth()`. Proof: diff `render`. QA: прочитать цикл; `drain` только на границах сегментов.
- AC-4 Diff только `VoiceEngine.swift` + тесты (+ при необходимости `project.pbxproj` для нового тест-файла). Proof: `git diff --stat 26473ad..HEAD`. QA: сверить список.
- AC-5 Звук: тест IN-4(e) побитно равен эталону; любые существующие golden/audio-тесты без изменений. Если неравно — **STOP**, отчёт с before/after (max abs diff, кадры), KEEP ME IN к nixter; не мержить, не «подкручивать» эталон.
- AC-6 Нет merge в main, нет force-push. Proof: `git log main` = `26473ad`. QA: проверить.
- AC-7 Нормы Drum как в CUT_7: auval/Synt-гейтов нет; запуск приложения не обязателен.

## Unlock order
CUT утверждён → Grok Bot запускает Eng (не PM): ветка от `26473ad` → IN-1 → IN-2 → IN-4 (тесты после каждого шага) → QA по AC-1..7 → Grok Bot роутит nixter для merge. IN-3 — только после отдельного решения nixter.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён; любое звуковое расхождение = FAIL/STOP.

## Change control
- 2026-11-03 — создан CUT_8 (PM), база `26473ad`, P2-1 IN (nixter GO). P2-1 был OUT в CUT_7.
