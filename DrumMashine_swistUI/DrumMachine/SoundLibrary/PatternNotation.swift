import Foundation

/// Step notation for factory patterns.
/// A 16-character row of `X` `x` `g` `-` stays one symbol per step.
/// A row that contains spaces is one token per step: `A` is accent at velocity 1,
/// and a suffix selects the articulation (`r` `s` `o` `p` `h` `b` or `1` `2` `3`).
nonisolated enum PatternNotation {
    nonisolated struct Hit: Equatable, Sendable {
        var active: Bool
        var velocity: Float
        var accent: Bool
        var articulation: Int
    }

    static func hits(in row: String) -> [Hit] {
        let tokens: [String]
        if row.contains(" ") {
            tokens = row.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        } else {
            tokens = row.map { String($0) }
        }
        return tokens.map(parse)
    }

    static func parse(_ token: String) -> Hit {
        guard let first = token.first else {
            return Hit(active: false, velocity: 0, accent: false, articulation: 0)
        }
        let active: Bool
        let velocity: Float
        var accent = false
        switch first {
        case "X":
            active = true
            velocity = 1
        case "x":
            active = true
            velocity = 0.75
        case "g":
            active = true
            velocity = 0.4
        case "A":
            active = true
            velocity = 1
            accent = true
        default:
            active = false
            velocity = 0
        }
        var articulation = 0
        for mark in token.dropFirst() {
            switch mark {
            case "r", "o", "b", "1": articulation = 1
            case "s", "p", "2": articulation = 2
            case "h", "3": articulation = 3
            default: break
            }
        }
        return Hit(active: active, velocity: velocity, accent: accent, articulation: articulation)
    }
}
