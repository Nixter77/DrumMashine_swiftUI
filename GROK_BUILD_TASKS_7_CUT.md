# GROK_BUILD_TASKS_7 — CUT (Binding PRD)

Дата: 2026-11-03 · База: main `32694b4` · Статус: **APPROVED-for-Eng (вариант A)** — nixter выбрал A, 2026-11-03.

## Decision needed (nixter)
Нет — **утверждён вариант A** (персистентность). Отложено: B (P3-1 theme `.id`, P3-5 toast `asyncAfter` — известны из Nightly `ddc9da0`/`0316ad2`, OUT этого CUT) и C (P2-1 VoiceEngine — отдельный раунд). Tip `32694b4`.

## Outcome (вариант A, одно предложение)
Старые и частично битые файлы проекта/сессии гарантированно открываются с дефолтами, и это доказано тестами.

## IN (вариант A)
- IN-1 Фикстуры legacy JSON (без новых ключей) в `DrumMashine_swistUITests/Fixtures/`.
- IN-2 Тесты decode-defaults: DrumProject session/slots, SoundPreset, track soundPreset, pattern/kit names (покрывает 11b3c00, 28e21e8).
- IN-3 Тест round-trip encode→decode == equal для DrumProject и GrooveSettings.
- IN-4 Тест: битый/пустой user_grooves.json → пустой список, без краша, лог через AppLog.
- IN-5 Только тесты + минимальный фикс decode, если тест падает (каждый фикс — отдельный коммит с причиной).

## OUT (вариант A)
- P2-1 VoiceEngine per-sample (отдельно, позже, решение nixter).
- P3-1 `.id(theme.style)` в MainLayoutView и P3-5 toast `asyncAfter` (вариант B, отложен).
- Любые изменения аудио-пути, scheduler, groove/swing, эффектов, Init/дефолтов звука.
- UI, виджеты, новые фичи.
- merge/force-push, правка истории main; Cloud Agents (если не попросят).
- Wake CodeReviewer/Nightly.

## AC (вариант A)
- AC-1 Все существующие 185 тестов PASS. Proof: лог xcodebuild test (DerivedData `~/.drum_dd`). QA: сверить число ≥185+новые, 0 fail.
- AC-2 ≥1 legacy-фикстура на каждый тип из IN-2 декодируется с ожидаемыми дефолтами. Proof: имена тестов. QA: прочитать assert'ы — сравнение конкретных значений, не просто `XCTAssertNoThrow`.
- AC-3 Round-trip DrumProject и GrooveSettings равны. Proof: тест. QA: модель с непустыми grooves/slots.
- AC-4 Битый user_grooves.json не крашит, возвращает []. Proof: тест. QA: проверить, что файл не перезаписан молча.
- AC-5 Diff не трогает файлы в `Audio/`, `Sequencer*`, `Effects*`, `VoiceEngine*`. Proof: `git diff --stat 32694b4..HEAD`. QA: сверить список.
- AC-6 Production-код изменён только если тест из AC-2..4 упал; каждое изменение обосновано в коммите. QA: нет "заодно".

## Unlock order
CUT утверждён → Eng может стартовать по этому файлу (запускает Grok Bot, не PM): ветка от `32694b4`, без merge → QA по AC-1..6 → Grok Bot роутит nixter для merge.

## Роли
- Eng: Grok Build по этому файлу; один коммит на IN; тесты после каждого.
- QA: независимая проверка AC с доказательствами; soft-pass запрещён.

## Change control
- 2026-11-03 — создан draft (PM), база `32694b4`.
- 2026-11-03 — добавлен вариант B (P3-1 + P3-5) из Nightly `ddc9da0`/`0316ad2`; tip `32694b4`.
- 2026-11-03 — nixter выбрал A → APPROVED-for-Eng; B/C отложены, секция B удалена.
