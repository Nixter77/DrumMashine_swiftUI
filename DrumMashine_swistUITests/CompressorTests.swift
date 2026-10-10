import Foundation
import Testing
@testable import DrumMashine_swistUI

struct CompressorTests {
    @Test func presetsAreValidAndApply() {
        #expect(EffectPresets.compressor.count == 6)
        #expect(Set(EffectPresets.compressor.map(\.id)).count == 6)
        for p in EffectPresets.compressor {
            #expect((-40...0).contains(p.threshold))
            #expect((0...1).contains(p.amount))
            #expect((0.1...200).contains(p.attackMs))
            #expect((10...1000).contains(p.releaseMs))
            #expect((0...20).contains(p.makeup))
        }
        var chain = EffectsChain()
        EffectPresets.compressorPreset("comp.punch").apply(to: &chain, bpm: 120)
        #expect(chain.compressor.isOn && chain.compressor.threshold == -20)
    }

    @Test func amountMapsToHeadroom() {
        #expect(BusCompressor.headroom(amount: 0) == 30)
        #expect(BusCompressor.headroom(amount: 1) == 1)
        #expect(BusCompressor.headroom(amount: 2) == 1)
    }

    @Test func oldChainDecodesWithCompressorOff() throws {
        let json = #"{"reverb":{"isOn":true}}"#.data(using: .utf8)!
        let chain = try JSONDecoder().decode(EffectsChain.self, from: json)
        #expect(chain.compressor == EffectsChain.CompressorSettings())
        #expect(chain.compressor.isOn == false)
    }

    @Test func scenesSetTheCompressor() {
        var chain = EffectsChain()
        EffectPresets.scenes.first { $0.id == "scene.club" }!.apply(to: &chain, bpm: 120)
        #expect(chain.compressor.isOn)
        EffectPresets.scenes.first { $0.id == "scene.clean" }!.apply(to: &chain, bpm: 120)
        #expect(chain.compressor.isOn == false)
    }
}
