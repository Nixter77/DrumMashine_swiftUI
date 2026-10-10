import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct SoundControlsTests {
    private func render(_ preset: SoundPreset) -> [Float] {
        DrumSynthesizer.samples(for: preset, sampleRate: 24_000)
    }

    private func differs(_ a: [Float], _ b: [Float]) -> Bool {
        if a.count != b.count { return true }
        var sum: Float = 0
        for i in a.indices { sum += abs(a[i] - b[i]) }
        return sum / Float(max(a.count, 1)) > 1e-5
    }

    /// One preset per voice and source kind: the eight defaults, every acoustic sample, and one of each perc mode.
    private var subjects: [SoundPreset] {
        var list = (0..<8).map { SoundLibraryManager.shared.defaultPreset(forTrackIndex: $0) }
        list += AcousticKit.presets()
        let library = SoundLibraryManager.shared.availableSounds
        for voice in SoundPreset.VoiceKind.allCases where voice != .fx {
            list += library.filter { $0.resolvedVoice == voice && $0.source == .synth }.prefix(3)
        }
        for mode in [SynthParams.PercMode.noise, .cowbell, .fm] {
            if let p = library.first(where: { $0.synth?.perc?.mode == mode }) { list.append(p) }
        }
        return list
    }

    @Test func everyTrackHasTuneDecayToneAndLevel() {
        for preset in subjects {
            let ids = Set(SoundControls.controls(for: preset).map(\.id))
            #expect(ids.isSuperset(of: ["tune", "tone", "level"]), "\(preset.name)")
            #expect(ids.contains("decay") || ids.contains("length"), "\(preset.name)")
        }
    }

    @Test func everyControlAudiblyChangesTheSound() {
        var dead: [String] = []
        defer { #expect(dead.isEmpty, "dead controls: \(dead)") }
        for preset in subjects {
            for control in SoundControls.controls(for: preset) {
                var low = preset
                control.set(&low, control.range.lowerBound)
                var high = preset
                control.set(&high, control.range.upperBound)
                let changed = differs(render(low), render(high))
                if !changed { dead.append("\(preset.name)/\(preset.resolvedVoice)/\(control.id)") }
                #expect(abs(control.get(high) - control.range.upperBound) < 0.51, "\(preset.name) \(control.id) get")
            }
        }
    }

    @Test func renderedBuffersStayInsideLimits() {
        for preset in AcousticKit.presets() {
            var edited = preset
            SoundControls.tone.set(&edited, -1)
            SoundControls.length.set(&edited, 0.2)
            SoundControls.tune.set(&edited, 7)
            let samples = render(edited)
            let peak = samples.map { abs($0) }.max() ?? 0
            #expect(peak <= 0.501 && peak > 0.01, "\(preset.name) peak \(peak)")
            #expect(samples.allSatisfy { $0.isFinite })
            #expect(samples.last == 0)
        }
    }

    @Test func toneFilterRoundTripsThroughJSON() throws {
        var preset = AcousticKit.presets()[0]
        preset.toneFilter = -0.4
        preset.volume = 0.6
        let data = try JSONEncoder().encode(preset)
        let back = try JSONDecoder().decode(SoundPreset.self, from: data)
        #expect(back.toneFilter == -0.4)
        #expect(back.volume == 0.6)
        let old = try JSONDecoder().decode(SoundPreset.self, from: Data(#"{"name":"x","category":"kick"}"#.utf8))
        #expect(old.toneFilter == nil)
    }
}

@MainActor
struct LibraryVisibilityTests {
    @Test func acousticFilterListsHatsAndEveryKitPiece() {
        let library = SoundLibraryManager.shared
        let closed = library.presets(for: .closedHat, style: .acoustic).map(\.name)
        let open = library.presets(for: .openHat, style: .acoustic).map(\.name)
        #expect(closed.contains("Real Hat Closed"))
        #expect(open.contains("Real Hat Open"))
        for piece in AcousticKit.presets() {
            #expect(library.presets(for: piece.resolvedVoice, style: .acoustic).contains { $0.id == piece.id }, "\(piece.name)")
        }
    }

    @Test func hatTrackPickerOffersClosedAndOpenHats() {
        let options = SoundLibraryManager.shared.presets(forTrackVoice: .closedHat)
        #expect(options.contains { $0.resolvedVoice == .openHat })
        #expect(options.contains { $0.name == "Real Hat Closed" })
        #expect(options.contains { $0.name == "Real Hat Open" })
        #expect(!options.contains { $0.resolvedVoice == .kick })
    }

    @Test func everyVoiceTabHasSounds() {
        for voice in SoundPreset.VoiceKind.allCases {
            #expect(!SoundLibraryManager.shared.presets(for: voice, style: nil).isEmpty, "\(voice)")
        }
    }
}
