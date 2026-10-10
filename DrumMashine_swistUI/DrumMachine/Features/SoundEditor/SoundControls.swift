import Foundation
import Combine

/// One knob in the sound editor. Every track, synth or sample, gets a list of these.
nonisolated struct SoundControl: Identifiable, Sendable {
    let id: String
    let title: String
    let range: ClosedRange<Double>
    let unit: String
    let get: @Sendable (SoundPreset) -> Double
    let set: @Sendable (inout SoundPreset, Double) -> Void
}

nonisolated enum SoundControls {
    static let maxSampleLength = 4.0

    /// Tune, decay/length, tone, level for every voice, plus the generator knobs of synth voices.
    static func controls(for preset: SoundPreset) -> [SoundControl] {
        var list: [SoundControl] = [tune]
        switch preset.source {
        case .synth:
            list.append(decay)
            list += voice(preset)
        case .sample, .bundled:
            list.append(length)
        }
        list += [tone, level]
        return list
    }

    static let tune = SoundControl(
        id: "tune", title: "Tune", range: -24...24, unit: "st",
        get: { Double($0.pitch) },
        set: { $0.pitch = Float($1.rounded()) }
    )

    static let decay = SoundControl(
        id: "decay", title: "Decay", range: 0.02...2.5, unit: "s",
        get: { Double($0.decay) },
        set: { $0.decay = Float($1) }
    )

    /// Sample amp envelope: fades the hit out over this many seconds. Max = full sample.
    static let length = SoundControl(
        id: "length", title: "Length", range: 0.03...maxSampleLength, unit: "s",
        get: { preset in
            preset.sustain >= 0.999 || preset.decay <= 0 ? maxSampleLength : Double(preset.decay)
        },
        set: { preset, value in
            if value >= maxSampleLength - 0.01 {
                preset.decay = 0
                preset.sustain = 1
            } else {
                preset.decay = Float(value)
                preset.sustain = 0
            }
            preset.release = 0
        }
    )

    static let tone = SoundControl(
        id: "tone", title: "Tone", range: -1...1, unit: "",
        get: { Double($0.toneFilter ?? 0) },
        set: { $0.toneFilter = abs($1) < 0.01 ? nil : Float($1) }
    )

    static let level = SoundControl(
        id: "level", title: "Level", range: 0...1, unit: "",
        get: { Double($0.volume) },
        set: { $0.volume = Float(min(max($1, 0), 1)) }
    )

    private static func synth(_ preset: inout SoundPreset, _ body: (inout SynthParams) -> Void) {
        var params = preset.synth ?? SynthParams()
        body(&params)
        preset.synth = params
    }

    private static func knob(
        _ id: String, _ title: String, _ range: ClosedRange<Double>, _ unit: String = "",
        get: @escaping @Sendable (SynthParams?) -> Double,
        set: @escaping @Sendable (inout SynthParams, Double) -> Void
    ) -> SoundControl {
        SoundControl(
            id: id, title: title, range: range, unit: unit,
            get: { get($0.synth) },
            set: { preset, value in synth(&preset) { set(&$0, value) } }
        )
    }

    // swiftlint:disable function_body_length
    static func voice(_ preset: SoundPreset) -> [SoundControl] {
        switch preset.resolvedVoice {
        case .kick:
            return [
                knob("kick.start", "Pitch", 40...400, "Hz", get: { $0?.kick?.startHz ?? 150 }, set: { s, v in s.kick = with(s.kick ?? .init()) { $0.startHz = v } }),
                knob("kick.click", "Click", 0...1, get: { $0?.kick?.click ?? 0.5 }, set: { s, v in s.kick = with(s.kick ?? .init()) { $0.click = v } }),
                knob("kick.noise", "Noise", 0...1, get: { $0?.kick?.noise ?? 0 }, set: { s, v in s.kick = with(s.kick ?? .init()) { $0.noise = v } }),
                knob("kick.drive", "Drive", 1...5, get: { $0?.kick?.drive ?? 1 }, set: { s, v in s.kick = with(s.kick ?? .init()) { $0.drive = v } }),
            ]
        case .snare:
            return [
                knob("snare.tone1", "Body", 80...800, "Hz", get: { $0?.snare?.tone1Hz ?? 180 }, set: { s, v in s.snare = with(s.snare ?? .init()) { $0.tone1Hz = v } }),
                knob("snare.tone2", "Ring", 100...2000, "Hz", get: { $0?.snare?.tone2Hz ?? 330 }, set: { s, v in s.snare = with(s.snare ?? .init()) { $0.tone2Hz = v } }),
                knob("snare.noise", "Snappy", 0...1.5, get: { $0?.snare?.noiseLevel ?? 0.8 }, set: { s, v in s.snare = with(s.snare ?? .init()) { $0.noiseLevel = v } }),
            ]
        case .closedHat, .openHat:
            return [
                knob("hat.band", "Color", 2_000...14_000, "Hz", get: { $0?.hat?.bandHz ?? 10_000 }, set: { s, v in s.hat = with(s.hat ?? .init()) { $0.bandHz = v } }),
                knob("hat.q", "Focus", 0.2...4, get: { $0?.hat?.bandQ ?? 0.8 }, set: { s, v in s.hat = with(s.hat ?? .init()) { $0.bandQ = v } }),
                knob("hat.noise", "Noise", 0...1, get: { $0?.hat?.noiseMix ?? 0 }, set: { s, v in s.hat = with(s.hat ?? .init()) { $0.noiseMix = v } }),
            ]
        case .clap:
            return [
                knob("clap.hp", "Color", 200...4000, "Hz", get: { $0?.clap?.hpHz ?? 800 }, set: { s, v in s.clap = with(s.clap ?? .init()) { $0.hpHz = v } }),
                knob("clap.bursts", "Hands", 1...6, get: { Double($0?.clap?.bursts ?? 3) }, set: { s, v in s.clap = with(s.clap ?? .init()) { $0.bursts = Int(v.rounded()) } }),
                knob("clap.tail", "Room", 0...1, get: { $0?.clap?.tailLevel ?? 0.4 }, set: { s, v in s.clap = with(s.clap ?? .init()) { $0.tailLevel = v } }),
            ]
        case .tom:
            return [
                knob("tom.start", "Pitch", 60...500, "Hz", get: { $0?.tom?.startHz ?? 200 }, set: { s, v in s.tom = with(s.tom ?? .init()) { $0.startHz = v } }),
                knob("tom.end", "Bend to", 40...300, "Hz", get: { $0?.tom?.endHz ?? 80 }, set: { s, v in s.tom = with(s.tom ?? .init()) { $0.endHz = v } }),
                knob("tom.stick", "Stick", 0...1, get: { $0?.tom?.stickNoise ?? 0 }, set: { s, v in s.tom = with(s.tom ?? .init()) { $0.stickNoise = v } }),
            ]
        case .ride:
            return [
                knob("ride.ping", "Bell", 1_000...8_000, "Hz", get: { $0?.ride?.pingHz ?? 5000 }, set: { s, v in s.ride = with(s.ride ?? .init()) { $0.pingHz = v } }),
                knob("ride.pingLevel", "Ping", 0...1, get: { $0?.ride?.pingLevel ?? 0.6 }, set: { s, v in s.ride = with(s.ride ?? .init()) { $0.pingLevel = v } }),
                knob("ride.sizzle", "Sizzle", 0...1, get: { $0?.ride?.sizzleLevel ?? 0.4 }, set: { s, v in s.ride = with(s.ride ?? .init()) { $0.sizzleLevel = v } }),
            ]
        case .crash:
            return [
                knob("crash.carrier", "Color", 80...800, "Hz", get: { $0?.crash?.carrierHz ?? 300 }, set: { s, v in s.crash = with(s.crash ?? .init()) { $0.carrierHz = v } }),
                knob("crash.index", "Metal", 0...12, get: { $0?.crash?.index ?? 5 }, set: { s, v in s.crash = with(s.crash ?? .init()) { $0.index = v } }),
                knob("crash.mix", "Wash", 0...1, get: { $0?.crash?.fmMix ?? 0.3 }, set: { s, v in s.crash = with(s.crash ?? .init()) { $0.fmMix = v } }),
            ]
        case .perc:
            switch preset.synth?.perc?.mode ?? .fm {
            case .noise:
                return [
                    knob("perc.band", "Color", 500...12_000, "Hz", get: { $0?.perc?.bandHz ?? 6000 }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.bandHz = v } }),
                    knob("perc.q", "Focus", 0.3...6, get: { $0?.perc?.bandQ ?? 1.5 }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.bandQ = v } }),
                    knob("perc.bursts", "Shakes", 1...6, get: { Double($0?.perc?.bursts ?? 1) }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.bursts = Int(v.rounded()) } }),
                ]
            case .cowbell:
                return [
                    knob("perc.carrier", "Pitch", 200...1500, "Hz", get: { $0?.perc?.carrierHz ?? 540 }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.carrierHz = v } }),
                    knob("perc.band", "Color", 500...8000, "Hz", get: { $0?.perc?.bandHz ?? 2640 }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.bandHz = v } }),
                ]
            case .fm:
                return [
                    knob("perc.carrier", "Pitch", 80...4000, "Hz", get: { $0?.perc?.carrierHz ?? 800 }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.carrierHz = v } }),
                    knob("perc.index", "Metal", 0...8, get: { $0?.perc?.index ?? 3 }, set: { s, v in s.perc = with(s.perc ?? .init()) { $0.index = v } }),
                ]
            }
        case .fx:
            return []
        }
    }

    private static func with<T>(_ value: T, _ body: (inout T) -> Void) -> T {
        var copy = value
        body(&copy)
        return copy
    }
}

/// Which track's sound editor is open. Pads (long press) and sequencer rows (name button) both set it.
@MainActor
final class SoundEditorRouter: ObservableObject {
    static let shared = SoundEditorRouter()
    @Published var trackIndex: Int?
}
