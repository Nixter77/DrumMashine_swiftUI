import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct PersistenceFailureTests {
    @Test func unwritableFolderKeepsMemoryAndTheNextFlushSucceeds() throws {
        let fixture = try FailureFixture()
        defer { fixture.remove() }
        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        var slots = manager.patterns
        slots[0].name = "Keep"
        slots[0].bpm = 99
        manager.replaceSlots(slots)
        manager.flushSave()
        #expect(manager.lastError == nil)
        #expect(manager.patterns[0].name == "Keep")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: fixture.directory.path
        )
        slots[0].bpm = 140
        manager.replaceSlots(slots)
        manager.flushSave()
        #expect(manager.lastError?.operation == .write)
        #expect(manager.lastError?.file == "patterns")
        #expect(manager.patterns[0].name == "Keep")
        #expect(manager.patterns[0].bpm == 140)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fixture.directory.path
        )
        manager.flushSave()
        #expect(manager.lastError == nil)
        let reloaded = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        #expect(reloaded.patterns[0].name == "Keep")
        #expect(reloaded.patterns[0].bpm == 140)
        #expect(reloaded.lastError == nil)
    }
}

@MainActor
private struct FailureFixture {
    let suite: String
    let directory: URL
    let defaults: UserDefaults

    init() throws {
        suite = "DrumMachineFailure-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
    }

    func remove() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}
