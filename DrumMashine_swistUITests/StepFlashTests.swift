import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_10 IN-5: pure flash model.
struct StepFlashTests {
    private func track(_ active: [Int], count: Int = 16, muted: Bool = false, solo: Bool = false) -> SequencerTrack {
        var t = SequencerTrack(soundPreset: SoundPreset(id: UUID(), name: "T", filename: "", category: .percussion), stepsCount: count)
        for i in active { t.steps[i].isActive = true }
        t.isMuted = muted
        t.isSolo = solo
        return t
    }

    @Test func activeUnmutedFlashes() {
        #expect(StepFlash.flashedRows(tracks: [track([0, 4]), track([4])], step: 4) == [0, 1])
    }

    @Test func inactiveDoesNotFlash() {
        #expect(StepFlash.flashedRows(tracks: [track([0]), track([1])], step: 0) == [0])
        #expect(StepFlash.flashedRows(tracks: [track([0])], step: 3) == [])
    }

    @Test func mutedDoesNotFlash() {
        #expect(StepFlash.flashedRows(tracks: [track([2], muted: true), track([2])], step: 2) == [1])
    }

    @Test func soloRuleMatchesScheduler() {
        let tracks = [track([5]), track([5], solo: true), track([5], muted: true, solo: true)]
        #expect(StepFlash.flashedRows(tracks: tracks, step: 5) == [1])
    }

    @Test func outOfRangeAndStepCounts() {
        let t16 = [track([15], count: 16)]
        let t32 = [track([31], count: 32)]
        #expect(StepFlash.flashedRows(tracks: t16, step: 15) == [0])
        #expect(StepFlash.flashedRows(tracks: t16, step: 16) == [])
        #expect(StepFlash.flashedRows(tracks: t16, step: -1) == [])
        #expect(StepFlash.flashedRows(tracks: t32, step: 31) == [0])
        #expect(StepFlash.flashedRows(tracks: t32, step: 32) == [])
    }

    @Test func emptyTracks() {
        #expect(StepFlash.flashedRows(tracks: [], step: 0) == [])
    }
}
