import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_7 IN-1/IN-2: legacy JSON without newer keys decodes with concrete defaults.
struct LegacyDecodeDefaultsTests {
    @Test func legacyProjectWithoutSessionOrSlotsGetsDefaults() throws {
        let project = try DrumProject.decode(fixture("legacy_project_v0"))
        #expect(project.name == "Old Beat")
        #expect(project.version == DrumProject.formatVersion)
        #expect(project.session.tracks.isEmpty)
        #expect(project.session.bpm == 120)
        #expect(project.session.swing == 0)
        #expect(project.session.masterVolume == 0.85)
        #expect(project.session.groove == GrooveSettings())
        #expect(project.slots.patterns.isEmpty)
        #expect(project.slots.activePatternIndex == 0)
        #expect(project.userPresets.isEmpty)
        #expect(project.kits.isEmpty)
        #expect(project.samples.isEmpty)
        #expect(project.scenes.isEmpty)
    }

    @Test func legacySessionWithoutNewKeysGetsDefaults() throws {
        let session = try JSONDecoder().decode(SessionState.self, from: fixture("legacy_session_v0"))
        #expect(session.bpm == 95)
        #expect(session.swing == 12)
        #expect(session.humanize == 0)
        #expect(session.groove == GrooveSettings())
        #expect(session.groove.grooveID == FactoryGrooves.cleanID)
        #expect(session.groove.amount == 100)
        #expect(session.groove.perTrack == Array(repeating: true, count: 8))
        #expect(session.stepCount == .sixteen)
        #expect(session.activePatternIndex == 0)
        #expect(session.masterVolume == 0.85)
        #expect(session.limiterEnabled == true)
        #expect(session.libraryInspectorOpen == true)
    }

    @Test func legacySoundPresetGetsEnvelopeAndSourceDefaults() throws {
        let presets = try JSONDecoder().decode([SoundPreset].self, from: fixture("legacy_sound_preset_v0"))
        #expect(presets.count == 2)
        let kick = presets[0]
        #expect(kick.name == "Old Kick")
        #expect(kick.category == .kick)
        #expect(kick.volume == 1.0)
        #expect(kick.pan == 0.0)
        #expect(kick.pitch == 0.0)
        #expect(kick.attack == 0.0)
        #expect(kick.decay == 0.1)
        #expect(kick.sustain == 1.0)
        #expect(kick.release == 0.1)
        #expect(kick.chokeGroup == nil)
        #expect(kick.basedOn == nil)
        #expect(kick.synth == nil)
        #expect(kick.source == .synth)
        #expect(kick.toneFilter == nil)
        #expect(presets[1].category == .percussion)
    }

    @Test func legacyTrackWithoutSoundPresetGetsPlaceholderSound() throws {
        let track = try JSONDecoder().decode(SequencerTrack.self, from: fixture("legacy_track_v0"))
        #expect(track.isMuted == true)
        #expect(track.isSolo == false)
        #expect(track.volume == 1.0)
        #expect(track.pan == 0.0)
        #expect(track.soundPreset.name == "Sound")
        #expect(track.soundPreset.filename == "")
        #expect(track.soundPreset.category == .percussion)
    }

    @Test func legacyPatternAndKitWithoutNamesGetDefaultNames() throws {
        struct Pair: Decodable { var pattern: DrumPattern; var kit: DrumKit }
        let pair = try JSONDecoder().decode(Pair.self, from: fixture("legacy_pattern_kit_v0"))
        #expect(pair.pattern.name == "Pattern")
        #expect(pair.pattern.bpm == 120)
        #expect(pair.pattern.swing == 0)
        #expect(pair.pattern.tracks.isEmpty)
        #expect(pair.kit.name == "Kit")
        #expect(pair.kit.sounds.isEmpty)
    }
}

func fixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: StandardPatternsGuard.self)
    let url = try #require(
        bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
    )
    return try Data(contentsOf: url)
}
