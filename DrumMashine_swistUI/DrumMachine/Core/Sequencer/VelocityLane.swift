import Foundation

/// Pure edits for the velocity lane and the track menu. The view and the engine call these
/// and do not invent a second curve. One call is one undo step at the call site.
nonisolated enum VelocityLane {
    static let ghostVelocity: Float = 0.35
    /// A bar under this draws the ghost mark.
    static let ghostMark: Float = 0.45
    static let resetVelocity: Float = 0.8

    static func clamp(_ velocity: Float) -> Float {
        min(1, max(0.02, velocity))
    }

    static func isGhostMark(_ velocity: Float) -> Bool {
        velocity < ghostMark
    }

    /// `activeOnly` is the option-drag: inactive steps stay put.
    static func paint(
        _ steps: [SequencerStep],
        index: Int,
        velocity: Float,
        activeOnly: Bool
    ) -> [SequencerStep] {
        guard steps.indices.contains(index) else { return steps }
        if activeOnly && !steps[index].isActive { return steps }
        var copy = steps
        copy[index].velocity = clamp(velocity)
        return copy
    }

    /// Double-click. Velocity only — an empty step stays empty.
    static func setDefault(_ steps: [SequencerStep], index: Int) -> [SequencerStep] {
        guard steps.indices.contains(index) else { return steps }
        var copy = steps
        copy[index].velocity = resetVelocity
        return copy
    }

    /// Linear 0.2…1 across the audible window. `up` starts quiet.
    static func ramp(_ steps: [SequencerStep], count: Int, up: Bool) -> [SequencerStep] {
        var copy = steps
        let n = min(max(count, 0), copy.count)
        guard n > 0 else { return steps }
        for index in 0..<n {
            let t: Float = n == 1 ? 1 : Float(index) / Float(n - 1)
            copy[index].velocity = up ? (0.2 + 0.8 * t) : (1 - 0.8 * t)
        }
        return copy
    }

    /// Multiply by 1 ± 10 %. Same seed, same velocities. Steps past `count` stay.
    static func humanize(_ steps: [SequencerStep], count: Int, seed: UInt64) -> [SequencerStep] {
        var copy = steps
        let n = min(max(count, 0), copy.count)
        guard n > 0 else { return steps }
        var rng = SeededRNG(seed: seed)
        for index in 0..<n {
            let signed = rng.nextUnit() * 2 - 1
            copy[index].velocity = clamp(copy[index].velocity * Float(1 + signed * 0.10))
        }
        return copy
    }

    static func allGhost(_ steps: [SequencerStep], count: Int) -> [SequencerStep] {
        mapWindow(steps, count: count) { step in
            step.velocity = ghostVelocity
            step.accent = nil
        }
    }

    static func allAccent(_ steps: [SequencerStep], count: Int) -> [SequencerStep] {
        mapWindow(steps, count: count) { step in
            step.accent = true
        }
    }

    static func reset(_ steps: [SequencerStep], count: Int) -> [SequencerStep] {
        mapWindow(steps, count: count) { step in
            step.velocity = resetVelocity
        }
    }

    static func scale(_ steps: [SequencerStep], count: Int, factor: Float) -> [SequencerStep] {
        mapWindow(steps, count: count) { step in
            step.velocity = clamp(step.velocity * factor)
        }
    }

    /// `on == false` stores nil, which is the pre-AD-1 unaccented step.
    static func setAccent(_ steps: [SequencerStep], index: Int, on: Bool) -> [SequencerStep] {
        guard steps.indices.contains(index) else { return steps }
        var copy = steps
        copy[index].accent = on ? true : nil
        return copy
    }

    /// Index 0 stores nil.
    static func setArticulation(_ steps: [SequencerStep], index: Int, articulation: Int) -> [SequencerStep] {
        guard steps.indices.contains(index) else { return steps }
        var copy = steps
        copy[index].articulation = articulation == 0 ? nil : articulation
        return copy
    }

    /// The step menu. Makes the hit a ghost and clears accent.
    static func ghost(_ steps: [SequencerStep], index: Int) -> [SequencerStep] {
        guard steps.indices.contains(index) else { return steps }
        var copy = steps
        copy[index].isActive = true
        copy[index].velocity = ghostVelocity
        copy[index].accent = nil
        return copy
    }

    /// Tag's first character, or the index when the preset has no tag. Empty at 0.
    static func letter(articulation: Int?, specs: [ArticulationSpec]) -> String {
        let index = articulation ?? 0
        guard index > 0 else { return "" }
        if specs.indices.contains(index), let tag = specs[index].tag, let first = tag.first {
            return String(first)
        }
        return String(index)
    }

    private static func mapWindow(
        _ steps: [SequencerStep],
        count: Int,
        _ body: (inout SequencerStep) -> Void
    ) -> [SequencerStep] {
        var copy = steps
        let n = min(max(count, 0), copy.count)
        guard n > 0 else { return steps }
        for index in 0..<n {
            body(&copy[index])
        }
        return copy
    }
}
