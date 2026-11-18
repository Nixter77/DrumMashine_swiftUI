import Accelerate
import CryptoKit
import Foundation
@testable import DrumMashine_swistUI

/// Measurement helpers for the acoustic-dynamics work. Not used by the app.
enum AudioMetrics {
    static func peak(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var maxValue: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_maxmgv(base, 1, &maxValue, vDSP_Length(buffer.count))
        }
        return maxValue
    }

    static func peakDb(_ samples: [Float]) -> Double {
        let value = peak(samples)
        guard value > 0 else { return -160 }
        return 20 * log10(Double(value))
    }

    /// RMS of the whole buffer when `window` is 0, otherwise the loudest window.
    static func rms(_ samples: [Float], window: Int = 0) -> Float {
        guard !samples.isEmpty else { return 0 }
        if window <= 0 || window >= samples.count {
            return rmsSlice(samples, start: 0, count: samples.count)
        }
        var best: Float = 0
        var offset = 0
        while offset < samples.count {
            let count = min(window, samples.count - offset)
            best = max(best, rmsSlice(samples, start: offset, count: count))
            if count < window { break }
            offset += window
        }
        return best
    }

    static func rmsDb(_ samples: [Float], window: Int = 0) -> Double {
        let value = rms(samples, window: window)
        guard value > 0 else { return -160 }
        return 20 * log10(Double(value))
    }

    /// Magnitude centroid of a 2048-point FFT. The default window is the first 80 ms.
    static func spectralCentroid(
        _ samples: [Float],
        sampleRate: Double,
        windowSeconds: Double = 0.080
    ) -> Double {
        let fftSize = 2048
        guard samples.count >= 32, sampleRate > 0 else { return 0 }
        let windowCount = min(samples.count, max(32, Int(windowSeconds * sampleRate)))
        var windowed = [Float](repeating: 0, count: fftSize)
        let copyCount = min(fftSize, windowCount)
        for index in 0..<copyCount {
            let phase = Double(index) / Double(max(copyCount - 1, 1))
            let hann = 0.5 * (1 - cos(2 * Double.pi * phase))
            windowed[index] = samples[index] * Float(hann)
        }
        guard let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                magnitudes.withUnsafeMutableBufferPointer { magnitudePointer in
                    guard let realBase = realPointer.baseAddress,
                          let imagBase = imagPointer.baseAddress,
                          let magnitudeBase = magnitudePointer.baseAddress else { return }
                    windowed.withUnsafeBytes { raw in
                        guard let complexBase = raw.bindMemory(to: DSPComplex.self).baseAddress else { return }
                        var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                        vDSP_ctoz(complexBase, 2, &split, 1, vDSP_Length(fftSize / 2))
                        vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, magnitudeBase, 1, vDSP_Length(fftSize / 2))
                    }
                }
            }
        }
        let binHz = sampleRate / Double(fftSize)
        var weighted = 0.0
        var total = 0.0
        // Bin 0 is DC+Nyquist packed by zrip. Skip it so a pure tone is not pulled down.
        for bin in 1..<(fftSize / 2) {
            let power = Double(magnitudes[bin])
            weighted += power * (Double(bin) * binHz)
            total += power
        }
        guard total > 0 else { return 0 }
        return weighted / total
    }

    /// Sum of FFT power between `lowHz` and `highHz` over `windowSeconds`.
    static func bandEnergy(
        _ samples: [Float],
        sampleRate: Double,
        lowHz: Double,
        highHz: Double,
        windowSeconds: Double = 0.080
    ) -> Double {
        let fftSize = 2048
        guard samples.count >= 32, sampleRate > 0, highHz > lowHz else { return 0 }
        let windowCount = min(samples.count, max(32, Int(windowSeconds * sampleRate)))
        var windowed = [Float](repeating: 0, count: fftSize)
        let copyCount = min(fftSize, windowCount)
        for index in 0..<copyCount { windowed[index] = samples[index] }
        guard let setup = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2)) else { return 0 }
        defer { vDSP_destroy_fftsetup(setup) }
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                magnitudes.withUnsafeMutableBufferPointer { magnitudePointer in
                    guard let realBase = realPointer.baseAddress,
                          let imagBase = imagPointer.baseAddress,
                          let magnitudeBase = magnitudePointer.baseAddress else { return }
                    windowed.withUnsafeBytes { raw in
                        guard let complexBase = raw.bindMemory(to: DSPComplex.self).baseAddress else { return }
                        var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                        vDSP_ctoz(complexBase, 2, &split, 1, vDSP_Length(fftSize / 2))
                        vDSP_fft_zrip(setup, &split, 1, 11, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, magnitudeBase, 1, vDSP_Length(fftSize / 2))
                    }
                }
            }
        }
        let binHz = sampleRate / Double(fftSize)
        var energy = 0.0
        for bin in 1..<(fftSize / 2) {
            let hz = Double(bin) * binHz
            if hz >= lowHz, hz < highHz { energy += Double(magnitudes[bin]) }
        }
        return energy
    }

    /// Time from 10% to 90% of the peak envelope, in milliseconds.
    static func attackTimeMs(_ samples: [Float], sampleRate: Double) -> Double {
        guard samples.count > 8, sampleRate > 0 else { return 0 }
        let hop = max(1, Int(0.001 * sampleRate))
        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / hop)
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + hop)
            var local: Float = 0
            for cursor in index..<end { local = max(local, abs(samples[cursor])) }
            envelope.append(local)
            index = end
        }
        let top = envelope.max() ?? 0
        guard top > 1e-6 else { return 0 }
        let low = top * 0.10
        let high = top * 0.90
        guard let start = envelope.firstIndex(where: { $0 >= low }),
              let end = envelope.firstIndex(where: { $0 >= high }),
              end >= start else { return 0 }
        return Double(end - start) * Double(hop) / sampleRate * 1000
    }

    /// Rough T60 from the peak-envelope slope after the peak, in seconds.
    static func decayT60(_ samples: [Float], sampleRate: Double) -> Double {
        guard samples.count > 16, sampleRate > 0 else { return 0 }
        let hop = max(1, Int(0.005 * sampleRate))
        var envelope: [Float] = []
        var index = 0
        while index < samples.count {
            let end = min(samples.count, index + hop)
            var local: Float = 0
            for cursor in index..<end { local = max(local, abs(samples[cursor])) }
            envelope.append(local)
            index = end
        }
        guard let peakIndex = envelope.indices.max(by: { envelope[$0] < envelope[$1] }) else { return 0 }
        let peak = envelope[peakIndex]
        guard peak > 1e-5 else { return 0 }
        let floor = peak * 0.001
        var last = peakIndex
        for cursor in peakIndex..<envelope.count {
            last = cursor
            if envelope[cursor] <= floor { break }
        }
        let drop = max(1e-8, Double(envelope[last]) / Double(peak))
        let seconds = Double(last - peakIndex) * Double(hop) / sampleRate
        let db = -20 * log10(drop)
        guard db > 0.1 else { return seconds }
        return seconds * (60 / db)
    }

    /// Approximate integrated loudness: 60 Hz highpass, +4 dB shelf at 1.5 kHz,
    /// RMS of 400 ms windows, gate at −70 dB.
    static func pseudoLUFS(_ samples: [Float], sampleRate: Double) -> Double {
        guard !samples.isEmpty, sampleRate > 0 else { return -160 }
        var shaped = samples
        var highpass = BiquadMetric.highpass(cutoff: 60, sampleRate: sampleRate)
        var shelf = BiquadMetric.highShelf(cutoff: 1_500, gainDb: 4, sampleRate: sampleRate)
        for index in shaped.indices {
            var value = highpass.process(Double(shaped[index]))
            value = shelf.process(value)
            shaped[index] = Float(value)
        }
        let window = max(1, Int(0.400 * sampleRate))
        var blocks: [Double] = []
        var offset = 0
        while offset < shaped.count {
            let count = min(window, shaped.count - offset)
            let power = Double(rmsSlice(shaped, start: offset, count: count))
            let db = power > 0 ? 20 * log10(power) : -160
            if db >= -70 { blocks.append(db) }
            if count < window { break }
            offset += window
        }
        guard !blocks.isEmpty else { return -160 }
        let meanPower = blocks.reduce(0.0) { $0 + pow(10, $1 / 10) } / Double(blocks.count)
        guard meanPower > 0 else { return -160 }
        return 10 * log10(meanPower)
    }

    /// Offline mix of one kit through `VoiceEngine`, left channel, no AVAudioEngine graph effects.
    static func renderKitGroove(
        kit: DrumKit,
        pattern: DrumPattern,
        bars: Int = 1,
        sampleRate: Double = 48_000
    ) throws -> [Float] {
        let engine = VoiceEngine(sampleRate: sampleRate)
        let count = min(8, min(kit.sounds.count, pattern.tracks.count))
        for index in 0..<count {
            let samples = DrumSynthesizer.samples(for: kit.sounds[index], sampleRate: sampleRate)
            engine.swapSample(track: index, samples: samples.isEmpty ? [0] : samples)
        }
        let steps = max(1, pattern.resolvedStepCount.rawValue)
        let samplesPerStep = sampleRate * 60.0 / max(pattern.bpm, 1) / 4.0
        let totalSteps = steps * max(1, bars)
        let frames = Int(Double(totalSteps) * samplesPerStep) + Int(sampleRate)
        var scheduled = false
        return try renderOffline(frames: frames, chunkFrames: 4096, sampleRate: sampleRate, beforeChunk: {
            guard !scheduled else { return }
            scheduled = true
            for step in 0..<totalSteps {
                let patternStep = step % steps
                let at = Int64((Double(step) * samplesPerStep).rounded())
                for track in 0..<count {
                    let row = pattern.tracks[track]
                    guard patternStep < row.steps.count, row.steps[patternStep].isActive else { continue }
                    engine.trigger(
                        track: track,
                        velocity: row.steps[patternStep].velocity,
                        chokeGroup: kit.sounds[track].chokeGroup ?? -1,
                        atSample: at,
                        lane: .sequencer
                    )
                }
            }
        }) { _ in engine.sourceNode }
    }

    /// 16-bit mono WAV. `url` nil writes under the temporary directory.
    @discardableResult
    static func writeWav(_ samples: [Float], to url: URL? = nil, sampleRate: Double = 48_000) throws -> URL {
        let destination = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("drum-metric-\(UUID().uuidString).wav")
        let rate = UInt32(max(1, sampleRate.rounded()))
        let dataBytes = samples.count * 2
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // RIFF
        header.append(uint32(UInt32(36 + dataBytes)))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // WAVE
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // fmt
        header.append(uint32(16))
        header.append(uint16(1)) // PCM
        header.append(uint16(1)) // mono
        header.append(uint32(rate))
        header.append(uint32(rate * 2))
        header.append(uint16(2))
        header.append(uint16(16))
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // data
        header.append(uint32(UInt32(dataBytes)))
        var body = Data()
        body.reserveCapacity(dataBytes)
        for sample in samples {
            let clipped = max(-1, min(1, sample))
            var value = Int16(clipped * 32_767).littleEndian
            withUnsafeBytes(of: &value) { body.append(contentsOf: $0) }
        }
        header.append(body)
        try header.write(to: destination)
        return destination
    }

    private static func uint16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 2)
    }

    private static func uint32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 4)
    }

    static func sha256Hex(_ samples: [Float]) -> String {
        let digest = SHA256.hash(data: Data(samples.withUnsafeBytes { Data($0) }))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func rmsSlice(_ samples: [Float], start: Int, count: Int) -> Float {
        guard count > 0 else { return 0 }
        var sum: Float = 0
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_svesq(base.advanced(by: start), 1, &sum, vDSP_Length(count))
        }
        return sqrt(sum / Float(count))
    }
}

/// Tiny biquads so the test helper does not reach into the synthesizer's private filters.
private struct BiquadMetric {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func highpass(cutoff: Double, sampleRate: Double) -> BiquadMetric {
        let w = 2 * Double.pi * cutoff / sampleRate
        let cosw = cos(w)
        let sinw = sin(w)
        let alpha = sinw / (2 * 0.707)
        let b0 = (1 + cosw) / 2
        let b1 = -(1 + cosw)
        let b2 = (1 + cosw) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosw
        let a2 = 1 - alpha
        return BiquadMetric(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highShelf(cutoff: Double, gainDb: Double, sampleRate: Double) -> BiquadMetric {
        let a = pow(10, gainDb / 40)
        let w = 2 * Double.pi * cutoff / sampleRate
        let cosw = cos(w)
        let sinw = sin(w)
        let alpha = sinw / 2 * sqrt((a + 1 / a) * (1 / 0.707 - 1) + 2)
        let b0 = a * ((a + 1) + (a - 1) * cosw + 2 * sqrt(a) * alpha)
        let b1 = -2 * a * ((a - 1) + (a + 1) * cosw)
        let b2 = a * ((a + 1) + (a - 1) * cosw - 2 * sqrt(a) * alpha)
        let a0 = (a + 1) - (a - 1) * cosw + 2 * sqrt(a) * alpha
        let a1 = 2 * ((a - 1) - (a + 1) * cosw)
        let a2 = (a + 1) - (a - 1) * cosw - 2 * sqrt(a) * alpha
        return BiquadMetric(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}
