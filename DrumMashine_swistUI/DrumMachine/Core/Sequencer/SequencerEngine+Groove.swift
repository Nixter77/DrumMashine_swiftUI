import Foundation

extension SequencerEngine {
    /// Builds a groove from the current pattern: per-16th accent from the mean active velocity
    /// (normalised to the loudest step). Timing stays straight: the SWING control is applied on top
    /// at playback, so copying it into the groove would double it.
    static func extractGroove(tracks: [SequencerTrack], stepCount: Int, swing: Double, name: String) -> GrooveTemplate {
        var sum = Array(repeating: 0.0, count: 16)
        var hits = Array(repeating: 0, count: 16)
        for track in tracks {
            for (i, step) in track.steps.prefix(stepCount).enumerated() where step.isActive {
                sum[i % 16] += Double(step.velocity)
                hits[i % 16] += 1
            }
        }
        let mean = (0..<16).map { hits[$0] > 0 ? sum[$0] / Double(hits[$0]) : 0 }
        let peak = mean.max() ?? 0
        let velocity = mean.map { peak > 0 && $0 > 0 ? max(0.5, $0 / peak) : 1.0 }
        _ = swing
        let timing = Array(repeating: 0.0, count: 16)
        return GrooveTemplate(id: "user-\(UUID().uuidString)", name: name, timing: timing, velocity: velocity).normalized()
    }

    /// Saves the current pattern's feel as a user groove and selects it.
    @discardableResult
    func extractGrooveFromPattern(name: String = "Мой грув") -> GrooveTemplate {
        let g = Self.extractGroove(tracks: tracks, stepCount: stepCount.rawValue, swing: swing, name: name)
        let saved = UserGrooveStore.shared.add(g)
        grooveSettings.grooveID = saved.id
        return saved
    }

    /// Writes the groove's velocity accents into the steps (timing stays on the grid) and turns the
    /// groove's VELOCITY to 0 so the accents are not applied twice. Nil when nothing changed.
    @discardableResult
    func bakeGrooveVelocities() -> (tracks: [SequencerTrack], settings: GrooveSettings)? {
        let before = (tracks: tracks, settings: grooveSettings)
        let snap = GrooveSnapshot(template: activeGroove, settings: grooveSettings)
        guard snap.isActive, snap.velocity.contains(where: { $0 != 1 }) else { return nil }
        var next = tracks
        for t in next.indices where snap.isOn(track: t) {
            for i in next[t].steps.indices where next[t].steps[i].isActive {
                let v = Double(next[t].steps[i].velocity) * snap.velocityMul(step: i)
                next[t].steps[i].velocity = Float(min(1, max(0.05, v)))
            }
        }
        guard next != tracks else { return nil }
        tracks = next
        grooveSettings.velocity = 0
        return before
    }
}
