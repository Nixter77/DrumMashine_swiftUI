import Foundation
import Testing
@testable import DrumMashine_swistUI

struct VelocityLaneTests {
    private func row(_ count: Int, velocity: Float = 0.8, active: Bool = false) -> [SequencerStep] {
        (0..<count).map { _ in
            var step = SequencerStep()
            step.velocity = velocity
            step.isActive = active
            return step
        }
    }

    @Test func paintWritesVelocityAndOptionSkipsRests() {
        let steps = row(4)
        var active = steps
        active[1].isActive = true

        let painted = VelocityLane.paint(steps, index: 0, velocity: 0.25, activeOnly: false)
        #expect(painted[0].velocity == 0.25)
        #expect(painted[0].isActive == false)
        #expect(painted[1].velocity == 0.8)

        let skipped = VelocityLane.paint(active, index: 0, velocity: 0.25, activeOnly: true)
        #expect(skipped[0].velocity == 0.8)
        let hit = VelocityLane.paint(active, index: 1, velocity: 0.25, activeOnly: true)
        #expect(hit[1].velocity == 0.25)

        let low = VelocityLane.paint(steps, index: 2, velocity: 0, activeOnly: false)
        #expect(low[2].velocity == 0.02)
        let high = VelocityLane.paint(steps, index: 2, velocity: 4, activeOnly: false)
        #expect(high[2].velocity == 1)
    }

    @Test func doubleClickSetsPointEightAndLeavesTheRest() {
        var steps = row(3, velocity: 0.4)
        steps[1].isActive = true
        steps[1].accent = true
        let next = VelocityLane.setDefault(steps, index: 1)
        #expect(next[1].velocity == 0.8)
        #expect(next[1].isActive)
        #expect(next[1].accent == true)
        #expect(next[0].velocity == 0.4)
        #expect(next[2].velocity == 0.4)
    }

    @Test func rampIsMonotonicAcrossTheWindow() {
        let steps = row(16, velocity: 0.5)
        let up = VelocityLane.ramp(steps, count: 16, up: true)
        let down = VelocityLane.ramp(steps, count: 16, up: false)
        #expect(abs(up[0].velocity - 0.2) < 0.001)
        #expect(up[15].velocity == 1)
        #expect(down[0].velocity == 1)
        #expect(abs(down[15].velocity - 0.2) < 0.001)
        for index in 1..<16 {
            #expect(up[index].velocity >= up[index - 1].velocity)
            #expect(down[index].velocity <= down[index - 1].velocity)
        }
        let short = VelocityLane.ramp(steps, count: 4, up: true)
        #expect(short[4].velocity == 0.5)
        #expect(short[0].isActive == false)
    }

    @Test func humanizeRepeatsForASeedAndStaysInsideTenPercent() {
        let steps = row(8, velocity: 0.8, active: true)
        let first = VelocityLane.humanize(steps, count: 8, seed: 42)
        let again = VelocityLane.humanize(steps, count: 8, seed: 42)
        let other = VelocityLane.humanize(steps, count: 8, seed: 99)
        #expect(first.map(\.velocity) == again.map(\.velocity))
        #expect(first.map(\.velocity) != other.map(\.velocity))
        for step in first {
            #expect(step.velocity >= 0.72 - 0.0001)
            #expect(step.velocity <= 0.88 + 0.0001)
            #expect(step.isActive)
        }
        let window = VelocityLane.humanize(steps, count: 4, seed: 7)
        #expect(window.prefix(4).map(\.velocity) != steps.prefix(4).map(\.velocity))
        #expect(Array(window.suffix(4)).map(\.velocity) == Array(steps.suffix(4)).map(\.velocity))
    }

    @Test func bulkGhostAccentResetAndScale() {
        var steps = row(4, velocity: 0.5, active: true)
        steps[0].accent = true
        steps[0].articulation = 2

        let ghosts = VelocityLane.allGhost(steps, count: 4)
        #expect(ghosts.allSatisfy { $0.velocity == VelocityLane.ghostVelocity && $0.accent == nil })
        #expect(ghosts[0].articulation == 2)
        #expect(ghosts[0].isActive)

        let accents = VelocityLane.allAccent(steps, count: 3)
        #expect(accents[0].accent == true)
        #expect(accents[2].accent == true)
        #expect(accents[3].accent == nil)
        #expect(accents[1].velocity == 0.5)

        let reset = VelocityLane.reset(steps, count: 4)
        #expect(reset.allSatisfy { $0.velocity == 0.8 })
        #expect(reset[0].accent == true)

        let louder = VelocityLane.scale(steps, count: 4, factor: 1.2)
        #expect(abs(louder[0].velocity - 0.6) < 0.001)
        var hot = row(1, velocity: 0.9)
        #expect(VelocityLane.scale(hot, count: 1, factor: 1.2)[0].velocity == 1)
        hot[0].velocity = 0.02
        #expect(VelocityLane.scale(hot, count: 1, factor: 0.8)[0].velocity == 0.02)
    }

    @Test func stepMenuSetsAccentArticulationAndGhost() {
        let steps = row(1, velocity: 0.8)
        let on = VelocityLane.setAccent(steps, index: 0, on: true)
        #expect(on[0].accent == true)
        let off = VelocityLane.setAccent(on, index: 0, on: false)
        #expect(off[0].accent == nil)

        let art = VelocityLane.setArticulation(steps, index: 0, articulation: 2)
        #expect(art[0].articulation == 2)
        #expect(VelocityLane.setArticulation(art, index: 0, articulation: 0)[0].articulation == nil)

        let ghost = VelocityLane.ghost(steps, index: 0)
        #expect(ghost[0].isActive)
        #expect(ghost[0].velocity == 0.35)
        #expect(ghost[0].accent == nil)
    }

    @Test func letterUsesTheTagAndGhostMarkIsUnderPointFourFive() {
        let specs = [
            ArticulationSpec(name: "Center", tag: ""),
            ArticulationSpec(name: "Rim", tag: "r"),
            ArticulationSpec(name: "Stick", tag: "s")
        ]
        #expect(VelocityLane.letter(articulation: nil, specs: specs) == "")
        #expect(VelocityLane.letter(articulation: 0, specs: specs) == "")
        #expect(VelocityLane.letter(articulation: 1, specs: specs) == "r")
        #expect(VelocityLane.letter(articulation: 4, specs: specs) == "4")
        #expect(VelocityLane.isGhostMark(0.449))
        #expect(!VelocityLane.isGhostMark(0.45))
        #expect(VelocityLane.isGhostMark(VelocityLane.ghostVelocity))
    }
}

@MainActor
struct VelocityLaneUndoTests {
    @Test func rampUndoAndRedoAreOneStep() {
        let engine = SequencerEngine()
        let undo = UndoManager()
        let original = engine.tracks[0].steps.map(\.velocity)
        engine.applyVelocityLane(track: 0, name: "Ramp up", undoManager: undo) { steps, count in
            steps = VelocityLane.ramp(steps, count: count, up: true)
        }
        let count = min(engine.stepCount.rawValue, engine.tracks[0].steps.count)
        #expect(count >= 2)
        #expect(abs(engine.tracks[0].steps[0].velocity - 0.2) < 0.001)
        #expect(engine.tracks[0].steps[count - 1].velocity == 1)
        #expect(undo.canUndo)
        #expect(!undo.canRedo)

        undo.undo()
        #expect(engine.tracks[0].steps.map(\.velocity) == original)
        #expect(undo.canRedo)

        undo.redo()
        #expect(abs(engine.tracks[0].steps[0].velocity - 0.2) < 0.001)
        undo.undo()
        #expect(engine.tracks[0].steps.map(\.velocity) == original)
        #expect(!undo.canUndo)
    }
}
