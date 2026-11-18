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

    /// TQ-1 and the ghost/accent windows on the shipped layer bank.
    /// `VoiceEngine` applies the curve. `acousticHit` is not the signal under test.
    @Test func playedLayerBanksMatchTheSnareAndGhostWindow() {
        var misses: [String] = []
        var lines: [String] = []
        for kit in AcousticKits.kits() {
            let sounds = kit.sounds
            guard sounds.count == 8 else {
                misses.append("\(kit.name) slots \(sounds.count)")
                continue
            }
            var banks: [LayerBank] = []
            banks.reserveCapacity(sounds.count)
            for preset in sounds {
                banks.append(DrumSynthesizer.layerBank(for: preset, sampleRate: rate))
            }
            let snare = AudioMetrics.pseudoLUFS(
                played(banks[1], velocity: 0.8, articulation: 0),
                sampleRate: rate
            )
            for (index, preset) in sounds.enumerated() {
                let hit = played(banks[index], velocity: 0.8, articulation: 0)
                let delta = AudioMetrics.pseudoLUFS(hit, sampleRate: rate) - snare
                let recipe = preset.articulations?.first?.recipe?.rawValue ?? "none"
                let band = band(for: preset)
                let line = String(
                    format: "PLAY %@ %@ %@ %+.2f [%.1f, %.1f]",
                    preset.filename, preset.resolvedVoice.rawValue, recipe, delta, band.lo, band.hi
                )
                lines.append(line)
                print(line)
                if delta < band.lo || delta > band.hi { misses.append(line) }
            }
            if sounds[2].articulations?.dropFirst().first?.recipe == .hatOpen {
                let hit = played(banks[2], velocity: 0.8, articulation: 1)
                let delta = AudioMetrics.pseudoLUFS(hit, sampleRate: rate) - snare
                let line = String(format: "PLAYOPEN %@ %+.2f [-9.0, -2.0]", sounds[2].filename, delta)
                lines.append(line)
                print(line)
                if delta < -9 || delta > -2 { misses.append(line) }
            }
            for index in [0, 1, 2, 5, 6] {
                let preset = sounds[index]
                guard let window = ghostWindow(for: preset) else { continue }
                let ghostBuf = played(banks[index], velocity: 0.25, articulation: 0)
                let accentBuf = played(banks[index], velocity: 1, articulation: 0)
                // One shared lift. pseudo-LUFS gates at −70 dB, and a quiet ghost
                // after the post-cap scale falls through that gate. The lift is not
                // part of playback; both hits move by the same amount.
                let lift = Float(0.5 / max(AudioMetrics.peak(accentBuf), 1e-6))
                let ghost = AudioMetrics.pseudoLUFS(lifted(ghostBuf, by: lift), sampleRate: rate)
                let accent = AudioMetrics.pseudoLUFS(lifted(accentBuf, by: lift), sampleRate: rate)
                let delta = ghost - accent
                let curveDb = curveDb(preset, velocity: 0.25)
                let line = String(
                    format: "GHOST %@ %@ %+.2f curve %+.2f [%.0f, %.0f]",
                    preset.filename, preset.resolvedVoice.rawValue, delta, curveDb, window.lo, window.hi
                )
                lines.append(line)
                print(line)
                if delta < window.lo || delta > window.hi { misses.append(line) }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ad6-playback-metrics.txt")
        try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(misses.isEmpty, "\(misses.joined(separator: " | "))")
    }

    /// Ghost (v=0.25) minus accent (v=1), in dB. Nil for voices the criterion does not name.
    private func ghostWindow(for preset: SoundPreset) -> (lo: Double, hi: Double)? {
        switch preset.resolvedVoice {
        case .kick:
            return (-18, -12)
        case .snare:
            return (-26, -18)
        case .closedHat, .openHat:
            return (-20, -14)
        case .ride, .crash:
            return (-24, -16)
        default:
            return nil
        }
    }

    private func curveDb(_ preset: SoundPreset, velocity: Double) -> Double {
        let curve = preset.dynamics?.resolvedCurve ?? .db(range: 30, shape: 1)
        let gain = curve.gain(at: velocity)
        guard gain > 1e-8 else { return -160 }
        return 20 * log10(gain)
    }

    private func lifted(_ samples: [Float], by factor: Float) -> [Float] {
        if abs(factor - 1) < 1e-6 { return samples }
        return samples.map { $0 * factor }
    }

    /// Left channel of one hit. Center pan is in both measurements, so dB deltas stay put.
    private func played(_ bank: LayerBank, velocity: Float, articulation: Int) -> [Float] {
        let engine = VoiceEngine(sampleRate: rate)
        engine.swapLayers(track: 0, bank: bank)
        engine.trigger(
            track: 0, velocity: velocity, chokeGroup: -1, atSample: 0, articulation: articulation
        )
        let frames = Int(1.25 * rate)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        left.initialize(repeating: 0, count: frames)
        right.initialize(repeating: 0, count: frames)
        defer {
            left.deinitialize(count: frames)
            right.deinitialize(count: frames)
            left.deallocate()
            right.deallocate()
        }
        engine.renderBlock(frameCount: frames, left: left, right: right)
        return Array(UnsafeBufferPointer(start: left, count: frames))
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
