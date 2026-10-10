import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct LibraryVoiceTests {
    @Test func assigningTom909ChangesTheTomPadAndLeavesTheClap() throws {
        let engine = SequencerEngine()
        let tom = try #require(
            SoundLibraryManager.shared.availableSounds.first { $0.filename == "tom_909" }
        )
        let clap = engine.tracks[3].soundPreset
        #expect(engine.trackIndex(for: .tom) == 4)
        #expect(engine.trackIndex(for: .clap) == 3)
        #expect(engine.trackIndex(for: .closedHat) == 2)
        #expect(engine.trackIndex(for: .openHat) == 2)
        let index = engine.assignToMatchingVoice(tom)
        #expect(index == 4)
        #expect(engine.tracks[4].soundPreset.filename == "tom_909")
        #expect(engine.tracks[4].soundPreset.basedOn == tom.id)
        #expect(engine.tracks[3].soundPreset.filename == clap.filename)
        #expect(engine.tracks[3].soundPreset.id == clap.id)
    }

    @Test func anFxPresetDoesNothingWhenNoTrackIsFx() throws {
        let engine = SequencerEngine()
        let fx = try #require(
            SoundLibraryManager.shared.availableSounds.first { $0.resolvedVoice == .fx }
        )
        let before = engine.tracks.map(\.soundPreset.filename)
        #expect(engine.trackIndex(for: .fx) == nil)
        #expect(engine.assignToMatchingVoice(fx) == nil)
        #expect(engine.tracks.map(\.soundPreset.filename) == before)
    }

    @Test func saveCopyOfAFactoryPresetKeepsTheSourceId() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("library-copy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = UserPresetStore(directory: directory)
        let factory = try #require(
            SoundLibraryManager.shared.availableSounds.first { $0.filename == "tom_909" }
        )
        let copy = try #require(store.saveCopy(of: factory))
        #expect(copy.id != factory.id)
        #expect(copy.origin == .user)
        #expect(copy.basedOn == factory.id)
        #expect(copy.name == factory.name + " копия")
        store.flush()
        let loaded = UserPresetStore(directory: directory)
        #expect(loaded.presets == [copy])
    }
}
