import Foundation

// MARK: - Effects Chain (codable, with per-effect on/off)
nonisolated struct EffectsChain: Codable, Sendable, Equatable {
    var reverb = ReverbSettings()
    var delay = DelaySettings()
    var distortion = DistortionSettings()
    var eq = EQSettings()
    var compressor = CompressorSettings()

    /// Factory rooms. The default matches the preset loaded before this control existed.
    nonisolated enum ReverbRoom: String, Codable, CaseIterable, Sendable, Identifiable, Equatable {
        case smallRoom, mediumRoom, largeRoom, mediumHall, largeHall

        var id: String { rawValue }

        var label: String {
            switch self {
            case .smallRoom: return "S"
            case .mediumRoom: return "M"
            case .largeRoom: return "L"
            case .mediumHall: return "H"
            case .largeHall: return "XL"
            }
        }
    }

    nonisolated struct ReverbSettings: Codable, Sendable, Equatable {
        var isOn: Bool = false
        var wetDryMix: Float = 0.3 // 0..1
        var room: ReverbRoom = .mediumHall
    }

    /// Three bands, each −12...+12 dB. Off bypasses the whole unit.
    nonisolated struct EQSettings: Codable, Sendable, Equatable {
        var isOn: Bool = false
        var low: Float = 0
        var mid: Float = 0
        var high: Float = 0
    }
    
    nonisolated struct DelaySettings: Codable, Sendable, Equatable {
        var isOn: Bool = false
        var wetDryMix: Float = 0.2    // 0..1
        var delayTime: Double = 0.25  // seconds
        var feedback: Float = 40.0     // 0..100
        var lowPassCutoff: Float = 15000.0  // Hz
        /// Beat fraction that owns `delayTime`. Nil is a manual TIME knob.
        var syncBeats: Double? = nil

        /// Rewrites `delayTime` from `syncBeats`. A manual time stays put.
        mutating func retime(bpm: Double) {
            guard let syncBeats else { return }
            delayTime = EffectPresets.delaySeconds(beats: syncBeats, bpm: bpm)
        }

        /// TIME knob. Drops tempo sync so a later BPM change leaves the time alone.
        mutating func applyManualTime(_ seconds: Double) {
            delayTime = seconds
            syncBeats = nil
        }
    }
    
    /// Bus compressor (Apple DynamicsProcessor) between EQ and the limiter.
    nonisolated struct CompressorSettings: Codable, Sendable, Equatable {
        var isOn: Bool = false
        var threshold: Float = -18   // dB, -40...0
        var amount: Float = 0.4      // 0...1, more = harder (maps to the unit's headroom)
        var attackMs: Float = 20     // 0.1...200
        var releaseMs: Float = 150   // 10...1000
        var makeup: Float = 3        // dB, 0...20

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
            threshold = try c.decodeIfPresent(Float.self, forKey: .threshold) ?? -18
            amount = try c.decodeIfPresent(Float.self, forKey: .amount) ?? 0.4
            attackMs = try c.decodeIfPresent(Float.self, forKey: .attackMs) ?? 20
            releaseMs = try c.decodeIfPresent(Float.self, forKey: .releaseMs) ?? 150
            makeup = try c.decodeIfPresent(Float.self, forKey: .makeup) ?? 3
        }
    }

    nonisolated struct DistortionSettings: Codable, Sendable, Equatable {
        var isOn: Bool = false
        var wetDryMix: Float = 0.3   // 0..1
        var preGain: Float = -6.0     // dB (-20..+20)
    }
}

extension EffectsChain {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reverb = try container.decodeIfPresent(ReverbSettings.self, forKey: .reverb) ?? ReverbSettings()
        delay = try container.decodeIfPresent(DelaySettings.self, forKey: .delay) ?? DelaySettings()
        distortion = try container.decodeIfPresent(DistortionSettings.self, forKey: .distortion) ?? DistortionSettings()
        eq = try container.decodeIfPresent(EQSettings.self, forKey: .eq) ?? EQSettings()
        compressor = try container.decodeIfPresent(CompressorSettings.self, forKey: .compressor) ?? CompressorSettings()
    }
}

extension EffectsChain.ReverbSettings {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
        wetDryMix = try container.decodeIfPresent(Float.self, forKey: .wetDryMix) ?? 0.3
        room = try container.decodeIfPresent(EffectsChain.ReverbRoom.self, forKey: .room) ?? .mediumHall
    }
}

extension EffectsChain.ReverbRoom {
    nonisolated init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .mediumHall
    }
}

extension EffectsChain.EQSettings {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
        low = try container.decodeIfPresent(Float.self, forKey: .low) ?? 0
        mid = try container.decodeIfPresent(Float.self, forKey: .mid) ?? 0
        high = try container.decodeIfPresent(Float.self, forKey: .high) ?? 0
    }
}

extension EffectsChain.DelaySettings {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
        wetDryMix = try container.decodeIfPresent(Float.self, forKey: .wetDryMix) ?? 0.2
        delayTime = try container.decodeIfPresent(Double.self, forKey: .delayTime) ?? 0.25
        feedback = try container.decodeIfPresent(Float.self, forKey: .feedback) ?? 40.0
        lowPassCutoff = try container.decodeIfPresent(Float.self, forKey: .lowPassCutoff) ?? 15000.0
        syncBeats = try container.decodeIfPresent(Double.self, forKey: .syncBeats)
    }
}

extension EffectsChain.DistortionSettings {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
        wetDryMix = try container.decodeIfPresent(Float.self, forKey: .wetDryMix) ?? 0.3
        preGain = try container.decodeIfPresent(Float.self, forKey: .preGain) ?? -6.0
    }
}
