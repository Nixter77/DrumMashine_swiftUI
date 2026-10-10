import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct DrumProjectTests {
    @Test func exportThenImportIntoAnEmptyStoreMatches() throws {
        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drumproj-dst-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: destDir) }
        let destDefaults = try #require(UserDefaults(suiteName: "DrumProjectDest-\(UUID().uuidString)"))

        let kick = SoundPreset(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "Kick",
            filename: "kick_808",
            category: .kick
        )
        var track = SequencerTrack(soundPreset: kick, stepsCount: 16)
        track.steps[0].isActive = true
        track.steps[0].velocity = 0.5
        var pattern = DrumPattern(name: "B", tracks: [track], bpm: 133, swing: 55, stepCount: .sixteen)
        pattern.id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let empty = DrumPattern(name: "A", tracks: [], bpm: 120, swing: 0)

        var project = DrumProject(name: "Round")
        project.id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        project.session = SessionState(
            tracks: [track],
            bpm: 133,
            swing: 55,
            humanize: 20,
            stepCount: .sixteen,
            activePatternIndex: 1,
            masterVolume: 0.5,
            limiterEnabled: false,
            libraryInspectorOpen: false
        )
        project.slots = PatternLibrary(patterns: [empty, pattern], activePatternIndex: 1)
        var user = kick
        user.id = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        user.name = "Мой кик"
        user.origin = .user
        project.userPresets = [user]
        project.kits = [DrumKit(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, name: "Kit", sounds: [])]
        project.samples = [ProjectSample(fileName: "ping.wav", originalName: "ping.wav", data: Data([1, 2, 3, 4]))]

        let decoded = try DrumProject.decode(project.encoded())
        #expect(decoded == project)

        let destPatterns = PatternManager(defaults: destDefaults, directory: destDir)
        var marker = DrumPattern(name: "OLD", tracks: [], bpm: 90, swing: 0)
        marker.id = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        destPatterns.replaceSlots([marker])
        destPatterns.flushSave()
        let before = try Data(contentsOf: destDir.appendingPathComponent("patterns.json"))

        let destSession = SessionStore(directory: destDir, patterns: destPatterns)
        let destPresets = UserPresetStore(directory: destDir)
        try decoded.apply(to: destPatterns, session: destSession, presets: destPresets, mode: .replace)

        let backups = destDir.appendingPathComponent("Backups", isDirectory: true)
        let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("project-") }
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy.appendingPathComponent("patterns.json")) == before)

        let loadedPatterns = PatternManager(defaults: destDefaults, directory: destDir)
        let loadedSession = try #require(SessionStore(directory: destDir, patterns: loadedPatterns).load())
        let loadedPresets = UserPresetStore(directory: destDir)
        #expect(loadedSession == decoded.session)
        #expect(loadedPatterns.patterns == destPatterns.patterns)
        #expect(loadedPatterns.activePatternIndex == decoded.slots.activePatternIndex)
        #expect(loadedPresets.presets == decoded.userPresets)
        let sample = destDir.appendingPathComponent("Samples/ping.wav")
        #expect(try Data(contentsOf: sample) == Data([1, 2, 3, 4]))
    }
}
