import Foundation

/// A groove: per-16th timing offsets (fractions of a step) and velocity multipliers.
/// Applied at playback only; the pattern itself is never changed.
nonisolated struct GrooveTemplate: Codable, Identifiable, Equatable, Sendable {
    static let length = 16
    static let timingRange: ClosedRange<Double> = -0.25...0.5
    static let velocityRange: ClosedRange<Double> = 0.5...1.2

    var id: String
    var name: String
    var timing: [Double]
    var velocity: [Double]

    var isClean: Bool { timing.allSatisfy { $0 == 0 } && velocity.allSatisfy { $0 == 1 } }

    /// Pads/trims to 16 and clamps into the legal ranges.
    func normalized() -> GrooveTemplate {
        func fit(_ a: [Double], _ fill: Double, _ r: ClosedRange<Double>) -> [Double] {
            (0..<Self.length).map { i in min(r.upperBound, max(r.lowerBound, i < a.count ? a[i] : fill)) }
        }
        return GrooveTemplate(id: id, name: name,
                              timing: fit(timing, 0, Self.timingRange),
                              velocity: fit(velocity, 1, Self.velocityRange))
    }
}

/// User-facing groove choice, saved with the session.
nonisolated struct GrooveSettings: Codable, Equatable, Sendable {
    var grooveID: String = FactoryGrooves.cleanID
    /// 0...100 overall strength (the DAW "Quantize %").
    var amount: Double = 100
    var timing: Double = 100
    var velocity: Double = 100
    var random: Double = 0
    var perTrack: [Bool] = Array(repeating: true, count: 8)

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        grooveID = try c.decodeIfPresent(String.self, forKey: .grooveID) ?? FactoryGrooves.cleanID
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 100
        timing = try c.decodeIfPresent(Double.self, forKey: .timing) ?? 100
        velocity = try c.decodeIfPresent(Double.self, forKey: .velocity) ?? 100
        random = try c.decodeIfPresent(Double.self, forKey: .random) ?? 0
        perTrack = try c.decodeIfPresent([Bool].self, forKey: .perTrack) ?? Array(repeating: true, count: 8)
    }

    func isTrackOn(_ index: Int) -> Bool { index < perTrack.count ? perTrack[index] : true }
}

/// Pre-scaled tables the scheduler reads. No allocation on use.
nonisolated struct GrooveSnapshot: Sendable, Equatable {
    /// Timing offset in steps, already scaled by amount × timing.
    var timing: [Double]
    /// Velocity multiplier, already blended by amount × velocity.
    var velocity: [Double]
    /// Max random jitter in steps.
    var randomDepth: Double
    var trackOn: [Bool]
    var isActive: Bool

    static let clean = GrooveSnapshot(timing: Array(repeating: 0, count: 16),
                                      velocity: Array(repeating: 1, count: 16),
                                      randomDepth: 0, trackOn: Array(repeating: true, count: 8), isActive: false)

    init(timing: [Double], velocity: [Double], randomDepth: Double, trackOn: [Bool], isActive: Bool) {
        self.timing = timing; self.velocity = velocity; self.randomDepth = randomDepth
        self.trackOn = trackOn; self.isActive = isActive
    }

    init(template: GrooveTemplate?, settings: GrooveSettings) {
        guard let t = template?.normalized() else { self = .clean; return }
        let a = max(0, min(100, settings.amount)) / 100
        let tm = a * max(0, min(100, settings.timing)) / 100
        let vm = a * max(0, min(100, settings.velocity)) / 100
        timing = t.timing.map { $0 * tm }
        velocity = t.velocity.map { 1 + ($0 - 1) * vm }
        randomDepth = a * max(0, min(100, settings.random)) / 100 * 0.05
        trackOn = (0..<8).map { settings.isTrackOn($0) }
        isActive = !t.isClean && a > 0 || randomDepth > 0
    }

    @inline(__always) func timingOffset(step: Int) -> Double { timing[((step % 16) + 16) % 16] }
    @inline(__always) func velocityMul(step: Int) -> Double { velocity[((step % 16) + 16) % 16] }
    @inline(__always) func isOn(track: Int) -> Bool { track < trackOn.count ? trackOn[track] : true }
}

/// Factory grooves modelled on classic machines and feels.
nonisolated enum FactoryGrooves {
    static let cleanID = "clean"

    private static func mpc(_ swing: Double) -> [Double] {
        let off = (swing - 50) / 50
        return (0..<16).map { $0 % 2 == 1 ? off : 0 }
    }
    private static let mpcVelocity: [Double] = (0..<16).map { $0 % 4 == 0 ? 1.0 : ($0 % 2 == 0 ? 0.95 : 0.88) }

    private static func accents(_ hits: Set<Int>, on: Double = 1.1, off: Double = 0.85) -> [Double] {
        (0..<16).map { hits.contains($0) ? on : off }
    }

    static let all: [GrooveTemplate] = [
        GrooveTemplate(id: cleanID, name: "Чистый", timing: Array(repeating: 0, count: 16), velocity: Array(repeating: 1, count: 16)),
        GrooveTemplate(id: "mpc54", name: "MPC 54%", timing: mpc(54), velocity: mpcVelocity),
        GrooveTemplate(id: "mpc58", name: "MPC 58%", timing: mpc(58), velocity: mpcVelocity),
        GrooveTemplate(id: "mpc62", name: "MPC 62%", timing: mpc(62), velocity: mpcVelocity),
        GrooveTemplate(id: "mpc66", name: "MPC 66%", timing: mpc(66), velocity: mpcVelocity),
        GrooveTemplate(id: "sp1200", name: "SP-1200",
                       // SP-1200 swing steps are coarse (…58, 63, 67…): use 63% plus a lazy backbeat
                       // and hard, gated accents so it does not sit next to MPC 58/62.
                       timing: (0..<16).map { i in i == 4 || i == 12 ? 0.06 : (i % 2 == 1 ? 0.26 : 0) },
                       velocity: (0..<16).map { i in i % 4 == 0 ? 1.2 : (i == 4 || i == 12 ? 1.15 : (i % 2 == 1 ? 0.62 : 0.85)) }),
        GrooveTemplate(id: "dilla", name: "Dilla",
                       timing: (0..<16).map { i in i == 4 || i == 12 ? 0.12 : (i % 2 == 1 ? 0.18 : (i % 4 == 2 ? 0.05 : 0)) },
                       velocity: (0..<16).map { i in i % 4 == 0 ? 1.0 : (i % 2 == 1 ? 0.7 : 0.85) }),
        GrooveTemplate(id: "shuffle8", name: "Shuffle 1/8",
                       timing: (0..<16).map { $0 % 4 == 2 ? 0.33 : 0 },
                       velocity: (0..<16).map { $0 % 4 == 0 ? 1.1 : ($0 % 4 == 2 ? 0.85 : 0.9) }),
        GrooveTemplate(id: "bossa", name: "Bossa",
                       timing: (0..<16).map { [3, 7, 11].contains($0) ? -0.05 : 0 },
                       velocity: accents([0, 3, 6, 10, 13])),
        GrooveTemplate(id: "afrobeat", name: "Afrobeat",
                       timing: (0..<16).map { $0 % 2 == 1 ? 0.10 : 0 },
                       velocity: accents([0, 3, 6, 10, 12])),
        GrooveTemplate(id: "onedrop", name: "Reggae One Drop",
                       timing: (0..<16).map { $0 % 4 == 2 ? 0.25 : 0 },
                       velocity: accents([8], on: 1.2, off: 0.9)),

        // Signature feels. Approximations from transcriptions/microtiming studies, not sampled performances.
        // Clyde Stubblefield ("Funky Drummer"): very light swing (~1.07:1 → off-16ths ≈ +0.07 step),
        // backbeat laid back, snare ghosts ~1/4 of the backbeat level.
        GrooveTemplate(id: "stubblefield", name: "Clyde Stubblefield",
                       timing: (0..<16).map { i in i == 4 || i == 12 ? 0.05 : (i % 2 == 1 ? 0.07 : 0) },
                       velocity: (0..<16).map { i in i == 4 || i == 12 ? 1.2 : (i % 4 == 0 ? 1.0 : (i % 2 == 1 ? 0.5 : 0.7)) }),
        // Steve Gadd ("50 Ways…", ~103 BPM): relaxed, slightly late backbeat, soft lilt on the off-16ths,
        // wave-like dynamics with a decrescendo through the roll in the second half.
        GrooveTemplate(id: "gadd", name: "Steve Gadd",
                       timing: (0..<16).map { i in i == 4 || i == 12 ? 0.04 : (i % 2 == 1 ? 0.08 : 0.01) },
                       velocity: [1.0, 0.6, 0.75, 0.9, 1.1, 0.6, 0.7, 0.62, 1.0, 0.95, 0.8, 0.7, 1.1, 0.62, 0.75, 0.6]),
        // Dave Weckl: tight, linear, Latin/songo accents (bass on the "&" of 2 and 4, 3-2 clave cells), almost on the grid.
        GrooveTemplate(id: "weckl", name: "Dave Weckl",
                       timing: (0..<16).map { [0, 3, 6, 10, 12, 14].contains($0) ? -0.015 : 0 },
                       velocity: (0..<16).map { [6, 14].contains($0) ? 1.15 : ([0, 3, 10, 12].contains($0) ? 1.05 : 0.72) }),
        // Vinnie Colaiuta: phrasing in threes across the barline, a hair ahead of the beat on the off-16ths.
        GrooveTemplate(id: "colaiuta", name: "Vinnie Colaiuta",
                       timing: (0..<16).map { $0 % 2 == 1 ? -0.03 : 0 },
                       velocity: (0..<16).map { $0 % 3 == 0 ? 1.15 : 0.78 }),
    ]

    static func template(id: String) -> GrooveTemplate? { all.first { $0.id == id } }
}
