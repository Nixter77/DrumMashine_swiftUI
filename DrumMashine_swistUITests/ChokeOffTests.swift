import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_13: the sequencer takes choke only from `soundPreset.chokeGroup`; nil = Off (-1) on every track.
@MainActor
struct ChokeOffTests {
    /// Reads the scheduler snapshot the engine published. `scheduler` is private, so Mirror (no new Core hook).
    private func scheduledChoke(_ engine: SequencerEngine, track: Int) throws -> Int {
        let child = Mirror(reflecting: engine).children.first { $0.label == "scheduler" }
        let scheduler = try #require(child?.value as? SequencerScheduler)
        let tracks = scheduler.pattern().tracks
        try #require(tracks.indices.contains(track))
        return tracks[track].chokeGroup
    }

    @Test func hihatTrackWithNilGroupIsOff() throws {
        let engine = SequencerEngine()
        engine.tracks[2].soundPreset.chokeGroup = nil
        #expect(try scheduledChoke(engine, track: 2) == -1)
    }

    @Test func rideTrackWithNilGroupIsOff() throws {
        let engine = SequencerEngine()
        engine.tracks[5].soundPreset.chokeGroup = nil
        #expect(try scheduledChoke(engine, track: 5) == -1)
    }

    @Test func hihatTrackWithGroupOneIsOne() throws {
        let engine = SequencerEngine()
        engine.tracks[2].soundPreset.chokeGroup = 1
        #expect(try scheduledChoke(engine, track: 2) == 1)
    }

    @Test func anyTrackWithGroupThreeIsThree() throws {
        let engine = SequencerEngine()
        for index in engine.tracks.indices {
            engine.tracks[index].soundPreset.chokeGroup = 3
            #expect(try scheduledChoke(engine, track: index) == 3, "track \(index)")
        }
    }

    @Test func everyFactoryHatPresetIsInGroupOne() {
        let hats = (FactoryPresets.additional() + AcousticKit.presets()).filter { $0.category == .hihat }
        #expect(hats.count == 12)
        for hat in hats {
            #expect(hat.chokeGroup == 1, "\(hat.name)")
        }
    }
}
