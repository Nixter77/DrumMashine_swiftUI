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

/// P2-4: FILL roles follow each track's sound, so a sound change moves the fill with it.
@MainActor
struct FillRoleTests {
    @Test func rolesFollowTheSoundAfterASwap() {
        let engine = SequencerEngine()
        let library = SoundLibraryManager.shared
        engine.tracks[4].soundPreset = library.defaultPreset(forTrackIndex: 7)   // tom pad -> perc
        engine.tracks[6].soundPreset = library.defaultPreset(forTrackIndex: 4)   // crash pad -> tom
        let roles = FillGenerator.Roles(voices: engine.tracks.map { $0.soundPreset.resolvedVoice })
        #expect(roles.tom == 6)
        #expect(roles.kick == 0)
        #expect(roles.busy.contains(4))   // perc is busy
        let base: [[Float?]] = (0..<8).map { _ in Array(repeating: nil, count: 16) }
        let f = FillGenerator.apply(.toms, base: base, stepCount: 16, roles: roles)
        #expect((10..<16).allSatisfy { f[6][$0] != nil })
        #expect((8..<16).allSatisfy { f[4][$0] == nil })
    }

    @Test func missingSnareFallsBackToClapAndSkipsAbsentRoles() {
        let roles = FillGenerator.Roles(voices: [.kick, .clap, .closedHat, .perc, .perc, .ride, .crash, .fx])
        #expect(roles.snare == 1)
        #expect(roles.tom == 1)
        #expect(FillGenerator.Roles.legacy == FillGenerator.Roles(voices: [.kick, .snare, .closedHat, .clap, .tom, .ride, .crash, .perc]))
    }
}
