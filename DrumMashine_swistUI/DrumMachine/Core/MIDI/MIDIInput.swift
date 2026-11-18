import CoreMIDI
import Foundation
import Synchronization

/// Lit for 150 ms after a Note On. The MIDI thread writes it; the transport reads it.
/// `mark()` reports whether the lamp must be woken, so the MIDI thread hops to the main actor
/// at most once per lit period, and nothing polls while no notes arrive.
nonisolated final class MIDIActivity: @unchecked Sendable {
    static let litNanoseconds: UInt64 = 150_000_000

    private let nanos = Atomic<UInt64>(0)
    /// True while a wake-up is pending or the lamp is lit. Cleared only by `rearm()`.
    private let woken = Atomic<Bool>(false)

    /// Returns true when the caller must wake the lamp (first note after it went dark).
    @discardableResult
    func mark(at now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) -> Bool {
        nanos.store(now, ordering: .releasing)
        return !woken.exchange(true, ordering: .acquiringAndReleasing)
    }

    func isLit(at now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) -> Bool {
        remainingLit(at: now) > 0
    }

    /// Nanoseconds until the lamp goes dark, 0 when it is already dark.
    func remainingLit(at now: UInt64 = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) -> UInt64 {
        let stamp = nanos.load(ordering: .acquiring)
        guard stamp > 0 else { return 0 }
        let elapsed = now &- stamp
        return elapsed < Self.litNanoseconds ? Self.litNanoseconds - elapsed : 0
    }

    /// Lets the next `mark()` wake the lamp again.
    func rearm() {
        woken.store(false, ordering: .releasing)
    }
}

/// Main-actor state for the transport's MIDI dot. Replaces a 20 Hz `TimelineView`, which kept the
/// whole window's layout running at display rate while idle (~38 % CPU in Instruments).
/// Wakes on the first note, sleeps until the lamp should go dark, then stops.
@Observable
final class MIDIActivityLamp {
    private(set) var isLit = false
    @ObservationIgnored private let activity: MIDIActivity
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let sleep: @Sendable (UInt64) async -> Void

    init(
        activity: MIDIActivity,
        sleep: @escaping @Sendable (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) {
        self.activity = activity
        self.sleep = sleep
    }

    var isRunning: Bool { task != nil }

    func wake() {
        if !isLit { isLit = true }
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let remaining = self.activity.remainingLit()
                if remaining > 0 {
                    await self.sleep(remaining)
                    continue
                }
                // Re-arm first, then re-check: a note that lands in between either shows up
                // here or wakes a fresh task after this one ends.
                self.activity.rearm()
                if self.activity.remainingLit() > 0 { continue }
                self.isLit = false
                self.task = nil
                return
            }
        }
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
        if activity.mark() {
            Task { @MainActor in MIDIHub.lamp.wake() }
        }
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
    nonisolated static let shared = MIDIInput()
    static let lamp = MIDIActivityLamp(activity: shared.activity)
}
