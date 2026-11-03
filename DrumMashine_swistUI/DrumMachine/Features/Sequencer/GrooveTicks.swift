import Foundation

/// CUT_11: per-step groove timing offsets (in steps) for the header ticks.
/// Reads the same `GrooveSnapshot` the scheduler plays; the scheduler maps step i to slot i % 16.
nonisolated enum GrooveTicks {
    /// Offsets for `stepCount` steps, or `[]` when the groove has no timing effect (view draws nothing).
    static func offsets(template: GrooveTemplate?, settings: GrooveSettings, stepCount: Int) -> [Double] {
        guard stepCount > 0 else { return [] }
        let snap = GrooveSnapshot(template: template, settings: settings)
        guard snap.isActive else { return [] }
        let values = (0..<stepCount).map { snap.timingOffset(step: $0) }
        return values.allSatisfy { $0 == 0 } ? [] : values
    }

    /// Below this a tick is not drawn.
    static let minVisible = 0.01
}
