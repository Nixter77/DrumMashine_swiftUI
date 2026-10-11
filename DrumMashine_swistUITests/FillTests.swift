import Foundation
import Testing
@testable import DrumMashine_swistUI

struct FillTests {
    private func base(_ n: Int) -> [[Float?]] {
        (0..<8).map { t in (0..<n).map { s in
            switch t {
            case 0: return s % 4 == 0 ? 1.0 : nil      // kick on beats
            case 1: return s % 8 == 4 ? 1.0 : nil      // snare 2 & 4
            case 2: return 0.7                          // hats every step
            default: return nil
            }
        } }
    }

    @Test func regionIsTheLastHalfBar() {
        #expect(FillGenerator.regionStart(stepCount: 16) == 8)
        #expect(FillGenerator.regionStart(stepCount: 8) == 4)
        #expect(FillGenerator.regionStart(stepCount: 32) == 24)
    }

    @Test func fillOnlyChangesTheRegion() {
        for style in FillStyle.allCases {
            let b = base(16)
            let f = FillGenerator.apply(style, base: b, stepCount: 16)
            for t in 0..<8 { for s in 0..<8 { #expect(f[t][s] == b[t][s]) } }
            #expect((8..<16).allSatisfy { f[2][$0] == nil })   // hats cleared in the fill
        }
    }

    @Test func snareRollGetsLouder() {
        let f = FillGenerator.apply(.snareRoll, base: base(16), stepCount: 16)
        let roll = (8..<16).compactMap { f[1][$0] }
        #expect(roll.count == 8)
        #expect(roll.first! < roll.last!)
    }

    @Test func tomsUseTheTomTrack() {
        let f = FillGenerator.apply(.toms, base: base(16), stepCount: 16)
        #expect((10..<16).allSatisfy { f[4][$0] != nil })
    }
}

@MainActor
struct FillPersistenceTests {
    /// FILL toggles republish the scheduler snapshot but never save session/pattern.
    @Test func fillTogglesDoNotSave() {
        let engine = SequencerEngine()
        let publishes = engine.snapshotPublishCount
        let saves = engine.persistCount
        engine.fillHeld = true
        engine.fillHeld = false
        engine.fillOnce = true
        engine.fillOnce = false
        #expect(engine.snapshotPublishCount == publishes + 4)
        #expect(engine.persistCount == saves)
    }
}
