import Foundation
import Testing
@testable import DrumMashine_swistUI

private let layerRate: Double = 48_000

private func shaped(_ amp: Float, count: Int) -> [Float] {
    var buffer = [Float](repeating: 0, count: count)
    let attack = min(32, count)
    for index in 0..<attack {
        buffer[index] = amp * Float(index) / Float(max(attack, 1))
    }
    if count > attack + 8 {
        for index in attack..<(count - 8) { buffer[index] = amp }
    }
    let fade = min(8, count)
    for index in 0..<fade {
        buffer[count - 1 - index] *= Float(index) / Float(fade)
    }
    buffer[count - 1] = 0
    return buffer
}

private func rms(_ buffer: [Float]) -> Float {
    guard !buffer.isEmpty else { return 0 }
    var sum: Float = 0
    for sample in buffer { sum += sample * sample }
    return sqrt(sum / Float(buffer.count))
}

private func renderHit(_ engine: VoiceEngine, velocity: Float, articulation: Int = 0, frames: Int) throws -> [Float] {
    engine.trigger(track: 0, velocity: velocity, chokeGroup: -1, atSample: 0, articulation: articulation)
    return try renderOffline(frames: frames, chunkFrames: min(frames, 4096), sampleRate: layerRate) { _ in engine.sourceNode }
}

struct LayerEngineTests {
    @Test func linearOneLayerMatchesTheLegacyMix() throws {
        var click = [Float](repeating: 0, count: 64)
        click[0] = 1
        let legacy = VoiceEngine(sampleRate: layerRate)
        legacy.swapSample(track: 0, samples: click)
        let legacyMix = try renderHit(legacy, velocity: 0.8, frames: 128)

        let bank = LayerBank.make(
            articulations: [[[click]]],
            velocityHi: [1],
            velocityRef: [1],
            curve: VelocityCurve.linear.curveTable(),
            useCurve: false
        )
        let layered = VoiceEngine(sampleRate: layerRate)
        layered.swapLayers(track: 0, bank: bank)
        let layeredMix = try renderHit(layered, velocity: 0.8, frames: 128)
        #expect(legacyMix.count == layeredMix.count)
        for index in legacyMix.indices {
            #expect(legacyMix[index].bitPattern == layeredMix[index].bitPattern)
        }
    }

    @Test func swapWhilePlayingKeepsTheOldBankAndDoesNotLeak() throws {
        let held = shaped(0.3, count: 2_000)
        let next = shaped(0.05, count: 2_000)
        let first = LayerBank.make(
            articulations: [[[held]]],
            velocityHi: [1], velocityRef: [0.8],
            curve: VelocityCurve.linear.curveTable(), useCurve: false
        )
        let second = LayerBank.make(
            articulations: [[[next]]],
            velocityHi: [1], velocityRef: [0.8],
            curve: VelocityCurve.linear.curveTable(), useCurve: false
        )
        let engine = VoiceEngine(sampleRate: layerRate, retireCapacity: 4)
        engine.swapLayers(track: 0, bank: first)
        let opening = try renderHit(engine, velocity: 1, frames: 200)
        engine.swapLayers(track: 0, bank: second)
        let continued = try renderOffline(frames: 200, chunkFrames: 200, sampleRate: layerRate) { _ in engine.sourceNode }
        let centre = Float(cos(Double.pi / 4))
        #expect(abs(opening[40] - 0.3 * centre) < 0.02)
        #expect(abs(continued[40] - 0.3 * centre) < 0.02)
        #expect(engine.leakedBufferCount == 0)
        _ = try renderOffline(frames: 4_000, chunkFrames: 512, sampleRate: layerRate, beforeChunk: {
            engine.drainRetired()
        }) { _ in engine.sourceNode }
        #expect(engine.leakedBufferCount == 0)
        #expect(engine.retireBacklogCount == 0)
    }

    @Test func retireOverflowParksLayerBanks() throws {
        let engine = VoiceEngine(sampleRate: layerRate, retireCapacity: 4)
        let buffer = [Float](repeating: 0.1, count: 32)
        for _ in 0..<21 {
            let bank = LayerBank.make(
                articulations: [[[buffer]]],
                velocityHi: [1], velocityRef: [1],
                curve: VelocityCurve.linear.curveTable(), useCurve: false
            )
            engine.swapLayers(track: 0, bank: bank)
        }
        _ = try renderOffline(frames: 512, chunkFrames: 512, sampleRate: layerRate) { _ in engine.sourceNode }
        #expect(engine.retireBacklogCount == 16)
        #expect(engine.leakedBufferCount == 0)
        _ = try renderOffline(frames: 512 * 8, chunkFrames: 512, sampleRate: layerRate, beforeChunk: {
            engine.drainRetired()
        }) { _ in engine.sourceNode }
        #expect(engine.retireBacklogCount == 0)
        #expect(engine.leakedBufferCount == 0)
    }

    @Test func crossfadeRmsRisesAcrossTheBoundary() throws {
        let quiet = shaped(0.12, count: 2_400)
        let loud = shaped(0.42, count: 2_400)
        let bank = LayerBank.make(
            articulations: [[[quiet], [loud]]],
            velocityHi: [0.5, 1],
            velocityRef: [0.25, 0.75],
            curve: VelocityCurve.linear.curveTable(),
            useCurve: false
        )
        var previous: Float = -1
        for step in 0..<21 {
            let velocity = 0.46 + Float(step) * (0.08 / 20)
            let engine = VoiceEngine(sampleRate: layerRate)
            engine.swapLayers(track: 0, bank: bank)
            let mix = try renderHit(engine, velocity: velocity, frames: 2_048)
            let level = rms(mix)
            #expect(level + 1e-6 >= previous)
            previous = level
        }
        let alone = VoiceEngine(sampleRate: layerRate)
        alone.swapLayers(track: 0, bank: LayerBank.make(
            articulations: [[[loud]]],
            velocityHi: [1], velocityRef: [0.75],
            curve: VelocityCurve.linear.curveTable(), useCurve: false
        ))
        let loudMix = try renderHit(alone, velocity: 0.5, frames: 96)
        let boundary = VoiceEngine(sampleRate: layerRate)
        boundary.swapLayers(track: 0, bank: bank)
        let cross = try renderHit(boundary, velocity: 0.5, frames: 96)
        func maxStep(_ buffer: [Float]) -> Float {
            var step: Float = 0
            let limit = min(buffer.count, Int(0.002 * layerRate))
            guard limit > 1 else { return 0 }
            for index in 1..<limit { step = max(step, abs(buffer[index] - buffer[index - 1])) }
            return step
        }
        #expect(maxStep(cross) <= maxStep(loudMix) * 1.2 + 1e-5)
    }

    @Test func roundRobinRotatesAndRepeatsAcrossEngines() throws {
        var low = [Float](repeating: 0, count: 8)
        low[0] = 0.2
        var high = [Float](repeating: 0, count: 8)
        high[0] = 0.5
        func bank() -> LayerBank {
            LayerBank.make(
                articulations: [[[low, high]]],
                velocityHi: [1], velocityRef: [0.8],
                curve: VelocityCurve.linear.curveTable(), useCurve: false
            )
        }
        func sequence() throws -> [Float] {
            let engine = VoiceEngine(sampleRate: layerRate)
            engine.swapLayers(track: 0, bank: bank())
            var markers: [Float] = []
            let mix = try renderOffline(frames: 300 * 8, chunkFrames: 8, sampleRate: layerRate, beforeChunk: {
                engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 0)
            }) { _ in engine.sourceNode }
            for hit in 0..<300 { markers.append(mix[hit * 8]) }
            return markers
        }
        let first = try sequence()
        let second = try sequence()
        #expect(first.count == 300)
        var lowCount = 0
        var highCount = 0
        var previous = -1
        for (index, marker) in first.enumerated() {
            let kind = marker < 0.25 ? 0 : 1
            if kind == 0 { lowCount += 1 } else { highCount += 1 }
            #expect(kind != previous)
            previous = kind
            #expect(abs(marker - second[index]) < 1e-6)
        }
        #expect(lowCount == 150)
        #expect(highCount == 150)
    }

    @Test func closedArticulationChokesOpenOnTheSameTrack() throws {
        let open = shaped(0.4, count: 4_000)
        let closed = shaped(0.05, count: 64)
        let bank = LayerBank.make(
            articulations: [ [[closed]], [[open]] ],
            velocityHi: [1], velocityRef: [1],
            curve: VelocityCurve.linear.curveTable(), useCurve: false
        )
        let choked = VoiceEngine(sampleRate: layerRate)
        choked.swapLayers(track: 0, bank: bank)
        choked.trigger(track: 0, velocity: 1, chokeGroup: 1, atSample: 0, articulation: 1)
        _ = try renderOffline(frames: 200, chunkFrames: 200, sampleRate: layerRate) { _ in choked.sourceNode }
        choked.trigger(track: 0, velocity: 1, chokeGroup: 1, atSample: 0, articulation: 0)
        let after = try renderOffline(frames: 2_000, chunkFrames: 512, sampleRate: layerRate) { _ in choked.sourceNode }
        let held = VoiceEngine(sampleRate: layerRate)
        held.swapLayers(track: 0, bank: bank)
        held.trigger(track: 0, velocity: 1, chokeGroup: 1, atSample: 0, articulation: 1)
        let sustain = try renderOffline(frames: 2_200, chunkFrames: 512, sampleRate: layerRate) { _ in held.sourceNode }
        let tail = Array(after.dropFirst(400))
        let body = Array(sustain.dropFirst(600))
        #expect(rms(tail) < rms(body) * 0.25)
    }

    @Test func dynamicsLayersStayOrderedFiniteAndDeterministic() throws {
        var preset = SoundPreset(id: UUID(), name: "Layer Kick", filename: "ac_test_kick", category: .kick)
        preset.voice = .kick
        preset.decay = 0.12
        preset.dynamics = Dynamics(
            layers: 4, roundRobin: 2,
            brightness: 0.4, transient: 0.6, pitch: 1.2, decay: 0.4, noise: 0.25, rrDetune: 18
        )
        let bank = DrumSynthesizer.layerBank(for: preset, sampleRate: layerRate)
        let again = DrumSynthesizer.layerBank(for: preset, sampleRate: layerRate)
        #expect(bank.layerCount == 4)
        #expect(bank.roundRobin == 2)
        #expect(bank.useCurve == 1)
        var previousPeak: Float = 0
        var previousRMS: Float = 0
        for layer in 0..<bank.layerCount {
            let left = bank.buffer(articulation: 0, layer: layer, roundRobin: 0)
            let right = bank.buffer(articulation: 0, layer: layer, roundRobin: 1)
            let twin = again.buffer(articulation: 0, layer: layer, roundRobin: 0)
            #expect(left != right)
            #expect(left.count == twin.count)
            var mismatches = 0
            var nonFinite = 0
            for index in left.indices {
                if left[index].bitPattern != twin[index].bitPattern { mismatches += 1 }
                if !left[index].isFinite { nonFinite += 1 }
            }
            #expect(mismatches == 0)
            #expect(nonFinite == 0)
            #expect(left.last == 0)
            var peak: Float = 0
            var sum: Float = 0
            var mean = 0.0
            for sample in left {
                peak = max(peak, abs(sample))
                sum += sample * sample
                mean += Double(sample)
            }
            mean /= Double(left.count)
            #expect(peak <= 0.5 + 0.001)
            #expect(abs(mean) < 1e-3)
            let level = sqrt(sum / Float(left.count))
            #expect(peak + 1e-5 >= previousPeak)
            #expect(level + 1e-5 >= previousRMS)
            previousPeak = peak
            previousRMS = level
            let other = rms(right)
            let db = 20 * log10(Double(max(level, 1e-8) / max(other, 1e-8)))
            #expect(abs(db) <= 0.7)
        }
        let preview = DrumSynthesizer.samples(for: preset, sampleRate: layerRate)
        #expect(preview.last == 0)
        var previewPeak: Float = 0
        for sample in preview {
            #expect(sample.isFinite)
            previewPeak = max(previewPeak, abs(sample))
        }
        #expect(previewPeak <= 0.5 + 0.001)
    }

    @Test func bundledLayerFilesSkipTheSynthRoundRobin() throws {
        var preset = SoundPreset(id: UUID(), name: "Bundled", filename: "ac_test_bundled", category: .kick)
        preset.voice = .kick
        preset.dynamics = Dynamics(curve: .linear, layers: 1, roundRobin: 2)
        preset.articulations = [ArticulationSpec(layerFiles: [["acoustic_kick.wav", "acoustic_kick.wav"]])]
        let bank = DrumSynthesizer.layerBank(for: preset, sampleRate: layerRate)
        let left = bank.buffer(articulation: 0, layer: 0, roundRobin: 0)
        let right = bank.buffer(articulation: 0, layer: 0, roundRobin: 1)
        #expect(left.count > 100)
        #expect(left.count == right.count)
        var peak: Float = 0
        for index in left.indices {
            #expect(left[index].bitPattern == right[index].bitPattern)
            peak = max(peak, abs(left[index]))
        }
        #expect(peak > 0.01)
        #expect(peak <= 0.5 + 0.001)
        #expect(left.last == 0)
    }
}

struct RenderSourceGuardTests {
    @Test func mixerRenderDoesNotAllocateLockOrLog() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DrumMashine_swistUI/DrumMachine/Core/AudioEngine/VoiceEngine.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains("final class Mixer") }) else {
            #expect(Bool(false))
            return
        }
        var body: [String] = []
        for line in lines[start...] {
            if body.count > 2 && line.hasPrefix("nonisolated ") { break }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            body.append(line)
        }
        let source = body.joined(separator: "\n")
        #expect(source.count > 500)
        for token in ["Array(", ".append(", "[Float](", "DispatchQueue", "print(", "AppLog"] {
            #expect(!source.contains(token))
        }
        let regex = try NSRegularExpression(pattern: "(?<![A-Za-z])lock")
        let range = NSRange(source.startIndex..., in: source)
        #expect(regex.firstMatch(in: source, range: range) == nil)
    }
}
