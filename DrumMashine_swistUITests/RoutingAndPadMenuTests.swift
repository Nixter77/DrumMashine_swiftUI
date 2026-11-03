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
            audio.flushPendingRouting()
        }
        var chain = saved
        chain.order = [.compressor, .eq, .reverb, .delay, .distortion]
        audio.effectsChain = chain
        audio.updateEffects()
        audio.flushPendingRouting()
        #expect(audio.connectedChainForTesting().map(ObjectIdentifier.init) == audio.routedNodes(chain.order).map(ObjectIdentifier.init))
        chain.order = EffectsChain.EffectSlot.defaultOrder
        audio.effectsChain = chain
        audio.updateEffects()
        audio.flushPendingRouting()
        #expect(audio.connectedChainForTesting().map(ObjectIdentifier.init) == audio.routedNodes(chain.order).map(ObjectIdentifier.init))
    }

    /// The debounced rewire on a running engine must ramp the master back up over real time,
    /// not jump (the fade task used to cancel itself, so every sleep returned at once).
    @Test func runningRewireFadesInOverRealTime() async throws {
        let audio = AudioEngineManager.shared
        // Engine start is asynchronous after init; give it a moment, then start it directly.
        for _ in 0..<30 where !audio.isEngineRunningForTesting {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if !audio.isEngineRunningForTesting { try? audio.engine.start() }
        try #require(audio.isEngineRunningForTesting, "needs a running engine")
        let saved = audio.effectsChain
        defer {
            audio.effectsChain = saved
            audio.updateEffects()
            audio.flushPendingRouting()
        }
        var chain = saved
        chain.order = [.distortion, .delay, .reverb, .eq, .compressor]
        audio.effectsChain = chain
        // Parallel suites flush routing on the shared engine, and a flush legitimately cancels
        // a running fade. Retry a few times; with the self-cancel bug every attempt is 0 steps.
        for _ in 0..<5 {
            await audio.runFadedRewireForTesting()
            if audio.lastRoutingFadeInSteps == AudioEngineManager.routingFadeSteps { break }
        }
        let duration = try #require(audio.lastRoutingFadeInDuration)
        let stepNanos = Int64(AudioEngineManager.routingFadeStepNanoseconds)
        let minimum = Duration.nanoseconds(stepNanos * Int64(AudioEngineManager.routingFadeSteps))
        #expect(audio.lastRoutingFadeInSteps == AudioEngineManager.routingFadeSteps)
        #expect(duration >= minimum)
        #expect(audio.engine.mainMixerNode.outputVolume == audio.masterVolume)
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

@MainActor
struct RoutingWhileRunningTests {
    /// Re-routing pauses the engine for the rewire and must leave it running as before.
    @Test func rerouteKeepsTheEngineRunningState() {
        let audio = AudioEngineManager.shared
        let saved = audio.effectsChain
        let before = audio.isEngineRunningForTesting
        defer { audio.effectsChain = saved; audio.updateEffects(); audio.flushPendingRouting() }
        var chain = saved
        chain.order = [.eq, .compressor, .reverb, .delay, .distortion]
        audio.effectsChain = chain
        audio.updateEffects()
        audio.flushPendingRouting()
        #expect(audio.isEngineRunningForTesting == before)
        #expect(audio.connectedChainForTesting().map(ObjectIdentifier.init) == audio.routedNodes(chain.order).map(ObjectIdentifier.init))
    }
}


@MainActor
struct RoutingDebounceTests {
    /// A burst of order changes on a running engine costs one rewire, after the burst.
    @Test func burstOfMovesRewiresOnce() {
        let audio = AudioEngineManager.shared
        guard audio.isEngineRunningForTesting else { return }
        let saved = audio.effectsChain
        defer { audio.effectsChain = saved; audio.updateEffects(); audio.flushPendingRouting() }
        let before = audio.routingRewireCount
        var chain = saved
        for _ in 0..<5 {
            chain.move(.compressor, by: -1)
            audio.effectsChain = chain
            audio.updateEffects()
        }
        // No await between the burst and the flush: other suites share the manager.
        #expect(audio.routingRewireCount == before)
        audio.flushPendingRouting()
        #expect(audio.routingRewireCount == before + 1)
        #expect(audio.isEngineRunningForTesting)
        #expect(audio.connectedChainForTesting().map(ObjectIdentifier.init) == audio.routedNodes(chain.order).map(ObjectIdentifier.init))
    }
}
