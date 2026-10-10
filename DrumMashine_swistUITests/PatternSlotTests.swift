import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct PatternSlotTests {
    @Test func editingSlotBSurvivesATripThroughC() throws {
        let fixture = try SlotFixture()
        defer { fixture.remove() }
        let manager = fixture.manager
        let engine = SequencerEngine()
        manager.selectSlot(1, in: engine)
        engine.tracks[0].steps[3].isActive = true
        engine.tracks[0].steps[3].velocity = 0.5
        manager.selectSlot(2, in: engine)
        #expect(engine.tracks[0].steps[3].isActive == false)
        manager.selectSlot(1, in: engine)
        #expect(manager.activePatternIndex == 1)
        #expect(engine.tracks[0].steps[3].isActive)
        #expect(engine.tracks[0].steps[3].velocity == 0.5)
    }

    @Test func anEmptySlotKeepsTheCurrentSounds() throws {
        let fixture = try SlotFixture()
        defer { fixture.remove() }
        let manager = fixture.manager
        let engine = SequencerEngine()
        let filenames = engine.tracks.map(\.soundPreset.filename)
        manager.selectSlot(1, in: engine)
        #expect(engine.tracks.map(\.soundPreset.filename) == filenames)
        #expect(engine.tracks.allSatisfy { track in
            !track.soundPreset.filename.hasPrefix("sound_") && !track.steps.contains { $0.isActive }
        })
    }

    @Test func anOldPatternArrayStillLoadsAndRemembersSlotA() throws {
        let fixture = try SlotFixture()
        defer { fixture.remove() }
        let pattern = DrumPattern(
            name: "A",
            tracks: SequencerEngine().tracks,
            bpm: 99,
            swing: 12,
            stepCount: .sixteen
        )
        let store = PersistenceStore(directory: fixture.directory)
        try store.write([pattern], name: "patterns", version: PersistenceStore.patternsVersion)
        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        #expect(manager.loadError == nil)
        #expect(manager.patterns[0].name == "A")
        #expect(manager.patterns[0].bpm == 99)
        #expect(manager.activePatternIndex == 0)
    }

    @Test func clearOfAFilledSlotUndoesOnce() throws {
        let fixture = try SlotFixture()
        defer { fixture.remove() }
        let manager = fixture.manager
        let engine = SequencerEngine()
        engine.tracks[0].steps[0].isActive = true
        manager.updateActive(from: engine)
        let undo = UndoManager()
        manager.performUndoable(
            sequencer: engine,
            undoManager: undo,
            actionName: "Clear Pattern"
        ) {
            engine.clearPattern()
        }
        #expect(engine.tracks[0].steps[0].isActive == false)
        undo.undo()
        #expect(engine.tracks[0].steps[0].isActive)
        #expect(manager.patterns[0].tracks[0].steps[0].isActive)
    }
}

@MainActor
private struct SlotFixture {
    let suite: String
    let directory: URL
    let defaults: UserDefaults
    let manager: PatternManager

    init() throws {
        suite = "DrumMachineSlots-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        manager = PatternManager(defaults: defaults, directory: directory)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
