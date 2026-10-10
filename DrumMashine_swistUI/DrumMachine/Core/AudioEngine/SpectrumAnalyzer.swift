import Accelerate
import AVFoundation
import Foundation
import Synchronization

/// One published reading. The arrays stay at a fixed count so the audio thread can fill them in place.
nonisolated struct MeterFrame: Sendable, Equatable {
    var bands: [Float]
    var waveform: [Float]
    var rmsL: Float
    var rmsR: Float
    var peakL: Float
    var peakR: Float

    static let silent = MeterFrame(
        bands: Array(repeating: 0, count: SpectrumAnalyzer.bandCount),
        waveform: Array(repeating: 0, count: SpectrumAnalyzer.waveformPoints),
        rmsL: 0,
        rmsR: 0,
        peakL: 0,
        peakR: 0
    )
}

/// FFT of the master mix, plus a short decimated waveform.
///
/// The tap calls `ingest` on the audio thread. Working buffers are allocated once
/// in `init` and only that thread writes them. The latest reading sits in `snapshot`.
/// `@unchecked Sendable`: those buffers never leave the tap, and the snapshot is the
/// only state shared with the main actor.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    static let fftSize = 1024
    static let bandCount = 32
    static let waveformPoints = 60

    private let snapshot = Mutex(MeterFrame.silent)
    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length

    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]
    private var smoothedBands: [Float]
    private var waveform: [Float]
    private var smoothL: Float = 0
    private var smoothR: Float = 0

    init() {
        log2n = vDSP_Length(log2(Double(Self.fftSize)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(FFT_RADIX2))
        window = [Float](repeating: 0, count: Self.fftSize)
        windowed = [Float](repeating: 0, count: Self.fftSize)
        real = [Float](repeating: 0, count: Self.fftSize)
        imag = [Float](repeating: 0, count: Self.fftSize)
        magnitudes = [Float](repeating: 0, count: Self.fftSize / 2)
        smoothedBands = [Float](repeating: 0, count: Self.bandCount)
        waveform = [Float](repeating: 0, count: Self.waveformPoints)
        window.withUnsafeMutableBufferPointer { pointer in
            guard let base = pointer.baseAddress else { return }
            vDSP_hann_window(base, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        }
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    /// Built here, not in a MainActor method, so the tap is not isolated to the main actor.
    nonisolated func makeTapBlock() -> AVAudioNodeTapBlock {
        { [weak self] buffer, _ in
            self?.ingest(buffer)
        }
    }

    /// Copies the latest reading. The destination arrays are allocated by the caller, not the tap.
    func copyFrame() -> MeterFrame {
        var bands = [Float](repeating: 0, count: Self.bandCount)
        var wave = [Float](repeating: 0, count: Self.waveformPoints)
        var rmsL: Float = 0
        var rmsR: Float = 0
        var peakL: Float = 0
        var peakR: Float = 0
        snapshot.withLock { current in
            for index in bands.indices {
                bands[index] = current.bands[index]
            }
            for index in wave.indices {
                wave[index] = current.waveform[index]
            }
            rmsL = current.rmsL
            rmsR = current.rmsR
            peakL = current.peakL
            peakR = current.peakR
        }
        return MeterFrame(
            bands: bands,
            waveform: wave,
            rmsL: rmsL,
            rmsR: rmsR,
            peakL: peakL,
            peakR: peakR
        )
    }

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let left = channels[0]
        let rmsL = rms(left, count: frameLength)
        let peakL = peak(left, count: frameLength)
        var rmsR = rmsL
        var peakR = peakL
        var right = left
        if buffer.format.channelCount > 1 {
            right = channels[1]
            rmsR = rms(right, count: frameLength)
            peakR = peak(right, count: frameLength)
        }

        smoothL = smoothL * 0.7 + rmsL * 0.3
        smoothR = smoothR * 0.7 + rmsR * 0.3

        if frameLength >= Self.fftSize {
            analyzeSpectrum(left)
        } else {
            for index in smoothedBands.indices {
                smoothedBands[index] *= 0.82
            }
        }
        pushEnvelope(louderChannel(left, right, count: frameLength), count: frameLength)
        publish(peakL: peakL, peakR: peakR)
    }

    private func rms(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        var meanSquare: Float = 0
        vDSP_measqv(samples, 1, &meanSquare, vDSP_Length(count))
        return sqrt(meanSquare)
    }

    private func peak(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        var magnitude: Float = 0
        vDSP_maxmgv(samples, 1, &magnitude, vDSP_Length(count))
        return magnitude
    }

    /// Signed peak of the louder channel, so the trace keeps polarity.
    private func louderChannel(
        _ left: UnsafePointer<Float>,
        _ right: UnsafePointer<Float>,
        count: Int
    ) -> UnsafePointer<Float> {
        abs(peak(left, count: count)) >= abs(peak(right, count: count)) ? left : right
    }

    private func analyzeSpectrum(_ samples: UnsafePointer<Float>) {
        guard let fftSetup else { return }
        window.withUnsafeBufferPointer { windowPointer in
            windowed.withUnsafeMutableBufferPointer { windowedPointer in
                guard let windowBase = windowPointer.baseAddress,
                      let windowedBase = windowedPointer.baseAddress else { return }
                vDSP_vmul(samples, 1, windowBase, 1, windowedBase, 1, vDSP_Length(Self.fftSize))
            }
        }

        windowed.withUnsafeBytes { raw in
            real.withUnsafeMutableBufferPointer { realPointer in
                imag.withUnsafeMutableBufferPointer { imagPointer in
                    guard let realBase = realPointer.baseAddress,
                          let imagBase = imagPointer.baseAddress,
                          let complexBase = raw.bindMemory(to: DSPComplex.self).baseAddress else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    vDSP_ctoz(complexBase, 2, &split, 1, vDSP_Length(Self.fftSize / 2))
                }
            }
        }

        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                magnitudes.withUnsafeMutableBufferPointer { magnitudePointer in
                    guard let realBase = realPointer.baseAddress,
                          let imagBase = imagPointer.baseAddress,
                          let magnitudeBase = magnitudePointer.baseAddress else { return }
                    var split = DSPSplitComplex(realp: realBase, imagp: imagBase)
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, magnitudeBase, 1, vDSP_Length(Self.fftSize / 2))
                }
            }
        }

        let binCount = Self.fftSize / 2
        let binsPerBand = binCount / Self.bandCount
        for band in 0..<Self.bandCount {
            let start = band * binsPerBand
            let end = min(start + binsPerBand, binCount)
            var maxMagnitude: Float = 0
            for bin in start..<end {
                maxMagnitude = max(maxMagnitude, magnitudes[bin])
            }
            let decibels = 10 * log10(maxMagnitude + 1e-10)
            let target = max(0, min(1, (decibels + 80) / 80))
            smoothedBands[band] = max(target, smoothedBands[band] * 0.82)
        }
    }

    private func pushEnvelope(_ samples: UnsafePointer<Float>, count: Int) {
        var extreme: Float = 0
        for index in 0..<count {
            let sample = samples[index]
            if abs(sample) > abs(extreme) {
                extreme = sample
            }
        }
        if waveform.count > 1 {
            for index in 1..<waveform.count {
                waveform[index - 1] = waveform[index]
            }
        }
        waveform[waveform.count - 1] = extreme
    }

    private func publish(peakL: Float, peakR: Float) {
        snapshot.withLock { frame in
            for index in smoothedBands.indices {
                frame.bands[index] = smoothedBands[index]
            }
            for index in waveform.indices {
                frame.waveform[index] = waveform[index]
            }
            frame.rmsL = smoothL
            frame.rmsR = smoothR
            frame.peakL = peakL
            frame.peakR = peakR
        }
    }
}
