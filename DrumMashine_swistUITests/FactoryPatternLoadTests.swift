import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct FactoryPatternLoadTests {
    @Test func loadIntoSlotBLeavesTheOthersAndRoundTrips() throws {
        let fixture = try PatternLoadFixture()
        defer { fixture.remove() }
        let manager = fixture.manager
        let engine = SequencerEngine()
        engine.tracks[0].steps[0].isActive = true
        engine.tracks[0].steps[0].velocity = 0.5
        manager.updateActive(from: engine)
        let slotA = manager.patterns[0]

        manager.selectSlot(1, in: engine)
        engine.tracks[3].steps[2].isActive = true
        engine.tracks[3].steps[2].velocity = 0.25
        engine.bpm = 100
        engine.swing = 12
        engine.tracks[0].volume = 0.3
        engine.tracks[0].pan = -0.5
        manager.updateActive(from: engine)
        let beforeB = manager.patterns[1]
        let slotC = manager.patterns[2]
        let slotD = manager.patterns[3]
        let sounds = engine.tracks.map(\.soundPreset)

        engine.play()
        let spec = try #require(FactoryPatterns.all().first { $0.id == "house_classic" })
        let undo = UndoManager()
        manager.loadFactoryPattern(spec, notesOnly: false, into: engine, undoManager: undo)

        #expect(undo.undoActionName == "Load Pattern")
        #expect(engine.isPlaying)
        #expect(manager.activePatternIndex == 1)
        #expect(manager.patterns[0] == slotA)
        #expect(manager.patterns[2] == slotC)
        #expect(manager.patterns[3] == slotD)
        #expect(manager.patterns[1].name == "B")
        #expect(manager.patterns[1].id == beforeB.id)
        #expect(manager.patterns[1].bpm == 124)
        #expect(manager.patterns[1].swing == 10)
        #expect(engine.bpm == 124)
        #expect(engine.swing == 10)
        #expect(engine.tracks[7].soundPreset.filename == "oh_909")
        #expect(engine.tracks[0].steps[0].isActive)
        #expect(engine.tracks[0].steps[0].velocity == 1)
        #expect(engine.tracks[0].volume == 1)

        let loaded = manager.patterns[1]
        manager.flushSave()
        let restarted = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        #expect(restarted.activePatternIndex == 1)
        #expect(restarted.patterns[1] == loaded)
        #expect(restarted.patterns[0] == slotA)

        undo.undo()
        #expect(manager.patterns[1] == beforeB)
        #expect(engine.bpm == 100)
        #expect(engine.swing == 12)
        #expect(engine.tracks[3].steps[2].isActive)
        #expect(engine.tracks[3].steps[2].velocity == 0.25)
        #expect(engine.tracks.map(\.soundPreset.filename) == sounds.map(\.filename))
        #expect(engine.isPlaying)

        manager.loadFactoryPattern(spec, notesOnly: true, into: engine, undoManager: undo)
        #expect(engine.bpm == 100)
        #expect(engine.swing == 12)
        #expect(engine.tracks[0].volume == 0.3)
        #expect(engine.tracks[0].pan == -0.5)
        #expect(engine.tracks.map(\.soundPreset) == sounds)
        #expect(engine.tracks[0].steps[0].isActive)
        #expect(engine.tracks[0].steps[0].velocity == 1)
        #expect(engine.tracks[2].steps[1].isActive)
        #expect(engine.tracks[2].steps[1].velocity == 0.4)
        #expect(manager.patterns[1].bpm == 100)
        #expect(manager.patterns[1].swing == 12)
        #expect(manager.patterns[1].name == "B")
        #expect(manager.patterns[1].tracks.map(\.soundPreset) == sounds)
        #expect(manager.patterns[0] == slotA)
        engine.stop()
    }
}

@MainActor
private struct PatternLoadFixture {
    let suite: String
    let directory: URL
    let defaults: UserDefaults
    let manager: PatternManager

    init() throws {
        suite = "DrumMachinePatternLoad-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        manager = PatternManager(defaults: defaults, directory: directory)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
