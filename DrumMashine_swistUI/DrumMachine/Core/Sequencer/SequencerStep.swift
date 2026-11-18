import Foundation

// MARK: - Core/Sequencer
nonisolated struct SequencerStep: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var isActive: Bool = false
    var velocity: Float = 0.8
    var probability: Float = 1.0
    /// Nil is an unaccented step, the same as a file written before AD-1.
    var accent: Bool? = nil
    /// Nil is articulation 0.
    var articulation: Int? = nil
}

extension SequencerStep {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        velocity = try container.decodeIfPresent(Float.self, forKey: .velocity) ?? 0.8
        probability = try container.decodeIfPresent(Float.self, forKey: .probability) ?? 1.0
        accent = try container.decodeIfPresent(Bool.self, forKey: .accent)
        articulation = try container.decodeIfPresent(Int.self, forKey: .articulation)
    }
}
