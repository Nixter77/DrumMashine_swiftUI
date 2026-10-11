//
//  DrumMashine_swistUITests.swift
//  DrumMashine_swistUITests
//
//  Created by Nikolay Nikolayenko on 18/02/2026.
//

import AVFoundation
import Testing
import XCTest
@testable import DrumMashine_swistUI

/// Captured when the test bundle loads, before any test writes.
private let standardPatternsHashAtLaunch = StandardDefaultsProbe.patternSHA256()

/// XCTest does not retain observers. This instance lives for the process.
private let standardPatternsGuard: StandardPatternsGuard = {
    let observer = StandardPatternsGuard()
    XCTestObservationCenter.shared.addTestObserver(observer)
    return observer
}()

final class StandardPatternsGuard: NSObject, XCTestObservation {
    func testBundleDidFinish(_ testBundle: Bundle) {
        XCTAssertEqual(
            StandardDefaultsProbe.patternSHA256(),
            standardPatternsHashAtLaunch,
            "The real pattern key changed during tests"
        )
    }
}

/// Offline bench rate. `analyze` and `onsets` measure time against this clock.
private let benchSampleRate: Double = 48_000

/// Peak, tail peak (last 5 ms), and whether any sample is NaN or Inf.
func analyze(_ s: [Float]) -> (peak: Float, tailPeak: Float, hasNaN: Bool) {
    let tailCount = min(s.count, Int(0.005 * benchSampleRate))
    let tailStart = s.count - tailCount
    var peak: Float = 0
    var tailPeak: Float = 0
    var hasNaN = false
    for (index, sample) in s.enumerated() {
        if !sample.isFinite {
            hasNaN = true
            continue
        }
        let magnitude = abs(sample)
        if magnitude > peak { peak = magnitude }
        if index >= tailStart, magnitude > tailPeak { tailPeak = magnitude }
    }
    return (peak, tailPeak, hasNaN)
}

/// Sample indices where the signal crosses `threshold` after at least 2 ms of silence.
/// The buffer start counts as silence, so a hit on sample 0 is an onset.
func onsets(_ s: [Float], threshold: Float) -> [Int] {
    let minSilence = Int(0.002 * benchSampleRate)
    var hits: [Int] = []
    var silence = minSilence
    var armed = true
    for index in s.indices {
        if abs(s[index]) > threshold {
            if armed {
                hits.append(index)
                armed = false
            }
            silence = 0
        } else {
            silence += 1
            if silence >= minSilence {
                armed = true
            }
        }
    }
    return hits
}

enum OfflineRenderError: Error {
    case format
    case buffer
    case stalled
    case status(AVAudioEngineManualRenderingStatus)
}

/// Renders `frames` of the engine in offline mode and returns the left channel.
func renderOffline(
    frames: Int,
    chunkFrames: Int = 4096,
    sampleRate: Double = benchSampleRate,
    beforeChunk: (() -> Void)? = nil,
    source: (AVAudioFormat) -> AVAudioNode
) throws -> [Float] {
    let engine = AVAudioEngine()
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 2,
        interleaved: false
    ) else {
        throw OfflineRenderError.format
    }
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    let node = source(format)
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    try engine.start()
    defer { engine.stop() }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else {
        throw OfflineRenderError.buffer
    }

    var left: [Float] = []
    left.reserveCapacity(frames)
    var remaining = frames
    while remaining > 0 {
        beforeChunk?()
        let chunk = AVAudioFrameCount(min(remaining, chunkFrames))
        let status = try engine.renderOffline(chunk, to: buffer)
        guard status == .success else { throw OfflineRenderError.status(status) }
        let count = Int(buffer.frameLength)
        if count == 0 { throw OfflineRenderError.stalled }
        if let channel = buffer.floatChannelData?[0] {
            left.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        }
        remaining -= count
    }
    return left
}

func renderVoices(frames: Int, prepare: (VoiceEngine) -> Void) throws -> [Float] {
    let engine = VoiceEngine(sampleRate: benchSampleRate)
    prepare(engine)
    return try renderOffline(frames: frames) { _ in engine.sourceNode }
}

func kickPattern(bpm: Double, stepCount: Int = 16, swing: Double = 0) -> PatternSnapshot {
    let active = (0..<stepCount).map { _ in StepSnapshot(isActive: true, velocity: 1, probability: 1) }
    let silent = (0..<stepCount).map { _ in StepSnapshot(isActive: false, velocity: 1, probability: 1) }
    var tracks = (0..<8).map { _ in
        TrackSnapshot(steps: silent, isMuted: false, isSolo: false, volume: 1, pan: 0, chokeGroup: -1)
    }
    tracks[0].steps = active
    return PatternSnapshot(tracks: tracks, stepCount: stepCount, bpm: bpm, swing: swing, humanize: 0)
}

func armedScheduler(bpm: Double, swing: Double = 0, stepCount: Int = 16) -> (VoiceEngine, SequencerScheduler) {
    let engine = VoiceEngine(sampleRate: benchSampleRate)
    var click = [Float](repeating: 0, count: 64)
    click[0] = 1
    engine.swapSample(track: 0, samples: click)
    let scheduler = SequencerScheduler(voiceEngine: engine, sampleRate: benchSampleRate)
    scheduler.replace(kickPattern(bpm: bpm, stepCount: stepCount, swing: swing))
    scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)
    return (engine, scheduler)
}

func drive(engine: VoiceEngine, scheduler: SequencerScheduler, frames: Int) throws -> [Float] {
    try renderOffline(frames: frames, chunkFrames: 512, beforeChunk: {
        scheduler.scheduleDue(now: engine.renderedFrames)
    }) { _ in engine.sourceNode }
}

func densePattern() -> PatternSnapshot {
    let steps = (0..<16).map { _ in StepSnapshot(isActive: true, velocity: 1, probability: 1) }
    let tracks = (0..<8).map { _ in
        TrackSnapshot(steps: steps, isMuted: false, isSolo: false, volume: 1, pan: 0, chokeGroup: -1)
    }
    return PatternSnapshot(tracks: tracks, stepCount: 16, bpm: 120, swing: 0, humanize: 0)
}

func renderLimitedPattern(frames: Int) throws -> [Float] {
    let engine = AVAudioEngine()
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: benchSampleRate,
        channels: 2,
        interleaved: false
    ) else { throw OfflineRenderError.format }
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    let voices = VoiceEngine(sampleRate: benchSampleRate)
    let hit = [Float](repeating: 0.5, count: 8_000)
    for track in 0..<8 {
        voices.swapSample(track: track, samples: hit)
    }
    let scheduler = SequencerScheduler(voiceEngine: voices, sampleRate: benchSampleRate)
    scheduler.replace(densePattern())
    scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)

    let reverb = AVAudioUnitReverb()
    reverb.loadFactoryPreset(.mediumHall)
    reverb.wetDryMix = 40
    let delay = AVAudioUnitDelay()
    delay.wetDryMix = 30
    delay.delayTime = 0.25
    delay.feedback = 40
    let limiter = MasterLimiter.makeNode()
    MasterLimiter.configure(limiter)

    engine.attach(voices.sourceNode)
    engine.attach(reverb)
    engine.attach(delay)
    engine.attach(limiter)
    engine.connect(voices.sourceNode, to: reverb, format: format)
    engine.connect(reverb, to: delay, format: format)
    engine.connect(delay, to: limiter, format: format)
    engine.connect(limiter, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = MasterLimiter.ceilingGain
    try engine.start()
    defer { engine.stop() }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else {
        throw OfflineRenderError.buffer
    }
    var left: [Float] = []
    left.reserveCapacity(frames)
    var remaining = frames
    while remaining > 0 {
        scheduler.scheduleDue(now: voices.renderedFrames)
        let chunk = AVAudioFrameCount(min(remaining, 512))
        let status = try engine.renderOffline(chunk, to: buffer)
        guard status == .success else { throw OfflineRenderError.status(status) }
        let count = Int(buffer.frameLength)
        if count == 0 { throw OfflineRenderError.stalled }
        if let channel = buffer.floatChannelData?[0] {
            left.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        }
        remaining -= count
    }
    return left
}

func expectOnsets(_ samples: [Float], match expected: [Int]) {
    let hits = onsets(samples, threshold: 0.2)
    #expect(hits.count == expected.count, "got \(hits.count) onsets, want \(expected.count)")
    if hits.count != expected.count {
        let preview = hits.prefix(8).map(String.init).joined(separator: ",")
        #expect(Bool(false), "first onsets \(preview)")
    }
    for (hit, want) in zip(hits, expected) {
        #expect(abs(hit - want) <= 1, "onset \(hit) wanted \(want)")
    }
}

func rms(_ samples: [Float], from start: Int, to end: Int) -> Float {
    guard end > start else { return 0 }
    var sum: Float = 0
    for index in start..<min(end, samples.count) {
        let sample = samples[index]
        sum += sample * sample
    }
    return sqrt(sum / Float(end - start))
}

/// Voices -> distortion -> delay -> reverb -> limiter, one hit on track 0 at frame 0.
func renderEffectChain(
    frames: Int,
    voice: [Float],
    configure: (AVAudioUnitDistortion, AVAudioUnitDelay, AVAudioUnitReverb) -> Void
) throws -> [Float] {
    let engine = AVAudioEngine()
    guard let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: benchSampleRate,
        channels: 2,
        interleaved: false
    ) else { throw OfflineRenderError.format }
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    let voices = VoiceEngine(sampleRate: benchSampleRate)
    voices.swapSample(track: 0, samples: voice)
    voices.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0)

    let distortion = AVAudioUnitDistortion()
    distortion.loadFactoryPreset(.multiDistortedCubed)
    distortion.bypass = true
    let delay = AVAudioUnitDelay()
    delay.bypass = true
    delay.delayTime = 0.25
    delay.feedback = 0
    delay.wetDryMix = 0
    let reverb = AVAudioUnitReverb()
    reverb.loadFactoryPreset(.mediumHall)
    reverb.bypass = true
    reverb.wetDryMix = 0
    configure(distortion, delay, reverb)

    let limiter = MasterLimiter.makeNode()
    MasterLimiter.configure(limiter)
    engine.attach(voices.sourceNode)
    engine.attach(distortion)
    engine.attach(delay)
    engine.attach(reverb)
    engine.attach(limiter)
    engine.connect(voices.sourceNode, to: distortion, format: format)
    engine.connect(distortion, to: delay, format: format)
    engine.connect(delay, to: reverb, format: format)
    engine.connect(reverb, to: limiter, format: format)
    engine.connect(limiter, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = MasterLimiter.ceilingGain
    try engine.start()
    defer { engine.stop() }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else {
        throw OfflineRenderError.buffer
    }
    var left: [Float] = []
    left.reserveCapacity(frames)
    var remaining = frames
    while remaining > 0 {
        let chunk = AVAudioFrameCount(min(remaining, 4096))
        let status = try engine.renderOffline(chunk, to: buffer)
        guard status == .success else { throw OfflineRenderError.status(status) }
        let count = Int(buffer.frameLength)
        if count == 0 { throw OfflineRenderError.stalled }
        if let channel = buffer.floatChannelData?[0] {
            left.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
        }
        remaining -= count
    }
    return left
}

func energy(_ samples: [Float], from start: Int, to end: Int) -> Float {
    var sum: Float = 0
    for index in start..<end {
        let sample = samples[index]
        sum += sample * sample
    }
    return sum
}

/// Stereo buffer with a sine on the left and silence on the right. Built off the main actor.
private func stereoSine(frequency: Double, amplitude: Float, frames: Int) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: benchSampleRate,
        channels: 2,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let left = buffer.floatChannelData![0]
    let right = buffer.floatChannelData![1]
    for index in 0..<frames {
        let phase = 2 * Double.pi * frequency * Double(index) / benchSampleRate
        left[index] = amplitude * Float(sin(phase))
        right[index] = 0
    }
    return buffer
}

/// Source node built outside the MainActor so the render block is not actor-isolated.
private func constantSource(format: AVAudioFormat, value: Float) -> AVAudioSourceNode {
    AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            for index in 0..<Int(frameCount) {
                samples[index] = value
            }
        }
        return noErr
    }
}

@MainActor
struct DrumMashine_swistUITests {

    @Test func analyzeMeasuresPeakTailAndNonFinite() {
        var signal = [Float](repeating: 0.5, count: 1_000)
        for index in (signal.count - 240)..<signal.count {
            signal[index] = 0.0002
        }
        let stats = analyze(signal)
        #expect(abs(stats.peak - 0.5) < 0.0001)
        #expect(abs(stats.tailPeak - 0.0002) < 0.00001)
        #expect(stats.hasNaN == false)

        signal[3] = .nan
        #expect(analyze(signal).hasNaN)
        signal[3] = .infinity
        #expect(analyze(signal).hasNaN)
    }

    @Test func onsetsFireAfterTwoMillisecondsOfSilence() {
        var signal = [Float](repeating: 0, count: 800)
        signal[200] = 0.5
        signal[201] = 0.4
        // A gap shorter than 2 ms must not split the hit.
        for index in 210..<220 {
            signal[index] = 0
        }
        signal[220] = 0.5
        // A real gap, then a second hit.
        signal[500] = 0.8

        #expect(onsets(signal, threshold: 0.1) == [200, 500])
    }

    @Test func offlineRenderReturnsTheLeftChannel() throws {
        let frames = 4_800
        let rendered = try renderOffline(frames: frames) { format in
            constantSource(format: format, value: 0.25)
        }
        #expect(rendered.count == frames)
        let stats = analyze(rendered)
        #expect(stats.hasNaN == false)
        #expect(stats.peak > 0.1)
        #expect(stats.peak <= 0.26)
    }

    @Test func kick808LengthFollowsEnvelopeTau() {
        let preset = SoundLibraryManager.shared.availableSounds.first { $0.filename == "kick_808" }
        #expect(preset != nil)
        guard let preset else { return }
        let tau = max(0.005, Double(preset.decay) * 0.4)
        let duration = max(0.2, tau * log(1000))
        let samples = DrumSynthesizer.samples(for: preset, sampleRate: 48_000)
        let expected = Int(48_000 * duration)
        #expect(abs(samples.count - expected) <= 2)
    }

    @Test func libraryCoversSixtyPresetsAndEightDefaults() {
        let library = SoundLibraryManager.shared.availableSounds
        #expect(library.count == 111 + AcousticKit.pieces.count)
        let defaults = (0..<8).map { SoundLibraryManager.shared.defaultPreset(forTrackIndex: $0) }
        #expect(defaults.count == 8)
        #expect(defaults.allSatisfy { !$0.name.isEmpty })
    }

    /// Every library preset and the eight track defaults stay finite and inside the −6 dBFS ceiling.
    @Test func synthesizedPresetsStayFinite() {
        for preset in presetsUnderTest() {
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: benchSampleRate)
            let stats = analyze(samples)
            #expect(!samples.isEmpty, "\(preset.name) produced no samples")
            #expect(stats.hasNaN == false, "\(preset.name) is not finite")
            #expect(stats.peak <= 0.51, "\(preset.name) peak \(stats.peak)")
            #expect(stats.peak > 0.01, "\(preset.name) is silent")
        }
    }

    @Test func synthesizedPresetsDecayBelowTheSilenceFloor() {
        for preset in presetsUnderTest() {
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: benchSampleRate)
            let stats = analyze(samples)
            #expect(stats.peak <= 0.51, "\(preset.name) peak \(stats.peak)")
            #expect(stats.tailPeak < 0.001, "\(preset.name) tail \(stats.tailPeak)")
        }
    }

    @Test func overlappingHitsKeepTheFirstTail() throws {
        let tone = [Float](repeating: 0.4, count: 24_000)
        let both = try renderVoices(frames: 12_000) { engine in
            engine.swapSample(track: 0, samples: tone)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 6_000)
        }
        let secondOnly = try renderVoices(frames: 12_000) { engine in
            engine.swapSample(track: 0, samples: tone)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 6_000)
        }
        let bothEnergy = energy(both, from: 7_200, to: 9_600)
        let secondEnergy = energy(secondOnly, from: 7_200, to: 9_600)
        #expect(bothEnergy > secondEnergy * 1.5)
    }

    @Test func chokeFadesTheOpenHatInThreeMilliseconds() throws {
        let open = [Float](repeating: 0.4, count: 48_000)
        var closed = [Float](repeating: 0, count: 64)
        closed[0] = 1
        let alone = try renderVoices(frames: 30_000) { engine in
            engine.swapSample(track: 0, samples: open)
            engine.trigger(track: 0, velocity: 1, chokeGroup: 1, atSample: 0)
        }
        let choked = try renderVoices(frames: 30_000) { engine in
            engine.swapSample(track: 0, samples: open)
            engine.swapSample(track: 1, samples: closed)
            engine.trigger(track: 0, velocity: 1, chokeGroup: 1, atSample: 0)
            engine.trigger(track: 1, velocity: 1, chokeGroup: 1, atSample: 24_000)
        }
        var maxDiff: Float = 0
        for index in 0..<24_000 {
            maxDiff = max(maxDiff, abs(choked[index] - alone[index]))
        }
        #expect(maxDiff < 0.0001)
        #expect(choked[24_144..<30_000].allSatisfy { abs($0) < 0.001 })
    }

    @Test(arguments: [1000, 4095, 4096, 4097])
    func triggerStartsOnTheRequestedFrame(_ frame: Int) throws {
        var click = [Float](repeating: 0, count: 64)
        click[0] = 1
        let rendered = try renderVoices(frames: 8_192) { engine in
            engine.swapSample(track: 0, samples: click)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: Int64(frame))
        }
        let hits = onsets(rendered, threshold: 0.2)
        #expect(hits == [frame])
    }

    @Test func sixtyFourTriggersUseThirtyTwoVoices() throws {
        let click = [Float](repeating: 0.2, count: 256)
        let engine = VoiceEngine(sampleRate: benchSampleRate)
        for index in 0..<64 {
            engine.swapSample(track: index % 8, samples: click)
            engine.trigger(track: index % 8, velocity: 1, chokeGroup: -1, atSample: 0)
        }
        let rendered = try renderOffline(frames: 64) { _ in engine.sourceNode }
        #expect(analyze(rendered).hasNaN == false)
        #expect(engine.activeVoiceCount == 32)
        #expect(engine.lateEventCount == 0)
    }

    @Test func straightGridHitsEverySixThousandFrames() throws {
        let (engine, scheduler) = armedScheduler(bpm: 120)
        let rendered = try drive(engine: engine, scheduler: scheduler, frames: 192_000)
        expectOnsets(rendered, match: (0..<32).map { $0 * 6_000 })
    }

    @Test func swingFiftyShiftsOddStepsByFifteenHundredFrames() throws {
        let (engine, scheduler) = armedScheduler(bpm: 120, swing: 50)
        let rendered = try drive(engine: engine, scheduler: scheduler, frames: 192_000)
        let expected = (0..<32).map { k in k * 6_000 + (k % 2 == 1 ? 1_500 : 0) }
        expectOnsets(rendered, match: expected)
    }

    @Test func bpmChangeReanchorsWithoutDoubling() throws {
        let (engine, scheduler) = armedScheduler(bpm: 120)
        var changed = false
        let rendered = try renderOffline(frames: 86_000, chunkFrames: 512, beforeChunk: {
            if !changed, engine.renderedFrames >= 46_080 {
                scheduler.update { $0.bpm = 140 }
                changed = true
            }
            scheduler.scheduleDue(now: engine.renderedFrames)
        }) { _ in engine.sourceNode }
        let sps = 60.0 / 140.0 / 4.0 * Double(benchSampleRate)
        var expected = (0..<8).map { $0 * 6_000 }
        for n in 0..<8 {
            expected.append(48_000 + Int((Double(n) * sps).rounded()))
        }
        expectOnsets(rendered, match: expected)
    }

    @Test func stopFadesThenStaysSilent() throws {
        let engine = VoiceEngine(sampleRate: benchSampleRate)
        engine.swapSample(track: 0, samples: [Float](repeating: 0.4, count: 20_000))
        let scheduler = SequencerScheduler(voiceEngine: engine, sampleRate: benchSampleRate)
        scheduler.replace(kickPattern(bpm: 120))
        scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)
        var didStop = false
        let rendered = try renderOffline(frames: 10_600, chunkFrames: 500, beforeChunk: {
            if engine.renderedFrames == 0 {
                scheduler.scheduleDue(now: 100_000)
            }
            if !didStop, engine.renderedFrames >= 1_000 {
                scheduler.stop()
                didStop = true
            }
        }) { _ in engine.sourceNode }
        #expect(energy(rendered, from: 0, to: 1_000) > 1)
        let tail = Array(rendered[1_240..<rendered.count])
        #expect(analyze(tail).peak < 0.00001)
    }

    @Test func oneThousandFastStepsAreNeitherSkippedNorDoubled() throws {
        let bpm = 720_000.0 / 336.0
        let (engine, scheduler) = armedScheduler(bpm: bpm, stepCount: 16)
        var flips = 0
        let rendered = try renderOffline(frames: 1_000 * 336, chunkFrames: 512, beforeChunk: {
            if engine.renderedFrames > 0, engine.renderedFrames % (336 * 2) < 512 {
                scheduler.update { snap in
                    if snap.tracks.count > 1 { snap.tracks[1].isMuted.toggle() }
                }
                flips += 1
            }
            scheduler.scheduleDue(now: engine.renderedFrames)
        }) { _ in engine.sourceNode }
        #expect(flips > 0)
        let hits = onsets(rendered, threshold: 0.2)
        #expect(hits.count == 1_000, "got \(hits.count) onsets")
        #expect(hits.first == 0)
        for pair in zip(hits, hits.dropFirst()) {
            #expect(abs((pair.1 - pair.0) - 336) <= 1, "gap \(pair.1 - pair.0) at \(pair.0)")
        }
    }

    @Test func deviceChangeResumesTheSavedStepAtTheNewRate() throws {
        let (engine, scheduler) = armedScheduler(bpm: 120)
        _ = try drive(engine: engine, scheduler: scheduler, frames: 24_000)
        let checkpoint = scheduler.checkpointAndPause()
        #expect(checkpoint.wasPlaying)
        #expect(checkpoint.step == 4)

        let restarted = VoiceEngine(sampleRate: 44_100)
        var click = [Float](repeating: 0, count: 64)
        click[0] = 1
        restarted.swapSample(track: 0, samples: click)
        scheduler.retarget(voiceEngine: restarted, sampleRate: 44_100)
        scheduler.resume(atStep: checkpoint.step, frame: 0, ioBufferFrames: 512, timer: false)
        let rendered = try renderOffline(frames: 30_000, chunkFrames: 512, sampleRate: 44_100, beforeChunk: {
            scheduler.scheduleDue(now: restarted.renderedFrames)
        }) { _ in restarted.sourceNode }

        let step = 60.0 / 120.0 / 4.0 * 44_100
        let expected = (0..<6).map { Int((Double($0) * step).rounded()) }
        expectOnsets(rendered, match: expected)
    }

    @Test func fxPresetsHaveDistinctSpectralCentroids() {
        let fx = SoundLibraryManager.shared.availableSounds.filter { $0.category == .fx }
        #expect(fx.count == 10)
        let rendered = fx.map { DrumSynthesizer.samples(for: $0, sampleRate: benchSampleRate) }
        #expect(rendered[0] == DrumSynthesizer.samples(for: fx[0], sampleRate: benchSampleRate))
        let centroids = rendered.map { spectralCentroid($0) }
        for i in 0..<centroids.count {
            for j in (i + 1)..<centroids.count {
                let gap = abs(centroids[i] - centroids[j])
                #expect(gap > 40, "\(fx[i].filename) \(Int(centroids[i])) vs \(fx[j].filename) \(Int(centroids[j]))")
            }
        }
    }

    @Test func closedHatKeepsEnergyAboveTwoKilohertz() {
        var hat = kickPreset(attack: 0.001, pitch: 0)
        hat.category = .hihat
        hat.filename = "hh_closed"
        hat.decay = 0.05
        let samples = DrumSynthesizer.samples(for: hat, sampleRate: benchSampleRate)
        let ratio = lowBandPowerRatio(samples, cutoff: 2_000)
        #expect(ratio < 0.001, "low-band ratio \(ratio)")
    }

    @Test func eqGainStaysWithinTwelveDecibels() {
        #expect(EffectMapping.eqGain(0) == 0)
        #expect(EffectMapping.eqGain(12) == 12)
        #expect(EffectMapping.eqGain(-12) == -12)
        #expect(EffectMapping.eqGain(40) == 12)
        #expect(EffectMapping.eqGain(-40) == -12)
    }

    @Test func configurationChangeRestartsTheRunningEngine() async {
        let audio = AudioEngineManager.shared
        await audio.recoverFromConfigurationChange()
        #expect(audio.engine.isRunning)
        #expect(audio.errorMessage == nil)
        #expect(audio.outputSampleRate > 0)
    }

    @Test func limitedMixOfEightTracksStaysUnderFullScale() throws {
        let rendered = try renderLimitedPattern(frames: 100_000)
        let stats = analyze(rendered)
        #expect(stats.hasNaN == false)
        #expect(stats.peak <= 0.9, "peak \(stats.peak)")
        #expect(stats.peak > 0.01, "limiter produced silence")
    }

    @Test func maxDelayFeedbackDecaysUnderTheLimiter() throws {
        #expect(EffectMapping.delayFeedback(100) == 85)
        let hit = [Float](repeating: 0.5, count: 8_000)
        let rendered = try renderEffectChain(frames: 480_000, voice: hit) { _, delay, reverb in
            delay.bypass = false
            delay.wetDryMix = EffectMapping.delayMix(1)
            delay.delayTime = 0.25
            delay.feedback = EffectMapping.delayFeedback(100)
            reverb.bypass = true
        }
        let stats = analyze(rendered)
        let head = analyze(Array(rendered.prefix(24_000)))
        let tail = analyze(Array(rendered.suffix(24_000)))
        #expect(stats.hasNaN == false)
        #expect(stats.peak <= 0.9, "peak \(stats.peak)")
        #expect(head.peak > 0.05, "delay produced silence")
        #expect(tail.peak < head.peak * 0.25, "tail \(tail.peak) head \(head.peak)")
    }

    @Test func fullReverbKeepsTheDryHit() throws {
        #expect(EffectMapping.reverbMix(1) == 50)
        let hit = [Float](repeating: 0.8, count: 240)
        let dry = try renderEffectChain(frames: 2_000, voice: hit) { _, _, reverb in
            reverb.bypass = true
        }
        let wet = try renderEffectChain(frames: 2_000, voice: hit) { _, _, reverb in
            reverb.bypass = false
            reverb.wetDryMix = EffectMapping.reverbMix(1)
        }
        let dryRMS = rms(dry, from: 0, to: 240)
        let wetRMS = rms(wet, from: 0, to: 240)
        #expect(dryRMS > 0.01, "dry hit was silent")
        #expect(wetRMS >= dryRMS * 0.4, "wet \(wetRMS) dry \(dryRMS)")
    }

    @Test func spectrumOfAKilohertzSinePeaksInBandOne() async {
        let frame = await analyzeSine(frequency: 1000, amplitude: 0.8, frames: SpectrumAnalyzer.fftSize, repeats: 2)
        let again = await analyzeSine(frequency: 1000, amplitude: 0.8, frames: SpectrumAnalyzer.fftSize, repeats: 2)
        let loudest = frame.bands.enumerated().max { $0.element < $1.element }?.offset
        #expect(frame.bands.count == SpectrumAnalyzer.bandCount)
        #expect(frame.waveform.count == SpectrumAnalyzer.waveformPoints)
        #expect(loudest == 1, "bands \(frame.bands)")
        #expect(frame.bands[1] > 0.5)
        #expect(frame.peakL > 0.7, "peakL \(frame.peakL)")
        #expect(frame.peakR < 0.01, "peakR \(frame.peakR)")
        #expect(frame.rmsL > 0.1, "rmsL \(frame.rmsL)")
        #expect(frame.rmsR < 0.01, "rmsR \(frame.rmsR)")
        #expect(abs(frame.waveform[frame.waveform.count - 1]) > 0.7)
        #expect(abs(frame.waveform[frame.waveform.count - 2]) > 0.7)
        #expect(again.bands == frame.bands)
        #expect(again.waveform == frame.waveform)
    }

    @Test func loadingASixteenStepSlotPadsTracksAndRecordingDoesNotCrash() throws {
        let sequencer = SequencerEngine()
        sequencer.stepCount = .thirtyTwo
        sequencer.recordMode = .overdub
        sequencer.isPlaying = true

        let manager = try isolatedPatternManager().manager
        manager.patterns[1] = slotPattern(name: "B", stepCount: nil)
        manager.loadPattern(slot: 1, into: sequencer)

        for step in 0...31 {
            sequencer.recordPadHit(trackIndex: 0, velocity: 0.8, atStep: step)
        }

        #expect(sequencer.stepCount == .sixteen)
        #expect(manager.activePatternIndex == 1)
        #expect(sequencer.tracks.count == 8)
        for track in sequencer.tracks {
            #expect(track.steps.count >= sequencer.stepCount.rawValue)
            #expect(track.steps.count >= 32)
        }
        #expect(sequencer.tracks[0].steps[0].isActive)
        #expect(sequencer.tracks[0].steps[31].isActive)
        #expect(sequencer.tracks[0].soundPreset.name == "B0")

        sequencer.apply(pattern: slotPattern(name: "C", stepCount: .thirtyTwo))
        #expect(sequencer.stepCount == .thirtyTwo)
        for track in sequencer.tracks {
            #expect(track.steps.count >= sequencer.stepCount.rawValue)
        }
    }

    @Test func patternStepCountDecodesWhenTheOldSaveOmitsIt() throws {
        let pattern = slotPattern(name: "A", stepCount: .thirtyTwo)
        let encoded = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(DrumPattern.self, from: encoded)
        #expect(decoded.stepCount == .thirtyTwo)
        #expect(decoded.resolvedStepCount == .thirtyTwo)

        // Key order is not part of the save format. Drop the field from the object.
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        var legacy = try #require(object)
        legacy.removeValue(forKey: "stepCount")
        let oldData = try JSONSerialization.data(withJSONObject: legacy)
        let old = try JSONDecoder().decode(DrumPattern.self, from: oldData)
        #expect(old.stepCount == nil)
        #expect(old.resolvedStepCount == .sixteen)
        #expect(old.name == "A")
        #expect(old.bpm == 99)
    }

    @Test func patternRoundTripKeepsThirtyTwoStepsAndSwing() throws {
        var pattern = slotPattern(name: "Swing", stepCount: .thirtyTwo)
        pattern.swing = 55
        var steps = (0..<32).map { _ in SequencerStep() }
        steps[31].isActive = true
        steps[31].velocity = 0.5
        pattern.tracks[0].steps = steps

        let data = try PatternStore.encode([pattern])
        let loaded = try #require(PatternStore.decode(data).first)
        #expect(loaded.stepCount == .thirtyTwo)
        #expect(loaded.resolvedStepCount == .thirtyTwo)
        #expect(loaded.swing == 55)
        #expect(loaded.bpm == pattern.bpm)
        #expect(loaded.name == pattern.name)
        #expect(loaded.tracks.count == 8)
        #expect(loaded.tracks[0].steps.count == 32)
        #expect(loaded.tracks[0].steps[31].isActive)
        #expect(loaded.tracks[0].steps[31].velocity == 0.5)
        #expect(loaded.tracks[1].steps.contains { $0.isActive } == false)

        let legacy = try JSONEncoder().encode([pattern])
        let migrated = try #require(PatternStore.decode(legacy).first)
        #expect(PatternStore.isLegacyArray(legacy))
        #expect(migrated.stepCount == .thirtyTwo)
        #expect(migrated.swing == 55)
        #expect(migrated.tracks[0].steps[31].isActive)
        #expect(migrated.tracks[0].steps[31].velocity == 0.5)
    }

    @Test func corruptPatternSaveFallsBackToFourEmptySlots() throws {
        let isolated = try isolatedPatternManager()
        isolated.defaults.set(Data("not-json".utf8), forKey: PatternManager.storageKey)
        let manager = PatternManager(defaults: isolated.defaults, directory: isolated.directory)

        #expect(manager.patterns.count == 4)
        #expect(manager.loadError?.contains("Could not read saved patterns") == true)
        #expect(isolated.defaults.data(forKey: PatternManager.storageKey) == Data("not-json".utf8))
        for pattern in manager.patterns {
            let active = pattern.tracks.contains { track in
                track.steps.contains { $0.isActive }
            }
            #expect(active == false)
        }
    }

    @Test func migratingTheDefaultsKeyWritesPatternsFileAndKeepsTheKey() throws {
        let isolated = try isolatedPatternManager()
        let original = [slotPattern(name: "A", stepCount: .sixteen)]
        let data = try PatternStore.encode(original)
        isolated.defaults.set(data, forKey: PatternManager.storageKey)
        let manager = PatternManager(defaults: isolated.defaults, directory: isolated.directory)

        #expect(manager.loadError == nil)
        #expect(manager.patterns.count == 4)
        #expect(manager.patterns[0].name == "A")
        #expect(manager.patterns[0].bpm == 99)
        #expect(isolated.defaults.data(forKey: PatternManager.storageKey) == data)

        let store = PersistenceStore(directory: isolated.directory)
        guard case .loaded(let saved) = try store.read(
            "patterns",
            as: PatternLibrary.self,
            maximumVersion: PersistenceStore.patternsVersion
        ) else {
            Issue.record("patterns.json was not written")
            return
        }
        #expect(saved.patterns[0].name == "A")
        #expect(saved.patterns[0].bpm == 99)
        #expect(saved.patterns[0].swing == 12)
        #expect(saved.activePatternIndex == 0)
    }

    @Test func legacyPatternBytesAreCopiedOnceAndTheKeyStays() throws {
        let isolated = try isolatedPatternManager()
        let payload = Data("legacy-bytes".utf8)
        isolated.defaults.set(payload, forKey: PatternManager.storageKey)
        _ = PatternManager(defaults: isolated.defaults, directory: isolated.directory)
        _ = PatternManager(defaults: isolated.defaults, directory: isolated.directory)

        let backups = isolated.directory.appendingPathComponent("Backups")
        let copies = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("legacy-patterns-") }
        #expect(copies.count == 1)
        let copy = try #require(copies.first)
        #expect(try Data(contentsOf: copy) == payload)
        #expect(isolated.defaults.data(forKey: PatternManager.storageKey) == payload)
    }

    @Test func standardPatternBytesAreUnchangedSoFar() {
        _ = standardPatternsGuard
        #expect(StandardDefaultsProbe.patternSHA256() == standardPatternsHashAtLaunch)
    }

    @Test func projectUsesTheSequencerSwingScale() {
        let engine = AudioEngineManager.shared
        let previousVolume = engine.masterVolume
        defer { engine.setMasterVolume(previousVolume) }
        engine.setMasterVolume(0.42)

        let fresh = DrumProject(name: "Scale")
        #expect(fresh.swing == 0)
        #expect(fresh.masterVolume == 0.85)
        #expect(DrumProject.preview.swing == 55)

        let project = DrumProject.fromCurrentState(
            name: "Live",
            bpm: 100,
            swing: 55,
            tracks: [],
            patterns: []
        )
        #expect(project.swing == 55)
        #expect(abs(project.masterVolume - 0.42) < 0.001)
    }

    @Test func tapTempoUsesTheMedianOfTheLastFourIntervals() {
        var taps = TapTempo()
        #expect(taps.register(at: 0) == nil)
        #expect(taps.register(at: 0.5) == 120)

        // Intervals 0.5, 0.5, 0.25, 1.0. The mean is 106.7 BPM. The median is 120.
        var median = TapTempo()
        let bpm = [0.0, 0.5, 1.0, 1.25, 2.25].compactMap { median.register(at: $0) }.last
        #expect(bpm == 120)

        var reset = TapTempo()
        _ = reset.register(at: 0)
        _ = reset.register(at: 0.5)
        #expect(reset.register(at: 3.0) == nil)
        #expect(reset.register(at: 3.5) == 120)
    }

    @Test func bpmSetterClampsToTheMusicalRange() {
        let sequencer = SequencerEngine()
        sequencer.bpm = 10
        #expect(sequencer.bpm == 40)
        sequencer.bpm = 900
        #expect(sequencer.bpm == 300)
        sequencer.bpm = 128
        #expect(sequencer.bpm == 128)
        sequencer.bpm = 128
        #expect(sequencer.bpm == 128)
    }

    @Test func humanizeStaysInsideTenPercentOfAStep() throws {
        let (engine, scheduler) = armedScheduler(bpm: 120)
        scheduler.update { $0.humanize = 100 }
        let rendered = try drive(engine: engine, scheduler: scheduler, frames: 96_000)
        let hits = onsets(rendered, threshold: 0.2)
        #expect(hits.count == 16)
        var moved = false
        for (index, hit) in hits.enumerated() {
            let delta = abs(hit - index * 6_000)
            #expect(delta <= 600, "step \(index) moved \(delta)")
            if delta > 1 { moved = true }
        }
        #expect(moved)
    }

    @Test func stepCountChangeWrapsTheGridOnTheFly() throws {
        var pattern = kickPattern(bpm: 120, stepCount: 16)
        for index in pattern.tracks[0].steps.indices where index != 0 {
            pattern.tracks[0].steps[index].isActive = false
        }
        let engine = VoiceEngine(sampleRate: benchSampleRate)
        var click = [Float](repeating: 0, count: 64)
        click[0] = 1
        engine.swapSample(track: 0, samples: click)
        let scheduler = SequencerScheduler(voiceEngine: engine, sampleRate: benchSampleRate)
        scheduler.replace(pattern)
        scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)
        var changed = false
        let rendered = try renderOffline(frames: 150_000, chunkFrames: 512, beforeChunk: {
            if !changed, engine.renderedFrames >= 7_000 {
                scheduler.update { $0.stepCount = 8 }
                changed = true
            }
            scheduler.scheduleDue(now: engine.renderedFrames)
        }) { _ in engine.sourceNode }
        #expect(changed)
        expectOnsets(rendered, match: [0, 48_000, 96_000, 144_000])
    }

    @Test func recordingQuantizesToTheNearestHeardStep() {
        let position = TransportPosition(
            anchor: 0,
            samplesPerStep: 1_000,
            stepNumberAtAnchor: 0,
            stepCount: 32,
            isPlaying: true
        )
        #expect(position.nearestStepIndex(at: 400) == 0)
        #expect(position.nearestStepIndex(at: 600) == 1)
        #expect(position.nearestStepIndex(at: 5_400) == 5)
        #expect(position.nearestStepIndex(at: 5_600) == 6)
        #expect(position.nearestStepIndex(at: 31_600) == 0)
        #expect(position.stepIndex(at: 600) == 0)
    }

    @Test func previewBetweenKicksLeavesTheKickOnsets() throws {
        var kick = [Float](repeating: 0, count: 128)
        kick[0] = 1
        let preview = [Float](repeating: 1, count: 400)
        let rendered = try renderVoices(frames: 24_000) { engine in
            engine.swapSample(track: 0, samples: kick)
            engine.swapSample(track: VoiceEngine.previewTrack, samples: preview)
            // The command ring plays triggers in queue order, so the preview sits between the kicks.
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 6_000)
            engine.trigger(track: VoiceEngine.previewTrack, velocity: 0.85, chokeGroup: -1, atSample: 9_000)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 12_000)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 18_000)
        }
        #expect(onsets(rendered, threshold: 0.2) == [0, 6_000, 9_000, 12_000, 18_000])
    }

    @Test func previewCacheKeepsSixteenAndTheNewestRate() {
        var cache = PreviewSampleCache(limit: 16)
        let ids = (0..<17).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            cache.store([Float(index)], id: id, sampleRate: 48_000)
        }
        #expect(cache.contains(id: ids[0]) == false)
        #expect(cache.samples(id: ids[1], sampleRate: 48_000) == [1])
        cache.store([99], id: UUID(), sampleRate: 48_000)
        #expect(cache.contains(id: ids[1]))
        #expect(cache.contains(id: ids[2]) == false)
        #expect(cache.samples(id: ids[3], sampleRate: 44_100) == nil)
    }

    @Test func attackOfATenthSoftensTheFirstFiftyMilliseconds() {
        let open = DrumSynthesizer.samples(for: kickPreset(attack: 0, pitch: 0), sampleRate: benchSampleRate)
        let slow = DrumSynthesizer.samples(for: kickPreset(attack: 0.1, pitch: 0), sampleRate: benchSampleRate)
        let window = Int(0.050 * benchSampleRate)
        let openRMS = rms(open, from: 0, to: window)
        let slowRMS = rms(slow, from: 0, to: window)
        #expect(slowRMS < openRMS * 0.6, "slow \(slowRMS) open \(openRMS)")
        #expect(open.last == 0)
        #expect(slow.last == 0)
    }

    @Test func pitchPlusTwelveRaisesTheKickFundamental() {
        let low = DrumSynthesizer.samples(for: kickPreset(attack: 0, pitch: 0), sampleRate: benchSampleRate)
        let high = DrumSynthesizer.samples(for: kickPreset(attack: 0, pitch: 12), sampleRate: benchSampleRate)
        let window = Int(0.020 * benchSampleRate)
        let lowCrossings = tonalCrossings(low.prefix(window))
        let highCrossings = tonalCrossings(high.prefix(window))
        #expect(Double(highCrossings) > Double(lowCrossings) * 1.6, "low \(lowCrossings) high \(highCrossings)")

        var hat = kickPreset(attack: 0.001, pitch: 0)
        hat.category = .hihat
        hat.filename = "hh_closed"
        hat.decay = 0.05
        var hatUp = hat
        hatUp.pitch = 12
        let closed = DrumSynthesizer.samples(for: hat, sampleRate: benchSampleRate)
        let raised = DrumSynthesizer.samples(for: hatUp, sampleRate: benchSampleRate)
        #expect(closed != raised)
    }

    @Test func shortSilenceStaysAtZero() async {
        let frame = await analyzeSine(frequency: 1000, amplitude: 0, frames: 64, repeats: 1)
        #expect(frame.bands.allSatisfy { $0 == 0 })
        #expect(frame.peakL == 0)
        #expect(frame.peakR == 0)
        #expect(frame.waveform.allSatisfy { $0 == 0 })
    }

    private func analyzeSine(frequency: Double, amplitude: Float, frames: Int, repeats: Int) async -> MeterFrame {
        let analyzer = SpectrumAnalyzer()
        let block = analyzer.makeTapBlock()
        await Task.detached {
            let buffer = stereoSine(frequency: frequency, amplitude: amplitude, frames: frames)
            let time = AVAudioTime(sampleTime: 0, atRate: benchSampleRate)
            for _ in 0..<repeats {
                block(buffer, time)
            }
        }.value
        return analyzer.copyFrame()
    }

    /// Power-weighted mean frequency of the first 1024 samples.
    private func spectralCentroid(_ samples: [Float]) -> Double {
        powers(samples).centroid
    }

    /// Share of power in bins below `cutoff`.
    private func lowBandPowerRatio(_ samples: [Float], cutoff: Double) -> Double {
        powers(samples, cutoff: cutoff).lowRatio
    }

    private func powers(_ samples: [Float], cutoff: Double = 2_000) -> (centroid: Double, lowRatio: Double) {
        let count = min(1024, samples.count)
        guard count > 8 else { return (0, 1) }
        var weighted = 0.0
        var total = 0.0
        var low = 0.0
        let half = count / 2
        for bin in 1..<half {
            var real = 0.0
            var imag = 0.0
            let omega = 2 * Double.pi * Double(bin) / Double(count)
            for index in 0..<count {
                let sample = Double(samples[index])
                let angle = omega * Double(index)
                real += sample * cos(angle)
                imag -= sample * sin(angle)
            }
            let power = real * real + imag * imag
            let frequency = Double(bin) * benchSampleRate / Double(count)
            weighted += frequency * power
            total += power
            if frequency < cutoff { low += power }
        }
        guard total > 0 else { return (0, 1) }
        return (weighted / total, low / total)
    }

    private func kickPreset(attack: Float, pitch: Float) -> SoundPreset {
        var preset = SoundPreset(id: UUID(), name: "kick", filename: "kick_test", category: .kick)
        preset.attack = attack
        preset.decay = 0.35
        preset.sustain = 0
        preset.release = 0.1
        preset.pitch = pitch
        return preset
    }

    /// Zero crossings after a 1 ms average, so the kick click does not dominate the first 20 ms.
    private func tonalCrossings(_ samples: ArraySlice<Float>) -> Int {
        let values = Array(samples)
        guard values.count > 48 else { return 0 }
        let width = 48
        var crossings = 0
        var previous: Float = 0
        var armed = false
        for index in width..<values.count {
            var sum: Float = 0
            for offset in 0..<width {
                sum += values[index - offset]
            }
            let smoothed = sum / Float(width)
            if armed, previous <= 0, smoothed > 0 {
                crossings += 1
            }
            previous = smoothed
            armed = true
        }
        return crossings
    }

    private func isolatedPatternManager() throws -> (manager: PatternManager, defaults: UserDefaults, directory: URL) {
        let suite = "DrumMachineTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        return (PatternManager(defaults: defaults, directory: directory), defaults, directory)
    }

    private func slotPattern(name: String, stepCount: StepCount?) -> DrumPattern {
        let tracks = (0..<8).map { index -> SequencerTrack in
            let preset = SoundPreset(
                id: UUID(),
                name: "\(name)\(index)",
                filename: "sound_\(index)",
                category: .kick
            )
            var track = SequencerTrack(soundPreset: preset, stepsCount: 16)
            track.volume = 0.4
            track.pan = -0.25
            return track
        }
        return DrumPattern(name: name, tracks: tracks, bpm: 99, swing: 12, stepCount: stepCount)
    }

    private func presetsUnderTest() -> [SoundPreset] {
        let library = SoundLibraryManager.shared.availableSounds
        let defaults = (0..<8).map { SoundLibraryManager.shared.defaultPreset(forTrackIndex: $0) }
        return library + defaults
    }
}


/// Audit #1/#3: one SPSC ring per producer. Two threads writing at once must not lose
/// or tear commands, and a pad hit must not wait behind a future sequencer trigger.
struct VoiceEngineLaneTests {
    @Test func twoWritersLoseNoCommands() throws {
        let engine = VoiceEngine(sampleRate: benchSampleRate)
        let rounds = 10
        let perWriter = 1_000
        _ = try renderOffline(frames: 512 * rounds, chunkFrames: 512, beforeChunk: {
            let group = DispatchGroup()
            DispatchQueue.global(qos: .userInteractive).async(group: group) {
                for i in 0..<perWriter {
                    engine.setTrackGain(track: i % 8, gain: 1, pan: 0, lane: .sequencer)
                }
            }
            DispatchQueue.global(qos: .userInitiated).async(group: group) {
                for i in 0..<perWriter {
                    engine.setTrackGain(track: i % 8, gain: 1, pan: 0, lane: .control)
                }
            }
            group.wait()
        }) { _ in engine.sourceNode }
        #expect(engine.appliedCommandCount == Int64(2 * perWriter * rounds))
        #expect(engine.lateEventCount == 0)
    }

    @Test func padHitIsNotHeldBehindFutureSequencerTrigger() throws {
        var click = [Float](repeating: 0, count: 64)
        click[0] = 1
        let rendered = try renderVoices(frames: 4_096) { engine in
            engine.swapSample(track: 0, samples: click)
            engine.swapSample(track: 1, samples: click)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 3_000, generation: 0, lane: .sequencer)
            engine.trigger(track: 1, velocity: 1, chokeGroup: -1, atSample: 0)
        }
        #expect(onsets(rendered, threshold: 0.2) == [0, 3_000])
    }
}


/// Audit #2: the theme rebuild must not create a second engine that steals the
/// device-change handlers, and a dropped engine must not keep a playhead loop alive.
@MainActor
struct SequencerOwnershipTests {
    @Test func extraEnginesAndLayoutInitsDoNotStealDeviceHandlers() {
        let owner = AppSequencer.shared
        #expect(AudioEngineManager.shared.deviceChangeOwner == ObjectIdentifier(owner))
        for _ in 0..<3 {
            _ = SequencerEngine()
            _ = MainLayoutView(sequencer: owner)
        }
        #expect(AudioEngineManager.shared.deviceChangeOwner == ObjectIdentifier(owner))
    }

    @Test func droppedEngineIsReleased() async throws {
        weak var released: SequencerEngine?
        do {
            let engine = SequencerEngine()
            released = engine
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(released == nil)
    }
}


/// Audit #8: the playhead poller exists only while playing.
@MainActor
struct PlayheadPollerTests {
    @Test func pollerRunsOnlyWhilePlaying() {
        let engine = SequencerEngine()
        #expect(engine.playheadTask == nil)
        engine.play()
        #expect(engine.playheadTask != nil)
        engine.stop()
        #expect(engine.playheadTask == nil)
    }
}


/// Audit #9: grid-wide edits publish one snapshot, not one per cell.
@MainActor
struct TrackBatchingTests {
    @Test func clearAndRandomizePublishOnce() {
        let engine = SequencerEngine()
        var before = engine.snapshotPublishCount
        engine.randomizePattern(density: 0.5)
        #expect(engine.snapshotPublishCount == before + 1)
        before = engine.snapshotPublishCount
        engine.clearPattern()
        #expect(engine.snapshotPublishCount == before + 1)
        #expect(engine.tracks.allSatisfy { $0.steps.allSatisfy { !$0.isActive } })
    }

    @Test func replaceRecordPublishesOnce() {
        let engine = SequencerEngine()
        engine.randomizePattern(density: 1)
        engine.recordMode = .replace
        engine.play()
        defer { engine.stop() }
        let before = engine.snapshotPublishCount
        engine.recordPadHit(trackIndex: 0, velocity: 0.7, atStep: 3)
        #expect(engine.snapshotPublishCount == before + 1)
        #expect(engine.tracks[0].steps.indices.filter { engine.tracks[0].steps[$0].isActive } == [3])
    }
}


/// Audit #7: 30 Hz meters that settle and back off when nothing changes.
@MainActor
struct MeterIdleTests {
    @Test func levelsDecayToExactZero() {
        var level: Float = 1
        for _ in 0..<200 { level = MeterModel.decayed(0, from: level) }
        #expect(level == 0)
        #expect(MeterModel.pollNanoseconds == 33_333_333)
    }

    @Test func unchangedPollsMakeTheModelIdle() {
        let meters = MeterModel.shared
        for _ in 0..<(MeterModel.idleAfterPolls * 10) where !meters.isIdle {
            meters.pull()
        }
        #expect(meters.isIdle)
    }
}


/// Audit #4: pan is computed per block but ramps smoothly and still converges.
struct BlockPanTests {
    @Test func hardPanChangeRampsWithoutSteps() throws {
        let dc = [Float](repeating: 0.5, count: 48_000)
        let engine = VoiceEngine(sampleRate: benchSampleRate)
        engine.swapSample(track: 0, samples: dc)
        engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0)
        var chunk = 0
        let left = try renderOffline(frames: 24_000, chunkFrames: 512, beforeChunk: {
            if chunk == 4 { engine.setTrackGain(track: 0, gain: 1, pan: 1) }
            chunk += 1
        }) { _ in engine.sourceNode }
        #expect(analyze(left).hasNaN == false)
        var maxStep: Float = 0
        for i in 1..<left.count { maxStep = max(maxStep, abs(left[i] - left[i - 1])) }
        #expect(maxStep < 0.005, "step \(maxStep)")
        let centre = 0.5 * Float(cos(Double.pi / 4))
        #expect(abs(left[1_000] - centre) < 1e-3)
        #expect(abs(left[left.count - 1]) < 1e-3)
    }
}


/// Audit #5: delayTime is written only when it changes by more than the epsilon.
@MainActor
struct DelayRetimeTests {
    @Test func epsilonGatesDelayTimeWrites() {
        #expect(AudioEngineManager.delayTimeChanged(from: 0.25, to: 0.25) == false)
        #expect(AudioEngineManager.delayTimeChanged(from: 0.25, to: 0.2505) == false)
        #expect(AudioEngineManager.delayTimeChanged(from: 0.25, to: 0.248) == true)
    }
}


/// P2-1: a full retire ring parks old buffers (no leak, no free on the audio thread);
/// they reach the main actor once it drains.
struct RetireOverflowTests {
    @Test func overflowParksAndLaterReleases() throws {
        let engine = VoiceEngine(sampleRate: benchSampleRate, retireCapacity: 4)
        let buffer = [Float](repeating: 0.1, count: 32)
        for _ in 0..<21 { engine.swapSample(track: 0, samples: buffer) }
        // One block applies all 21 swaps: 20 old buffers, ring holds 4, 16 parked.
        _ = try renderOffline(frames: 512, chunkFrames: 512) { _ in engine.sourceNode }
        #expect(engine.retireBacklogCount == 16)
        #expect(engine.leakedBufferCount == 0)
        _ = try renderOffline(frames: 512 * 8, chunkFrames: 512, beforeChunk: {
            engine.drainRetired()
        }) { _ in engine.sourceNode }
        #expect(engine.retireBacklogCount == 0)
        #expect(engine.leakedBufferCount == 0)
    }
}
