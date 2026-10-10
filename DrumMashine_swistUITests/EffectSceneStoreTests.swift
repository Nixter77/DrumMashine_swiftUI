import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct EffectSceneStoreTests {
    @Test func saveThenANewStoreLoadsTheSameScene() throws {
        let fixture = try SceneFixture()
        defer { fixture.remove() }
        let store = EffectSceneStore(directory: fixture.directory)
        var chain = EffectsChain()
        chain.reverb.isOn = true
        chain.reverb.wetDryMix = 0.15
        chain.delay.isOn = true
        chain.delay.syncBeats = 0.75
        chain.delay.delayTime = 0.375
        let saved = try #require(store.save(name: "  Night  ", chain: chain))
        #expect(saved.name == "Night")
        #expect(store.save(name: "   ", chain: chain) == nil)
        store.flush()

        let loaded = EffectSceneStore(directory: fixture.directory)
        #expect(loaded.scenes.count == 1)
        #expect(loaded.scenes[0] == saved)

        loaded.rename(id: saved.id, to: "Day")
        loaded.flush()
        let renamed = EffectSceneStore(directory: fixture.directory)
        #expect(renamed.scenes[0].name == "Day")
        #expect(renamed.scenes[0].chain == chain)

        renamed.delete(id: saved.id)
        renamed.flush()
        let empty = EffectSceneStore(directory: fixture.directory)
        #expect(empty.scenes.isEmpty)
    }

    @Test func drumprojRoundTripKeepsScenesAndBacksUpTheOldFile() throws {
        let source = try SceneFixture()
        let destination = try SceneFixture()
        defer {
            source.remove()
            destination.remove()
        }
        let store = EffectSceneStore(directory: source.directory)
        var chain = EffectsChain()
        chain.distortion.isOn = true
        chain.distortion.wetDryMix = 0.6
        let saved = try #require(store.save(name: "Fuzz", chain: chain))
        store.flush()

        let patterns = PatternManager(defaults: source.defaults, directory: source.directory)
        let session = SessionStore(directory: source.directory, patterns: patterns)
        let presets = UserPresetStore(directory: source.directory)
        let project = DrumProject.capture(
            name: "Beat",
            patterns: patterns,
            session: session,
            presets: presets
        )
        #expect(project.scenes == [saved])
        let decoded = try DrumProject.decode(project.encoded())
        #expect(decoded.scenes == [saved])

        let destPatterns = PatternManager(defaults: destination.defaults, directory: destination.directory)
        let marker = Data("scene-marker".utf8)
        try marker.write(to: destination.directory.appendingPathComponent("effect_scenes.json"))
        let destSession = SessionStore(directory: destination.directory, patterns: destPatterns)
        let destPresets = UserPresetStore(directory: destination.directory)
        try decoded.apply(
            to: destPatterns,
            session: destSession,
            presets: destPresets,
            mode: .replace
        )

        let loaded = EffectSceneStore(directory: destination.directory)
        #expect(loaded.scenes == [saved])
        let backups = destination.directory.appendingPathComponent("Backups", isDirectory: true)
        let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("project-") }
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy.appendingPathComponent("effect_scenes.json")) == marker)
    }

    @Test func oldProjectWithoutScenesOpens() throws {
        var project = DrumProject(name: "Old")
        var chain = EffectsChain()
        chain.reverb.isOn = true
        project.scenes = [EffectScene(id: UUID(), name: "Room", chain: chain)]
        let encoded = try project.encoded()
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "scenes")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try DrumProject.decode(stripped)
        #expect(decoded.scenes.isEmpty)
        #expect(decoded.name == "Old")
        #expect(decoded.session.bpm == project.session.bpm)
    }

    @Test func corruptScenesFileShowsTheBannerAndDoesNotCrash() throws {
        let fixture = try SceneFixture()
        defer {
            PersistenceAlerts.shared.clear(file: EffectSceneStore.fileName)
            fixture.remove()
        }
        let garbage = Data("not-json".utf8)
        try garbage.write(to: fixture.directory.appendingPathComponent("effect_scenes.json"))

        let store = EffectSceneStore(directory: fixture.directory)
        #expect(store.scenes.isEmpty)
        let error = try #require(PersistenceAlerts.shared.lastError)
        #expect(error.file == EffectSceneStore.fileName)
        #expect(PersistenceAlerts.shared.isVisible)
        #expect(PersistenceAlerts.shared.text(for: error).contains("сцены"))
        let quarantined = try FileManager.default.contentsOfDirectory(
            at: fixture.directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".corrupt-") }
        #expect(quarantined.count == 1)
        #expect(try Data(contentsOf: quarantined[0]) == garbage)
    }

    @Test func userSceneAppliesTheChainAndUndoesAsEffectPreset() {
        let holder = SceneChainHolder()
        let edits = EffectPresetEditSession()
        let undo = UndoManager()
        edits.read = { holder.chain }
        edits.commit = { holder.chain = $0 }
        edits.undoManager = undo

        var chain = EffectsChain()
        chain.delay.isOn = true
        chain.delay.syncBeats = 0.5
        chain.delay.delayTime = 0.25
        chain.reverb.isOn = true
        chain.reverb.wetDryMix = 0.15
        let scene = EffectScene(id: UUID(), name: "Night", chain: chain)
        edits.chooseUserScene(scene, bpm: 90)

        #expect(undo.undoActionName == "Effect Preset")
        #expect(edits.labels.scene == "Night")
        #expect(edits.labels.reverb == nil)
        #expect(holder.chain.reverb.wetDryMix == 0.15)
        #expect(holder.chain.delay.syncBeats == 0.5)
        #expect(holder.chain.delay.delayTime == EffectPresets.delaySeconds(beats: 0.5, bpm: 90))

        undo.undo()
        #expect(undo.redoActionName == "Effect Preset")
        #expect(holder.chain == EffectsChain())
        #expect(edits.labels.scene == nil)
    }
}

@MainActor
private struct SceneFixture {
    let suite: String
    let directory: URL
    let defaults: UserDefaults

    init() throws {
        suite = "DrumMachineScenes-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class SceneChainHolder {
    var chain = EffectsChain()
}
