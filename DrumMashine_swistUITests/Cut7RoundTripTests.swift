import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_7 IN-3: encode → decode is equal for a non-empty project and for groove settings.
struct Cut7RoundTripTests {
    @Test func grooveSettingsRoundTrip() throws {
        var groove = GrooveSettings()
        groove.grooveID = "mpc-62"
        groove.amount = 70
        groove.timing = 55
        groove.velocity = 40
        groove.random = 12
        groove.perTrack = [true, false, true, true, false, true, true, false]
        let data = try JSONEncoder().encode(groove)
        #expect(try JSONDecoder().decode(GrooveSettings.self, from: data) == groove)
    }

    @Test func drumProjectWithGrooveAndSlotsRoundTrips() throws {
        func preset(_ n: Int) -> SoundPreset {
            SoundPreset(id: UUID(), name: "P\(n)", filename: "sound_\(n)", category: .kick)
        }
        var tracks = (0..<8).map { SequencerTrack(soundPreset: preset($0)) }
        tracks[0].steps[0].isActive = true
        tracks[2].volume = 0.5
        var groove = GrooveSettings()
        groove.grooveID = "swing-16"
        groove.amount = 64
        groove.perTrack[3] = false

        var project = DrumProject(name: "Round")
        project.session = SessionState(tracks: tracks, bpm: 97, swing: 33, masterVolume: 0.7)
        project.session.groove = groove
        let patterns = ["A", "B"].map { DrumPattern(name: $0, tracks: tracks, stepCount: .sixteen) }
        project.slots = PatternLibrary(patterns: patterns, activePatternIndex: 1)
        project.userPresets = [preset(9)]

        #expect(!project.slots.patterns.isEmpty)
        let decoded = try DrumProject.decode(project.encoded())
        #expect(decoded == project)
        #expect(decoded.session.groove == groove)
        #expect(decoded.slots.activePatternIndex == 1)
    }
}
