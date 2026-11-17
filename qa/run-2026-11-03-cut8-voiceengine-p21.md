# QA CUT_8 P2-1 VoiceEngine — 2026-11-03 (Asia/Jerusalem)
Deploy under test: local Mac tip, Mac-Home-2
SHA claimed: 111fc0ede64353c48ed3f6de11357856beb94986 — verified `git rev-parse HEAD` on cut8-voiceengine-p21 (tracks origin, in sync)
Cut: GROK_BUILD_TASKS_8_CUT.md · AC_IDS: AC-1..AC-7
Commits: 26473ad -> e63956f (IN-4 tests+golden) -> 111fc0e (IN-1+IN-2). merge-base with origin/main = 26473ad.

- AC-1 PASS: `xcodebuild test -scheme DrumMashine_swistUI -destination platform=macOS -only-testing:DrumMashine_swistUITests -derivedDataPath ~/.drum_dd` → TEST SUCCEEDED, 199 passed / 0 failed (194 + 5). Log: qa/run-2026-11-03-cut8-voiceengine-p21.xcodebuild.log
- AC-2 PASS: VoiceEngineSegmentRenderTests: midBlockTriggerStartsOnItsFrame (a), multipleAndEdgeFrameEvents (b), lateEventStillCounted (c), gainRampMatchesOnePoleReference (d), offlineRenderBitIdenticalToBaseline (e). Asserts are concrete (nonZeroFrames == [300], lateEventCount == 1, per-frame abs<1e-6, FNV-64 equality).
- AC-3 PASS: render loop now `while segmentStart < frameCount`; drain(control→sequencer) only at segment start; inner loop has `if !gainSettled { smooth() }`; planPan after frame-0 commands preserved; gainSettled cleared in setGain.
- AC-4 PASS: VoiceEngine.swift (+47/-8), VoiceEngineSegmentRenderTests.swift (+164). No pbxproj, no other product files.
- AC-5 PASS: golden FNV-64 (12102173626081619070 / 1463802545885221317) independently re-run at e63956f where VoiceEngine.swift == 26473ad (empty diff) → PASS (qa/run-2026-11-03-cut8-baseline-e63956f.log, separate DD ~/.drum_dd_qa8base). Same test passes on tip → bit-identical. Existing tests unchanged.
- AC-6 PASS: origin/main = 26473ad; 111fc0e only on cut8-voiceengine-p21 (local+origin). WARN-note: local `main` = 3206c2b (5 local unpushed commits by Nikolay, 2026-11-03 06:12 IST, P2-2/P2-3/P3-*) — not a cut8 merge, not touched by QA; CUT text "git log main = 26473ad" holds for origin/main only.
- AC-7 PASS: no auval/Synt gates run; app launch not required.
OUT confirmed: IN-3 throttle not implemented (smooth still per-frame until settled). Mid-block live commands: nextDueFrame makes non-trigger heads due next frame — matches drain semantics.
FAIL repro: none. Commits by QA: none.
---
verdict: PASS
sha: 111fc0ede64353c48ed3f6de11357856beb94986
block_failed: []
warn_failed: []
share_sample: null
fixtures_cut: CUT_8
---
