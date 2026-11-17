# CANONICAL AC PACK — CUT_7 (вариант A, persistence)
Source: GROK_BUILD_TASKS_7_CUT.md · base main 32694b4 · branch cut7-persistence. All AC = BLOCK. Soft-pass запрещён.
- AC-1 Все существующие 185 тестов PASS; итог ≥185+новые, 0 fail (xcodebuild test, DerivedData ~/.drum_dd).
- AC-2 ≥1 legacy-фикстура на каждый тип IN-2 (DrumProject session/slots, SoundPreset, track soundPreset, pattern/kit names) с конкретными assert'ами значений, не XCTAssertNoThrow.
- AC-3 Round-trip DrumProject и GrooveSettings равны; модель с непустыми grooves/slots.
- AC-4 Битый/пустой user_grooves.json → [], без краша, лог через AppLog/logger; файл не перезаписан молча.
- AC-5 `git diff --stat 32694b4..HEAD` не трогает Audio/, Sequencer*, Effects*, VoiceEngine*.
- AC-6 Prod-код изменён только если тест AC-2..4 упал; каждое изменение обосновано в коммите; нет «заодно».
OUT: merge, force-push, P2-1, P3-1/P3-5, UI.
