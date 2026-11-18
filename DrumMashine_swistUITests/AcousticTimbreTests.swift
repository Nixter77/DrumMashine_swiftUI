import Foundation
import Testing
@testable import DrumMashine_swistUI

private let timbreRate: Double = 48_000

private func acousticPreset(
    voice: SoundPreset.VoiceKind,
    filename: String,
    decay: Float = 0.2,
    dynamics: Dynamics = Dynamics(layers: 4, roundRobin: 1, brightness: 0.55, transient: 0.7, pitch: 1.0, noise: 0.15),
    articulations: [ArticulationSpec]? = nil,
    synth: SynthParams? = nil,
    mic: MicMix? = nil
) -> SoundPreset {
    var preset = SoundPreset(id: UUID(), name: filename, filename: filename, category: .kick)
    preset.voice = voice
    preset.decay = decay
    preset.dynamics = dynamics
    preset.articulations = articulations
    preset.synth = synth
    preset.mic = mic
    return preset
}

struct AcousticTimbreTests {
    @Test func kickCentroidRisesFromQuietToAccent() {
        let preset = acousticPreset(
            voice: .kick,
            filename: "ac_timbre_kick",
            synth: SynthParams(membrane: .init(f0: 56, damping: 0.35, beater: 0.9, port: false))
        )
        let quiet = DrumSynthesizer.acousticHit(preset: preset, velocity: 0.25, sampleRate: timbreRate)
        let accent = DrumSynthesizer.acousticHit(preset: preset, velocity: 1, sampleRate: timbreRate)
        let quietCentroid = AudioMetrics.spectralCentroid(quiet, sampleRate: timbreRate, windowSeconds: 0.030)
        let accentCentroid = AudioMetrics.spectralCentroid(accent, sampleRate: timbreRate, windowSeconds: 0.030)
        #expect(quietCentroid > 20)
        #expect(accentCentroid >= quietCentroid * 1.4)
    }

    @Test func accentIsBrighterOnTheFiveDrumFamilies() {
        let cases: [(SoundPreset.VoiceKind, AcousticRecipe, String, Float)] = [
            (.kick, .membraneKick, "ac_bright_kick", 0.25),
            (.snare, .snareCenter, "ac_bright_snare", 0.2),
            (.closedHat, .hatClosed, "ac_bright_hat", 0.08),
            (.ride, .rideBow, "ac_bright_ride", 0.4),
            (.crash, .crash, "ac_bright_crash", 0.35)
        ]
        for (voice, recipe, name, decay) in cases {
            let preset = acousticPreset(
                voice: voice,
                filename: name,
                decay: decay,
                articulations: [ArticulationSpec(recipe: recipe, wires: voice == .snare ? 0.9 : nil)]
            )
            let quiet = DrumSynthesizer.acousticHit(preset: preset, velocity: voice == .snare ? 0.2 : 0.25, sampleRate: timbreRate)
            let accent = DrumSynthesizer.acousticHit(preset: preset, velocity: 1, sampleRate: timbreRate)
            let quietCentroid = AudioMetrics.spectralCentroid(quiet, sampleRate: timbreRate, windowSeconds: 0.030)
            let accentCentroid = AudioMetrics.spectralCentroid(accent, sampleRate: timbreRate, windowSeconds: 0.030)
            #expect(quietCentroid > 20, "\(name) quiet")
            #expect(accentCentroid >= quietCentroid * 1.4, "\(name) \(accentCentroid) vs \(quietCentroid)")
        }
    }

    @Test func snareWireEnergyTriplesFromGhostToAccent() {
        let preset = acousticPreset(
            voice: .snare,
            filename: "ac_timbre_snare",
            articulations: [ArticulationSpec(recipe: .snareCenter, f0: 200, wires: 0.85)],
            synth: SynthParams(snareModel: .init(f0: 200, wires: 0.85, buzz: 0.3))
        )
        let ghost = DrumSynthesizer.acousticHit(preset: preset, velocity: 0.2, sampleRate: timbreRate)
        let accent = DrumSynthesizer.acousticHit(preset: preset, velocity: 1, sampleRate: timbreRate)
        let ghostBand = AudioMetrics.bandEnergy(ghost, sampleRate: timbreRate, lowHz: 3_000, highHz: 8_000, windowSeconds: 0.08)
        let accentBand = AudioMetrics.bandEnergy(accent, sampleRate: timbreRate, lowHz: 3_000, highHz: 8_000, windowSeconds: 0.08)
        #expect(ghostBand > 0)
        #expect(accentBand >= ghostBand * 3)
    }

    @Test func articulationsChangeTheInstrument() {
        let snare = acousticPreset(
            voice: .snare,
            filename: "ac_timbre_snare_art",
            articulations: [
                ArticulationSpec(name: "center", recipe: .snareCenter, f0: 200, wires: 0.8),
                ArticulationSpec(name: "rim", recipe: .snareRimshot, f0: 210, wires: 0.7),
                ArticulationSpec(name: "stick", recipe: .snareCrossStick, f0: 180, wires: 0)
            ]
        )
        let center = DrumSynthesizer.acousticHit(preset: snare, velocity: 1, articulation: 0, sampleRate: timbreRate)
        let rim = DrumSynthesizer.acousticHit(preset: snare, velocity: 1, articulation: 1, sampleRate: timbreRate)
        let stick = DrumSynthesizer.acousticHit(preset: snare, velocity: 1, articulation: 2, sampleRate: timbreRate)
        let centerCentroid = AudioMetrics.spectralCentroid(center, sampleRate: timbreRate, windowSeconds: 0.03)
        let rimCentroid = AudioMetrics.spectralCentroid(rim, sampleRate: timbreRate, windowSeconds: 0.03)
        #expect(rimCentroid > centerCentroid)
        let centerWires = AudioMetrics.bandEnergy(center, sampleRate: timbreRate, lowHz: 3_000, highHz: 8_000)
        let stickWires = AudioMetrics.bandEnergy(stick, sampleRate: timbreRate, lowHz: 3_000, highHz: 8_000)
        #expect(stickWires < centerWires * 0.5)

        let hat = acousticPreset(
            voice: .closedHat,
            filename: "ac_timbre_hat",
            decay: 0.4,
            articulations: [
                ArticulationSpec(recipe: .hatClosed),
                ArticulationSpec(recipe: .hatOpen),
                ArticulationSpec(recipe: .hatPedal)
            ]
        )
        let closed = DrumSynthesizer.acousticHit(preset: hat, velocity: 1, articulation: 0, sampleRate: timbreRate)
        let open = DrumSynthesizer.acousticHit(preset: hat, velocity: 1, articulation: 1, sampleRate: timbreRate)
        let pedal = DrumSynthesizer.acousticHit(preset: hat, velocity: 1, articulation: 2, sampleRate: timbreRate)
        #expect(open.count > closed.count * 3)
        #expect(pedal.count < closed.count)

        let ride = acousticPreset(
            voice: .ride,
            filename: "ac_timbre_ride",
            decay: 0.5,
            articulations: [
                ArticulationSpec(recipe: .rideBow),
                ArticulationSpec(recipe: .rideBell)
            ]
        )
        let bow = DrumSynthesizer.acousticHit(preset: ride, velocity: 0.9, articulation: 0, sampleRate: timbreRate)
        let bell = DrumSynthesizer.acousticHit(preset: ride, velocity: 0.9, articulation: 1, sampleRate: timbreRate)
        let bowLow = AudioMetrics.bandEnergy(bow, sampleRate: timbreRate, lowHz: 600, highHz: 1_600, windowSeconds: 0.05)
        let bellLow = AudioMetrics.bandEnergy(bell, sampleRate: timbreRate, lowHz: 600, highHz: 1_600, windowSeconds: 0.05)
        #expect(bellLow > bowLow)

        let tom = acousticPreset(
            voice: .tom,
            filename: "ac_timbre_tom",
            articulations: [
                ArticulationSpec(tag: "1", recipe: .membraneTom, f0: 220),
                ArticulationSpec(tag: "3", recipe: .membraneTom, f0: 90)
            ]
        )
        let high = DrumSynthesizer.acousticHit(preset: tom, velocity: 0.8, articulation: 0, sampleRate: timbreRate)
        let floor = DrumSynthesizer.acousticHit(preset: tom, velocity: 0.8, articulation: 1, sampleRate: timbreRate)
        let highCentroid = AudioMetrics.spectralCentroid(high, sampleRate: timbreRate, windowSeconds: 0.05)
        let floorCentroid = AudioMetrics.spectralCentroid(floor, sampleRate: timbreRate, windowSeconds: 0.05)
        #expect(highCentroid > floorCentroid * 1.3)
    }

    @Test func velocitySweepDoesNotLoseLevel() throws {
        let preset = acousticPreset(voice: .kick, filename: "ac_timbre_sweep", decay: 0.16)
        let bank = DrumSynthesizer.layerBank(for: preset, sampleRate: timbreRate)
        var previousPeak: Float = 0
        var previousRMS: Float = 0
        for step in 0..<20 {
            let velocity = Float(0.05 + Double(step) * 0.05)
            let engine = VoiceEngine(sampleRate: timbreRate)
            engine.swapLayers(track: 0, bank: bank)
            engine.trigger(track: 0, velocity: velocity, chokeGroup: -1, atSample: 0)
            let mix = try renderOffline(frames: 8_000, chunkFrames: 4_000, sampleRate: timbreRate) { _ in engine.sourceNode }
            let peak = AudioMetrics.peak(mix)
            let level = AudioMetrics.rms(mix)
            #expect(peak + 1e-5 >= previousPeak)
            #expect(level + 1e-5 >= previousRMS)
            previousPeak = peak
            previousRMS = level
        }
    }

    @Test func roomTailOutlastsTheDryHit() {
        let dry = acousticPreset(voice: .kick, filename: "ac_timbre_dry", decay: 0.04)
        var wet = dry
        wet.mic = MicMix(close: 1, overhead: 0.4, room: 0.9, roomTone: 0.2, roomSize: .medium)
        let dryHit = DrumSynthesizer.acousticHit(preset: dry, velocity: 1, sampleRate: timbreRate)
        let wetHit = DrumSynthesizer.acousticHit(preset: wet, velocity: 1, sampleRate: timbreRate)
        #expect(wetHit.count > dryHit.count + Int(0.05 * timbreRate))
        let extra = Array(wetHit[dryHit.count..<wetHit.count])
        #expect(AudioMetrics.rms(extra) > 0.002)
    }

    @Test func acousticHitsRepeatBitForBit() {
        let preset = acousticPreset(
            voice: .snare,
            filename: "ac_timbre_repeat",
            articulations: [ArticulationSpec(recipe: .snareCenter, wires: 0.7)]
        )
        let first = DrumSynthesizer.acousticHit(preset: preset, velocity: 0.8, sampleRate: timbreRate)
        let second = DrumSynthesizer.acousticHit(preset: preset, velocity: 0.8, sampleRate: timbreRate)
        #expect(first.count == second.count)
        var mismatches = 0
        for index in first.indices where first[index].bitPattern != second[index].bitPattern {
            mismatches += 1
        }
        #expect(mismatches == 0)
    }

    @Test func everyRecipeStaysFinite() {
        let recipes: [AcousticRecipe] = [
            .membraneKick, .membraneTom, .snareCenter, .snareRimshot, .snareCrossStick,
            .brushTap, .brushSwirl, .brushSlap,
            .hatClosed, .hatOpen, .hatPedal, .hatHalfOpen,
            .rideBow, .rideBell, .rideEdge, .crash, .splash, .china,
            .conga, .bongo, .cajon, .djembe, .shaker, .tambourine, .clap, .snap,
            .cowbell, .agogo, .timbale, .wood, .guiro, .triangle,
            .orchestralBass, .timpani, .concertSnare, .suspendedCymbal
        ]
        for recipe in recipes {
            let preset = acousticPreset(
                voice: .perc,
                filename: "ac_timbre_\(recipe.rawValue)",
                decay: 0.08,
                articulations: [ArticulationSpec(recipe: recipe)]
            )
            let hit = DrumSynthesizer.acousticHit(preset: preset, velocity: 0.85, sampleRate: timbreRate)
            #expect(hit.count > 8)
            #expect(hit.last == 0)
            var peak: Float = 0
            var nonFinite = 0
            for sample in hit {
                if !sample.isFinite { nonFinite += 1 }
                peak = max(peak, abs(sample))
            }
            #expect(nonFinite == 0)
            #expect(peak > 0.0001)
        }
    }
}
