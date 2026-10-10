import Foundation
import Testing
@testable import DrumMashine_swistUI

/// Old saves omit keys that later gained defaults. Decoding must keep those defaults.
@MainActor
struct CodableToleranceTests {
    @Test func soundPresetWithOnlyTheCoreKeysUsesDefaults() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let json = """
        {"id":"\(id.uuidString)","name":"Kick","filename":"kick_808","category":"kick"}
        """
        let preset = try JSONDecoder().decode(SoundPreset.self, from: Data(json.utf8))
        #expect(preset == SoundPreset(id: id, name: "Kick", filename: "kick_808", category: .kick))
    }

    @Test func soundPresetWithoutAnIdGetsOneAndAnUnknownCategoryIsPercussion() throws {
        let json = #"{"name":"Odd","category":"not-a-category"}"#
        let preset = try JSONDecoder().decode(SoundPreset.self, from: Data(json.utf8))
        #expect(preset.name == "Odd")
        #expect(preset.filename == "")
        #expect(preset.category == .percussion)
        #expect(preset.volume == 1)
    }

    @Test func encodedSoundPresetRoundTrips() throws {
        var preset = SoundPreset(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Snare",
            filename: "snare_808",
            category: .snare
        )
        preset.pitch = 3
        preset.chokeGroup = 1
        let data = try JSONEncoder().encode(preset)
        #expect(try JSONDecoder().decode(SoundPreset.self, from: data) == preset)
    }

    @Test func emptyEffectsChainUsesDefaults() throws {
        let chain = try JSONDecoder().decode(EffectsChain.self, from: Data("{}".utf8))
        #expect(chain == EffectsChain())
    }

    @Test func reverbWithoutARoomKeepsTheDefaultRoom() throws {
        let json = #"{"reverb":{"isOn":true,"wetDryMix":0.5,"room":"cathedral"}}"#
        let chain = try JSONDecoder().decode(EffectsChain.self, from: Data(json.utf8))
        #expect(chain.reverb.isOn)
        #expect(chain.reverb.wetDryMix == 0.5)
        #expect(chain.reverb.room == .mediumHall)
        #expect(chain.delay == EffectsChain.DelaySettings())
    }

    @Test func patternWithoutTempoOrTracksUsesDefaults() throws {
        let pattern = try JSONDecoder().decode(DrumPattern.self, from: Data(#"{"name":"A"}"#.utf8))
        #expect(pattern.name == "A")
        #expect(pattern.bpm == 120)
        #expect(pattern.swing == 0)
        #expect(pattern.tracks.isEmpty)
        #expect(pattern.stepCount == nil)
        #expect(pattern.resolvedStepCount == .sixteen)
    }

    @Test func stepAndKitOmitOptionalKeys() throws {
        let step = try JSONDecoder().decode(SequencerStep.self, from: Data("{}".utf8))
        #expect(step.isActive == false)
        #expect(step.velocity == 0.8)
        #expect(step.probability == 1)
        let kit = try JSONDecoder().decode(DrumKit.self, from: Data(#"{"name":"808"}"#.utf8))
        #expect(kit.name == "808")
        #expect(kit.sounds.isEmpty)
    }

    @Test func fourEmptySlotsRoundTripAsADocumentAndAsABareArray() throws {
        let patterns = fourEmptyPatterns()
        let document = try PatternStore.encode(patterns)
        #expect(try PatternStore.decode(document) == patterns)
        let bare = try JSONEncoder().encode(patterns)
        #expect(try PatternStore.decode(bare) == patterns)
    }

    @Test func legacyPatternFixtureDecodesFourEmptySlots() throws {
        let bundle = Bundle(for: StandardPatternsGuard.self)
        let url = try #require(
            bundle.url(forResource: "legacy_patterns_v2", withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: "legacy_patterns_v2", withExtension: "json")
        )
        let patterns = try PatternStore.decode(Data(contentsOf: url))
        #expect(patterns.count == 4)
        #expect(patterns.map(\.name) == ["A", "B", "C", "D"])
        #expect(patterns.allSatisfy { $0.tracks.count == 8 && $0.resolvedStepCount == .sixteen })
        #expect(patterns.allSatisfy { pattern in
            pattern.tracks.allSatisfy { track in track.steps.allSatisfy { !$0.isActive } }
        })
    }
}

/// Four empty slots, the same shape as `PatternManager.makeEmptyPattern`, with fixed ids.
private func fourEmptyPatterns() -> [DrumPattern] {
    let names = ["KICK", "SNARE", "HIHAT", "CLAP", "TOM", "RIDE", "CRASH", "PERC"]
    let categories: [SoundPreset.SoundCategory] = [
        .kick, .snare, .hihat, .percussion, .percussion, .cymbals, .cymbals, .percussion
    ]
    var next = 0
    func makeID() -> UUID {
        next += 1
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", next))!
    }
    return (0..<4).map { slot in
        let tracks = (0..<8).map { index -> SequencerTrack in
            let preset = SoundPreset(
                id: makeID(),
                name: names[index],
                filename: "sound_\(index)",
                category: categories[index]
            )
            var track = SequencerTrack(soundPreset: preset)
            track.id = makeID()
            for step in track.steps.indices {
                track.steps[step].id = makeID()
            }
            return track
        }
        var pattern = DrumPattern(name: ["A", "B", "C", "D"][slot], tracks: tracks, stepCount: .sixteen)
        pattern.id = makeID()
        return pattern
    }
}
