# CUT_9 manual QA (AC-5) — branch cut9-ui-pin
Automated: ThemeStoreTests (persist + withObservationTracking, pre-existing) and ThemeToastSourceGuardTests (new) PASS.
Manual checks still to perform by QA (screenshots/record into qa/cut9/):
- (a) Toggle theme during Play: audio uninterrupted; library scroll/open popups preserved.
- (b) Double quick Save slot / Assign preset: highlight holds 1.2 s from last press, no flicker.
- (c) Close library mid-highlight: no errors / stuck highlight.
Code facts on tip: no `.id(theme` in code; both toasts use `.task(id: flashToken)` + `guard !Task.isCancelled`; no asyncAfter.
