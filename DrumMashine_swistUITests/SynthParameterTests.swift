import Foundation
import Testing
@testable import DrumMashine_swistUI

/// Each generator parameter has to move the buffer. Defaults stay on the D-0 hash path.
@MainActor
struct SynthParameterTests {
    @Test func everyVoiceParameterChangesTheBuffer() {
        let library = SoundLibraryManager.shared
        func preset(_ filename: String) -> SoundPreset {
            library.availableSounds.first { $0.filename == filename }!
        }
        func expectChange(_ filename: String, _ edit: (inout SoundPreset) -> Void) {
            let original = preset(filename)
            var edited = original
            edit(&edited)
            let before = DrumSynthesizer.samples(for: original, sampleRate: 48_000)
            let after = DrumSynthesizer.samples(for: edited, sampleRate: 48_000)
            #expect(before != after, "\(filename) did not change")
        }

        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(startHz: 80)) }
        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(endHz: 30)) }
        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(sweep: 0.2)) }
        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(click: 0)) }
        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(clickMs: 30)) }
        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(drive: 4)) }
        expectChange("kick_808") { $0.synth = SynthParams(kick: .init(noise: 0.8)) }

        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(tone1Hz: 90)) }
        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(tone2Hz: 700)) }
        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(tone1Level: 0.05)) }
        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(tone2Level: 1)) }
        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(bodyTau: 0.04)) }
        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(noiseHPHz: 4000)) }
        expectChange("snare_808") { $0.synth = SynthParams(snare: .init(noiseLevel: 0.1)) }

        expectChange("hh_closed") { $0.synth = SynthParams(hat: .init(open: true)) }
        expectChange("hh_closed") { $0.synth = SynthParams(hat: .init(hpHz: 3000)) }
        expectChange("hh_closed") { $0.synth = SynthParams(hat: .init(bandHz: 4000)) }
        expectChange("hh_closed") { $0.synth = SynthParams(hat: .init(bandQ: 3)) }
        expectChange("hh_closed") { $0.synth = SynthParams(hat: .init(noiseMix: 0.9)) }
        expectChange("hh_open") { $0.synth = SynthParams(hat: .init(open: false)) }

        expectChange("clap_808") { $0.synth = SynthParams(clap: .init(bursts: 1)) }
        expectChange("clap_808") { $0.synth = SynthParams(clap: .init(spacing: 0.04)) }
        expectChange("clap_808") { $0.synth = SynthParams(clap: .init(hpHz: 2000)) }
        expectChange("clap_808") { $0.synth = SynthParams(clap: .init(lpHz: 900)) }
        expectChange("clap_808") { $0.synth = SynthParams(clap: .init(tailLevel: 0.05)) }

        expectChange("tom_low") { $0.synth = SynthParams(tom: .init(startHz: 90)) }
        expectChange("tom_low") { $0.synth = SynthParams(tom: .init(endHz: 40)) }
        expectChange("tom_low") { $0.synth = SynthParams(tom: .init(sweep: 0.2)) }
        expectChange("tom_low") { $0.synth = SynthParams(tom: .init(stickNoise: 0.9)) }

        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(pingHz: 2000)) }
        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(pingModHz: 200)) }
        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(pingLevel: 0.05)) }
        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(sizzleLevel: 0.95)) }
        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(sizzleTau: 1.4)) }
        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(hpHz: 800)) }
        expectChange("ride_bell") { $0.synth = SynthParams(ride: .init(lpHz: 2500)) }

        expectChange("crash_14") { $0.synth = SynthParams(crash: .init(carrierHz: 120)) }
        expectChange("crash_14") { $0.synth = SynthParams(crash: .init(modHz: 180)) }
        expectChange("crash_14") { $0.synth = SynthParams(crash: .init(index: 1)) }
        expectChange("crash_14") { $0.synth = SynthParams(crash: .init(fmMix: 0.9)) }
        expectChange("crash_14") { $0.synth = SynthParams(crash: .init(hpHz: 500)) }

        expectChange("conga") { $0.synth = SynthParams(perc: .init(carrierHz: 200)) }
        expectChange("conga") { $0.synth = SynthParams(perc: .init(ratio: 2.5)) }
        expectChange("conga") { $0.synth = SynthParams(perc: .init(index: 0.2)) }
        expectChange("conga") { $0.synth = SynthParams(perc: .init(indexDecay: 4)) }
        expectChange("conga") { $0.synth = SynthParams(perc: .init(mode: .cowbell, carrierHz: 540, secondHz: 800)) }
        expectChange("conga") { $0.synth = SynthParams(perc: .init(mode: .noise, bandHz: 7000, bandQ: 2, bursts: 2, spacing: 0.02)) }
        expectChange("conga") { $0.synth = SynthParams(perc: .init(mode: .cowbell, bandHz: 1000, bandQ: 0.4)) }

        expectChange("kick_808") { $0.synth = SynthParams(lofi: .init(bitDepth: 8)) }
        expectChange("kick_808") { $0.synth = SynthParams(lofi: .init(downsample: 4)) }
        expectChange("kick_808") { $0.synth = SynthParams(lofi: .init(saturation: 0.9)) }
        expectChange("fx_noise") { $0.synth = SynthParams(lofi: .init(bitDepth: 8, downsample: 3)) }
    }

    @Test func eightBitLoFiStaysInside256LevelsBeforeNormalize() {
        var preset = SoundLibraryManager.shared.availableSounds.first { $0.filename == "kick_808" }!
        preset.synth = SynthParams(lofi: .init(bitDepth: 8))
        let dry = DrumSynthesizer.samplesBeforeNormalize(for: preset, sampleRate: 48_000)
        #expect(Set(dry).count <= 256)
        #expect(Set(dry).count > 8)
    }
}
