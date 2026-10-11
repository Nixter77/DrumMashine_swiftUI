import Foundation

// MARK: - Effects Chain (codable, with per-effect on/off)
nonisolated struct EffectsChain: Codable, Sendable, Equatable {
    var reverb = ReverbSettings()
    var delay = DelaySettings()
    var distortion = DistortionSettings()
    var eq = EQSettings()
    var compressor = CompressorSettings()
    /// Signal order of the five rack effects. The limiter always stays last.
    var order: [EffectSlot] = EffectSlot.defaultOrder
    /// Kick-ducks-the-rest, applied inside the voice mixer before every effect.
    var sidechain = SidechainSettings()

    /// Rack effects that can be reordered in the routing view.
    nonisolated enum EffectSlot: String, Codable, CaseIterable, Sendable, Identifiable, Equatable {
        case distortion, delay, reverb, eq, compressor

        static let defaultOrder: [EffectSlot] = [.distortion, .delay, .reverb, .eq, .compressor]
        var id: String { rawValue }

        var title: String {
            switch self {
            case .distortion: return "Distortion"
            case .delay: return "Delay"
            case .reverb: return "Reverb"
            case .eq: return "EQ"
            case .compressor: return "Compressor"
            }
        }

        var icon: String {
            switch self {
            case .distortion: return "bolt.fill"
            case .delay: return "repeat"
            case .reverb: return "water.waves"
            case .eq: return "slider.vertical.3"
            case .compressor: return "arrow.down.right.and.arrow.up.left"
            }
        }
    }

    /// Every slot exactly once. Unknown or missing entries fall back to the default positions.
    nonisolated static func sanitized(_ order: [EffectSlot]) -> [EffectSlot] {
        var seen: [EffectSlot] = []
        for slot in order where !seen.contains(slot) { seen.append(slot) }
        for slot in EffectSlot.defaultOrder where !seen.contains(slot) { seen.append(slot) }
        return seen
    }

    func isOn(_ slot: EffectSlot) -> Bool {
        switch slot {
        case .distortion: return distortion.isOn
        case .delay: return delay.isOn
        case .reverb: return reverb.isOn
        case .eq: return eq.isOn
        case .compressor: return compressor.isOn
        }
    }

    mutating func setOn(_ slot: EffectSlot, _ on: Bool) {
        switch slot {
        case .distortion: distortion.isOn = on
        case .delay: delay.isOn = on
        case .reverb: reverb.isOn = on
        case .eq: eq.isOn = on
        case .compressor: compressor.isOn = on
        }
    }

    mutating func move(_ slot: EffectSlot, by offset: Int) {
        guard let from = order.firstIndex(of: slot) else { return }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return }
        order.remove(at: from)
        order.insert(slot, at: to)
    }

    mutating func move(_ slot: EffectSlot, before target: EffectSlot?) {
        guard order.contains(slot), slot != target else { return }
        order.removeAll { $0 == slot }
        if let target, let index = order.firstIndex(of: target) {
            order.insert(slot, at: index)
        } else {
            order.append(slot)
        }
    }

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
        // Unknown slot names (newer file) are dropped rather than failing the whole chain.
        sidechain = try container.decodeIfPresent(SidechainSettings.self, forKey: .sidechain) ?? SidechainSettings()
        let raw = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        order = Self.sanitized(raw.compactMap(EffectSlot.init(rawValue:)))
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
