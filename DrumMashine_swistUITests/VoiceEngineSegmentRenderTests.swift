import AVFoundation
import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_8 P2-1: segment render + settled-gain skip must not change a single sample.
private let segChunk = 512
private let segRate: Double = 48_000
private let panCenter = Float(cos(Double.pi / 4))

private func fnv64(_ samples: [Float]) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for sample in samples {
        var bits = sample.bitPattern
        for _ in 0..<4 {
            hash ^= UInt64(bits & 0xff)
            hash = hash &* 0x100000001b3
            bits >>= 8
        }
    }
    return hash
}

private func nonZeroFrames(_ samples: [Float]) -> [Int] {
    samples.indices.filter { samples[$0] != 0 }
}

/// Deterministic multi-track scenario: mid-block triggers, chokes, both lanes,
/// gain/pan moves between blocks, a lane blocked behind a future trigger.
private func goldenScenario() throws -> [Float] {
    let engine = VoiceEngine(sampleRate: segRate)
    for track in 0..<5 {
        let length = 900 + track * 377
        let samples = (0..<length).map { index -> Float in
            let decay = Float(length - index) / Float(length)
            return decay * Float(sin(Double(index) * (0.031 + Double(track) * 0.017)))
        }
        engine.swapSample(track: track, samples: samples)
    }
    var chunk = 0
    return try renderOffline(frames: 480 * 40, chunkFrames: 480, beforeChunk: {
        let base = Int64(chunk * 480)
        switch chunk {
        case 0:
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0)
            engine.trigger(track: 1, velocity: 0.8, chokeGroup: 1, atSample: 37, lane: .sequencer)
            engine.trigger(track: 2, velocity: 0.6, chokeGroup: 1, atSample: 479, lane: .sequencer)
        case 2:
            engine.setTrackGain(track: 0, gain: 0.3, pan: -0.7)
            engine.trigger(track: 3, velocity: 0.9, chokeGroup: -1, atSample: base + 200, lane: .sequencer)
            // Held behind the future trigger above on the sequencer lane.
            engine.setTrackGain(track: 3, gain: 0.5, pan: 0.6, lane: .sequencer)
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: base + 10)
        case 5:
            engine.trigger(track: 4, velocity: 1, chokeGroup: -1, atSample: base + 1)
            engine.trigger(track: 4, velocity: 0.7, chokeGroup: -1, atSample: base + 2)
            engine.trigger(track: 1, velocity: 1, chokeGroup: 1, atSample: base + 300, lane: .sequencer)
            engine.trigger(track: 2, velocity: 1, chokeGroup: 1, atSample: base + 301, lane: .sequencer)
        case 9:
            engine.setTrackGain(track: 1, gain: 0, pan: 1)
            engine.setTrackGain(track: 4, gain: 1.4, pan: -1)
            for step in 0..<8 {
                engine.trigger(track: step % 5, velocity: 0.5, chokeGroup: -1, atSample: base + Int64(step * 59))
            }
        case 14:
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: base - 100) // late
            engine.setTrackGain(track: 0, gain: 1, pan: 0)
            engine.setTrackGain(track: 1, gain: 0.9, pan: 0)
        case 20:
            engine.stopAll(fadeFrames: 64)
        case 22:
            for track in 0..<5 {
                engine.trigger(track: track, velocity: 1, chokeGroup: -1, atSample: base + Int64(track * 96))
            }
        default:
            break
        }
        chunk += 1
    }) { _ in engine.sourceNode }
}

@MainActor
struct VoiceEngineSegmentRenderTests {

    /// (a) A trigger due mid-block starts on exactly that frame.
    @Test func midBlockTriggerStartsOnItsFrame() throws {
        let out = try renderOffline(frames: segChunk * 2, chunkFrames: segChunk, beforeChunk: nil) { _ in
            let engine = VoiceEngine(sampleRate: segRate)
            engine.swapSample(track: 0, samples: [1])
            engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 300)
            return engine.sourceNode
        }
        #expect(nonZeroFrames(out) == [300])
        #expect(abs(out[300] - panCenter) < 1e-6)
    }

    /// (b) Several events in one block, on frames 0 and frameCount-1, and on the next block's first frame.
    @Test func multipleAndEdgeFrameEvents() throws {
        let frames: [Int64] = [0, 100, 101, 511, 512]
        let out = try renderVoices(frames: segChunk * 2) { engine in
            for (track, at) in frames.enumerated() {
                engine.swapSample(track: track, samples: [Float(track + 1) * 0.1])
                engine.trigger(track: track, velocity: 1, chokeGroup: -1, atSample: at, lane: track % 2 == 0 ? .sequencer : .control)
            }
        }
        #expect(nonZeroFrames(out) == frames.map(Int.init))
        for (track, at) in frames.enumerated() {
            #expect(abs(out[Int(at)] - Float(track + 1) * 0.1 * panCenter) < 1e-6)
        }
    }

    /// (c) An event already in the past is still counted late and plays on the next block's first frame.
    @Test func lateEventStillCounted() throws {
        let engine = VoiceEngine(sampleRate: segRate)
        engine.swapSample(track: 0, samples: [1])
        var chunk = 0
        let out = try renderOffline(frames: segChunk * 3, chunkFrames: segChunk, beforeChunk: {
            if chunk == 2 {
                engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 100)
            }
            chunk += 1
        }) { _ in engine.sourceNode }
        #expect(engine.lateEventCount == 1)
        #expect(nonZeroFrames(out) == [segChunk * 2])
    }

    /// (d) Gain ramp after setGain equals a per-frame one-pole reference.
    @Test func gainRampMatchesOnePoleReference() throws {
        let engine = VoiceEngine(sampleRate: segRate)
        engine.swapSample(track: 0, samples: [Float](repeating: 1, count: segChunk * 48))
        var chunk = 0
        let out = try renderOffline(frames: segChunk * 40, chunkFrames: segChunk, beforeChunk: {
            if chunk == 0 { engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0) }
            if chunk == 1 { engine.setTrackGain(track: 0, gain: 0.25, pan: 0) }
            chunk += 1
        }) { _ in engine.sourceNode }
        let alpha = Float(1 - exp(-1.0 / (0.005 * segRate)))
        var gain: Float = 1
        var target: Float = 1
        for frame in 0..<out.count {
            if frame == segChunk { target = 0.25 }
            let expected = gain * panCenter
            #expect(abs(out[frame] - expected) < 1e-6, "frame \(frame)")
            if abs(out[frame] - expected) >= 1e-6 { break }
            gain += alpha * (target - gain)
            if abs(gain) < 1e-15 { gain = 0 }
        }
        // Settled at the end: steady output (one-pole reached its float fixed point).
        #expect(out[out.count - 1] == out[out.count - 2])
    }

    /// (e) Offline render is bit-identical to the 26473ad baseline.
    @Test func offlineRenderBitIdenticalToBaseline() throws {
        let scenario = try goldenScenario()
        let (engine, scheduler) = armedScheduler(bpm: 137, swing: 0.3)
        let sequenced = try drive(engine: engine, scheduler: scheduler, frames: 48_000)
        let scenarioHash = fnv64(scenario)
        let sequencedHash = fnv64(sequenced)
        print("CUT8_GOLDEN scenario=\(String(scenarioHash, radix: 16)) sequenced=\(String(sequencedHash, radix: 16)) nz=\(nonZeroFrames(scenario).count)")
        #expect(nonZeroFrames(scenario).count > 5_000)
        #expect(scenarioHash == 12_102_173_626_081_619_070)
        #expect(sequencedHash == 1_463_802_545_885_221_317)
    }
}
