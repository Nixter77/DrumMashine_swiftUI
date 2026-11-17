# CANONICAL AC PACK — CUT_9 (D2, P3-1+P3-5 pin) · base 61f3bee
Source: GROK_BUILD_TASKS_9_CUT.md (binding). All AC treated BLOCK severity (cut sets no WARN tier).
- AC-1 All existing tests PASS (>= base count), xcodebuild test -derivedDataPath ~/.drum_dd, 0 fail.
- AC-2 IN-2 (ThemeStoreTests) + IN-3 (source-scan guard) exist and PASS, real asserts.
- AC-3 No `.id(theme…)` in code; MainLayoutView:13-14 comment current. grep + diff.
- AC-4 Both toasts on `.task(id: flashToken)` + `Task.isCancelled` guard, no asyncAfter. Read both bodies.
- AC-5 Manual QA proof (a) theme toggle during Play (b) double Save/Assign highlight 1.2s no flicker (c) close library mid-highlight. Proof: screenshots/recording in qa/cut9/. No DEFER clause in cut.
- AC-6 Diff only MainLayoutView (comment/IN-5), PatternSlots/SoundLibrary (IN-4/5 only), new tests (+pbxproj).
- AC-7 No merge to main / force-push; origin/main = 61f3bee.
