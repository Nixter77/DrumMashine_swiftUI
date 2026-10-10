import Foundation

/// Factory effect presets and scenes. Every number in the tables lives here.
nonisolated enum EffectPresets {
    static let reverb: [ReverbPreset] = [
        ReverbPreset(id: "reverb.room", name: "Room", room: .smallRoom, mix: 0.20),
        ReverbPreset(id: "reverb.studio", name: "Studio", room: .mediumRoom, mix: 0.25),
        ReverbPreset(id: "reverb.bigRoom", name: "Big Room", room: .largeRoom, mix: 0.30),
        ReverbPreset(id: "reverb.hall", name: "Hall", room: .mediumHall, mix: 0.35),
        ReverbPreset(id: "reverb.cathedral", name: "Cathedral", room: .largeHall, mix: 0.50)
    ]

    static let delay: [DelayPreset] = [
        DelayPreset(id: "delay.slapback", name: "Slapback", beats: nil, seconds: 0.09, feedback: 10, mix: 0.25, lowPassHz: 8000),
        DelayPreset(id: "delay.1_16", name: "1/16", beats: 0.25, seconds: 0, feedback: 25, mix: 0.20, lowPassHz: 12000),
        DelayPreset(id: "delay.1_8", name: "1/8", beats: 0.5, seconds: 0, feedback: 35, mix: 0.25, lowPassHz: 10000),
        DelayPreset(id: "delay.1_4_dotted", name: "1/4 Dotted", beats: 0.75, seconds: 0, feedback: 40, mix: 0.25, lowPassHz: 9000),
        DelayPreset(id: "delay.dub", name: "Dub", beats: 0.75, seconds: 0, feedback: 70, mix: 0.35, lowPassHz: 3000)
    ]

    static let distortion: [DistortionPreset] = [
        DistortionPreset(id: "distortion.warm", name: "Warm", mix: 0.15, preGain: -10),
        DistortionPreset(id: "distortion.crunch", name: "Crunch", mix: 0.35, preGain: 0),
        DistortionPreset(id: "distortion.fuzz", name: "Fuzz", mix: 0.60, preGain: 10),
        DistortionPreset(id: "distortion.destroy", name: "Destroy", mix: 0.85, preGain: 18)
    ]

    static let eq: [EQPreset] = [
        EQPreset(id: "eq.punch", name: "Punch", low: 4, mid: -2, high: 2),
        EQPreset(id: "eq.bright", name: "Bright", low: 0, mid: 0, high: 5),
        EQPreset(id: "eq.scoop", name: "Scoop", low: 3, mid: -5, high: 3),
        EQPreset(id: "eq.warm", name: "Warm", low: 3, mid: 0, high: -4),
        EQPreset(id: "eq.telephone", name: "Telephone", low: -12, mid: 6, high: -12)
    ]

    static let compressor: [CompressorPreset] = [
        CompressorPreset(id: "comp.gentle", name: "Gentle", threshold: -12, amount: 0.2, attackMs: 40, releaseMs: 300, makeup: 1.5),
        CompressorPreset(id: "comp.glue", name: "Glue", threshold: -18, amount: 0.35, attackMs: 30, releaseMs: 200, makeup: 3),
        CompressorPreset(id: "comp.punch", name: "Punch", threshold: -20, amount: 0.55, attackMs: 25, releaseMs: 120, makeup: 5),
        CompressorPreset(id: "comp.snap", name: "Snap", threshold: -24, amount: 0.5, attackMs: 5, releaseMs: 60, makeup: 4),
        CompressorPreset(id: "comp.squash", name: "Squash", threshold: -30, amount: 0.8, attackMs: 1, releaseMs: 80, makeup: 5),
        CompressorPreset(id: "comp.smash", name: "Smash", threshold: -36, amount: 0.95, attackMs: 0.1, releaseMs: 40, makeup: 6)
    ]

    static let scenes: [Scene] = [
        Scene(id: "scene.clean", name: "Clean", reverb: .off, delay: .off, distortion: .off, eq: .off),
        Scene(id: "scene.club", name: "Club", reverb: .preset("reverb.room", mix: 0.15), delay: .off, distortion: .off, eq: .preset("eq.punch"), compressor: .preset("comp.glue")),
        Scene(id: "scene.lofiTape", name: "Lo-Fi Tape", reverb: .preset("reverb.room", mix: 0.15), delay: .off, distortion: .preset("distortion.warm"), eq: .bands(low: 2, mid: 1, high: -8), compressor: .preset("comp.squash")),
        Scene(id: "scene.dub", name: "Dub", reverb: .preset("reverb.hall", mix: nil), delay: .preset("delay.dub"), distortion: .off, eq: .preset("eq.warm")),
        Scene(id: "scene.industrial", name: "Industrial", reverb: .preset("reverb.bigRoom", mix: 0.25), delay: .preset("delay.1_16"), distortion: .preset("distortion.fuzz"), eq: .preset("eq.scoop"), compressor: .preset("comp.smash")),
        Scene(id: "scene.ambient", name: "Ambient", reverb: .preset("reverb.cathedral", mix: nil), delay: .preset("delay.1_4_dotted"), distortion: .off, eq: .off)
    ]

    /// `beats × 60 / bpm`, clamped to the delay's 0.05…2.0 s range.
    static func delaySeconds(beats: Double, bpm: Double) -> Double {
        guard bpm > 0 else { return 2 }
        return min(2, max(0.05, beats * 60 / bpm))
    }

    /// Label on the TIME knob while `syncBeats` is set. Dub and 1/4 dotted share `1/4.`.
    static func delayFractionLabel(beats: Double) -> String {
        if abs(beats - 0.25) < 0.000_001 { return "1/16" }
        if abs(beats - 0.5) < 0.000_001 { return "1/8" }
        if abs(beats - 0.75) < 0.000_001 { return "1/4." }
        return String(format: "%.2f", beats)
    }

    static func reverbPreset(_ id: String) -> ReverbPreset {
        guard let preset = reverb.first(where: { $0.id == id }) else {
            preconditionFailure("missing reverb preset \(id)")
        }
        return preset
    }

    static func delayPreset(_ id: String) -> DelayPreset {
        guard let preset = delay.first(where: { $0.id == id }) else {
            preconditionFailure("missing delay preset \(id)")
        }
        return preset
    }

    static func distortionPreset(_ id: String) -> DistortionPreset {
        guard let preset = distortion.first(where: { $0.id == id }) else {
            preconditionFailure("missing distortion preset \(id)")
        }
        return preset
    }

    static func compressorPreset(_ id: String) -> CompressorPreset {
        guard let preset = compressor.first(where: { $0.id == id }) else {
            preconditionFailure("missing compressor preset \(id)")
        }
        return preset
    }

    nonisolated struct CompressorPreset: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let threshold: Float
        let amount: Float
        let attackMs: Float
        let releaseMs: Float
        let makeup: Float

        func apply(to chain: inout EffectsChain, bpm: Double) {
            _ = bpm
            chain.compressor.isOn = true
            chain.compressor.threshold = threshold
            chain.compressor.amount = amount
            chain.compressor.attackMs = attackMs
            chain.compressor.releaseMs = releaseMs
            chain.compressor.makeup = makeup
        }
    }

    static func eqPreset(_ id: String) -> EQPreset {
        guard let preset = eq.first(where: { $0.id == id }) else {
            preconditionFailure("missing eq preset \(id)")
        }
        return preset
    }

    nonisolated struct ReverbPreset: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let room: EffectsChain.ReverbRoom
        let mix: Float

        func apply(to chain: inout EffectsChain, bpm: Double) {
            _ = bpm
            chain.reverb.isOn = true
            chain.reverb.room = room
            chain.reverb.wetDryMix = mix
        }
    }

    nonisolated struct DelayPreset: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        /// Nil keeps `seconds` and does not follow the tempo.
        let beats: Double?
        let seconds: Double
        let feedback: Float
        let mix: Float
        let lowPassHz: Float

        func apply(to chain: inout EffectsChain, bpm: Double) {
            chain.delay.isOn = true
            chain.delay.wetDryMix = mix
            chain.delay.feedback = feedback
            chain.delay.lowPassCutoff = lowPassHz
            chain.delay.syncBeats = beats
            if let beats {
                chain.delay.delayTime = EffectPresets.delaySeconds(beats: beats, bpm: bpm)
            } else {
                chain.delay.delayTime = seconds
            }
        }
    }

    nonisolated struct DistortionPreset: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let mix: Float
        let preGain: Float

        func apply(to chain: inout EffectsChain, bpm: Double) {
            _ = bpm
            chain.distortion.isOn = true
            chain.distortion.wetDryMix = mix
            chain.distortion.preGain = preGain
        }
    }

    nonisolated struct EQPreset: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let low: Float
        let mid: Float
        let high: Float

        func apply(to chain: inout EffectsChain, bpm: Double) {
            _ = bpm
            chain.eq.isOn = true
            chain.eq.low = low
            chain.eq.mid = mid
            chain.eq.high = high
        }
    }

    nonisolated struct Scene: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let reverb: ReverbChoice
        let delay: DelayChoice
        let distortion: DistortionChoice
        let eq: EQChoice
        var compressor: CompressorChoice = .off

        func apply(to chain: inout EffectsChain, bpm: Double) {
            switch compressor {
            case .off:
                chain.compressor.isOn = false
            case .preset(let id):
                EffectPresets.compressorPreset(id).apply(to: &chain, bpm: bpm)
            }
            switch reverb {
            case .off:
                chain.reverb.isOn = false
            case .preset(let id, let mix):
                EffectPresets.reverbPreset(id).apply(to: &chain, bpm: bpm)
                if let mix {
                    chain.reverb.wetDryMix = mix
                }
            }
            switch delay {
            case .off:
                chain.delay.isOn = false
            case .preset(let id):
                EffectPresets.delayPreset(id).apply(to: &chain, bpm: bpm)
            }
            switch distortion {
            case .off:
                chain.distortion.isOn = false
            case .preset(let id):
                EffectPresets.distortionPreset(id).apply(to: &chain, bpm: bpm)
            }
            switch eq {
            case .off:
                chain.eq.isOn = false
            case .preset(let id):
                EffectPresets.eqPreset(id).apply(to: &chain, bpm: bpm)
            case .bands(let low, let mid, let high):
                chain.eq.isOn = true
                chain.eq.low = low
                chain.eq.mid = mid
                chain.eq.high = high
            }
        }
    }

    nonisolated enum ReverbChoice: Equatable, Sendable {
        case off
        case preset(String, mix: Float?)
    }

    nonisolated enum DelayChoice: Equatable, Sendable {
        case off
        case preset(String)
    }

    nonisolated enum DistortionChoice: Equatable, Sendable {
        case off
        case preset(String)
    }

    nonisolated enum CompressorChoice: Equatable, Sendable {
        case off
        case preset(String)
    }

    nonisolated enum EQChoice: Equatable, Sendable {
        case off
        case preset(String)
        case bands(low: Float, mid: Float, high: Float)
    }
}
