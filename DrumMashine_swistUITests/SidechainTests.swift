import Foundation
import Testing
@testable import DrumMashine_swistUI

struct SidechainTests {
    @Test func envelopeAttackHoldReleaseShape() {
        var env = SidechainEnvelope(sampleRate: 48_000)
        env.trigger(depth: 0.6, releaseMs: 100)
        var gains: [Float] = []
        for _ in 0..<(144 + 480 + 4_800 + 10) { gains.append(env.next()) }
        // Attack: smooth and monotonic down over 3 ms, no step bigger than a few %.
        #expect(gains[0] > 0.99)
        for i in 1..<144 { #expect(gains[i] <= gains[i - 1] + 1e-6) }
        #expect(zip(gains, gains.dropFirst()).allSatisfy { abs($0 - $1) < 0.02 })
        #expect(abs(gains[143] - 0.4) < 1e-3)
        // Hold at the bottom, then a monotonic release back to unity.
        #expect(abs(gains[300] - 0.4) < 1e-3)
        let mid = gains[144 + 480 + 2_400]
        #expect(mid > 0.6 && mid < 0.8)
        for i in (144 + 480 + 1)..<(144 + 480 + 4_800) { #expect(gains[i] >= gains[i - 1] - 1e-6) }
        #expect(gains.last == 1)
        #expect(env.isIdle)
    }

    @Test func retriggerStartsFromCurrentLevel() {
        var env = SidechainEnvelope(sampleRate: 48_000)
        env.trigger(depth: 0.8, releaseMs: 200)
        for _ in 0..<2_000 { _ = env.next() }
        let before = env.level
        env.trigger(depth: 0.8, releaseMs: 200)
        let first = 1 - env.next()
        #expect(abs(first - before) < 0.02)
    }

    @Test func depthAndVelocityScaling() {
        var s = SidechainSettings()
        s.isOn = true
        s.amount = 0.5
        var p = SidechainParams(packed: s.packed)
        #expect(abs(p.depth(velocity: 1) - 0.5) < 1e-3)
        #expect(abs(p.depth(velocity: 0.5) - 0.25) < 1e-3)
        s.velocityScaling = false
        p = SidechainParams(packed: s.packed)
        #expect(abs(p.depth(velocity: 0.3) - 0.5) < 1e-3)
        #expect(p.releaseMs == 180)
    }

    @Test func maskNeverDucksTheSource() {
        var s = SidechainSettings()
        s.isOn = true
        s.sourceTrack = 3
        s.ducked[5] = false
        let p = SidechainParams(packed: s.packed)
        #expect(!p.ducks(track: 3))
        #expect(!p.ducks(track: 5))
        #expect(p.ducks(track: 0) && p.ducks(track: 7))
        #expect(!p.ducks(track: 8))
        #expect(s.duckMask.nonzeroBitCount == 6)
        s.isOn = false
        #expect(!SidechainParams(packed: s.packed).ducks(track: 0))
    }

    @Test func persistenceAndOldSessions() throws {
        let old = try JSONDecoder().decode(EffectsChain.self, from: Data(#"{"reverb":{"isOn":true}}"#.utf8))
        #expect(old.sidechain == SidechainSettings())
        #expect(!old.sidechain.isOn)
        var chain = EffectsChain()
        chain.sidechain.isOn = true
        chain.sidechain.sourceTrack = 1
        chain.sidechain.amount = 0.7
        chain.sidechain.ducked[2] = false
        let data = try JSONEncoder().encode(chain)
        let back = try JSONDecoder().decode(EffectsChain.self, from: data)
        #expect(back.sidechain == chain.sidechain)
        let scene = EffectScene(id: UUID(), name: "p", chain: chain)
        let sceneData = try JSONEncoder().encode(scene)
        #expect(try JSONDecoder().decode(EffectScene.self, from: sceneData).chain.sidechain == chain.sidechain)
        var preset = SidechainSettings()
        SidechainSettings.presets[0].apply(to: &preset)
        #expect(preset.isOn && preset.amount == 0.8)
    }

    /// Track 1 holds a steady tone; a kick on track 0 must dip it right after the hit and let it recover.
    @Test func offlineRenderDucksAndRecovers() throws {
        let tone = (0..<96_000).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) * 0.3 }
        var click = [Float](repeating: 0, count: 64)
        click[0] = 0.01
        func run(_ on: Bool) throws -> [Float] {
            try renderVoices(frames: 48_000) { engine in
                engine.swapSample(track: 0, samples: click)
                engine.swapSample(track: 1, samples: tone)
                var s = SidechainSettings()
                s.isOn = on
                s.amount = 0.8
                s.releaseMs = 150
                s.velocityScaling = false
                engine.setSidechain(s)
                engine.trigger(track: 1, velocity: 1, chokeGroup: -1, atSample: 0)
                engine.trigger(track: 0, velocity: 1, chokeGroup: -1, atSample: 9_600)
            }
        }
        func rms(_ x: [Float], _ r: Range<Int>) -> Float {
            sqrt(x[r].reduce(0) { $0 + $1 * $1 } / Float(r.count))
        }
        let dry = try run(false)
        let wet = try run(true)
        let before = 8_000..<9_400
        let dip = 9_900..<10_300
        let after = 30_000..<31_000
        #expect(abs(rms(wet, before) - rms(dry, before)) < 0.005)
        #expect(rms(wet, dip) < rms(dry, dip) * 0.4)
        #expect(abs(rms(wet, after) - rms(dry, after)) < 0.01)
    }
}
