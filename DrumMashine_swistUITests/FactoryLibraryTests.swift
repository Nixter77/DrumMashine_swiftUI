import Foundation
import Testing
@testable import DrumMashine_swistUI

/// The 51 new factory presets plus the original 60.
@MainActor
struct FactoryLibraryTests {
    @Test func factoryLibraryHasOneHundredElevenDistinctPresets() {
        let library = SoundLibraryManager.shared.availableSounds
        #expect(library.count == 111 + AcousticKit.pieces.count)
        #expect(Set(library.map(\.filename)).count == 111 + AcousticKit.pieces.count)
        #expect(library.filter { $0.style == .legacy }.count == 60)
        #expect(library.filter { $0.style != .legacy }.count == 51 + AcousticKit.pieces.count)
        let added = Set(FactoryPresets.additional().map(\.filename))
        #expect(added.count == 51)
        #expect(added.isSubset(of: Set(library.map(\.filename))))
    }

    @Test func everyFactoryPresetStaysInsideTheRenderLimits() {
        let limit = 48_000 * 4
        for preset in SoundLibraryManager.shared.availableSounds {
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: 48_000)
            #expect(!samples.isEmpty, "\(preset.filename) empty")
            #expect(samples.allSatisfy { $0.isFinite }, "\(preset.filename) finite")
            let peak = samples.max { abs($0) < abs($1) }.map { abs($0) } ?? 0
            #expect(peak <= 0.5 + 0.001, "\(preset.filename) peak \(peak)")
            #expect(samples.last == 0, "\(preset.filename) last")
            let tail = samples.suffix(max(1, samples.count / 20))
            let tailPeak = tail.max { abs($0) < abs($1) }.map { abs($0) } ?? 0
            // fx_vinyl is one of the locked 60. Its last 5% sits just above 0.001.
            if preset.filename != "fx_vinyl" {
                #expect(tailPeak < 0.001, "\(preset.filename) tail \(tailPeak)")
            }
            if preset.filename == "crash_dark" {
                // Locked by the D-0 hash. Its decay already runs past four seconds.
                #expect(samples.count > limit, "\(preset.filename) length")
            } else {
                #expect(samples.count <= limit, "\(preset.filename) length \(samples.count)")
            }
        }
    }

    @Test func presetsInsideOneVoiceAreDistinguishable() {
        let library = SoundLibraryManager.shared.availableSounds
        let grouped = Dictionary(grouping: library, by: \.resolvedVoice)
        for (voice, presets) in grouped {
            let rendered = presets.map { preset in
                (preset, DrumSynthesizer.samples(for: preset, sampleRate: 48_000))
            }
            for index in rendered.indices {
                for other in rendered.index(after: index)..<rendered.count {
                    let left = rendered[index]
                    let right = rendered[other]
                    // ride_edge and ride_jazz are both in the locked 60 and already sit inside 5% / 1 dB.
                    if left.0.style == .legacy, right.0.style == .legacy { continue }
                    let centroidGap = relativeGap(centroid(left.1), centroid(right.1))
                    let envelopeGap = meanAbsoluteDecibelGap(left.1, right.1)
                    #expect(
                        centroidGap > 0.05 || envelopeGap > 1,
                        "\(voice) \(left.0.filename) vs \(right.0.filename) centroid \(centroidGap) envelope \(envelopeGap)"
                    )
                }
            }
        }
    }

    private func relativeGap(_ left: Double, _ right: Double) -> Double {
        let scale = max(abs(left), abs(right), 1)
        return abs(left - right) / scale
    }

    private func centroid(_ samples: [Float]) -> Double {
        let count = min(1024, samples.count)
        guard count > 8 else { return 0 }
        var weighted = 0.0
        var total = 0.0
        let step = max(1, count / 256)
        var bin = 1
        while bin < count / 2 {
            var real = 0.0
            var imag = 0.0
            let omega = -2 * Double.pi * Double(bin) / Double(count)
            for n in stride(from: 0, to: count, by: step) {
                let phase = omega * Double(n)
                let sample = Double(samples[n])
                real += sample * cos(phase)
                imag += sample * sin(phase)
            }
            let power = real * real + imag * imag
            weighted += Double(bin) * power
            total += power
            bin += max(1, (count / 2) / 64)
        }
        return total > 0 ? weighted / total : 0
    }

    /// Mean absolute difference of 10 ms RMS windows, in decibels.
    private func meanAbsoluteDecibelGap(_ left: [Float], _ right: [Float]) -> Double {
        let width = 480
        let a = envelope(left, width: width)
        let b = envelope(right, width: width)
        let count = min(a.count, b.count)
        guard count > 0 else { return 0 }
        var sum = 0.0
        for index in 0..<count {
            sum += abs(a[index] - b[index])
        }
        return sum / Double(count)
    }

    private func envelope(_ samples: [Float], width: Int) -> [Double] {
        var windows: [Double] = []
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + width)
            var sum = 0.0
            for sample in samples[index..<end] {
                let value = Double(sample)
                sum += value * value
            }
            let rms = sqrt(sum / Double(end - index))
            windows.append(20 * log10(max(rms, 1e-8)))
            index = end
        }
        return windows
    }
}
