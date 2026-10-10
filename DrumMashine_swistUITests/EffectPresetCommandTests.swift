import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct EffectPresetCommandTests {
    @Test func sceneChoiceUndoesUnderTheEffectPresetName() {
        let holder = ChainHolder()
        let edits = EffectPresetEditSession()
        let undo = UndoManager()
        edits.read = { holder.chain }
        edits.commit = { holder.chain = $0 }
        edits.undoManager = undo

        let dub = EffectPresets.scenes.first { $0.name == "Dub" }!
        edits.chooseScene(dub, bpm: 120)

        #expect(undo.undoActionName == "Effect Preset")
        #expect(edits.labels.scene == "Dub")
        #expect(holder.chain.reverb.isOn)
        #expect(holder.chain.delay.isOn)
        #expect(holder.chain.distortion.isOn == false)
        #expect(holder.chain.delay.delayTime == 0.375)
        #expect(holder.chain.eq.isOn)

        undo.undo()
        #expect(undo.redoActionName == "Effect Preset")
        #expect(holder.chain == EffectsChain())
        #expect(edits.labels.scene == nil)
        #expect(holder.chain.reverb.isOn == false)
        #expect(holder.chain.delay.isOn == false)

        undo.redo()
        #expect(edits.labels.scene == "Dub")
        #expect(holder.chain.reverb.isOn)
        #expect(holder.chain.delay.isOn)
        #expect(holder.chain.distortion.isOn == false)
    }

    @Test func manualKnobClearsThatBlockAndTheSceneName() {
        let labels = EffectPresetLabels()
        labels.reverb = "Hall"
        labels.delay = "Dub"
        labels.scene = "Dub"
        labels.clear(.reverb)
        #expect(labels.reverb == nil)
        #expect(labels.scene == nil)
        #expect(labels.delay == "Dub")
    }

    @Test func presetChoiceClearsTheSceneAndKeepsTheOtherNames() {
        let holder = ChainHolder()
        holder.chain.distortion.preGain = 7
        let edits = EffectPresetEditSession()
        edits.read = { holder.chain }
        edits.commit = { holder.chain = $0 }
        edits.labels.scene = "Club"
        edits.labels.delay = "1/8"
        edits.chooseReverb(EffectPresets.reverbPreset("reverb.hall"), bpm: 100)
        #expect(edits.labels.reverb == "Hall")
        #expect(edits.labels.scene == nil)
        #expect(edits.labels.delay == "1/8")
        #expect(holder.chain.reverb.isOn)
        #expect(holder.chain.reverb.room == .mediumHall)
        #expect(holder.chain.distortion.preGain == 7)
    }
}

@MainActor
private final class ChainHolder {
    var chain = EffectsChain()
}
