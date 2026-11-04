import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_14: a pad tap uses the same choke group as the sequencer (nil = Off → -1 in the engine).
@MainActor
struct LivePadChokeTests {
    private func preset(group: Int?) -> SoundPreset {
        var p = SequencerEngine().tracks[2].soundPreset
        p.chokeGroup = group
        return p
    }

    private func scheduledChoke(_ engine: SequencerEngine, track: Int) throws -> Int {
        let child = Mirror(reflecting: engine).children.first { $0.label == "scheduler" }
        let scheduler = try #require(child?.value as? SequencerScheduler)
        let tracks = scheduler.pattern().tracks
        try #require(tracks.indices.contains(track))
        return tracks[track].chokeGroup
    }

    @Test func groupOneMapsToOne() {
        #expect(PadTriggerChoke.group(for: preset(group: 1)) == 1)
    }

    @Test func nilMapsToNilWhichEngineTreatsAsOff() {
        let group = PadTriggerChoke.group(for: preset(group: nil))
        #expect(group == nil)
        #expect((group ?? -1) == -1)
    }

    @Test func groupFourMapsToFour() {
        #expect(PadTriggerChoke.group(for: preset(group: 4)) == 4)
    }

    @Test func helperMatchesSequencerForNilOneThree() throws {
        for value in [nil, 1, 3] as [Int?] {
            let engine = SequencerEngine()
            engine.tracks[2].soundPreset.chokeGroup = value
            let pad = PadTriggerChoke.group(for: engine.tracks[2].soundPreset) ?? -1
            #expect(pad == (try scheduledChoke(engine, track: 2)), "group \(String(describing: value))")
        }
    }
}
