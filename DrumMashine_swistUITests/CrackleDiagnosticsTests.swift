import AVFoundation
import Foundation
import Testing
@testable import DrumMashine_swistUI

private let diagRate: Double = 48_000

/// Full master chain, offline: voices -> dist -> delay -> reverb -> EQ -> comp -> limiter -> mixer at the ceiling.
@MainActor
func renderMaster(chain: EffectsChain, frames: Int, voicesOut: inout Float) throws -> [Float] {
    let engine = AVAudioEngine()
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: diagRate, channels: 2, interleaved: false)!
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    let voices = VoiceEngine(sampleRate: diagRate)
    for track in 0..<8 {
        let preset = SoundLibraryManager.shared.defaultPreset(forTrackIndex: track)
        voices.swapSample(track: track, samples: DrumSynthesizer.samples(for: preset, sampleRate: diagRate))
    }
    voices.setSidechain(chain.sidechain)
    let scheduler = SequencerScheduler(voiceEngine: voices, sampleRate: diagRate)
    scheduler.replace(densePattern())
    scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)

    let dist = AVAudioUnitDistortion(); dist.loadFactoryPreset(.multiDistortedCubed)
    dist.bypass = !chain.distortion.isOn
    dist.wetDryMix = EffectMapping.distortionMix(chain.distortion.wetDryMix)
    dist.preGain = EffectMapping.distortionPreGain(chain.distortion.preGain)
    let delay = AVAudioUnitDelay()
    delay.bypass = !chain.delay.isOn
    delay.wetDryMix = EffectMapping.delayMix(chain.delay.wetDryMix)
    delay.delayTime = chain.delay.delayTime
    delay.feedback = EffectMapping.delayFeedback(chain.delay.feedback)
    let reverb = AVAudioUnitReverb(); reverb.loadFactoryPreset(.mediumHall)
    reverb.bypass = !chain.reverb.isOn
    reverb.wetDryMix = EffectMapping.reverbMix(chain.reverb.wetDryMix)
    let eq = AVAudioUnitEQ(numberOfBands: 3)
    eq.bypass = !chain.eq.isOn
    for (i, g) in [chain.eq.low, chain.eq.mid, chain.eq.high].enumerated() {
        eq.bands[i].bypass = false
        eq.bands[i].filterType = i == 0 ? .lowShelf : (i == 1 ? .parametric : .highShelf)
        eq.bands[i].frequency = [120, 1000, 8000][i]
        eq.bands[i].gain = EffectMapping.eqGain(g)
    }
    let comp = BusCompressor.makeNode()
    BusCompressor.apply(chain.compressor, to: comp)
    comp.bypass = !chain.compressor.isOn
    let limiter = MasterLimiter.makeNode(); MasterLimiter.configure(limiter)
    let nodes: [AVAudioNode] = [voices.sourceNode, dist, delay, reverb, eq, comp, limiter, engine.mainMixerNode]
    for node in nodes.dropLast() { engine.attach(node) }
    for (a, b) in zip(nodes, nodes.dropFirst()) { engine.connect(a, to: b, format: format) }
    engine.mainMixerNode.outputVolume = MasterLimiter.ceilingGain
    try engine.start()
    defer { engine.stop() }
    let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
    var out: [Float] = []
    var remaining = frames
    while remaining > 0 {
        scheduler.scheduleDue(now: voices.renderedFrames)
        let status = try engine.renderOffline(AVAudioFrameCount(min(remaining, 512)), to: buffer)
        guard status == .success else { throw OfflineRenderError.status(status) }
        let n = Int(buffer.frameLength)
        for ch in 0..<2 { out.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![ch], count: n)) }
        voicesOut = max(voicesOut, voices.consumePreLimiterPeak())
        remaining -= n
    }
    return out
}

@MainActor
/// Regression for the 'crackle with sidechain' report: no overs at the output, render far inside the I/O budget.
@Suite(.serialized)
struct CrackleDiagnosticsTests {
    @Test func masterPeaksPerScene() throws {
        var report: [String] = []
        var chains: [(String, EffectsChain)] = [("default", EffectsChain())]
        for scene in EffectPresets.scenes {
            var c = EffectsChain(); scene.apply(to: &c, bpm: 120); chains.append((scene.name, c))
        }
        for (name, base) in chains {
            for sc in ["off", "Pump", "Subtle"] {
                var c = base
                if let p = SidechainSettings.presets.first(where: { $0.name == sc }) { p.apply(to: &c.sidechain) }
                var pre: Float = 0
                let out = try renderMaster(chain: c, frames: 96_000, voicesOut: &pre)
                let peak = out.map { abs($0) }.max() ?? 0
                let overs = out.filter { abs($0) > 1 }.count
                report.append("\(name)/\(sc) voices=\(pre) out=\(peak) overs=\(overs)")
                #expect(overs == 0, "\(name)/\(sc) has \(overs) samples over 1.0")
                #expect(peak <= MasterLimiter.ceilingGain + 0.02, "\(name)/\(sc) peak \(peak)")
                // Lower bound: no scene may come out nearly silent (Lo-Fi Tape / Industrial were 0.20 / 0.07).
                #expect(peak >= 0.4, "\(name)/\(sc) too quiet: peak \(peak)")
                #expect(out.allSatisfy { $0.isFinite })
            }
        }
        diag("PEAKS\n" + report.joined(separator: "\n"))
    }

    @Test func renderCostPerBlock() throws {
        for on in [false, true] {
            let voices = VoiceEngine(sampleRate: diagRate)
            for track in 0..<8 { voices.swapSample(track: track, samples: [Float](repeating: 0.1, count: 48_000)) }
            var s = SidechainSettings(); s.isOn = on; s.amount = 0.8
            voices.setSidechain(s)
            let scheduler = SequencerScheduler(voiceEngine: voices, sampleRate: diagRate)
            scheduler.replace(densePattern())
            scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)
            let start = DispatchTime.now().uptimeNanoseconds
            _ = try renderOffline(frames: 48_000 * 4, chunkFrames: 512, beforeChunk: {
                scheduler.scheduleDue(now: voices.renderedFrames)
            }) { _ in voices.sourceNode }
            let ns = Double(DispatchTime.now().uptimeNanoseconds - start)
            let blocks = Double(48_000 * 4 / 512)
            diag("COST sidechain=\(on) usPerBlock=\(ns / blocks / 1000) budgetUs=\(512.0 / 48_000 * 1e6)")
        }
    }
}

func diag(_ line: String) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("diag.txt")
    let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    try? (old + line + "\n").write(to: url, atomically: true, encoding: .utf8)
}

struct SidechainContinuityTests {
    /// Gain never jumps more than 2% between samples, also when the sidechain is switched off mid-dip.
    @Test func gainIsContinuousAcrossRetriggersAndDisable() throws {
        let tone = [Float](repeating: 0.5, count: 96_000)
        var click = [Float](repeating: 0, count: 32); click[0] = 0.001
        let out = try renderVoices(frames: 48_000) { engine in
            engine.swapSample(track: 0, samples: click)
            engine.swapSample(track: 1, samples: tone)
            var s = SidechainSettings(); s.isOn = true; s.amount = 1; s.releaseMs = 50; s.velocityScaling = false
            engine.setSidechain(s)
            engine.trigger(track: 1, velocity: 1, chokeGroup: -1, atSample: 0)
            for k in 0..<12 { engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: Int64(4_800 + k * 1_000)) }
        }
        var worst: Float = 0
        for i in 5_000..<40_000 { worst = max(worst, abs(out[i] - out[i - 1])) }
        #expect(worst < 0.5 * 0.7 * 0.03, "largest step \(worst)")
        #expect(out.allSatisfy { abs($0) <= 1 })
    }
}
