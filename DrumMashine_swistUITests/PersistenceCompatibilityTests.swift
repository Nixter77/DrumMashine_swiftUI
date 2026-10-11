import Foundation
import Testing
@testable import DrumMashine_swistUI

/// Migration, corrupt files, and version compatibility.
/// Case 6 (unwritable folder) is `PersistenceFailureTests`.
/// D-0 `voice`, `synth`, and `source` must stay optional: `oldPresetWithoutNewFieldsDecodes` omits them.
@MainActor
struct PersistenceCompatibilityTests {
    @Test func oldArrayInDefaultsBecomesPatternsFileAndKeepsTheKey() throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let original = samplePattern(name: "Array", bpm: 99)
        let data = try JSONEncoder().encode([original])
        fixture.defaults.set(data, forKey: PatternManager.storageKey)

        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        let saved = try loadedLibrary(fixture.directory)
        #expect(saved.patterns[0] == original)
        #expect(saved.activePatternIndex == 0)
        #expect(fixture.defaults.data(forKey: PatternManager.storageKey) == data)
        #expect(try backupBytes(fixture.directory) == data)
        #expect(manager.loadError == nil)
    }

    @Test func documentV1InDefaultsBecomesPatternsFileAndKeepsTheKey() throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let original = samplePattern(name: "Document", bpm: 88)
        let data = try PatternStore.encode([original])
        fixture.defaults.set(data, forKey: PatternManager.storageKey)

        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        let saved = try loadedLibrary(fixture.directory)
        #expect(saved.patterns[0] == original)
        #expect(fixture.defaults.data(forKey: PatternManager.storageKey) == data)
        #expect(try backupBytes(fixture.directory) == data)
        #expect(manager.loadError == nil)
    }

    @Test func garbagePatternsFileIsQuarantinedAndTheBackupLoads() throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let original = samplePattern(name: "Bak", bpm: 90)
        let store = PersistenceStore(directory: fixture.directory)
        let library = PatternLibrary(patterns: [original], activePatternIndex: 0)
        try store.write(library, name: "patterns", version: PersistenceStore.patternsVersion)
        try store.write(library, name: "patterns", version: PersistenceStore.patternsVersion)
        let garbage = Data("not-json".utf8)
        try garbage.write(to: store.fileURL("patterns"))

        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        #expect(manager.lastError != nil)
        #expect(manager.patterns[0] == original)
        let corrupt = try corruptFiles(fixture.directory)
        #expect(corrupt.count == 1)
        #expect(try Data(contentsOf: corrupt[0]) == garbage)
        #expect(FileManager.default.fileExists(atPath: store.fileURL("patterns").path) == false)
        manager.flushSave()
        #expect(try Data(contentsOf: corrupt[0]) == garbage)
    }

    @Test func newerVersionIsLeftUntouchedAndFlushDoesNotOverwrite() throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("patterns.json")
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let body = Data(#"{"version":99,"savedAt":"2026-10-08T00:00:00Z","payload":{}}"#.utf8)
        try body.write(to: url)

        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        #expect(try Data(contentsOf: url) == body)
        #expect(manager.lastError?.isNewerVersion == true)
        #expect(manager.patterns.count == 4)
        #expect(manager.patterns.allSatisfy { pattern in
            !pattern.tracks.contains { $0.steps.contains { $0.isActive } }
        })

        var edited = manager.patterns
        edited[0].name = "ShouldNotLand"
        edited[0].bpm = 140
        manager.replaceSlots(edited)
        manager.flushSave()
        #expect(try Data(contentsOf: url) == body)
    }

    @Test func oldPresetWithoutNewFieldsDecodes() throws {
        let json = """
        {"name":"A","bpm":90,"tracks":[{"soundPreset":{"id":"11111111-1111-1111-1111-111111111111","name":"Kick","filename":"kick_808","category":"kick"},"steps":[]}]}
        """
        let pattern = try JSONDecoder().decode(DrumPattern.self, from: Data(json.utf8))
        let preset = pattern.tracks[0].soundPreset
        #expect(preset.origin == .factory)
        #expect(preset.basedOn == nil)
        #expect(preset.attack == 0)
        #expect(preset.decay == 0.1)
        #expect(preset.sustain == 1)
        #expect(preset.release == 0.1)
        #expect(preset.pitch == 0)
        #expect(preset.volume == 1)
    }
}

@MainActor
private struct CompatibilityFixture {
    let suite: String
    let directory: URL
    let defaults: UserDefaults

    init() throws {
        suite = "DrumMachineCompat-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func samplePattern(name: String, bpm: Double) -> DrumPattern {
    let preset = SoundPreset(
        id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
        name: "Kick",
        filename: "kick_808",
        category: .kick
    )
    var track = SequencerTrack(soundPreset: preset, stepsCount: 16)
    track.steps[0].isActive = true
    track.steps[0].velocity = 0.5
    return DrumPattern(name: name, tracks: [track], bpm: bpm, swing: 12, stepCount: .sixteen)
}

@MainActor
private func loadedLibrary(_ directory: URL) throws -> PatternLibrary {
    let store = PersistenceStore(directory: directory)
    guard case .loaded(let saved) = try store.read(
        "patterns",
        as: PatternLibrary.self,
        maximumVersion: PersistenceStore.patternsVersion
    ) else {
        Issue.record("patterns.json did not load")
        throw CompatibilityReadError.missing
    }
    return saved
}

@MainActor
private func backupBytes(_ directory: URL) throws -> Data {
    let backups = directory.appendingPathComponent("Backups")
    let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.hasPrefix("legacy-patterns-") }
    let copy = try #require(copies.first)
    #expect(copies.count == 1)
    return try Data(contentsOf: copy)
}

@MainActor
private func corruptFiles(_ directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent.contains(".corrupt-") }
}

private enum CompatibilityReadError: Error {
    case missing
}

/// Old or hand-trimmed files without the session/slots or name/category keys still load.
struct MissingKeyToleranceTests {
    @Test func projectWithoutSessionAndSlotsDecodes() throws {
        let old = #"{"version":1,"name":"Old beat"}"#
        let project = try JSONDecoder().decode(DrumProject.self, from: Data(old.utf8))
        #expect(project.name == "Old beat")
        #expect(project.session.tracks.isEmpty)
        #expect(project.session.bpm == 120)
        #expect(project.slots.patterns.isEmpty)
    }

    @Test func presetWithoutNameAndCategoryDecodes() throws {
        let old = #"{"filename":"kick_01","volume":0.8}"#
        let preset = try JSONDecoder().decode(SoundPreset.self, from: Data(old.utf8))
        #expect(preset.name == "Sound")
        #expect(preset.category == .percussion)
        #expect(preset.volume == 0.8)
    }
}
