import Foundation

/// Drum-machine style fills: the end of the loop is replaced by a snare/tom figure while FILL is active.
/// Track order: 0 kick, 1 snare, 2 closed hat, 3 clap, 4 tom, 5 ride, 6 crash, 7 perc.
nonisolated enum FillStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case snareRoll, toms, build, halfTime

    var id: String { rawValue }
    var title: String {
        switch self {
        case .snareRoll: return "Snare Roll"
        case .toms: return "Toms"
        case .build: return "Build-up"
        case .halfTime: return "Break"
        }
    }
}

nonisolated enum FillGenerator {
    /// Track roles. Derived from each track's sound (see `Roles(voices:)`), not its index.
    struct Roles: Equatable, Sendable {
        var kick: Int?
        var snare: Int?
        var tom: Int?
        /// Busy voices cleared inside the fill region (snare, hats, clap, tom, ride, perc).
        var busy: [Int]
        /// Kick tracks: keep only their first hit in the region.
        var kicks: [Int]

        /// Factory layout: 0 kick, 1 snare, 2 hat, 3 clap, 4 tom, 5 ride, 6 crash, 7 perc.
        static let legacy = Roles(kick: 0, snare: 1, tom: 4, busy: [1, 2, 3, 4, 5, 7], kicks: [0])

        init(kick: Int?, snare: Int?, tom: Int?, busy: [Int], kicks: [Int]) {
            self.kick = kick; self.snare = snare; self.tom = tom; self.busy = busy; self.kicks = kicks
        }

        /// From the voice of each track's current sound. The snare part falls back to a clap,
        /// the tom part to the snare; a role with no matching track is simply not played.
        init(voices: [SoundPreset.VoiceKind]) {
            func first(_ kinds: [SoundPreset.VoiceKind]) -> Int? {
                for kind in kinds { if let i = voices.firstIndex(of: kind) { return i } }
                return nil
            }
            kick = first([.kick])
            snare = first([.snare, .clap])
            tom = first([.tom]) ?? snare
            let busyKinds: Set<SoundPreset.VoiceKind> = [.snare, .closedHat, .openHat, .clap, .tom, .ride, .perc]
            busy = voices.indices.filter { busyKinds.contains(voices[$0]) }
            kicks = voices.indices.filter { voices[$0] == .kick }
        }
    }

    /// First step of the fill region: the last half bar (8 of 16, 4 of 8, the last 8 of 32).
    static func regionStart(stepCount n: Int) -> Int { n <= 8 ? n / 2 : n - 8 }

    /// Active/velocity per track for the whole loop with the fill written over the region.
    /// `base` is [track][step] = velocity or nil when off.
    static func apply(_ style: FillStyle, base: [[Float?]], stepCount n: Int, roles: Roles = .legacy) -> [[Float?]] {
        guard n >= 4, !base.isEmpty else { return base }
        var out = base
        let start = regionStart(stepCount: n)
        let len = n - start
        // Clear the busy voices in the region; the kick keeps only its first hit there.
        for t in roles.busy where t < out.count {
            for s in start..<n where s < out[t].count { out[t][s] = nil }
        }
        for k in roles.kicks where k < out.count {
            for s in (start + 1)..<n where s < out[k].count { out[k][s] = nil }
        }
        let kick = roles.kick, snare = roles.snare, tom = roles.tom

        func set(_ t: Int?, _ s: Int, _ v: Float) {
            guard let t, t < out.count, s >= 0, s < out[t].count else { return }
            out[t][s] = min(1, max(0.05, v))
        }
        func ramp(_ i: Int, from a: Float, to b: Float) -> Float {
            len <= 1 ? b : a + (b - a) * Float(i) / Float(len - 1)
        }

        switch style {
        case .snareRoll:
            for i in 0..<len { set(snare, start + i, ramp(i, from: 0.45, to: 1.0)) }
        case .toms:
            for i in 0..<len {
                if i < 2 { set(snare, start + i, 0.9) } else { set(tom, start + i, ramp(i, from: 1.0, to: 0.7)) }
            }
            set(kick, n - 1, 0.9)
        case .build:
            // 8ths, then 16ths in the last quarter of the region, getting louder.
            for i in 0..<len where i >= len / 2 || i % 2 == 0 {
                set(snare, start + i, ramp(i, from: 0.5, to: 1.0))
            }
            set(kick, start, 1.0)
            set(kick, start + len / 2, 1.0)
        case .halfTime:
            // Stop-time break: silence apart from a snare hit and a kick pickup.
            set(snare, start, 1.0)
            set(kick, n - 2, 0.8)
            set(snare, n - 1, 0.7)
        }
        return out
    }
}
