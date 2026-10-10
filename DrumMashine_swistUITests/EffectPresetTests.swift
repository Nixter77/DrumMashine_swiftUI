import Foundation
import Testing
@testable import DrumMashine_swistUI

struct EffectPresetTests {
    @Test func countsAndIDs() {
        #expect(EffectPresets.reverb.count == 5)
        #expect(EffectPresets.delay.count == 5)
        #expect(EffectPresets.distortion.count == 4)
        #expect(EffectPresets.eq.count == 5)
        #expect(EffectPresets.scenes.count == 6)
        let ids = EffectPresets.reverb.map(\.id)
            + EffectPresets.delay.map(\.id)
            + EffectPresets.distortion.map(\.id)
            + EffectPresets.eq.map(\.id)
            + EffectPresets.scenes.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { !$0.isEmpty })
    }

    @Test func presetsMatchTheTableAndLeaveOtherBlocksAlone() {
        expectReverb("Room", room: .smallRoom, mix: 0.20)
        expectReverb("Studio", room: .mediumRoom, mix: 0.25)
        expectReverb("Big Room", room: .largeRoom, mix: 0.30)
        expectReverb("Hall", room: .mediumHall, mix: 0.35)
        expectReverb("Cathedral", room: .largeHall, mix: 0.50)

        expectDelay("Slapback", bpm: 120, time: 0.09, feedback: 10, mix: 0.25, lowPass: 8000)
        expectDelay("1/16", bpm: 60, time: 0.25, feedback: 25, mix: 0.20, lowPass: 12000)
        expectDelay("1/8", bpm: 120, time: 0.25, feedback: 35, mix: 0.25, lowPass: 10000)
        expectDelay("1/4 Dotted", bpm: 120, time: 0.375, feedback: 40, mix: 0.25, lowPass: 9000)
        expectDelay("Dub", bpm: 120, time: 0.375, feedback: 70, mix: 0.35, lowPass: 3000)

        expectDistortion("Warm", mix: 0.15, preGain: -10)
        expectDistortion("Crunch", mix: 0.35, preGain: 0)
        expectDistortion("Fuzz", mix: 0.60, preGain: 10)
        expectDistortion("Destroy", mix: 0.85, preGain: 18)

        expectEQ("Punch", low: 4, mid: -2, high: 2)
        expectEQ("Bright", low: 0, mid: 0, high: 5)
        expectEQ("Scoop", low: 3, mid: -5, high: 3)
        expectEQ("Warm", low: 3, mid: 0, high: -4)
        expectEQ("Telephone", low: -12, mid: 6, high: -12)
    }

    @Test func slowTempoClampsDelay() {
        var chain = seeded()
        EffectPresets.delayPreset("delay.dub").apply(to: &chain, bpm: 20)
        #expect(chain.delay.delayTime == 2)
        EffectPresets.delayPreset("delay.1_16").apply(to: &chain, bpm: 10_000)
        #expect(chain.delay.delayTime == 0.05)
    }

    @Test func cleanTurnsBlocksOffWithoutTouchingValues() {
        var chain = seeded()
        let before = chain
        scene("Clean").apply(to: &chain, bpm: 120)
        #expect(chain.reverb.isOn == false)
        #expect(chain.delay.isOn == false)
        #expect(chain.distortion.isOn == false)
        #expect(chain.eq.isOn == false)
        #expect(chain.reverb.wetDryMix == before.reverb.wetDryMix)
        #expect(chain.reverb.room == before.reverb.room)
        #expect(chain.delay.delayTime == before.delay.delayTime)
        #expect(chain.delay.feedback == before.delay.feedback)
        #expect(chain.distortion.preGain == before.distortion.preGain)
        #expect(chain.eq.low == before.eq.low)
        #expect(chain.eq.mid == before.eq.mid)
        #expect(chain.eq.high == before.eq.high)
    }

    @Test func scenesCombinePresets() {
        var club = seeded()
        scene("Club").apply(to: &club, bpm: 120)
        #expect(club.reverb.isOn)
        #expect(club.reverb.room == .smallRoom)
        #expect(club.reverb.wetDryMix == 0.15)
        #expect(club.delay.isOn == false)
        #expect(club.distortion.isOn == false)
        #expect(club.eq.isOn)
        #expect(club.eq.low == 4)
        #expect(club.eq.mid == -2)
        #expect(club.eq.high == 2)
        #expect(club.delay.delayTime == 1.1)

        var tape = seeded()
        scene("Lo-Fi Tape").apply(to: &tape, bpm: 120)
        #expect(tape.reverb.isOn)
        #expect(tape.reverb.wetDryMix == 0.15)
        #expect(tape.delay.isOn == false)
        #expect(tape.distortion.isOn)
        #expect(tape.distortion.wetDryMix == 0.15)
        #expect(tape.distortion.preGain == -10)
        #expect(tape.eq.isOn)
        #expect(tape.eq.low == 2)
        #expect(tape.eq.mid == 1)
        #expect(tape.eq.high == -8)

        var dub = seeded()
        scene("Dub").apply(to: &dub, bpm: 120)
        #expect(dub.reverb.isOn)
        #expect(dub.reverb.room == .mediumHall)
        #expect(dub.reverb.wetDryMix == 0.35)
        #expect(dub.delay.isOn)
        #expect(dub.delay.delayTime == 0.375)
        #expect(dub.delay.feedback == 70)
        #expect(dub.distortion.isOn == false)
        #expect(dub.distortion.preGain == 7)
        #expect(dub.eq.isOn)
        #expect(dub.eq.low == 3)
        #expect(dub.eq.high == -4)

        var industrial = seeded()
        scene("Industrial").apply(to: &industrial, bpm: 120)
        #expect(industrial.reverb.room == .largeRoom)
        #expect(industrial.reverb.wetDryMix == 0.25)
        #expect(industrial.delay.delayTime == 0.125)
        #expect(industrial.distortion.wetDryMix == 0.60)
        #expect(industrial.distortion.preGain == 10)
        #expect(industrial.eq.mid == -5)
        #expect(industrial.reverb.isOn && industrial.delay.isOn && industrial.distortion.isOn && industrial.eq.isOn)

        var ambient = seeded()
        scene("Ambient").apply(to: &ambient, bpm: 120)
        #expect(ambient.reverb.room == .largeHall)
        #expect(ambient.reverb.wetDryMix == 0.50)
        #expect(ambient.delay.delayTime == 0.375)
        #expect(ambient.delay.feedback == 40)
        #expect(ambient.distortion.isOn == false)
        #expect(ambient.eq.isOn == false)
        #expect(ambient.eq.low == 1)
    }

    @Test func eighthNoteDelayFollowsTheTempo() {
        var chain = EffectsChain()
        EffectPresets.delayPreset("delay.1_8").apply(to: &chain, bpm: 120)
        #expect(chain.delay.syncBeats == 0.5)
        #expect(chain.delay.delayTime == 0.25)
        chain.delay.retime(bpm: 90)
        let expected = EffectPresets.delaySeconds(beats: 0.5, bpm: 90)
        #expect(chain.delay.delayTime == expected)
        #expect(abs(chain.delay.delayTime - 0.333) < 0.001)
        #expect(EffectPresets.delayFractionLabel(beats: 0.5) == "1/8")
        #expect(EffectPresets.delayFractionLabel(beats: 0.25) == "1/16")
        #expect(EffectPresets.delayFractionLabel(beats: 0.75) == "1/4.")
    }

    @Test func manualTimeStopsFollowingTheTempo() {
        var chain = EffectsChain()
        EffectPresets.delayPreset("delay.1_8").apply(to: &chain, bpm: 120)
        chain.delay.applyManualTime(0.42)
        #expect(chain.delay.syncBeats == nil)
        chain.delay.retime(bpm: 90)
        #expect(chain.delay.delayTime == 0.42)

        EffectPresets.delayPreset("delay.slapback").apply(to: &chain, bpm: 80)
        #expect(chain.delay.syncBeats == nil)
        #expect(chain.delay.delayTime == 0.09)
        chain.delay.retime(bpm: 60)
        #expect(chain.delay.delayTime == 0.09)
    }

    @Test func oldSessionWithoutSyncBeatsDecodes() throws {
        let json = """
        {"bpm":110,"effectsChain":{"delay":{"isOn":true,"wetDryMix":0.25,"delayTime":0.5,"feedback":12,"lowPassCutoff":4000}}}
        """
        let state = try JSONDecoder().decode(SessionState.self, from: Data(json.utf8))
        #expect(state.bpm == 110)
        #expect(state.effectsChain.delay.syncBeats == nil)
        #expect(state.effectsChain.delay.isOn)
        #expect(state.effectsChain.delay.delayTime == 0.5)
        #expect(state.effectsChain.delay.feedback == 12)
        #expect(state.effectsChain.delay.wetDryMix == 0.25)
        #expect(state.effectsChain.delay.lowPassCutoff == 4000)
        #expect(state.effectsChain.reverb == EffectsChain.ReverbSettings())

        let encoded = try JSONEncoder().encode(state.effectsChain.delay)
        let decoded = try JSONDecoder().decode(EffectsChain.DelaySettings.self, from: encoded)
        #expect(decoded == state.effectsChain.delay)
    }

    private func expectReverb(_ name: String, room: EffectsChain.ReverbRoom, mix: Float) {
        var chain = seeded()
        let before = chain
        let preset = EffectPresets.reverb.first { $0.name == name }!
        preset.apply(to: &chain, bpm: 100)
        #expect(chain.reverb.isOn)
        #expect(chain.reverb.room == room)
        #expect(chain.reverb.wetDryMix == mix)
        #expect(chain.delay == before.delay)
        #expect(chain.distortion == before.distortion)
        #expect(chain.eq == before.eq)
    }

    private func expectDelay(_ name: String, bpm: Double, time: Double, feedback: Float, mix: Float, lowPass: Float) {
        var chain = seeded()
        let before = chain
        let preset = EffectPresets.delay.first { $0.name == name }!
        preset.apply(to: &chain, bpm: bpm)
        #expect(chain.delay.isOn)
        #expect(chain.delay.delayTime == time)
        #expect(chain.delay.feedback == feedback)
        #expect(chain.delay.wetDryMix == mix)
        #expect(chain.delay.lowPassCutoff == lowPass)
        #expect(chain.delay.syncBeats == preset.beats)
        #expect(chain.reverb == before.reverb)
        #expect(chain.distortion == before.distortion)
        #expect(chain.eq == before.eq)
    }

    private func expectDistortion(_ name: String, mix: Float, preGain: Float) {
        var chain = seeded()
        let before = chain
        let preset = EffectPresets.distortion.first { $0.name == name }!
        preset.apply(to: &chain, bpm: 90)
        #expect(chain.distortion.isOn)
        #expect(chain.distortion.wetDryMix == mix)
        #expect(chain.distortion.preGain == preGain)
        #expect(chain.reverb == before.reverb)
        #expect(chain.delay == before.delay)
        #expect(chain.eq == before.eq)
    }

    private func expectEQ(_ name: String, low: Float, mid: Float, high: Float) {
        var chain = seeded()
        let before = chain
        let preset = EffectPresets.eq.first { $0.name == name }!
        preset.apply(to: &chain, bpm: 90)
        #expect(chain.eq.isOn)
        #expect(chain.eq.low == low)
        #expect(chain.eq.mid == mid)
        #expect(chain.eq.high == high)
        #expect(chain.reverb == before.reverb)
        #expect(chain.delay == before.delay)
        #expect(chain.distortion == before.distortion)
    }

    private func scene(_ name: String) -> EffectPresets.Scene {
        EffectPresets.scenes.first { $0.name == name }!
    }

    private func seeded() -> EffectsChain {
        var chain = EffectsChain()
        chain.reverb.wetDryMix = 0.11
        chain.reverb.room = .largeHall
        chain.delay.isOn = true
        chain.delay.wetDryMix = 0.12
        chain.delay.delayTime = 1.1
        chain.delay.feedback = 11
        chain.delay.lowPassCutoff = 1111
        chain.distortion.isOn = true
        chain.distortion.wetDryMix = 0.13
        chain.distortion.preGain = 7
        chain.eq.isOn = true
        chain.eq.low = 1
        chain.eq.mid = 2
        chain.eq.high = 3
        return chain
    }
}
