import CryptoKit
import Foundation
import Testing
@testable import DrumMashine_swistUI

/// SHA-256 of the 60 factory buffers at 48 kHz, taken before D-0 changed voice routing.
/// The fixture is little-endian `Float` bytes, one line per filename.
@MainActor
struct FactoryBufferTests {
    @Test func legacyFactoryBuffersMatchTheD0Hashes() throws {
        let sounds = SoundLibraryManager.shared.availableSounds.filter { $0.style == .legacy }
        #expect(sounds.count == 60)
        var lines: [String] = []
        lines.reserveCapacity(sounds.count)
        for preset in sounds {
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: 48_000)
            let digest = SHA256.hash(data: Data(samples.withUnsafeBytes { Data($0) }))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            lines.append("\(preset.filename) \(hex) \(samples.count)")
        }
        let text = lines.joined(separator: "\n") + "\n"
        let written = FileManager.default.temporaryDirectory
            .appendingPathComponent("factory-hashes-48k.txt")
        try text.write(to: written, atomically: true, encoding: .utf8)

        let bundle = Bundle(for: StandardPatternsGuard.self)
        let fixture = try #require(
            bundle.url(forResource: "factory_buffers_48k", withExtension: "txt", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "factory_buffers_48k", withExtension: "txt")
        )
        let expected = try String(contentsOf: fixture, encoding: .utf8)
        #expect(text == expected)
        _ = written
    }

    @Test func clapTrackUsesTheClapVoiceAfterLaunch() {
        let engine = SequencerEngine()
        let filenames = engine.tracks.map(\.soundPreset.filename)
        #expect(filenames == [
            "kick_808", "snare_808", "hh_closed", "clap_808",
            "tom_low", "ride_bell", "crash_14", "conga"
        ])
        #expect(engine.tracks[3].soundPreset.voice == .clap)
        #expect(engine.tracks[3].soundPreset.resolvedVoice == .clap)
        #expect(engine.tracks[7].soundPreset.voice == .perc)
    }

    @Test func missingVoiceFollowsTheOldFilenameGuess() {
        var preset = SoundPreset(id: UUID(), name: "Clap", filename: "clap_808", category: .percussion)
        #expect(preset.voice == nil)
        #expect(preset.synth == nil)
        #expect(preset.source == .synth)
        #expect(preset.resolvedVoice == .clap)
        preset.filename = "tom_low"
        #expect(preset.resolvedVoice == .tom)
        preset.category = .hihat
        preset.filename = "hh_open"
        preset.decay = 0.35
        #expect(preset.resolvedVoice == .openHat)
        preset.decay = 0.05
        #expect(preset.resolvedVoice == .closedHat)
        preset.voice = .closedHat
        preset.decay = 0.9
        #expect(preset.resolvedVoice == .closedHat)
    }
}
