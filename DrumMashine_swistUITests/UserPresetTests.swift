import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct UserPresetTests {
    @Test func factoryKick808HasTheSameIDAcrossManagers() {
        let first = SoundLibraryManager().availableSounds.first { $0.filename == "kick_808" }
        let second = SoundLibraryManager().availableSounds.first { $0.filename == "kick_808" }
        let other = SoundLibraryManager().availableSounds.first { $0.filename == "kick_deep" }
        #expect(first?.id == second?.id)
        #expect(first?.origin == .factory)
        #expect(first?.basedOn == nil)
        #expect(first?.id != other?.id)
    }

    @Test func saveRenameDuplicateAndDeleteRoundTrip() throws {
        let fixture = PresetFixture()
        defer { fixture.remove() }
        let store = UserPresetStore(directory: fixture.directory)
        var preset = SoundLibraryManager().sounds(for: .snare)[0]
        preset.id = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        preset.name = "Мой снейр"
        preset.origin = .user
        preset.basedOn = SoundLibraryManager.factoryID(filename: "snare_808")
        preset.decay = 0.5
        store.save(preset)
        store.flush()

        let loaded = UserPresetStore(directory: fixture.directory)
        #expect(loaded.presets == [preset])
        loaded.rename(id: preset.id, to: "  Снейр 2  ")
        let copy = try #require(loaded.duplicate(id: preset.id))
        #expect(copy.name == "Снейр 2 копия")
        #expect(copy.id != preset.id)
        #expect(copy.origin == .user)
        #expect(copy.basedOn == preset.basedOn)
        loaded.flush()

        let renamed = UserPresetStore(directory: fixture.directory)
        #expect(renamed.presets.count == 2)
        #expect(renamed.preset(id: preset.id)?.name == "Снейр 2")
        renamed.delete(id: preset.id)
        renamed.flush()
        let remaining = UserPresetStore(directory: fixture.directory)
        #expect(remaining.presets.map(\.id) == [copy.id])
    }

    @Test func resetRestoresTheAssignedPreset() {
        let factory = SoundLibraryManager().sounds(for: .snare).first { $0.filename == "snare_808" }!
        var pad = factory
        pad.basedOn = factory.id
        pad.decay = 0.9
        pad.sustain = 0.5
        pad.pitch = 7
        let restored = pad.restored(fromFactory: [factory], users: [])
        #expect(restored.decay == factory.decay)
        #expect(restored.sustain == factory.sustain)
        #expect(restored.pitch == factory.pitch)
        #expect(restored.id == pad.id)
        #expect(restored.basedOn == factory.id)
    }

    @Test func deletingAPresetLeavesThePadCopy() throws {
        let fixture = PresetFixture()
        defer { fixture.remove() }
        let store = UserPresetStore(directory: fixture.directory)
        var user = SoundLibraryManager().sounds(for: .snare)[0]
        user.id = UUID()
        user.name = "Мой снейр"
        user.origin = .user
        user.decay = 0.5
        store.save(user)
        store.flush()
        var pad = user
        pad.basedOn = user.id
        pad.decay = 0.25
        store.delete(id: user.id)
        store.flush()
        let reloaded = UserPresetStore(directory: fixture.directory)
        #expect(reloaded.presets.isEmpty)
        #expect(pad.name == "Мой снейр")
        #expect(pad.decay == 0.25)
        #expect(pad.filename == user.filename)
    }

    @Test func previewCacheMissesWhenTheSameIDChangesParameters() {
        var cache = PreviewSampleCache(limit: 16)
        let id = UUID()
        cache.store([1], id: id, parameterHash: 1, sampleRate: 48_000)
        cache.store([2], id: id, parameterHash: 2, sampleRate: 48_000)
        #expect(cache.samples(id: id, parameterHash: 1, sampleRate: 48_000) == [1])
        #expect(cache.samples(id: id, parameterHash: 2, sampleRate: 48_000) == [2])
    }
}

private struct PresetFixture {
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DrumMachinePresets-\(UUID().uuidString)", isDirectory: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
