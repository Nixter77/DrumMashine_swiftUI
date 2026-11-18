import Foundation
import Testing
@testable import DrumMashine_swistUI

/// T-LVL-1, T-LVL-3, T-LVL-4, T-LVL-5, T-PERF-1…3.
/// Drives `DrumSynthesizer.layerBank`, `acousticHit`, and `VoiceEngine`.
struct AcousticBudgetTests {
    private let rate = 48_000.0

    @Test func layerBanksStayInsideLevelMemoryAndTimeBudgets() {
        let clock = ContinuousClock()
        var notes: [String] = []
        var misses: [String] = []
        for (kit, slug) in zip(AcousticKits.kits(), AcousticKits.slugs) {
            var slowestPreview = 0.0
            var slowName = ""
            for preset in kit.sounds {
                let started = clock.now
                _ = DrumSynthesizer.samples(for: preset, sampleRate: rate)
                let elapsed = seconds(from: started, to: clock.now)
                if elapsed > slowestPreview {
                    slowestPreview = elapsed
                    slowName = preset.filename
                }
            }
            notes.append(String(format: "PREVIEW %@ %.3f s %@", slug, slowestPreview, slowName))
            if slowestPreview > 0.200 {
                misses.append(String(format: "%@ first layer %.3f s (%@)", slug, slowestPreview, slowName))
            }

            var banks: [LayerBank] = []
            var bytes = 0
            var largest = 0
            let bankStarted = clock.now
            for preset in kit.sounds {
                let bank = DrumSynthesizer.layerBank(for: preset, sampleRate: rate)
                let size = bank.storageCount * MemoryLayout<Float>.size
                bytes += size
                largest = max(largest, size)
                banks.append(bank)
                misses.append(contentsOf: inspect(bank, filename: preset.filename))
            }
            let bankSeconds = seconds(from: bankStarted, to: clock.now)
            let megabytes = Double(bytes) / 1_048_576
            notes.append(String(format: "BANK %@ %.3f s %.2f MB", slug, bankSeconds, megabytes))
            if bytes > 48 * 1_048_576 {
                misses.append(String(format: "%@ buffers %.2f MB", slug, megabytes))
            }
            if bytes + largest > 64 * 1_048_576 {
                misses.append(String(format: "%@ engine %.2f MB", slug, Double(bytes + largest) / 1_048_576))
            }
            #if arch(arm64)
            let renderBudget = 2.5
            #else
            let renderBudget = 180.0
            #endif
            if bankSeconds > renderBudget {
                misses.append(String(format: "%@ render %.3f s", slug, bankSeconds))
            }

            let engine = VoiceEngine(sampleRate: rate)
            for (track, bank) in banks.enumerated() {
                engine.swapLayers(track: track, bank: bank)
                engine.trigger(track: track, velocity: 1, chokeGroup: -1, atSample: 0)
            }
            let frames = 8_192
            let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            left.initialize(repeating: 0, count: frames)
            right.initialize(repeating: 0, count: frames)
            engine.renderBlock(frameCount: frames, left: left, right: right)
            let peak = engine.consumePreLimiterPeak()
            left.deinitialize(count: frames)
            right.deinitialize(count: frames)
            left.deallocate()
            right.deallocate()
            notes.append(String(format: "SUM %@ peak %.4f", slug, peak))
            if peak > 0.951 {
                misses.append(String(format: "%@ eight-track peak %.4f", slug, peak))
            }
        }
        writeMetrics(notes)
        #expect(misses.isEmpty, "\(misses.prefix(10).joined(separator: " | "))")
    }

    @Test func referenceGrooveStaysWithinOneAndAHalfDecibels() {
        let quiet: Set<String> = ["Brushes Ballad", "Orchestral"]
        var rows: [(name: String, lufs: Double)] = []
        for kit in AcousticKits.kits() {
            let mix = referenceGroove(kit)
            rows.append((kit.name, AudioMetrics.pseudoLUFS(mix, sampleRate: rate)))
        }
        let normal = rows.filter { !quiet.contains($0.name) }.map(\.lufs).sorted()
        let median = (normal[normal.count / 2 - 1] + normal[normal.count / 2]) / 2
        var misses: [String] = []
        var lines: [String] = []
        for row in rows {
            let delta = row.lufs - median
            lines.append(String(format: "GROOVE %@ %+.2f (abs %.2f)", row.name, delta, row.lufs))
            if quiet.contains(row.name) {
                if delta > 0.05 || delta < -6 { misses.append(lines.last ?? row.name) }
            } else if abs(delta) > 1.5 {
                misses.append(lines.last ?? row.name)
            }
        }
        writeMetrics(lines)
        #expect(misses.isEmpty, "\(misses.joined(separator: " | "))")
    }

    @Test func thirtyTwoCrossfadingVoicesStayInsideTheBlockBudget() {
        let frames = 512
        let quiet = tone(0.08, count: 16_384)
        let loud = tone(DrumSynthesizer.dynamicsBufferPeak, count: 16_384)
        let bank = LayerBank.make(
            articulations: [[[quiet], [loud]]],
            velocityHi: [0.5, 1],
            velocityRef: [0.25, 0.75],
            curve: VelocityCurve.db(range: 30, shape: 1).curveTable(),
            useCurve: true
        )
        let engine = VoiceEngine(sampleRate: rate)
        for track in 0..<8 {
            engine.swapLayers(track: track, bank: bank)
            for _ in 0..<4 {
                engine.trigger(track: track, velocity: 0.5, chokeGroup: -1, atSample: 0)
            }
        }
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
        #expect(engine.activeVoiceCount == 32)
        let rounds = 20
        let clock = ContinuousClock()
        let started = clock.now
        for _ in 0..<rounds {
            engine.renderBlock(frameCount: frames, left: left, right: right)
        }
        let elapsed = seconds(from: started, to: clock.now)
        let perBlock = elapsed / Double(rounds)
        let limit = (Double(frames) / rate) * 0.25
        writeMetrics([String(format: "BLOCK %.3f ms limit %.3f ms", perBlock * 1_000, limit * 1_000)])
        #expect(perBlock <= limit, "\(String(format: "block %.3f ms", perBlock * 1_000))")
    }

    private func inspect(_ bank: LayerBank, filename: String) -> [String] {
        var misses: [String] = []
        let window = Int(0.050 * rate)
        let cap = DrumSynthesizer.dynamicsBufferPeak + 0.002
        for art in 0..<bank.articulationCount {
            var previousRMS: Float = -1
            var previousCentroid = 0.0
            for layer in 0..<bank.layerCount {
                let left = bank.buffer(articulation: art, layer: layer, roundRobin: 0)
                let stats = bufferStats(left)
                if stats.nonFinite > 0 || left.last != 0 || abs(stats.mean) >= 1e-3 || stats.peak > cap {
                    misses.append("\(filename) a\(art) l\(layer) peak \(stats.peak) mean \(stats.mean) nan \(stats.nonFinite)")
                }
                if bank.roundRobin >= 2 {
                    let right = bank.buffer(articulation: art, layer: layer, roundRobin: 1)
                    if AudioMetrics.sha256Hex(left) == AudioMetrics.sha256Hex(right) {
                        misses.append("\(filename) a\(art) l\(layer) rr hash")
                    }
                    let other = AudioMetrics.rms(right)
                    let db = 20 * log10(Double(max(stats.rms, 1e-8) / max(other, 1e-8)))
                    if abs(db) > 0.7 {
                        misses.append(String(format: "%@ a%d l%d rr %.2f dB", filename, art, layer, db))
                    }
                    let corr = correlation(left, right, count: window)
                    if corr >= 0.995 || corr <= 0.6 {
                        misses.append(String(format: "%@ a%d l%d corr %.4f", filename, art, layer, corr))
                    }
                }
                if layer > 0, previousRMS > 0 {
                    let db = 20 * log10(Double(max(stats.rms, 1e-8) / max(previousRMS, 1e-8)))
                    let centroid = AudioMetrics.spectralCentroid(left, sampleRate: rate)
                    let span = max(centroid, previousCentroid, 1)
                    let ratio = abs(centroid - previousCentroid) / span
                    if abs(db) > 4 {
                        misses.append(String(format: "%@ a%d l%d step %.2f dB", filename, art, layer, db))
                    }
                    if ratio > 0.35 {
                        misses.append(String(format: "%@ a%d l%d centroid %.2f", filename, art, layer, ratio))
                    }
                }
                previousRMS = stats.rms
                previousCentroid = AudioMetrics.spectralCentroid(left, sampleRate: rate)
            }
        }
        return misses
    }

    /// Eight bars, same grid on every kit: kick, snare, hat, one ghost, one crash.
    private func referenceGroove(_ kit: DrumKit) -> [Float] {
        let bpm = 100.0
        let bars = 8
        let stepsPerBar = 16
        let stepSeconds = 60.0 / bpm / 4.0
        let totalSteps = bars * stepsPerBar
        let total = Int(stepSeconds * Double(totalSteps) * rate) + Int(rate)
        var mix = [Float](repeating: 0, count: total)
        var cache: [String: [Float]] = [:]
        func place(track: Int, step: Int, velocity: Double) {
            let preset = kit.sounds[track]
            let key = "\(preset.filename)|\(velocity)"
            let hit: [Float]
            if let cached = cache[key] {
                hit = cached
            } else {
                hit = DrumSynthesizer.acousticHit(
                    preset: preset, velocity: velocity, sampleRate: rate
                )
                cache[key] = hit
            }
            let start = min(total - 1, Int(Double(step) * stepSeconds * rate))
            let count = min(hit.count, total - start)
            guard count > 0 else { return }
            for index in 0..<count { mix[start + index] += hit[index] }
        }
        for bar in 0..<bars {
            let base = bar * stepsPerBar
            if bar == 0 { place(track: 6, step: base, velocity: 0.9) }
            for beat in [0, 8] { place(track: 0, step: base + beat, velocity: 0.85) }
            for beat in [4, 12] { place(track: 1, step: base + beat, velocity: 0.9) }
            place(track: 1, step: base + 6, velocity: 0.35)
            for step in stride(from: 0, to: stepsPerBar, by: 2) {
                place(track: 2, step: base + step, velocity: 0.7)
            }
        }
        return mix
    }

    private func tone(_ amplitude: Float, count: Int) -> [Float] {
        var buffer = [Float](repeating: 0, count: count)
        let step = Float(2 * Double.pi * 440 / rate)
        for index in buffer.indices {
            buffer[index] = amplitude * sin(step * Float(index))
        }
        buffer[buffer.count - 1] = 0
        return buffer
    }

    private func bufferStats(_ buffer: [Float]) -> (peak: Float, rms: Float, mean: Double, nonFinite: Int) {
        guard !buffer.isEmpty else { return (0, 0, 0, 0) }
        var peak: Float = 0
        var mean = 0.0
        var nonFinite = 0
        for sample in buffer {
            if sample.isFinite {
                mean += Double(sample)
                peak = max(peak, abs(sample))
            } else {
                nonFinite += 1
            }
        }
        mean /= Double(buffer.count)
        return (peak, AudioMetrics.rms(buffer), mean, nonFinite)
    }

    private func correlation(_ a: [Float], _ b: [Float], count: Int) -> Double {
        let n = min(count, a.count, b.count)
        guard n > 8 else { return 0 }
        var dot = 0.0
        var aa = 0.0
        var bb = 0.0
        for index in 0..<n {
            let x = Double(a[index])
            let y = Double(b[index])
            dot += x * y
            aa += x * x
            bb += y * y
        }
        let denom = (aa * bb).squareRoot()
        guard denom > 1e-12 else { return 0 }
        return dot / denom
    }

    private func seconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        start.duration(to: end) / Duration.seconds(1)
    }

    private func writeMetrics(_ lines: [String]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ad6-budget-metrics.txt")
        let prior = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let text = prior + lines.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
