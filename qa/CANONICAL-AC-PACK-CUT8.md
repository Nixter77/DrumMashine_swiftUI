# Canonical AC pack — CUT_8 (P2-1 VoiceEngine), locked to GROK_BUILD_TASKS_8_CUT.md, base 26473ad
| AC | Check | Expected | Severity |
|---|---|---|---|
| AC-1 | xcodebuild test -derivedDataPath ~/.drum_dd (unit target) | 0 fail; count = base(194) + new | BLOCK |
| AC-2 | IN-4 (a)-(e) tests exist + pass, concrete frame/sample asserts | 5 tests PASS | BLOCK |
| AC-3 | read Mixer.render loop | drain only at segment boundaries; smooth() not unconditional per-frame | BLOCK |
| AC-4 | git diff --stat 26473ad..HEAD | only VoiceEngine.swift + tests (+pbxproj) | BLOCK |
| AC-5 | IN-4(e) bit-exact vs 26473ad golden; existing audio tests unchanged | equal; else STOP | BLOCK |
| AC-6 | no merge to main, no force-push | main lacks cut8; origin/main = 26473ad | BLOCK |
| AC-7 | no auval/Synt gates; app launch not required | n/a | INFO |
OUT: IN-3 throttle, CUT_7 persistence, UI/P3, scheduler, effects, unrelated VoiceEngine refactors.
