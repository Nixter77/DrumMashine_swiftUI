import Foundation

/// Offline mix of a kit's factory demo. Playback goes to the preview track only.
nonisolated enum KitPreview {
    static func mix(pattern: DrumPattern, sampleRate: Double = 48_000) -> [Float] {
        let rate = max(8_000, sampleRate)
        let bpm = min(240, max(40, pattern.bpm))
        let stepSeconds = 60.0 / bpm / 4.0
        let steps = 16
        let tail = Int(1.5 * rate)
        let total = Int(stepSeconds * Double(steps) * rate) + tail
        guard total > 8 else { return [0] }
        var mix = [Float](repeating: 0, count: total)
        for track in pattern.tracks.prefix(8) {
            var lane = [Float](repeating: 0, count: total)
            let choke = track.soundPreset.chokeGroup != nil
            for (index, step) in track.steps.prefix(steps).enumerated() where step.isActive {
                let start = min(total - 1, Int(Double(index) * stepSeconds * rate))
                if choke { silence(from: start, in: &lane, sampleRate: rate) }
                let hit = DrumSynthesizer.acousticHit(
                    preset: track.soundPreset,
                    velocity: Double(min(1, max(0, step.velocity))),
                    articulation: step.articulation ?? 0,
                    sampleRate: rate
                )
                add(hit, to: &lane, at: start)
            }
            for index in mix.indices { mix[index] += lane[index] }
        }
        var peak: Float = 0
        for sample in mix { peak = max(peak, abs(sample)) }
        if peak > 0.5 {
            let scale = 0.5 / peak
            for index in mix.indices { mix[index] *= scale }
        }
        if let last = mix.indices.last { mix[last] = 0 }
        return mix
    }

    private static func silence(from start: Int, in lane: inout [Float], sampleRate: Double) {
        guard start < lane.count else { return }
        let fade = min(lane.count - start, max(1, Int(0.005 * sampleRate)))
        for index in 0..<fade {
            let gain = Float(fade - index) / Float(fade)
            lane[start + index] *= gain
        }
        if start + fade < lane.count {
            for index in (start + fade)..<lane.count { lane[index] = 0 }
        }
    }

    private static func add(_ hit: [Float], to lane: inout [Float], at start: Int) {
        let count = min(hit.count, lane.count - start)
        guard count > 0 else { return }
        for index in 0..<count { lane[start + index] += hit[index] }
    }
}
