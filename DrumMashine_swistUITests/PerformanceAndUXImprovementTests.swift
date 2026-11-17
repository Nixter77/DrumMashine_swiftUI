import AVFoundation
import Foundation
import Observation
import Synchronization
import Testing
@testable import DrumMashine_swistUI

struct PerformanceAndUXImprovementTests {
    private static let testSampleRate: Double = 48_000

    private static func sineStereoBuffer(frequency: Double, amplitude: Float, frames: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: testSampleRate,
            channels: 2,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for index in 0..<frames {
            let phase = 2.0 * Double.pi * frequency * Double(index) / testSampleRate
            let sample = amplitude * Float(sin(phase))
            left[index] = sample
            right[index] = sample
        }
        return buffer
    }

    @Test func spectrumAnalyzerSettlesToExactZeroInSilence() async {
        let analyzer = SpectrumAnalyzer()
        let tap = analyzer.makeTapBlock()

        await Task.detached {
            let loud = Self.sineStereoBuffer(frequency: 1_000, amplitude: 0.8, frames: 1_024)
            let silence = Self.sineStereoBuffer(frequency: 1_000, amplitude: 0, frames: 1_024)
            let time = AVAudioTime(sampleTime: 0, atRate: Self.testSampleRate)

            tap(loud, time)
            for _ in 0..<90 {
                tap(silence, time)
            }
        }.value

        #expect(analyzer.copyFrame() == MeterFrame.silent)
    }

    @MainActor
    @Test func allBaseLibraryHiHatsHaveChokeGroupOne() {
        let hats = SoundLibraryManager.shared.availableSounds.filter { $0.category == .hihat }
        #expect(!hats.isEmpty)
        for hat in hats {
            #expect(hat.chokeGroup == 1, "\(hat.name) (\(hat.filename)) chokeGroup=\(String(describing: hat.chokeGroup))")
        }
    }

    @MainActor
    @Test func soundEditorRouterIsObservableAndTracksPadSelection() {
        let router = SoundEditorRouter.shared
        let previous = router.trackIndex
        defer { router.trackIndex = previous }

        let _: any Observable = router
        router.trackIndex = nil

        let observedChange = Mutex(false)
        withObservationTracking {
            _ = router.trackIndex
        } onChange: {
            observedChange.withLock { $0 = true }
        }

        router.trackIndex = 3
        #expect(observedChange.withLock { $0 })
        #expect(router.trackIndex == 3)

        router.trackIndex = nil
        #expect(router.trackIndex == nil)
    }

    @Test func oversampledKickAndCurvedADSRStayInsideLimits() {
        var preset = SoundPreset(
            id: UUID(),
            name: "Driven Kick",
            filename: "test_driven_kick",
            category: .kick
        )
        preset.voice = .kick
        preset.style = .classic808
        preset.attack = 0.01
        preset.decay = 0.2
        preset.sustain = 0.2
        preset.release = 0.1
        preset.synth = SynthParams(kick: SynthParams.Kick(drive: 4.5))

        let samples = DrumSynthesizer.samples(for: preset, sampleRate: Self.testSampleRate)
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.isFinite })
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak > 0.01 && peak <= 0.501, "peak \(peak)")
        #expect(samples.last == 0)
    }
}
