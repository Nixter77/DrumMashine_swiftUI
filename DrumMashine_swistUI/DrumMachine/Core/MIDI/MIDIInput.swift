import CoreMIDI
import Foundation
import Synchronization

/// Lit for 150 ms after a Note On. The MIDI thread writes it; the transport reads it.
nonisolated final class MIDIActivity: @unchecked Sendable {
    private let nanos = Atomic<UInt64>(0)

    func mark() {
        nanos.store(clock_gettime_nsec_np(CLOCK_UPTIME_RAW), ordering: .releasing)
    }

    func isLit() -> Bool {
        let stamp = nanos.load(ordering: .acquiring)
        guard stamp > 0 else { return false }
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        return now &- stamp < 150_000_000
    }
}

/// Route copied from the main actor. The callback only reads this box.
nonisolated final class MIDIRouteBox: @unchecked Sendable {
    struct State: Sendable {
        var map = MIDIMap.gm
        var sensitivity = VelocitySensitivity.medium
        var chokes = [Int](repeating: -1, count: 9)
        var cc4: Int?
    }

    private let state = Mutex(State())

    func update(map: MIDIMap, sensitivity: VelocitySensitivity, chokes: [Int]) {
        state.withLock {
            $0.map = map
            $0.sensitivity = sensitivity
            $0.chokes = chokes
        }
    }

    func choke(track: Int) -> Int {
        state.withLock { $0.chokes.indices.contains(track) ? $0.chokes[track] : -1 }
    }

    func consume(events: [MIDIEvent]) -> [MIDIHit] {
        state.withLock { route in
            var hits: [MIDIHit] = []
            for event in events {
                if case .controlChange(_, 4, let value) = event {
                    route.cc4 = value
                    continue
                }
                if let hit = MIDIResolver.hit(
                    event: event,
                    cc4: route.cc4,
                    map: route.map,
                    sensitivity: route.sensitivity
                ) {
                    hits.append(hit)
                }
            }
            return hits
        }
    }
}

/// CoreMIDI input. The callback writes the `.midi` lane only, never `.control`.
/// A sandbox without a device, or a failed client, leaves `lastError` and does not add entitlements.
nonisolated final class MIDIInput: @unchecked Sendable {
    let activity = MIDIActivity()
    let route = MIDIRouteBox()
    private(set) var lastError: String?
    private var client = MIDIClientRef()
    private var port = MIDIPortRef()
    private let engineBox = Mutex<VoiceEngine?>(nil)
    private var started = false
    var onRecord: (@Sendable (MIDIHit) -> Void)?

    func attach(_ engine: VoiceEngine) {
        engineBox.withLock { $0 = engine }
    }

    func start() {
        guard !started else { return }
        started = true
        let status = MIDIClientCreateWithBlock("DrumMashine" as CFString, &client) { [weak self] notification in
            self?.connectSources()
            _ = notification
        }
        guard status == noErr else {
            lastError = "MIDIClientCreateWithBlock \(status)"
            return
        }
        let portStatus = MIDIInputPortCreateWithBlock(client, "In" as CFString, &port) { [weak self] packetList, _ in
            self?.receive(packetList)
        }
        guard portStatus == noErr else {
            lastError = "MIDIInputPortCreateWithBlock \(portStatus)"
            return
        }
        connectSources()
    }

    private func connectSources() {
        let count = MIDIGetNumberOfSources()
        for index in 0..<count {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(port, source, nil)
        }
    }

    private func receive(_ packetList: UnsafePointer<MIDIPacketList>) {
        var hits: [MIDIHit] = []
        var packet = packetList.pointee.packet
        for _ in 0..<packetList.pointee.numPackets {
            let count = Int(packet.length)
            let bytes = withUnsafePointer(to: packet.data) { pointer -> [UInt8] in
                pointer.withMemoryRebound(to: UInt8.self, capacity: max(count, 1)) { rebound in
                    Array(UnsafeBufferPointer(start: rebound, count: count))
                }
            }
            hits.append(contentsOf: route.consume(events: MIDIPacketParser.events(bytes: bytes)))
            packet = MIDIPacketNext(&packet).pointee
        }
        let engine = engineBox.withLock { $0 }
        guard !hits.isEmpty, let engine else { return }
        activity.mark()
        for hit in hits {
            engine.trigger(
                track: hit.track,
                velocity: hit.velocity,
                chokeGroup: route.choke(track: hit.track),
                atSample: 0,
                generation: nil,
                lane: .midi
            )
            onRecord?(hit)
        }
    }
}

/// One shared client for the app. Unit tests do not call `start`.
enum MIDIHub {
    static let shared = MIDIInput()
}
