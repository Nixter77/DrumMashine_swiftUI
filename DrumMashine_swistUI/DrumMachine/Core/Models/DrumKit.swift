import Foundation
import Combine

// MARK: - Core/Models
nonisolated struct DrumKit: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var sounds: [SoundPreset]
    var mic: MicMix? = nil
    var dynamicsDefault: Dynamics? = nil
    /// One Russian line shown on the kit row.
    var character: String? = nil
    /// Nil plays back as +0.2. Stored values are clamped to 0…0.4.
    var accentAmount: Double? = nil

    var resolvedAccentAmount: Double { min(0.4, max(0, accentAmount ?? 0.2)) }
}

extension DrumKit {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Kit"
        sounds = try container.decodeIfPresent([SoundPreset].self, forKey: .sounds) ?? []
        mic = try container.decodeIfPresent(MicMix.self, forKey: .mic)
        dynamicsDefault = try container.decodeIfPresent(Dynamics.self, forKey: .dynamicsDefault)
        character = try container.decodeIfPresent(String.self, forKey: .character)
        accentAmount = try container.decodeIfPresent(Double.self, forKey: .accentAmount)
    }
}
