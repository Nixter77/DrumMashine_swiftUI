import Foundation

/// Generator parameters. Every field is optional so an old preset omits them
/// and the synthesizer keeps the constants those generators already use.
nonisolated struct SynthParams: Codable, Equatable, Sendable, Hashable {
    var kick: Kick?
    var snare: Snare?
    var hat: Hat?
    var clap: Clap?
    var tom: Tom?
    var ride: Ride?
    var crash: Crash?
    var perc: Perc?
    var lofi: LoFi?

    nonisolated struct Kick: Codable, Equatable, Sendable, Hashable {
        var startHz: Double?
        var endHz: Double?
        var sweep: Double?
        var click: Double?
        var clickMs: Double?
        var drive: Double?
        var noise: Double?
    }

    nonisolated struct Snare: Codable, Equatable, Sendable, Hashable {
        var tone1Hz: Double?
        var tone2Hz: Double?
        var tone1Level: Double?
        var tone2Level: Double?
        var bodyTau: Double?
        var noiseHPHz: Double?
        var noiseLevel: Double?
    }

    nonisolated struct Hat: Codable, Equatable, Sendable, Hashable {
        var open: Bool?
        var hpHz: Double?
        var bandHz: Double?
        var bandQ: Double?
        var noiseMix: Double?
    }

    nonisolated struct Clap: Codable, Equatable, Sendable, Hashable {
        var bursts: Int?
        var spacing: Double?
        var hpHz: Double?
        var lpHz: Double?
        var tailLevel: Double?
    }

    nonisolated struct Tom: Codable, Equatable, Sendable, Hashable {
        var startHz: Double?
        var endHz: Double?
        var sweep: Double?
        var stickNoise: Double?
    }

    nonisolated struct Ride: Codable, Equatable, Sendable, Hashable {
        var pingHz: Double?
        var pingModHz: Double?
        var pingLevel: Double?
        var sizzleLevel: Double?
        var sizzleTau: Double?
        var hpHz: Double?
        var lpHz: Double?
    }

    nonisolated struct Crash: Codable, Equatable, Sendable, Hashable {
        var carrierHz: Double?
        var modHz: Double?
        var index: Double?
        var fmMix: Double?
        var hpHz: Double?
    }

    nonisolated struct Perc: Codable, Equatable, Sendable, Hashable {
        var mode: PercMode?
        var carrierHz: Double?
        /// Second cowbell square. Nil uses `carrierHz * ratio`.
        var secondHz: Double?
        var ratio: Double?
        var index: Double?
        var indexDecay: Double?
        var bandHz: Double?
        var bandQ: Double?
        var bursts: Int?
        var spacing: Double?
    }

    nonisolated struct LoFi: Codable, Equatable, Sendable, Hashable {
        var bitDepth: Int?
        var downsample: Int?
        var saturation: Double?
    }

    nonisolated enum PercMode: String, Codable, Equatable, Sendable, Hashable {
        case fm, cowbell, noise
    }
}

/// Library filter. The original sixty presets are `.legacy`.
nonisolated enum FactoryStyle: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case classic808, style909, acoustic, lofi, trap, legacy

    var title: String {
        switch self {
        case .classic808: return "808"
        case .style909: return "909"
        case .acoustic: return "ACOUSTIC"
        case .lofi: return "LO-FI"
        case .trap: return "TRAP"
        case .legacy: return "LEGACY"
        }
    }
}

/// Where the buffer comes from. `.synth` is every factory preset. `.sample` is D-4.
nonisolated enum SoundSource: Codable, Equatable, Sendable, Hashable {
    case synth
    case sample(fileName: String, originalName: String)
}

// MARK: - Core/Models
nonisolated struct SoundPreset: Identifiable, Codable, Sendable, Equatable {
    var id: UUID
    var name: String
    var filename: String
    var category: SoundCategory
    
    // Sound Parameters
    var volume: Float = 1.0
    var pan: Float = 0.0       // -1.0 (left) to 1.0 (right)
    var pitch: Float = 0.0     // semitones
    
    // ADSR Envelope
    var attack: Float = 0.0    // seconds
    var decay: Float = 0.1     // seconds
    var sustain: Float = 1.0   // 0.0 - 1.0
    var release: Float = 0.1   // seconds
    
    // Choke Group (sounds in same group mute each other, e.g. hi-hat open/closed)
    var chokeGroup: Int? = nil  // 1-4 or nil

    /// Factory presets ship with the app. User presets live in `user_presets.json`.
    var origin: Origin = .factory
    /// The library preset this pad was assigned from. RESET reads that preset.
    var basedOn: UUID? = nil
    /// Nil keeps the old filename guess. Factory presets store the kind explicitly.
    var voice: VoiceKind? = nil
    /// Nil uses the generator constants. Set fields override those constants.
    var synth: SynthParams? = nil
    var source: SoundSource = .synth
    /// Nil on a user preset that was not copied from the factory list.
    var style: FactoryStyle? = nil

    nonisolated enum Origin: String, Codable, Sendable, Equatable {
        case factory
        case user
    }
    
    nonisolated enum SoundCategory: String, Codable, CaseIterable, Sendable, Equatable {
        case kick, snare, hihat, percussion, fx, cymbals
        
        var displayName: String {
            switch self {
            case .kick: return "Kick"
            case .snare: return "Snare"
            case .hihat: return "Hi-Hat"
            case .percussion: return "Percussion"
            case .fx: return "FX"
            case .cymbals: return "Cymbals"
            }
        }
        
        var iconName: String {
            switch self {
            case .kick: return "circle.fill"
            case .snare: return "hexagon.fill"
            case .hihat: return "triangle.fill"
            case .percussion: return "diamond.fill"
            case .fx: return "sparkles"
            case .cymbals: return "star.fill"
            }
        }
    }

    nonisolated enum VoiceKind: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
        case kick, snare, closedHat, openHat, clap, tom, ride, crash, perc, fx
    }
}

extension SoundPreset {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        filename = try container.decodeIfPresent(String.self, forKey: .filename) ?? ""
        category = try container.decode(SoundCategory.self, forKey: .category)
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        pan = try container.decodeIfPresent(Float.self, forKey: .pan) ?? 0.0
        pitch = try container.decodeIfPresent(Float.self, forKey: .pitch) ?? 0.0
        attack = try container.decodeIfPresent(Float.self, forKey: .attack) ?? 0.0
        decay = try container.decodeIfPresent(Float.self, forKey: .decay) ?? 0.1
        sustain = try container.decodeIfPresent(Float.self, forKey: .sustain) ?? 1.0
        release = try container.decodeIfPresent(Float.self, forKey: .release) ?? 0.1
        chokeGroup = try container.decodeIfPresent(Int.self, forKey: .chokeGroup)
        if let raw = try container.decodeIfPresent(String.self, forKey: .origin) {
            origin = Origin(rawValue: raw) ?? .factory
        } else {
            origin = .factory
        }
        basedOn = try container.decodeIfPresent(UUID.self, forKey: .basedOn)
        if let raw = try container.decodeIfPresent(String.self, forKey: .voice) {
            voice = VoiceKind(rawValue: raw)
        } else {
            voice = nil
        }
        synth = try container.decodeIfPresent(SynthParams.self, forKey: .synth)
        source = try container.decodeIfPresent(SoundSource.self, forKey: .source) ?? .synth
        if let raw = try container.decodeIfPresent(String.self, forKey: .style) {
            style = FactoryStyle(rawValue: raw)
        } else {
            style = nil
        }
    }

    /// Stored `voice`, or the same filename guess the synthesizer used before D-0.
    nonisolated var resolvedVoice: VoiceKind {
        if let voice { return voice }
        return Self.inferredVoice(category: category, filename: filename, decay: decay)
    }

    /// Closed hat when `decay <= 0.15`. Tom, clap, and ride win over the shared category.
    nonisolated static func inferredVoice(category: SoundCategory, filename: String, decay: Float) -> VoiceKind {
        let name = filename.lowercased()
        switch category {
        case .kick:
            return .kick
        case .snare:
            return .snare
        case .hihat:
            return decay > 0.15 ? .openHat : .closedHat
        case .percussion:
            if name.contains("tom") { return .tom }
            if name.contains("clap") { return .clap }
            return .perc
        case .cymbals:
            return name.contains("ride") ? .ride : .crash
        case .fx:
            return .fx
        }
    }

    /// Fields that change the synthesized buffer. The preview cache mixes this with the id.
    nonisolated var synthesisHash: Int {
        var hasher = Hasher()
        hasher.combine(filename)
        hasher.combine(category.rawValue)
        hasher.combine(pitch)
        hasher.combine(attack)
        hasher.combine(decay)
        hasher.combine(sustain)
        hasher.combine(release)
        hasher.combine(resolvedVoice.rawValue)
        hasher.combine(synth)
        hasher.combine(source)
        return hasher.finalize()
    }

    /// Envelope and pitch of the preset this pad was assigned from. Missing source leaves the pad as it is.
    nonisolated func restored(fromFactory factory: [SoundPreset], users: [SoundPreset]) -> SoundPreset {
        let source = users.first { $0.id == basedOn }
            ?? factory.first { $0.id == basedOn }
            ?? users.first { $0.id == id }
            ?? factory.first { $0.id == id }
            ?? factory.first { !$0.filename.isEmpty && $0.filename == filename }
        guard let source else { return self }
        var copy = self
        copy.volume = source.volume
        copy.pan = source.pan
        copy.pitch = source.pitch
        copy.attack = source.attack
        copy.decay = source.decay
        copy.sustain = source.sustain
        copy.release = source.release
        copy.chokeGroup = source.chokeGroup
        return copy
    }
}

extension SoundPreset.SoundCategory {
    /// An unknown raw value is percussion, so an old or newer file still opens.
    nonisolated init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .percussion
    }
}
