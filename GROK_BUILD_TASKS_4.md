# GROK_BUILD_TASKS_4 — пресеты эффектов и сцены

База: `a54b718` (40 ритмов). Сначала закоммить этот файл (`docs: add GROK_BUILD_TASKS_4`), потом **по одному коммиту на задачу**. Если лимит кончится посреди работы, готовые задачи останутся целыми, а следующая начнётся с чистого места. В конце допиши `progress.md`.

Ты не слышишь звук. Значения ниже переноси как есть; nixter подстроит на слух.

## Что есть в коде (проверено на `a54b718`)

- `EffectsChain` (`Core/AudioEngine/EffectsChain.swift`): `reverb {isOn, wetDryMix 0…1, room}`, `delay {isOn, wetDryMix 0…1, delayTime 0.05…2.0 с, feedback 0…100, lowPassCutoff Гц}`, `distortion {isOn, wetDryMix 0…1, preGain −20…+20 дБ}`, `eq {isOn, low, mid, high −12…+12 дБ}`.
- `ReverbRoom`: `smallRoom`, `mediumRoom`, `largeRoom`, `mediumHall`, `largeHall`.
- Применение: `AudioEngineManager.shared.effectsChain = …` и `updateEffects()` (`AudioEngineManager.swift:593`), оно же сохраняет сессию.
- Цепочка общая на весь проект и уже лежит в `SessionState.effectsChain` и в `.drumproj` (`DrumProject.session`).
- UI: `Features/EffectsRack/EffectsRackView.swift`, модули `EffectModuleView` (REVERB, DELAY, DISTORT, 3-BAND EQ).

## Пресеты по эффектам

Выбор пресета включает этот эффект (`isOn = true`) и ставит значения. Остальные эффекты не трогает.

**Reverb**

| имя | room | mix |
|---|---|---|
| Room | smallRoom | 0.20 |
| Studio | mediumRoom | 0.25 |
| Big Room | largeRoom | 0.30 |
| Hall | mediumHall | 0.35 |
| Cathedral | largeHall | 0.50 |

**Delay.** «Доли» — время в долях такта по BPM: `delayTime = доли × 60 / bpm`, зажать в 0.05…2.0.

| имя | время | feedback | mix | lowPass Гц |
|---|---|---|---|---|
| Slapback | 0.09 с (без синхронизации) | 10 | 0.25 | 8000 |
| 1/16 | 0.25 доли | 25 | 0.20 | 12000 |
| 1/8 | 0.5 доли | 35 | 0.25 | 10000 |
| 1/4 Dotted | 0.75 доли | 40 | 0.25 | 9000 |
| Dub | 0.75 доли | 70 | 0.35 | 3000 |

**Distortion**

| имя | mix (DRIVE) | preGain дБ |
|---|---|---|
| Warm | 0.15 | −10 |
| Crunch | 0.35 | 0 |
| Fuzz | 0.60 | +10 |
| Destroy | 0.85 | +18 |

**EQ**

| имя | low | mid | high |
|---|---|---|---|
| Punch | +4 | −2 | +2 |
| Bright | 0 | 0 | +5 |
| Scoop | +3 | −5 | +3 |
| Warm | +3 | 0 | −4 |
| Telephone | −12 | +6 | −12 |

## Сцены (все четыре эффекта сразу)

Сцена задаёт все четыре блока, включая выключенные. «off» = `isOn = false`, остальные значения блока не трогать.

| сцена | reverb | delay | distortion | EQ |
|---|---|---|---|---|
| Clean | off | off | off | off |
| Club | Room, mix 0.15 | off | off | Punch |
| Lo-Fi Tape | Room, mix 0.15 | off | Warm | low +2, mid +1, high −8 |
| Dub | Hall | Dub | off | Warm |
| Industrial | Big Room, mix 0.25 | 1/16 | Fuzz | Scoop |
| Ambient | Cathedral | 1/4 Dotted | off | off |

«Room, mix 0.15» = пресет Room, но mix 0.15. «low +2, mid +1, high −8» — EQ с этими значениями без имени пресета.

---

## Задачи

### F-1 (P0) Данные пресетов и сцен
- **Файлы:** новый `Core/AudioEngine/EffectPresets.swift`.
- **Сделать:** `enum EffectPresets` со списками `reverb`, `delay`, `distortion`, `eq` и `scenes` по таблицам выше. Каждый пресет — `id` (строка, `reverb.room` и т.п.), `name` и функция `apply(to: inout EffectsChain, bpm: Double)`. Все значения только в этом файле.
- **Проверка:** тесты `EffectPresetTests`: число пресетов 5/5/4/5 и 6 сцен, id уникальны; каждый пресет даёт значения из таблицы и `isOn == true` только у своего блока; `Clean` выключает все четыре; `Dub` при 120 BPM даёт `delayTime == 0.375`, `1/16` при 60 BPM — `0.25`; при 20 BPM время зажато в 2.0.

### F-2 (P0) Делей следует за темпом
- **Файлы:** `EffectsChain.swift`, `AudioEngineManager.swift`, `SequencerEngine.swift`, `EffectsRackView.swift`.
- **Сделать:** в `DelaySettings` новое поле `syncBeats: Double?` (`decodeIfPresent`, по умолчанию nil, старые сохранения читаются как раньше). Синхронные пресеты ставят `syncBeats`; при смене BPM `delayTime` пересчитывается. Ручное движение ручки TIME сбрасывает `syncBeats` в nil. На ручке TIME при синхронизации показывать долю (`1/8`, `1/4.`) вместо секунд.
- **Проверка:** тесты: смена BPM 120 → 90 с пресетом 1/8 даёт 0.333 с; после ручного TIME смена BPM время не меняет; JSON старой сессии без `syncBeats` декодируется.

### F-3 (P0) Меню пресетов и сцен в интерфейсе
- **Файлы:** `EffectsRackView.swift`.
- **Сделать:** в заголовке каждого модуля маленькое меню `PRESET ▾` со списком пресетов этого эффекта. Слева от модулей меню `SCENE ▾` со сценами (и пользовательскими сценами из F-4 отдельной секцией). Рядом с меню видно имя последнего выбранного пресета или сцены; после ручного движения любой ручки этого блока имя пропадает. Применение через `effectsChain` + `updateEffects()`; Cmd+Z отменяет выбор пресета или сцены (имя действия «Effect Preset»).
- **Проверка:** снимок раскладки 1100×720, ничего не обрезано и не наезжает; UI-тест: SCENE → Dub → reverb и delay включены, distortion выключен.

### F-4 (P1) Свои сцены
- **Файлы:** новый `Core/Persistence/EffectSceneStore.swift`, `DrumProject.swift`, `EffectsRackView.swift`.
- **Сделать:** в меню SCENE пункт «Сохранить текущие эффекты…» с полем имени. Сцена = имя + копия `EffectsChain`. Хранить рядом с остальными данными в Application Support (`effect_scenes.json`, версия, как у `PatternStore`). Контекстное меню: переименовать, удалить. Сцены входят в экспорт и импорт `.drumproj` (`decodeIfPresent`, старые файлы открываются).
- **Проверка:** тесты: сохранить → новый экземпляр стора → сцена на месте и `==`; экспорт/импорт `.drumproj` сохраняет сцены; старый `.drumproj` без поля открывается; битый `effect_scenes.json` показывает существующий баннер ошибки и не роняет запуск.

### F-5 (P2) Запись в progress.md
- Список пресетов и сцен со значениями (можно ссылкой на этот файл) и чек-лист для nixter: прослушать каждую сцену на 2–3 ритмах, отметить, что подправить.

## Не трогать
- Сами эффекты и их маршрутизацию в аудиодвижке, только значения.
- Ритмы и пресеты звуков.
