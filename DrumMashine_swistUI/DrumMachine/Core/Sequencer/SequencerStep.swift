import Foundation

// MARK: - Core/Sequencer
nonisolated struct SequencerStep: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var isActive: Bool = false
    var velocity: Float = 0.8
    var probability: Float = 1.0
}

extension SequencerStep {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        velocity = try container.decodeIfPresent(Float.self, forKey: .velocity) ?? 0.8
        probability = try container.decodeIfPresent(Float.self, forKey: .probability) ?? 1.0
    }
}
