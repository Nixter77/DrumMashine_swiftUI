import Foundation

/// Sidechain "pumping": hits on the source track duck the chosen tracks inside the voice mixer.
nonisolated struct SidechainSettings: Codable, Sendable, Equatable {
    var isOn: Bool = false
    var sourceTrack: Int = 0
    /// Duck depth 0...1 (1 = full silence at the bottom of the dip).
    var amount: Float = 0.5
    /// Release time in ms, 50...600.
    var releaseMs: Float = 180
    /// Depth follows the source hit's velocity.
    var velocityScaling: Bool = true
    /// Tracks that get ducked. The source track is never ducked.
    var ducked: [Bool] = Array(repeating: true, count: 8)

    static let releaseRange: ClosedRange<Float> = 50...600

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isOn = try c.decodeIfPresent(Bool.self, forKey: .isOn) ?? false
        sourceTrack = min(7, max(0, try c.decodeIfPresent(Int.self, forKey: .sourceTrack) ?? 0))
        amount = min(1, max(0, try c.decodeIfPresent(Float.self, forKey: .amount) ?? 0.5))
        releaseMs = min(600, max(50, try c.decodeIfPresent(Float.self, forKey: .releaseMs) ?? 180))
        velocityScaling = try c.decodeIfPresent(Bool.self, forKey: .velocityScaling) ?? true
        let raw = try c.decodeIfPresent([Bool].self, forKey: .ducked) ?? []
        ducked = (0..<8).map { $0 < raw.count ? raw[$0] : true }
    }

    /// Bit per ducked track; the source bit is always clear.
    var duckMask: UInt8 {
        var mask: UInt8 = 0
        for index in 0..<min(8, ducked.count) where ducked[index] && index != sourceTrack {
            mask |= 1 << UInt8(index)
        }
        return mask
    }

    /// One 64-bit word, so the render thread reads a consistent set with a single atomic load.
    var packed: UInt64 {
        var word = UInt64(duckMask)
        word |= UInt64(min(7, max(0, sourceTrack))) << 8
        if isOn { word |= 1 << 11 }
        if velocityScaling { word |= 1 << 12 }
        word |= UInt64(UInt16((min(1, max(0, amount)) * 65_535).rounded())) << 16
        word |= UInt64(UInt16(min(600, max(50, releaseMs)).rounded())) << 32
        return word
    }

    struct Preset: Identifiable, Sendable {
        let id: String
        let name: String
        let amount: Float
        let releaseMs: Float

        func apply(to settings: inout SidechainSettings) {
            settings.isOn = true
            settings.amount = amount
            settings.releaseMs = releaseMs
        }
    }

    static let presets: [Preset] = [
        Preset(id: "sidechain.pump", name: "Pump", amount: 0.8, releaseMs: 260),
        Preset(id: "sidechain.subtle", name: "Subtle", amount: 0.3, releaseMs: 120),
    ]
}

/// Render-thread view of `SidechainSettings.packed`. Plain value, no allocation.
nonisolated struct SidechainParams: Equatable {
    var enabled = false
    var source = 0
    var mask: UInt8 = 0
    var amount: Float = 0
    var releaseMs: Float = 180
    var velocityScaling = true

    init() {}

    init(packed word: UInt64) {
        mask = UInt8(word & 0xFF)
        source = Int((word >> 8) & 0x7)
        enabled = (word >> 11) & 1 == 1
        velocityScaling = (word >> 12) & 1 == 1
        amount = Float((word >> 16) & 0xFFFF) / 65_535
        releaseMs = Float((word >> 32) & 0xFFFF)
    }

    func ducks(track: Int) -> Bool {
        enabled && track >= 0 && track < 8 && track != source && (mask >> UInt8(track)) & 1 == 1
    }

    func depth(velocity: Float) -> Float {
        let v = velocityScaling ? min(1, max(0, velocity)) : 1
        return min(1, max(0, amount * v))
    }
}

/// Gain envelope: smooth attack (3 ms) to the dip, short hold (10 ms), cosine release back to 1.
/// A new hit restarts from the current level, so overlapping hits never jump (no click).
nonisolated struct SidechainEnvelope {
    static let attackSeconds = 0.003
    static let holdSeconds = 0.010

    let sampleRate: Double
    private(set) var level: Float = 0
    private var phase = 0 // 0 idle, 1 attack, 2 hold, 3 release
    private var counter = 0
    private var startLevel: Float = 0
    private var peak: Float = 0
    private var attackFrames = 1
    private var holdFrames = 1
    private var releaseFrames = 1

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    var isIdle: Bool { phase == 0 }

    mutating func trigger(depth: Float, releaseMs: Float) {
        attackFrames = max(1, Int(Self.attackSeconds * sampleRate))
        holdFrames = max(1, Int(Self.holdSeconds * sampleRate))
        releaseFrames = max(1, Int(Double(releaseMs) / 1000 * sampleRate))
        startLevel = level
        peak = max(depth, level)
        phase = 1
        counter = 0
    }

    /// Gain for this frame (1 = untouched), then advances one frame.
    mutating func next() -> Float {
        switch phase {
        case 1:
            let t = Float(counter + 1) / Float(attackFrames)
            let s = t * t * (3 - 2 * t)
            level = startLevel + (peak - startLevel) * s
            counter += 1
            if counter >= attackFrames { phase = 2; counter = 0 }
        case 2:
            level = peak
            counter += 1
            if counter >= holdFrames { phase = 3; counter = 0 }
        case 3:
            let t = Float(counter) / Float(releaseFrames)
            level = peak * 0.5 * (1 + cos(Float.pi * min(1, t)))
            counter += 1
            if counter >= releaseFrames { phase = 0; counter = 0; level = 0 }
        default:
            level = 0
        }
        return 1 - level
    }
}
