import Foundation

/// CUT_12: UI model for `SoundPreset.chokeGroup` (1…4 or nil).
/// Values outside 1…4 are kept as `.other(n)` so the editor never drops them.
nonisolated enum ChokeGroupOption: Hashable, CaseIterable {
    case off, g1, g2, g3, g4
    case other(Int)

    static var allCases: [ChokeGroupOption] { [.off, .g1, .g2, .g3, .g4] }

    init(preset value: Int?) {
        switch value {
        case nil: self = .off
        case 1: self = .g1
        case 2: self = .g2
        case 3: self = .g3
        case 4: self = .g4
        case let n?: self = .other(n)
        }
    }

    var presetValue: Int? {
        switch self {
        case .off: return nil
        case .g1: return 1
        case .g2: return 2
        case .g3: return 3
        case .g4: return 4
        case .other(let n): return n
        }
    }

    var badge: String? { presetValue.map { "C\($0)" } }

    var label: String { presetValue.map(String.init) ?? "Off" }

    /// Picker options; an out-of-range current value is appended so it stays visible.
    static func options(including current: ChokeGroupOption) -> [ChokeGroupOption] {
        allCases.contains(current) ? allCases : allCases + [current]
    }
}
