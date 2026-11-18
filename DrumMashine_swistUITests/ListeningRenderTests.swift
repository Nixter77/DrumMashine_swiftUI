import Accelerate
import Foundation
import Testing
@testable import DrumMashine_swistUI

/// One cached groove hit. File-level so the render closure is not isolated to the main actor.
private struct GrooveHit {
    var art: Int
    var velocityBits: UInt64
    var preset: SoundPreset
}

private final class GrooveHitBox {
    var samples: [Float] = []
}

/// Synthesizes unique hits on the concurrent pool. Each box is written by one iteration.
private func renderGrooveHits(_ jobs: [GrooveHit], sampleRate: Double) -> [[Float]] {
    let boxes = jobs.map { _ in GrooveHitBox() }
    jobs.withUnsafeBufferPointer { jobPointer in
        boxes.withUnsafeBufferPointer { boxPointer in
            DispatchQueue.concurrentPerform(iterations: jobPointer.count) { index in
                let job = jobPointer[index]
                boxPointer[index].samples = DrumSynthesizer.acousticHit(
                    preset: job.preset,
                    velocity: Double(bitPattern: job.velocityBits),
                    articulation: job.art,
                    sampleRate: sampleRate
                )
            }
        }
    }
    return boxes.map(\.samples)
}

/// Writes the §11 listening pack. Runs only when `DRUM_RENDER=1`. Files stay outside the repo.
@MainActor
struct ListeningRenderTests {
    private let rate = 48_000.0

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DRUM_RENDER"] == "1"))
    func writesGrooveRampAndRoundRobinForEachKit() throws {
        let directory = try outputDirectory()
        let patterns = FactoryPatterns.acoustic()
        for (kit, slug) in zip(AcousticKits.kits(), AcousticKits.slugs) {
            print("LISTEN \(slug)")
            let spec = patterns.first {
                $0.kitID == AcousticKits.kitID(slug: slug)
            }
            let pattern = spec.map { FactoryPatterns.makePattern($0) }
            let grooveStarted = CFAbsoluteTimeGetCurrent()
            let mixed = mixGroove(kit, pattern: pattern)
            let mixedAt = CFAbsoluteTimeGetCurrent()
            let groove = scale(mixed)
            try writeFastWav(groove, to: directory.appendingPathComponent("kit_\(slug)_groove.wav"), sampleRate: rate)
            print(String(format: "LISTEN %@ groove %.1fs write %.1fs", slug, mixedAt - grooveStarted, CFAbsoluteTimeGetCurrent() - mixedAt))

            let bankStarted = CFAbsoluteTimeGetCurrent()
            let sounds = Array(kit.sounds.prefix(8))
            let banks = layerBanks(sounds)
            let engine = VoiceEngine(sampleRate: rate)
            for (track, bank) in banks.enumerated() {
                engine.swapLayers(track: track, bank: bank)
            }
            print(String(format: "LISTEN %@ bank %.1fs", slug, CFAbsoluteTimeGetCurrent() - bankStarted))
            let ramp = scale(renderRamp(engine, voices: kit.sounds.count))
            try writeFastWav(ramp, to: directory.appendingPathComponent("kit_\(slug)_velocity_ramp.wav"), sampleRate: rate)
            let robin = scale(renderRoundRobin(engine, track: 1))
            try writeFastWav(robin, to: directory.appendingPathComponent("kit_\(slug)_rr.wav"), sampleRate: rate)
        }
        let names = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
        for slug in AcousticKits.slugs {
            #expect(names.contains("kit_\(slug)_groove.wav"))
            #expect(names.contains("kit_\(slug)_velocity_ramp.wav"))
            #expect(names.contains("kit_\(slug)_rr.wav"))
        }
        let note = directory.path + "\n"
        try note.write(
            to: FileManager.default.temporaryDirectory.appendingPathComponent("ad6-listening-path.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// Eight bars of the kit's factory demo. `acousticHit` keeps articulation, velocity, and the level trim.
    /// Unique hits are synthesized together; the mix itself stays ordered so hat choke still fades the lane.
    private func mixGroove(_ kit: DrumKit, pattern: DrumPattern?) -> [Float] {
        let bpm = pattern?.bpm ?? 100
        let steps = 16
        let bars = 8
        let stepSeconds = 60.0 / bpm / 4.0
        let totalSteps = steps * bars
        let total = Int(stepSeconds * Double(totalSteps) * rate) + Int(1.5 * rate)
        var mix = [Float](repeating: 0, count: max(8, total))

        struct HitKey: Hashable {
            var filename: String
            var art: Int
            var velocityBits: UInt64
        }
        struct Placement {
            var track: Int
            var start: Int
            var key: HitKey
            var choke: Bool
        }
        var jobs: [HitKey: SoundPreset] = [:]
        var placements: [Placement] = []
        for track in kit.sounds.prefix(8).indices {
            let choke = kit.sounds[track].chokeGroup != nil
            let preset = kit.sounds[track]
            for step in 0..<totalSteps {
                let index = step % steps
                let row = pattern?.tracks[track]
                let active = row?.steps.indices.contains(index) == true && row?.steps[index].isActive == true
                guard active, let hitStep = row?.steps[index] else { continue }
                let start = min(mix.count - 1, Int(Double(step) * stepSeconds * rate))
                let art = hitStep.articulation ?? 0
                let velocity = Double(min(1, max(0, hitStep.velocity)))
                let key = HitKey(filename: preset.filename, art: art, velocityBits: velocity.bitPattern)
                placements.append(Placement(track: track, start: start, key: key, choke: choke))
                if jobs[key] == nil { jobs[key] = preset }
            }
        }

        let pairs = jobs.map { entry in
            (key: entry.key, job: GrooveHit(art: entry.key.art, velocityBits: entry.key.velocityBits, preset: entry.value))
        }
        let renderedSamples = renderGrooveHits(pairs.map(\.job), sampleRate: rate)
        var rendered: [HitKey: [Float]] = [:]
        rendered.reserveCapacity(pairs.count)
        for (index, pair) in pairs.enumerated() {
            rendered[pair.key] = renderedSamples[index]
        }

        var lanes = Array(repeating: [Float](repeating: 0, count: mix.count), count: min(8, kit.sounds.count))
        for placement in placements {
            if placement.choke { fadeOut(from: placement.start, in: &lanes[placement.track]) }
            if let hit = rendered[placement.key] {
                add(hit, to: &lanes[placement.track], at: placement.start)
            }
        }
        let frameCount = vDSP_Length(mix.count)
        for lane in lanes {
            mix.withUnsafeMutableBufferPointer { mixPointer in
                lane.withUnsafeBufferPointer { lanePointer in
                    guard let mixBase = mixPointer.baseAddress, let laneBase = lanePointer.baseAddress else { return }
                    vDSP_vadd(mixBase, 1, laneBase, 1, mixBase, 1, frameCount)
                }
            }
        }
        return mix
    }

    /// Eight independent banks. Each build only reads its preset.
    private func layerBanks(_ sounds: [SoundPreset]) -> [LayerBank] {
        let sampleRate = rate
        let lock = NSLock()
        var slots = Array<LayerBank?>(repeating: nil, count: sounds.count)
        sounds.withUnsafeBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: buffer.count) { index in
                let bank = DrumSynthesizer.layerBank(for: buffer[index], sampleRate: sampleRate)
                lock.lock()
                slots[index] = bank
                lock.unlock()
            }
        }
        return slots.compactMap { $0 }
    }

    private func renderRamp(_ engine: VoiceEngine, voices: Int) -> [Float] {
        let gap = Int(0.22 * rate)
        var mix: [Float] = []
        mix.reserveCapacity(voices * 16 * gap)
        for track in 0..<min(8, voices) {
            for step in 0..<16 {
                let velocity = Float(0.1 + 0.9 * Double(step) / 15)
                engine.trigger(track: track, velocity: velocity, chokeGroup: -1, atSample: 0)
                mix.append(contentsOf: render(engine, frames: gap))
            }
        }
        return mix
    }

    private func renderRoundRobin(_ engine: VoiceEngine, track: Int) -> [Float] {
        let gap = Int(0.25 * rate)
        var mix: [Float] = []
        for _ in 0..<8 {
            engine.trigger(track: track, velocity: 0.8, chokeGroup: -1, atSample: 0)
            mix.append(contentsOf: render(engine, frames: gap))
        }
        return mix
    }

    private func render(_ engine: VoiceEngine, frames: Int) -> [Float] {
        var collected: [Float] = []
        collected.reserveCapacity(frames)
        var remaining = frames
        while remaining > 0 {
            let chunk = remaining
            let left = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: chunk)
            left.initialize(repeating: 0, count: chunk)
            right.initialize(repeating: 0, count: chunk)
            engine.renderBlock(frameCount: chunk, left: left, right: right)
            collected.append(contentsOf: UnsafeBufferPointer(start: left, count: chunk))
            left.deinitialize(count: chunk)
            right.deinitialize(count: chunk)
            left.deallocate()
            right.deallocate()
            remaining -= chunk
        }
        return collected
    }

    private func scale(_ samples: [Float]) -> [Float] {
        var copy = samples
        var peak: Float = 0
        for sample in copy { peak = max(peak, abs(sample)) }
        guard peak > 1e-8 else { return copy.isEmpty ? [0] : copy }
        let gain = 0.5 / peak
        for index in copy.indices { copy[index] *= gain }
        if !copy.isEmpty { copy[copy.count - 1] = 0 }
        return copy
    }

    private func fadeOut(from start: Int, in lane: inout [Float]) {
        guard start < lane.count else { return }
        let fade = min(lane.count - start, max(1, Int(0.005 * rate)))
        for index in 0..<fade {
            lane[start + index] *= Float(fade - index) / Float(fade)
        }
        // Stored dynamics hits are at most 1.15 s, so the previous hat's tail ends inside this window.
        let clearEnd = min(lane.count, start + fade + Int(1.20 * rate))
        if start + fade < clearEnd {
            lane.withUnsafeMutableBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                vDSP_vclr(base.advanced(by: start + fade), 1, vDSP_Length(clearEnd - start - fade))
            }
        }
    }

    private func add(_ hit: [Float], to lane: inout [Float], at start: Int) {
        let count = min(hit.count, lane.count - start)
        guard count > 0 else { return }
        lane.withUnsafeMutableBufferPointer { lanePointer in
            hit.withUnsafeBufferPointer { hitPointer in
                guard let laneBase = lanePointer.baseAddress, let hitBase = hitPointer.baseAddress else { return }
                vDSP_vadd(laneBase.advanced(by: start), 1, hitBase, 1, laneBase.advanced(by: start), 1, vDSP_Length(count))
            }
        }
    }

    /// Same 16-bit mono layout as `AudioMetrics.writeWav`, without a Data append per sample.
    private func writeFastWav(_ samples: [Float], to url: URL, sampleRate: Double) throws {
        let dataBytes = samples.count * 2
        var pcm = Data(count: dataBytes)
        pcm.withUnsafeMutableBytes { raw in
            let dest = raw.bindMemory(to: Int16.self)
            for index in samples.indices {
                let clipped = max(-1, min(1, samples[index]))
                dest[index] = Int16(clipped * 32_767).littleEndian
            }
        }
        let rate = UInt32(max(1, sampleRate.rounded()))
        var header = Data()
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        header.append(uint32(UInt32(36 + dataBytes)))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        header.append(uint32(16))
        header.append(uint16(1))
        header.append(uint16(1))
        header.append(uint32(rate))
        header.append(uint32(rate * 2))
        header.append(uint16(2))
        header.append(uint16(16))
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        header.append(uint32(UInt32(dataBytes)))
        header.append(pcm)
        try header.write(to: url)
    }

    private func uint16(_ value: UInt16) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 2)
    }

    private func uint32(_ value: UInt32) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: 4)
    }

    private func outputDirectory() throws -> URL {
        let candidates = [
            URL(fileURLWithPath: "/Users/nikolay/Desktop/DrumMashine_listening", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/DrumMashine_listening"),
            FileManager.default.temporaryDirectory.appendingPathComponent("DrumMashine_listening")
        ]
        for candidate in candidates {
            do {
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
                let probe = candidate.appendingPathComponent(".write-probe")
                try Data("ok".utf8).write(to: probe)
                try? FileManager.default.removeItem(at: probe)
                return candidate
            } catch {
                continue
            }
        }
        throw CocoaError(.fileWriteUnknown)
    }
}
