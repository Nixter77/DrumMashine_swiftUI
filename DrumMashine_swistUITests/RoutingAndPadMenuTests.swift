import AVFoundation
import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct EffectRoutingTests {
    @Test func oldChainWithoutOrderDecodesToDefault() throws {
        let old = #"{"reverb":{"isOn":true},"delay":{},"distortion":{},"eq":{},"compressor":{}}"#
        let chain = try JSONDecoder().decode(EffectsChain.self, from: Data(old.utf8))
        #expect(chain.order == EffectsChain.EffectSlot.defaultOrder)
        #expect(chain.reverb.isOn)
    }

    @Test func orderRoundTripsAndBadOrdersAreRepaired() throws {
        var chain = EffectsChain()
        chain.order = [.reverb, .compressor, .eq, .delay, .distortion]
        let data = try JSONEncoder().encode(chain)
        let back = try JSONDecoder().decode(EffectsChain.self, from: data)
        #expect(back.order == chain.order)
        let broken = #"{"order":["eq","eq","warp","reverb"]}"#
        let repaired = try JSONDecoder().decode(EffectsChain.self, from: Data(broken.utf8))
        #expect(repaired.order == [.eq, .reverb, .distortion, .delay, .compressor])
    }

    @Test func sessionAndSceneKeepTheOrder() throws {
        var chain = EffectsChain()
        chain.move(.compressor, by: -4)
        #expect(chain.order.first == .compressor)
        let scene = EffectScene(id: UUID(), name: "x", chain: chain)
        let back = try JSONDecoder().decode(EffectScene.self, from: JSONEncoder().encode(scene))
        #expect(back.chain.order == chain.order)
    }

    @Test func moveHelpers() {
        var chain = EffectsChain()
        chain.move(.distortion, by: 1)
        #expect(chain.order == [.delay, .distortion, .reverb, .eq, .compressor])
        chain.move(.compressor, before: .delay)
        #expect(chain.order == [.compressor, .delay, .distortion, .reverb, .eq])
        chain.move(.compressor, before: nil)
        #expect(chain.order.last == .compressor)
        chain.setOn(.eq, true)
        #expect(chain.isOn(.eq))
    }

    @Test func graphFollowsTheChosenOrderAndCanReset() {
        let audio = AudioEngineManager.shared
        let saved = audio.effectsChain
        defer {
            audio.effectsChain = saved
            audio.updateEffects()
        }
        var chain = saved
        chain.order = [.compressor, .eq, .reverb, .delay, .distortion]
        audio.effectsChain = chain
        audio.updateEffects()
        #expect(audio.connectedChainForTesting().map(ObjectIdentifier.init) == audio.routedNodes(chain.order).map(ObjectIdentifier.init))
        chain.order = EffectsChain.EffectSlot.defaultOrder
        audio.effectsChain = chain
        audio.updateEffects()
        #expect(audio.connectedChainForTesting().map(ObjectIdentifier.init) == audio.routedNodes(chain.order).map(ObjectIdentifier.init))
    }
}

@MainActor
struct PadSoundMenuTests {
    @Test func hatTrackMenuGroupsSynthAcousticAndUser() {
        var user = AcousticKit.presets()[6]
        user.id = UUID()
        user.origin = .user
        user.name = "My Hat"
        var userKick = AcousticKit.presets()[0]
        userKick.id = UUID()
        let sections = SoundLibraryManager.shared.pickerSections(forTrackVoice: .closedHat, users: [user, userKick])
        #expect(!sections.synth.isEmpty)
        #expect(sections.synth.allSatisfy { $0.source == .synth && [.closedHat, .openHat].contains($0.resolvedVoice) })
        #expect(Set(sections.acoustic.map(\.name)) == ["Real Hat Closed", "Real Hat Open"])
        #expect(sections.user.map(\.name) == ["My Hat"])
    }

    @Test func everyTrackHasSomethingToPick() {
        for index in 0..<8 {
            let voice = SoundLibraryManager.shared.defaultPreset(forTrackIndex: index).resolvedVoice
            let sections = SoundLibraryManager.shared.pickerSections(forTrackVoice: voice, users: [])
            #expect(!sections.synth.isEmpty, "track \(index)")
        }
    }
}
