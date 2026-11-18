import Foundation
import Testing
@testable import DrumMashine_swistUI

/// TQ-1. Single hits at velocity 0.8 through `acousticHit`, not the peak-normalized preview.
@MainActor
struct AcousticLevelTests {
    private let rate = 48_000.0

    @Test func hitsAtPointEightSitNearTheSnare() {
        var misses: [String] = []
        for kit in AcousticKits.kits() {
            let sounds = kit.sounds
            guard sounds.count == 8 else {
                misses.append("\(kit.name) slots \(sounds.count)")
                continue
            }
            let snareHit = DrumSynthesizer.acousticHit(preset: sounds[1], velocity: 0.8, sampleRate: rate)
            let snare = AudioMetrics.pseudoLUFS(snareHit, sampleRate: rate)
            let snarePeak = max(1e-8, AudioMetrics.peak(snareHit))
            for preset in sounds {
                let hit = DrumSynthesizer.acousticHit(preset: preset, velocity: 0.8, sampleRate: rate)
                let delta = AudioMetrics.pseudoLUFS(hit, sampleRate: rate) - snare
                let peak = max(1e-8, AudioMetrics.peak(hit))
                let aligned = delta - 20 * log10(Double(peak / snarePeak))
                let band = band(for: preset)
                let line = "\(preset.filename) \(String(format: "%+.2f", delta)) pk \(String(format: "%.3f", peak)) al \(String(format: "%+.2f", aligned)) [\(band.lo), \(band.hi)]"
                print("LVL \(line)")
                if delta < band.lo || delta > band.hi {
                    misses.append(line)
                }
            }
            if sounds[2].articulations?.dropFirst().first?.recipe == .hatOpen {
                let hit = DrumSynthesizer.acousticHit(preset: sounds[2], velocity: 0.8, articulation: 1, sampleRate: rate)
                let delta = AudioMetrics.pseudoLUFS(hit, sampleRate: rate) - snare
                let line = "\(sounds[2].filename) open \(String(format: "%+.2f", delta)) [-9, -2]"
                print("LVL \(line)")
                if delta < -9 || delta > -2 { misses.append(line) }
            }
        }
        #expect(misses.isEmpty, "\(misses.joined(separator: " | "))")
    }

    /// Target interval widened by the TQ-1 tolerance.
    private func band(for preset: SoundPreset) -> (lo: Double, hi: Double) {
        let recipe = preset.articulations?.first?.recipe
        switch preset.resolvedVoice {
        case .kick:
            return (-2.5, 2.5)
        case .snare:
            return (-0.05, 0.05)
        case .closedHat, .openHat:
            if recipe == .shaker { return (-14, -6) }
            return (-11, -4)
        case .clap:
            return (-6, 1)
        case .tom:
            return (-5, 2)
        case .ride:
            if recipe == .cowbell || recipe == .tambourine { return (-8, 0) }
            return (-12, -5)
        case .crash:
            return (-7, 0)
        case .perc:
            switch recipe {
            case .shaker, .tambourine, .triangle, .wood, .guiro:
                return (-14, -6)
            default:
                return (-8, 0)
            }
        case .fx:
            return (-40, 40)
        }
    }
}
