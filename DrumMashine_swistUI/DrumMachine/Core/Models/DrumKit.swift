import Foundation
import Combine

// MARK: - Core/Models
nonisolated struct DrumKit: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var sounds: [SoundPreset]
}

extension DrumKit {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        sounds = try container.decodeIfPresent([SoundPreset].self, forKey: .sounds) ?? []
    }
}
