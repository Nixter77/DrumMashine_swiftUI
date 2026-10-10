import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct AcousticKitTests {
    @Test func everyPieceShipsInTheBundleAndRenders() {
        for preset in AcousticKit.presets() {
            guard case .bundled(let file) = preset.source else {
                Issue.record("\(preset.name) is not bundled"); continue
            }
            #expect(BundledSamples.url(for: file) != nil, "\(file) missing from bundle")
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: 48_000)
            #expect(samples.count > 4_800, "\(file) too short \(samples.count)")
            #expect(samples.count <= 48_000 * 4, "\(file) too long")
            let peak = samples.map { abs($0) }.max() ?? 0
            #expect(peak > 0.05 && peak <= 0.501, "\(file) peak \(peak)")
            #expect(samples.allSatisfy { $0.isFinite })
        }
    }

    @Test func kitIsInTheLibraryUnderAcousticWithStableIDs() {
        let library = SoundLibraryManager.shared.availableSounds
        let kit = AcousticKit.presets()
        #expect(kit.count == 13)
        for preset in kit {
            #expect(preset.style == .acoustic)
            #expect(library.contains { $0.id == preset.id })
        }
        #expect(kit.map(\.id) == AcousticKit.presets().map(\.id))
        #expect(Set(kit.map(\.resolvedVoice)).isSuperset(of: [.kick, .snare, .closedHat, .openHat, .tom, .ride, .crash]))
    }

    @Test func ghostNoteIsQuieterThanTheMainSnare() {
        let kit = AcousticKit.presets()
        let snare = kit.first { $0.filename == "real_acoustic_snare" }!
        let ghost = kit.first { $0.filename == "real_acoustic_snare_ghost" }!
        let a = DrumSynthesizer.samples(for: snare, sampleRate: 48_000).map { abs($0) }.max() ?? 0
        let b = DrumSynthesizer.samples(for: ghost, sampleRate: 48_000).map { abs($0) }.max() ?? 0
        #expect(b < a * 0.5)
    }

    @Test func bundledSourceRoundTripsThroughJSON() throws {
        let preset = AcousticKit.presets()[0]
        let data = try JSONEncoder().encode(preset)
        let back = try JSONDecoder().decode(SoundPreset.self, from: data)
        #expect(back.source == preset.source)
    }
}
