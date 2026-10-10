import Foundation

// MARK: - Core/Sequencer
nonisolated struct SequencerTrack: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var soundPreset: SoundPreset
    var steps: [SequencerStep]
    var isMuted: Bool = false
    var isSolo: Bool = false
    
    // Additional parameters for mixing
    var volume: Float = 1.0
    var pan: Float = 0.0
    
    init(soundPreset: SoundPreset, stepsCount: Int = 16) {
        self.soundPreset = soundPreset
        self.steps = (0..<stepsCount).map { _ in SequencerStep() }
    }
}

extension SequencerTrack {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        soundPreset = try container.decode(SoundPreset.self, forKey: .soundPreset)
        steps = try container.decodeIfPresent([SequencerStep].self, forKey: .steps) ?? []
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSolo = try container.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0.0
    }
}
