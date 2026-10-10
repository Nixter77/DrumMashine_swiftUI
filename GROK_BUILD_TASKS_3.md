# GROK_BUILD_TASKS_3 — библиотека готовых ритмов (factory patterns)

База: `b0526dc` (все задачи из `GROK_BUILD_TASKS_2.md` закрыты). Сначала закоммить этот файл (`docs: add GROK_BUILD_TASKS_3`), потом по одному коммиту на задачу, пуш после каждой зелёной задачи, в конце допиши `progress.md`.

Цель: 19 готовых ритмов в 9 стилях. Ритм загружается в текущий слот (A–D) одним нажатием из библиотеки, со своим темпом, свингом и звуками кита. Загрузка отменяется через Cmd+Z.

Ты не слышишь звук: сетки ниже переноси **символ в символ**, не «улучшай». nixter подстроит на слух сам, правки придут отдельным файлом.

## Что есть в коде (проверено на `b0526dc`)

- `DrumPattern` (`Core/Models/PatternManager.swift:8`): `name`, `tracks: [SequencerTrack]`, `bpm`, `swing`, `stepCount`.
- `SequencerTrack.soundPreset` хранит пресет на дорожку. `SequencerStep`: `isActive`, `velocity`, `probability`.
- 8 дорожек: 0 kick, 1 snare, 2 closed hat, 3 clap, 4 tom, 5 ride, 6 crash, 7 perc (`SoundLibraryManager.defaultPreset(forTrackIndex:)`). Отдельной дорожки open hat нет, поэтому где нужен open hat, ритм ставит его на дорожку 7.
- Свинг 0…100, сдвиг = swing/100 × полшага (`SequencerScheduler.swift:250`).
- Киты `FactoryKits.all()`: `kit.808`, `kit.909`, `kit.acoustic`, `kit.lofi`, `kit.trap`, по 8 пресетов в порядке дорожек 0…7.
- Стабильные id: `SoundLibraryManager.factoryID(filename:)`.
- `SequencerEngine.apply(pattern:)` грузит дорожки, звуки, громкость, темп и свинг.
- `PatternManager.performUndoable(...)` (строка 256) — образец для отмены.
- Библиотека: `Features/SoundLibrary/SoundLibraryView.swift`, страницы `LibraryPage` (есть USER и KITS).
- Подпись дорожки в секвенсоре — `track.soundPreset.name` (`SequencerView.swift:226`), так что open hat на дорожке 7 подпишется сам.

## Формат сетки

Одна строка — одна дорожка, 16 символов = 16 шагов (шестнадцатые, шаг 1 = индекс 0).

| символ | значение |
|---|---|
| `X` | удар, velocity 1.0 |
| `x` | удар, velocity 0.75 |
| `g` | тихий удар (ghost), velocity 0.4 |
| `-` | пусто |

`probability` у всех шагов 1.0. Дорожки, которых нет в таблице ритма, пустые. `stepCount` = `.sixteen` у всех. Громкость 1.0, панорама 0 на всех дорожках.

Ключи дорожек: `K`=0, `S`=1, `CH`=2, `CL`=3, `T`=4, `R`=5, `CR`=6, `P`=7.

## Ритмы

«Звук P» — замена пресета на дорожке 7 (filename из `FactoryPresets.swift`). Если не указано, на дорожке остаётся пресет кита.

### House

**house_classic — House Classic** · 124 BPM · swing 10 · kit.909 · звук P `oh_909`
```
K  X---X---X---X---
CH -g-g-g-g-g-g-g-g
CL ----X-------X---
P  --x---x---x---x-
```

**house_deep — Deep House** · 122 BPM · swing 30 · kit.lofi · звук P `perc_shaker`
```
K  X---X---X---X---
CH --x---x---x---x-
CL ----x-------x---
P  -gxg-gxg-gxg-gxg
```

### Techno

**techno_drive — Techno Drive** · 130 BPM · swing 0 · kit.909 · звук P `oh_909`
```
K  X---X---X---X---
CH xg-gxg-gxg-gxg-g
CL ----X-------X---
P  --x---x---x---x-
```

**techno_minimal — Minimal Techno** · 126 BPM · swing 15 · kit.909 (P = `perc_rim_808` из кита)
```
K  X---X---X---X---
CH --x---x---x---x-
CL ----x-------x---
P  ---x--x----x-x--
```

### Hip-Hop

**hiphop_boombap — Boom Bap** · 90 BPM · swing 55 · kit.acoustic
```
K  X-----x---X--x--
S  ----X--g----X---
CH x-x-x-x-x-x-x-x-
```

**hiphop_lazy — Lazy Hip-Hop** · 85 BPM · swing 60 · kit.lofi
```
K  X-------xx------
S  ----X-------X---
CH x-xgx-xgx-xgx-xg
CL ------------x---
```

**hiphop_808 — 808 Hip-Hop** · 95 BPM · swing 20 · kit.808
```
K  X--x---x--X-----
S  ----X-------X---
CH x-x-x-x-x-x-x-x-
P  -------x--------
```

### Trap (half-time)

**trap_basic — Trap** · 140 BPM · swing 0 · kit.trap
```
K  X-----x---x-----
S  --------X-------
CL --------X-------
CH x-x-x-x-x-xgxgx-
```

**trap_drill — Drill** · 142 BPM · swing 0 · kit.trap
```
K  X-----x--x----x-
S  --------X------g
CH x--x--x-x--x--x-
```

### Drum & Bass

**dnb_twostep — DnB Two-Step** · 174 BPM · swing 0 · kit.acoustic
```
K  X---------X-----
S  ----X-------X---
CH x-x-x-x-x-x-x-x-
```

**dnb_roller — DnB Roller** · 172 BPM · swing 0 · kit.acoustic
```
K  X-----x---x-----
S  ----X--g-g--X--g
CH x-gxx-gxx-gxx-gx
```

### Rock

**rock_basic — Rock Beat** · 110 BPM · swing 0 · kit.acoustic
```
K  X-------X-X-----
S  ----X-------X---
CH x-x-x-x-x-x-x-x-
CR X---------------
```

**rock_halftime — Half-Time Rock** · 90 BPM · swing 0 · kit.acoustic
```
K  X-------X--x----
S  --------X-------
R  x-x-x-x-x-x-x-x-
CR X---------------
```

### Funk

**funk_basic — Funk** · 100 BPM · swing 15 · kit.acoustic
```
K  X-x-------X--x--
S  ----X--g-g--X-g-
CH xgxgxgxgxgxgxgxg
```

**funk_disco — Disco** · 118 BPM · swing 0 · kit.acoustic · звук P `oh_acoustic`
```
K  X---X---X---X---
S  ----X-------X---
CH x--gx--gx--gx--g
P  --x---x---x---x-
```

### Reggaeton

**reggaeton_dembow — Dembow** · 95 BPM · swing 0 · kit.808
```
K  X---X---X---X---
S  ---x--x----x--x-
CH g-g-g-g-g-g-g-g-
```

**reggaeton_perreo — Perreo** · 98 BPM · swing 0 · kit.808 · звук P `perc_rim_808`
```
K  X---X---X---X---
S  ---x--x----x--x-
CL ------X-------X-
P  --g---g---g---g-
```

### Lo-Fi

**lofi_chill — Lo-Fi Chill** · 78 BPM · swing 60 · kit.lofi
```
K  X-------x-x-----
S  ----X-------X---
CH x-xgx-xgx-xgx-xg
```

**lofi_jazzy — Lo-Fi Jazzy** · 84 BPM · swing 65 · kit.lofi
```
K  X------x--x-----
S  ----X-------X--g
CH ----g-------g---
R  x---x--xx---x--x
```

---

## Задачи

### E-1 (P0) Модель и данные ритмов
- **Файлы:** новый `SoundLibrary/FactoryPatterns.swift`.
- **Сделать:** `struct FactoryPatternSpec { id, name, genre, bpm, swing, kitID, trackOverrides: [Int: String], rows: [Int: String] }` и `enum FactoryPatterns { static func all() -> [FactoryPatternSpec]; static func makePattern(_ spec:) -> DrumPattern }`. Все 19 ритмов из таблицы выше, жанры в том же порядке. Парсер сетки по таблице символов. Пресеты дорожек = копии пресетов кита по filename (как в `FactoryKits.kit`), потом применить `trackOverrides`. `DrumPattern.id` = `factoryID(filename: "pattern.<id>")`, `name` = английское имя из таблицы.
- **Проверка:** тесты `FactoryPatternTests`: ровно 19 ритмов, id уникальны и стабильны между вызовами, каждая строка ровно 16 символов из `Xxg-`, каждый `kitID` и каждый filename в overrides существует в `SoundLibraryManager.availableSounds`, velocity по символам совпадает (проверь `house_classic` и `dnb_roller` поштучно), bpm и swing совпадают.

### E-2 (P0) Загрузка ритма в текущий слот с отменой
- **Файлы:** `Core/Models/PatternManager.swift`, при необходимости `SequencerEngine.swift`.
- **Сделать:** `func loadFactoryPattern(_ spec:, notesOnly: Bool, into sequencer:, undoManager:)`. Обычная загрузка заменяет сетку, звуки, темп и свинг в **активном** слоте и сохраняет. `notesOnly: true` меняет только сетку (`isActive`, `velocity`), а звуки, громкость, панораму, темп и свинг оставляет как были. Обе загрузки через `performUndoable`, имя действия «Load Pattern». Подтверждений не нужно, Cmd+Z возвращает слот как был. Если идёт воспроизведение, оно не останавливается. Имя слота не трогай.
- **Проверка:** тесты: загрузка в слот B не меняет A, C, D; undo возвращает слот `==` прежнему; `notesOnly` сохраняет `soundPreset` всех 8 дорожек; после `flush()` и новых экземпляров стора (как в C-1) загруженный ритм на месте.

### E-3 (P0) Вкладка «PATTERNS» в библиотеке
- **Файлы:** `Features/SoundLibrary/SoundLibraryView.swift`.
- **Сделать:** новая страница `LibraryPage.patterns` рядом с USER и KITS, со счётчиком 19. Список сгруппирован по жанрам (заголовки секций), в строке имя, BPM и имя кита. Работает существующий поиск (по имени и жанру). Клик или Enter загружает в активный слот. В контекстном меню «Загрузить только ноты» (`notesOnly: true`). После загрузки в строке видна отметка, какой ритм сейчас в слоте; она пропадает, когда сетку меняют руками.
- **Проверка:** снимок раскладки на 1100×720 со страницей PATTERNS, ничего не обрезано; UI-тест: открыть PATTERNS → выбрать `Boom Bap` → BPM в транспорте 90, свинг 55.

### E-4 (P1) Готовность к правкам на слух
- **Сделать:** сетки, BPM, свинг и звуки лежат только в `FactoryPatterns.swift` одной таблицей, без дублей в UI и тестах (тесты читают из той же таблицы, кроме двух поштучных проверок в E-1). В `progress.md` добавь список 19 ритмов с BPM и китами и чек-лист для nixter: прослушать каждый стиль, отметить, что подправить.

## Не трогать
- Формат `patterns.json` и сохранения: ритм после загрузки — обычный паттерн слота.
- Пресеты звуков и киты из раунда 2.
- Готовые ритмы — только данные в коде, никаких WAV/MIDI файлов.
