import Foundation

/// Playback and synthesis controls for an acoustic preset.
/// Nil on `SoundPreset` means the legacy linear-gain buffer.
/// `curve` is playback-only and is not part of `synthesisHash`.
nonisolated struct Dynamics: Codable, Equatable, Sendable, Hashable {
    var curve: VelocityCurve?
    var layers: Int?
    var roundRobin: Int?
    var brightness: Double?
    var transient: Double?
    var pitch: Double?
    var decay: Double?
    var noise: Double?
    var humanize: Double?
    var rrDetune: Double?

    var resolvedCurve: VelocityCurve { curve ?? .db(range: 30, shape: 1) }
    /// 4, not 5: a full kit stays inside the 48 MB buffer budget.
    var resolvedLayers: Int { min(8, max(1, layers ?? 4)) }
    /// 2, not 3: same budget. Cymbal callers may still pass 2 explicitly.
    var resolvedRoundRobin: Int { min(4, max(1, roundRobin ?? 2)) }

    init(
        curve: VelocityCurve? = nil,
        layers: Int? = nil,
        roundRobin: Int? = nil,
        brightness: Double? = nil,
        transient: Double? = nil,
        pitch: Double? = nil,
        decay: Double? = nil,
        noise: Double? = nil,
        humanize: Double? = nil,
        rrDetune: Double? = nil
    ) {
        self.curve = curve
        self.layers = layers
        self.roundRobin = roundRobin
        self.brightness = brightness
        self.transient = transient
        self.pitch = pitch
        self.decay = decay
        self.noise = noise
        self.humanize = humanize
        self.rrDetune = rrDetune
    }
}

/// Linear gain, a dB curve, or a monotonic table of 8…16 points.
nonisolated enum VelocityCurve: Equatable, Sendable, Hashable {
    case linear
    case db(range: Double, shape: Double)
    case table([Double])

    /// Gain at `velocity` in 0…1. `db` is 1 at velocity 1.
    func gain(at velocity: Double) -> Double {
        let v = min(1, max(0, velocity))
        switch normalized {
        case .linear:
            return v
        case .db(let range, let shape):
            if v >= 1 { return 1 }
            let db = -range * pow(1 - v, shape)
            let linear = pow(10, db / 20)
            return min(1, max(0, linear))
        case .table(let points):
            return Self.interpolate(points, velocity: v)
        }
    }

    /// 128 monotonic gains, index 0 at velocity 0 and index 127 at velocity 1.
    func curveTable() -> [Float] {
        var previous = 0.0
        var table = [Float]()
        table.reserveCapacity(128)
        for index in 0..<128 {
            let g = max(previous, gain(at: Double(index) / 127))
            previous = g
            table.append(Float(g))
        }
        return table
    }

    var normalized: VelocityCurve {
        switch self {
        case .table(let points):
            return .table(Self.monotonic(points))
        default:
            return self
        }
    }

    /// Clamp each point to 0…1, then sort so the table rises with velocity.
    static func monotonic(_ points: [Double]) -> [Double] {
        points.map { min(1, max(0, $0.isFinite ? $0 : 0)) }.sorted()
    }

    private static func interpolate(_ points: [Double], velocity: Double) -> Double {
        let rising = monotonic(points)
        guard rising.count >= 2 else { return velocity }
        let last = Double(rising.count - 1)
        let position = min(last, max(0, velocity * last))
        let lower = Int(position)
        let upper = min(rising.count - 1, lower + 1)
        let fraction = position - Double(lower)
        return rising[lower] + (rising[upper] - rising[lower]) * fraction
    }
}

nonisolated extension VelocityCurve: Codable {
    private enum CodingKeys: String, CodingKey { case linear, db, table }
    private struct DBBody: Codable { var range: Double; var shape: Double }
    private struct Empty: Codable {}

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        if keyed.allKeys.isEmpty {
            self = .db(range: 30, shape: 1)
            return
        }
        if keyed.contains(.linear) {
            self = .linear
            return
        }
        if let body = try keyed.decodeIfPresent(DBBody.self, forKey: .db) {
            self = .db(range: body.range, shape: body.shape)
            return
        }
        if let points = try keyed.decodeIfPresent([Double].self, forKey: .table) {
            self = .table(Self.monotonic(points))
            return
        }
        self = .db(range: 30, shape: 1)
    }

    func encode(to encoder: Encoder) throws {
        var keyed = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .linear:
            try keyed.encode(Empty(), forKey: .linear)
        case .db(let range, let shape):
            try keyed.encode(DBBody(range: range, shape: shape), forKey: .db)
        case .table(let points):
            try keyed.encode(Self.monotonic(points), forKey: .table)
        }
    }
}

/// Close / overhead / room baked into the buffer. Nil fields use the resolved defaults.
nonisolated struct MicMix: Codable, Equatable, Sendable, Hashable {
    var close: Double?
    var overhead: Double?
    var room: Double?
    var roomTone: Double?
    var roomSize: RoomSize?

    var resolvedClose: Double { close ?? 1 }
    var resolvedOverhead: Double { overhead ?? 0.35 }
    var resolvedRoom: Double { room ?? 0.2 }
    var resolvedRoomTone: Double { roomTone ?? 0.5 }
    var resolvedRoomSize: RoomSize { roomSize ?? .medium }
}

nonisolated enum RoomSize: String, Codable, Equatable, Sendable, Hashable {
    case small, medium, large, hall
}

/// Named acoustic generator. Unknown raw values stay nil on the articulation.
nonisolated enum AcousticRecipe: String, Codable, Equatable, Sendable, Hashable {
    case membraneKick, membraneTom
    case snareCenter, snareRimshot, snareCrossStick
    case brushTap, brushSwirl, brushSlap
    case hatClosed, hatOpen, hatPedal, hatHalfOpen
    case rideBow, rideBell, rideEdge
    case crash, splash, china
    case conga, bongo, cajon, djembe, shaker, tambourine, clap, snap
    case cowbell, agogo, timbale, wood, guiro, triangle
    case orchestralBass, timpani, concertSnare, suspendedCymbal
}

nonisolated struct ArticulationSpec: Codable, Equatable, Sendable, Hashable {
    var name: String?
    var tag: String?
    var recipe: AcousticRecipe?
    var f0: Double?
    var decayScale: Double?
    var wires: Double?
    var layerFiles: [[String]]?

    private enum CodingKeys: String, CodingKey {
        case name, tag, recipe, f0, decayScale, wires, layerFiles
    }

    init(
        name: String? = nil,
        tag: String? = nil,
        recipe: AcousticRecipe? = nil,
        f0: Double? = nil,
        decayScale: Double? = nil,
        wires: Double? = nil,
        layerFiles: [[String]]? = nil
    ) {
        self.name = name
        self.tag = tag
        self.recipe = recipe
        self.f0 = f0
        self.decayScale = decayScale
        self.wires = wires
        self.layerFiles = layerFiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        tag = try container.decodeIfPresent(String.self, forKey: .tag)
        if let raw = try container.decodeIfPresent(String.self, forKey: .recipe) {
            recipe = AcousticRecipe(rawValue: raw)
        } else {
            recipe = nil
        }
        f0 = try container.decodeIfPresent(Double.self, forKey: .f0)
        decayScale = try container.decodeIfPresent(Double.self, forKey: .decayScale)
        wires = try container.decodeIfPresent(Double.self, forKey: .wires)
        layerFiles = try container.decodeIfPresent([[String]].self, forKey: .layerFiles)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(tag, forKey: .tag)
        if let recipe { try container.encode(recipe.rawValue, forKey: .recipe) }
        try container.encodeIfPresent(f0, forKey: .f0)
        try container.encodeIfPresent(decayScale, forKey: .decayScale)
        try container.encodeIfPresent(wires, forKey: .wires)
        try container.encodeIfPresent(layerFiles, forKey: .layerFiles)
    }
}

/// Accent, then groove, then deterministic velocity humanize.
/// The scheduler keeps today's expression when accent is off and the spread is 0.
nonisolated enum VelocityMath {
    static func resolve(
        velocity: Float,
        accent: Bool,
        accentAmount: Float,
        grooveMultiplier: Float?,
        humanizeSpread: Float,
        unitSigned: Double
    ) -> Float {
        var value = velocity
        if accent {
            let add = min(0.4, max(0, accentAmount))
            value = min(1, value + add)
        }
        if let grooveMultiplier {
            value = min(1, max(0, value * grooveMultiplier))
        }
        if humanizeSpread > 0 {
            value += humanizeSpread * Float(unitSigned)
            value = min(1, max(0.02, value))
        } else if accent {
            value = min(1, max(0.02, value))
        }
        return value
    }

    /// Session knob 0…100 maps to ±0…0.15. The preset spread is used when it is larger.
    static func spread(sessionPercent: Double, dynamicsHumanize: Double) -> Float {
        let knob = Float(min(100, max(0, sessionPercent)) / 100 * 0.15)
        let preset = Float(min(0.15, max(0, dynamicsHumanize)))
        return max(knob, preset)
    }
}

nonisolated enum PadVelocityMode: String, Codable, Equatable, Sendable, Hashable {
    case fixed, position, pressure
}

nonisolated enum VelocitySensitivity: String, Codable, Equatable, Sendable, Hashable {
    case soft, medium, hard

    /// Applied to continuous pad and MIDI input. Ghost, accent, and full-level skip it.
    var shape: Double {
        switch self {
        case .soft: return 0.6
        case .medium: return 1
        case .hard: return 1.6
        }
    }
}

nonisolated struct PadHit: Equatable, Sendable {
    var velocity: Float
    var accent: Bool
}

/// Pad hit → velocity. Views only forward location, pressure, and modifier flags.
nonisolated enum PadVelocity {
    static func interpret(
        mode: PadVelocityMode,
        y: Double,
        height: Double,
        pressure: Double?,
        option: Bool,
        shift: Bool,
        fullLevel: Bool,
        sensitivity: VelocitySensitivity
    ) -> PadHit {
        if fullLevel { return PadHit(velocity: 1, accent: false) }
        if option { return PadHit(velocity: 0.35, accent: false) }
        if shift { return PadHit(velocity: 1, accent: true) }
        let raw: Double
        switch mode {
        case .fixed:
            raw = 1
        case .position:
            raw = position(y: y, height: height)
        case .pressure:
            if let pressure {
                raw = min(1, max(0, pressure))
            } else {
                raw = position(y: y, height: height)
            }
        }
        let shaped = pow(min(1, max(0, raw)), sensitivity.shape)
        return PadHit(velocity: Float(min(1, max(0, shaped))), accent: false)
    }

    /// y = 0 is the top of the pad (loud). The bottom is 0.25.
    static func position(y: Double, height: Double) -> Double {
        let span = height > 1 ? height : 1
        let clamped = min(span, max(0, y))
        return 0.25 + 0.75 * (1 - clamped / span)
    }

    /// Peak pressure inside the first `window` seconds. All-zero samples mean no Force Touch.
    static func peakPressure(samples: [(time: Double, pressure: Double)], window: Double = 0.012) -> Double? {
        guard let first = samples.first else { return nil }
        let end = first.time + window
        var peak = 0.0
        var sawForce = false
        for sample in samples where sample.time <= end + 1e-9 {
            if sample.pressure > 0.001 {
                sawForce = true
                peak = max(peak, sample.pressure)
            }
        }
        return sawForce ? min(1, peak) : nil
    }
}

nonisolated enum KeyDecision: Equatable, Sendable {
    case pass
    case consume
    case playToggle
    case fillOnce
    case pad(track: Int, ghost: Bool, accent: Bool)
}

/// Keys 1–8 play pads. Space and F stay play and fill-once. Option is ghost only on 1–8.
nonisolated enum KeyboardRouter {
    static func decide(
        characters: String,
        keyCode: UInt16,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool,
        isRepeat: Bool,
        audioReady: Bool,
        isKeyWindow: Bool,
        isPanel: Bool,
        hasSheet: Bool,
        firstResponderIsText: Bool
    ) -> KeyDecision {
        guard audioReady, isKeyWindow, !isPanel, !hasSheet, !firstResponderIsText else { return .pass }
        if command || control { return .pass }
        let pad = padIndex(characters)
        if option, pad == nil { return .pass }
        if keyCode == 49 || characters == " " {
            return isRepeat ? .consume : .playToggle
        }
        if characters == "f" || characters == "F" {
            return isRepeat ? .consume : .fillOnce
        }
        if let pad {
            if isRepeat { return .consume }
            return .pad(track: pad, ghost: option, accent: shift && !option)
        }
        return .pass
    }

    static func padIndex(_ characters: String) -> Int? {
        switch characters {
        case "1": return 0
        case "2": return 1
        case "3": return 2
        case "4": return 3
        case "5": return 4
        case "6": return 5
        case "7": return 6
        case "8": return 7
        default: return nil
        }
    }
}

/// xorshift-style LCG. `randomizePattern` seeds it from the pattern id and a counter.
nonisolated struct SeededRNG: Sendable {
    var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x4D595DF4D0F33173 : seed
    }

    mutating func nextUnit() -> Double {
        state = state &* 6364136223846793005 &+ 1
        return Double(state >> 11) / Double(UInt64.max >> 11)
    }

    static func mix(uuid: UUID?, counter: UInt64) -> UInt64 {
        var hash = counter &+ 0x9E3779B97F4A7C15
        guard let uuid else { return hash == 0 ? 1 : hash }
        withUnsafeBytes(of: uuid.uuid) { raw in
            for byte in raw {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001B3
            }
        }
        return hash == 0 ? 1 : hash
    }
}

nonisolated struct MIDIBinding: Codable, Equatable, Sendable, Hashable {
    var track: Int
    var articulation: Int
}

/// Editable GM drum map. Index is the MIDI note number.
nonisolated struct MIDIMap: Codable, Equatable, Sendable, Hashable {
    var notes: [MIDIBinding?]

    private enum CodingKeys: String, CodingKey { case notes }

    init(notes: [MIDIBinding?]) {
        if notes.count == 128 {
            self.notes = notes
        } else {
            var fitted = [MIDIBinding?](repeating: nil, count: 128)
            for index in 0..<min(128, notes.count) { fitted[index] = notes[index] }
            self.notes = fitted
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try container.decodeIfPresent([MIDIBinding?].self, forKey: .notes) ?? []
        self.init(notes: decoded.isEmpty ? Self.gm.notes : decoded)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notes, forKey: .notes)
    }

    func binding(note: Int) -> MIDIBinding? {
        guard notes.indices.contains(note) else { return nil }
        return notes[note]
    }

    /// CC4 on the hat. Below 40 the note's own articulation stands.
    /// 40…95 is half-open (3). 96…127 is pedal (2).
    func hatArticulation(cc4: Int) -> Int? {
        if cc4 >= 96 { return 2 }
        if cc4 >= 40 { return 3 }
        return nil
    }

    static let gm: MIDIMap = {
        var notes = [MIDIBinding?](repeating: nil, count: 128)
        func put(_ note: Int, _ track: Int, _ articulation: Int) {
            notes[note] = MIDIBinding(track: track, articulation: articulation)
        }
        put(35, 0, 0)
        put(36, 0, 0)
        put(38, 1, 0)
        put(40, 1, 1)
        put(37, 1, 2)
        put(42, 2, 0)
        put(44, 2, 2)
        put(46, 2, 1)
        put(39, 3, 0)
        put(50, 4, 0)
        put(48, 4, 0)
        put(47, 4, 1)
        put(45, 4, 1)
        put(43, 4, 2)
        put(41, 4, 2)
        put(51, 5, 0)
        put(59, 5, 0)
        put(53, 5, 1)
        put(49, 6, 0)
        put(57, 6, 0)
        put(55, 6, 2)
        put(52, 6, 3)
        put(54, 7, 0)
        put(56, 7, 1)
        for note in 60...64 { put(note, 7, 2) }
        put(69, 7, 3)
        put(70, 7, 3)
        put(75, 7, 4)
        put(76, 7, 5)
        put(77, 7, 5)
        put(81, 7, 6)
        return MIDIMap(notes: notes)
    }()
}

nonisolated enum MIDIEvent: Equatable, Sendable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
}

nonisolated struct MIDIHit: Equatable, Sendable {
    var track: Int
    var velocity: Float
    var articulation: Int
}

/// One MIDI message stream. Note On velocity 0 is Note Off.
nonisolated enum MIDIPacketParser {
    static func events(bytes: [UInt8]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        var index = 0
        var status: UInt8 = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte >= 0x80 {
                status = byte
                index += 1
                if status >= 0xF0 { continue }
            }
            guard status >= 0x80 else {
                index += 1
                continue
            }
            let kind = status & 0xF0
            let channel = Int(status & 0x0F)
            let needed = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            guard index + needed <= bytes.count else { break }
            let data1 = Int(bytes[index])
            let data2 = needed == 2 ? Int(bytes[index + 1]) : 0
            index += needed
            switch kind {
            case 0x90:
                events.append(.noteOn(channel: channel, note: data1, velocity: data2))
            case 0x80:
                events.append(.noteOff(channel: channel, note: data1, velocity: data2))
            case 0xB0:
                events.append(.controlChange(channel: channel, controller: data1, value: data2))
            default:
                break
            }
        }
        return events
    }
}

nonisolated enum MIDIResolver {
    /// Note Off and Note On velocity 0 produce no hit. Sensitivity shapes the 1…127 range.
    static func hit(
        event: MIDIEvent,
        cc4: Int?,
        map: MIDIMap,
        sensitivity: VelocitySensitivity
    ) -> MIDIHit? {
        guard case .noteOn(_, let note, let midiVelocity) = event, midiVelocity > 0 else { return nil }
        guard var binding = map.binding(note: note) else { return nil }
        if binding.track == 2, let cc4, let override = map.hatArticulation(cc4: cc4) {
            binding.articulation = override
        }
        let unit = Double(min(127, midiVelocity)) / 127
        let shaped = pow(unit, sensitivity.shape)
        return MIDIHit(
            track: binding.track,
            velocity: Float(min(1, max(0, shaped))),
            articulation: binding.articulation
        )
    }
}
