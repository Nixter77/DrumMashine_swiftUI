import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct FactoryKitTests {
    @Test func loadingThe909KitSetsTheEightFilenamesAndKeepsTheGrid() throws {
        let engine = SequencerEngine()
        engine.tracks[0].steps[0].isActive = true
        engine.tracks[0].steps[0].velocity = 0.5
        let before = engine.tracks.map(\.soundPreset.filename)
        let steps = engine.tracks.map(\.steps)
        let kit = try #require(FactoryKits.all().first { $0.name == "909" })
        let filenames = [
            "kick_909", "snare_909", "ch_909", "clap_909",
            "tom_909", "ride_909", "crash_909", "perc_rim_808"
        ]
        #expect(kit.sounds.map(\.filename) == filenames)
        #expect(kit.sounds.map(\.id) == filenames.map { SoundLibraryManager.factoryID(filename: $0) })
        let undo = UndoManager()
        engine.loadKit(kit, undoManager: undo)
        #expect(engine.tracks.map(\.soundPreset.filename) == filenames)
        #expect(engine.tracks.map(\.steps) == steps)
        #expect(engine.kitBadge == "909")
        engine.notePadSoundEdited()
        #expect(engine.kitBadge == "909*")
        undo.undo()
        #expect(engine.tracks.map(\.soundPreset.filename) == before)
        #expect(engine.tracks[0].steps[0].isActive)
        #expect(engine.tracks[0].steps[0].velocity == 0.5)
        #expect(engine.kitBadge == nil)
    }
}
