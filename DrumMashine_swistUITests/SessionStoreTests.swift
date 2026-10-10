import Foundation
import Testing
@testable import DrumMashine_swistUI

/// Session JSON lives in a temp folder. These tests do not flush the shared store.
@MainActor
struct SessionStoreTests {
    @Test func sessionFileRoundTripsTheLiveFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-roundtrip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let kick = SoundPreset(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Kick",
            filename: "kick_808",
            category: .kick
        )
        var snare = SoundPreset(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Snare",
            filename: "snare_808",
            category: .snare
        )
        snare.pitch = 3
        var state = SessionState(tracks: [
            SequencerTrack(soundPreset: kick),
            SequencerTrack(soundPreset: snare)
        ])
        state.bpm = 133
        state.swing = 12
        state.humanize = 20
        state.tracks[0].steps[0].isActive = true
        state.tracks[0].steps[0].velocity = 0.5
        state.effectsChain.reverb.isOn = true
        state.masterVolume = 0.5
        state.limiterEnabled = false
        state.activePatternIndex = 1

        let store = PersistenceStore(directory: directory)
        try store.write(state, name: SessionStore.fileName, version: SessionStore.version)
        let read = try store.read(SessionStore.fileName, as: SessionState.self, maximumVersion: SessionStore.version)
        guard case .loaded(let loaded) = read else {
            Issue.record("session.json did not load")
            return
        }
        #expect(loaded.bpm == 133)
        #expect(loaded.swing == 12)
        #expect(loaded.humanize == 20)
        #expect(loaded.tracks[0].steps[0].isActive)
        #expect(loaded.tracks[0].steps[0].velocity == 0.5)
        #expect(loaded.tracks[1].soundPreset.pitch == 3)
        #expect(loaded.effectsChain.reverb.isOn)
        #expect(loaded.masterVolume == 0.5)
        #expect(loaded.limiterEnabled == false)
        #expect(loaded.activePatternIndex == 1)
        #expect(loaded.libraryInspectorOpen == true)

        let engine = SequencerEngine(session: loaded)
        #expect(engine.isPlaying == false)
        #expect(engine.currentStep == 0)
        #expect(engine.bpm == 133)
        #expect(engine.swing == 12)
        #expect(engine.humanize == 20)
        #expect(engine.tracks.count == 8)
        #expect(engine.tracks[0].steps[0].isActive)
        #expect(engine.tracks[0].steps[0].velocity == 0.5)
        #expect(engine.tracks[1].soundPreset.pitch == 3)
        #expect(engine.tracks.allSatisfy { !$0.soundPreset.filename.hasPrefix("sound_") })
    }

    @Test func freshSequencerUsesTheLibraryKick() {
        let engine = SequencerEngine()
        #expect(engine.isPlaying == false)
        #expect(engine.currentStep == 0)
        #expect(engine.tracks[0].soundPreset.filename == "kick_808")
        #expect(engine.tracks.allSatisfy { !$0.soundPreset.filename.hasPrefix("sound_") })
    }

    @Test func sessionMissingKeysKeepsDefaults() throws {
        let state = try JSONDecoder().decode(SessionState.self, from: Data(#"{"bpm":133}"#.utf8))
        #expect(state.bpm == 133)
        #expect(state.tracks.isEmpty)
        #expect(state.swing == 0)
        #expect(state.humanize == 0)
        #expect(state.stepCount == .sixteen)
        #expect(state.activePatternIndex == 0)
        #expect(state.masterVolume == 0.85)
        #expect(state.limiterEnabled == true)
        #expect(state.libraryInspectorOpen == true)
        #expect(state.effectsChain.reverb.isOn == false)
    }
}
