import Foundation
import Testing
@testable import DrumMashine_swistUI

struct AudioMetricsTests {
    @Test func sinePeakOfOneHalfIsMinusSixDecibels() {
        let count = 48_000
        let rate = Double(count)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = Float(0.5 * sin(2 * Double.pi * 1_000 * Double(index) / rate))
        }
        let db = AudioMetrics.peakDb(samples)
        #expect(abs(db - (-6.0206)) < 0.01)
    }

    @Test func sineCentroidStaysNearOneKilohertz() {
        let rate = 48_000.0
        let samples = (0..<8_192).map { index -> Float in
            Float(sin(2 * Double.pi * 1_000 * Double(index) / rate))
        }
        let centroid = AudioMetrics.spectralCentroid(samples, sampleRate: rate)
        #expect(abs(centroid - 1_000) / 1_000 < 0.05, "centroid \(centroid)")
    }

    @Test func noiseIsFiniteAndLouderThanSilence() {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        let samples = (0..<4_096).map { _ -> Float in
            state = state &* 6364136223846793005 &+ 1
            return Float(Int64(bitPattern: state) % 2000) / 2000
        }
        #expect(AudioMetrics.peak(samples) > 0.1)
        #expect(AudioMetrics.rms(samples, window: 0) > 0.05)
        #expect(AudioMetrics.pseudoLUFS(samples, sampleRate: 48_000).isFinite)
        #expect(AudioMetrics.attackTimeMs(samples, sampleRate: 48_000).isFinite)
        #expect(AudioMetrics.decayT60(samples, sampleRate: 48_000).isFinite)
    }

    @Test @MainActor func renderKitGrooveProducesAFiniteMix() throws {
        let kit = FactoryKits.all().first { $0.name == "808" }!
        let pattern = FactoryPatterns.makePattern(FactoryPatterns.all()[0])
        let mix = try AudioMetrics.renderKitGroove(kit: kit, pattern: pattern, bars: 1)
        #expect(mix.count > 1_000)
        var finite = true
        for sample in mix where !sample.isFinite { finite = false }
        #expect(finite)
        #expect(AudioMetrics.peak(mix) > 0)
        let url = try AudioMetrics.writeWav(mix, sampleRate: 48_000)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }
}
