import AVFoundation
import Foundation
import Synchronization

/// 32-voice mixer behind one stereo `AVAudioSourceNode`.
///
/// Control and render threads share only the SPSC rings and `Atomic` counters.
/// `@unchecked Sendable` is the protocol those rings implement: the render
/// block never locks, allocates, or touches the main actor.
nonisolated final class VoiceEngine: @unchecked Sendable {
    static let voiceCount = 32
    static let trackCount = 8
    static let previewTrack = 8
    static let maxVoicesPerTrack = 4

    let sourceNode: AVAudioSourceNode
    let sampleRate: Double
    private let mixer: Mixer

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        let mixer = Mixer(sampleRate: sampleRate)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!
        self.mixer = mixer
        // Built in this nonisolated init, so the block does not inherit MainActor.
        sourceNode = AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList in
            isSilence.pointee = false
            mixer.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
            return noErr
        }
    }

    var renderedFrames: Int64 { mixer.renderedFrames }
    var lateEventCount: Int64 { mixer.lateEventCount }
    /// Commands the render thread has applied (all lanes). Diagnostic / test hook.
    var appliedCommandCount: Int64 { mixer.appliedCommandCount }
    var activeVoiceCount: Int { mixer.activeVoiceCount }

    /// Peak of the voice sum since the last read, before the master limiter.
    func consumePreLimiterPeak() -> Float { mixer.consumePreLimiterPeak() }

    /// Each lane is a single-producer ring. `.sequencer` is written only by the
    /// scheduler queue; `.control` only by the main actor (pads, gains, swaps, preview).
    /// Never write one lane from two threads.
    enum Lane: Sendable { case control, sequencer }

    /// `atSample <= 0` means "now": applied at the start of the next block, never counted late.
    func trigger(
        track: Int, velocity: Float, chokeGroup: Int, atSample: Int64,
        generation: Int? = nil, lane: Lane = .control
    ) {
        mixer.trigger(
            track: track,
            velocity: velocity,
            chokeGroup: chokeGroup,
            atSample: atSample,
            generation: generation,
            ring: lane == .sequencer ? mixer.sequencerRing : mixer.controlRing
        )
    }

    /// Sequencer `stop` bumps this so triggers already in the ring are dropped.
    /// Pad triggers pass `generation: nil` and are not filtered.
    func setAcceptedGeneration(_ value: Int) {
        mixer.setAcceptedGeneration(value)
    }

    func stopAll(fadeFrames: Int) {
        mixer.stopAll(fadeFrames: fadeFrames)
    }

    func setTrackGain(track: Int, gain: Float, pan: Float, lane: Lane = .control) {
        mixer.setTrackGain(
            track: track, gain: gain, pan: pan,
            ring: lane == .sequencer ? mixer.sequencerRing : mixer.controlRing
        )
    }

    /// Sidechain params, one atomic word. Safe from any thread; the render block reads it once per block.
    func setSidechain(_ settings: SidechainSettings) {
        mixer.sidechainWord.store(settings.packed, ordering: .releasing)
    }

    func swapSample(track: Int, samples: [Float]) {
        mixer.swapSample(track: track, samples: samples)
    }

    func drainRetired() {
        mixer.drainRetired()
    }
}

/// Render-side state. Not visible outside this file.
/// `nonisolated` so the render block does not inherit the module's MainActor default.
nonisolated private final class Mixer: @unchecked Sendable {
    static let voiceCount = VoiceEngine.voiceCount
    static let trackCount = VoiceEngine.trackCount
    static let slotCount = 9
    static let ringCapacity = 1024
    static let ringMask = 1023

    let sampleRate: Double
    private let chokeFadeFrames: Int
    private let trackStealFrames: Int
    private let poolStealFrames: Int
    private let gainAlpha: Float

    private let voices: UnsafeMutablePointer<Voice>
    /// One SPSC ring per producer thread; the render thread drains both.
    let controlRing = CommandRing(capacity: ringCapacity)
    let sequencerRing = CommandRing(capacity: ringCapacity)
    private let retired: UnsafeMutablePointer<Retired>
    private let retiredHead = Atomic<Int>(0)
    private let retiredTail = Atomic<Int>(0)
    private let frameClock = Atomic<Int64>(0)
    private let lateCounter = Atomic<Int64>(0)
    private let appliedCounter = Atomic<Int64>(0)
    private let activeCounter = Atomic<Int>(0)
    private let orderCounter = Atomic<Int64>(1)
    private let acceptedGeneration = Atomic<Int>(0)
    /// Written by stop() so a fade is not stuck behind a future trigger in the command ring.
    private let pendingFade = Atomic<Int>(0)
    private let peakBits = Atomic<UInt32>(0)
    /// `SidechainSettings.packed`. Written by the main actor, read once per render block.
    let sidechainWord = Atomic<UInt64>(0)
    /// Render-thread only.
    private var sidechain = SidechainParams()
    private var sidechainEnvelope: SidechainEnvelope
    private var duckGain: Float = 1

    private let slotPtr: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>
    private let slotCount: UnsafeMutablePointer<Int>
    private let targetGain: UnsafeMutablePointer<Float>
    private let targetPan: UnsafeMutablePointer<Float>
    private let smoothGain: UnsafeMutablePointer<Float>
    private let smoothPan: UnsafeMutablePointer<Float>
    /// Per-block pan law: L/R coefficient at the block start and per-frame step (linear ramp).
    private let panL: UnsafeMutablePointer<Float>
    private let panR: UnsafeMutablePointer<Float>
    private let panStepL: UnsafeMutablePointer<Float>
    private let panStepR: UnsafeMutablePointer<Float>

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        chokeFadeFrames = max(1, Int(0.003 * sampleRate))
        trackStealFrames = chokeFadeFrames
        poolStealFrames = max(1, Int(0.001 * sampleRate))
        gainAlpha = Float(1 - exp(-1.0 / (0.005 * sampleRate)))
        sidechainEnvelope = SidechainEnvelope(sampleRate: sampleRate)

        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        retired = .allocate(capacity: Self.ringCapacity)
        retired.initialize(repeating: Retired(), count: Self.ringCapacity)
        slotPtr = .allocate(capacity: Self.slotCount)
        slotPtr.initialize(repeating: nil, count: Self.slotCount)
        slotCount = .allocate(capacity: Self.slotCount)
        slotCount.initialize(repeating: 0, count: Self.slotCount)
        targetGain = .allocate(capacity: Self.slotCount)
        targetGain.initialize(repeating: 1, count: Self.slotCount)
        smoothGain = .allocate(capacity: Self.slotCount)
        smoothGain.initialize(repeating: 1, count: Self.slotCount)
        targetPan = .allocate(capacity: Self.slotCount)
        targetPan.initialize(repeating: 0, count: Self.slotCount)
        smoothPan = .allocate(capacity: Self.slotCount)
        smoothPan.initialize(repeating: 0, count: Self.slotCount)
        let centre = Float(cos(Double.pi / 4))
        panL = .allocate(capacity: Self.slotCount)
        panL.initialize(repeating: centre, count: Self.slotCount)
        panR = .allocate(capacity: Self.slotCount)
        panR.initialize(repeating: centre, count: Self.slotCount)
        panStepL = .allocate(capacity: Self.slotCount)
        panStepL.initialize(repeating: 0, count: Self.slotCount)
        panStepR = .allocate(capacity: Self.slotCount)
        panStepR.initialize(repeating: 0, count: Self.slotCount)
    }

    deinit {
        drainRetired()
        for slot in 0..<Self.slotCount {
            if let ptr = slotPtr[slot] {
                ptr.deinitialize(count: slotCount[slot])
                ptr.deallocate()
            }
        }
        voices.deinitialize(count: Self.voiceCount)
        voices.deallocate()
        retired.deinitialize(count: Self.ringCapacity)
        retired.deallocate()
        slotPtr.deinitialize(count: Self.slotCount)
        slotPtr.deallocate()
        slotCount.deinitialize(count: Self.slotCount)
        slotCount.deallocate()
        targetGain.deinitialize(count: Self.slotCount)
        targetGain.deallocate()
        smoothGain.deinitialize(count: Self.slotCount)
        smoothGain.deallocate()
        targetPan.deinitialize(count: Self.slotCount)
        targetPan.deallocate()
        smoothPan.deinitialize(count: Self.slotCount)
        smoothPan.deallocate()
        for ptr in [panL, panR, panStepL, panStepR] {
            ptr.deinitialize(count: Self.slotCount)
            ptr.deallocate()
        }
    }

    var renderedFrames: Int64 { frameClock.load(ordering: .acquiring) }
    var lateEventCount: Int64 { lateCounter.load(ordering: .acquiring) }
    var appliedCommandCount: Int64 { appliedCounter.load(ordering: .acquiring) }
    var activeVoiceCount: Int { activeCounter.load(ordering: .acquiring) }

    func consumePreLimiterPeak() -> Float {
        Float(bitPattern: peakBits.exchange(0, ordering: .acquiringAndReleasing))
    }

    func setAcceptedGeneration(_ value: Int) {
        acceptedGeneration.store(value, ordering: .releasing)
    }

    func trigger(
        track: Int, velocity: Float, chokeGroup: Int, atSample: Int64, generation: Int?, ring: CommandRing
    ) {
        guard track >= 0, track < Self.slotCount else { return }
        enqueue(ring, Command(
            kind: .trigger, track: Int32(track), velocity: velocity,
            gain: 0, pan: 0, atSample: atSample, fadeFrames: 0,
            sampleCount: 0, samplePtr: nil, chokeGroup: Int32(chokeGroup),
            generation: Int32(generation ?? 0), checkGeneration: generation != nil
        ))
    }

    func stopAll(fadeFrames: Int) {
        pendingFade.store(max(1, fadeFrames), ordering: .releasing)
    }

    func setTrackGain(track: Int, gain: Float, pan: Float, ring: CommandRing) {
        guard track >= 0, track < Self.trackCount else { return }
        enqueue(ring, Command(
            kind: .setGain, track: Int32(track), velocity: 0,
            gain: gain, pan: pan, atSample: 0, fadeFrames: 0,
            sampleCount: 0, samplePtr: nil, chokeGroup: -1
        ))
    }

    func swapSample(track: Int, samples: [Float]) {
        guard track >= 0, track < Self.slotCount, !samples.isEmpty else { return }
        drainRetired()
        let ptr = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        let dest = UnsafeMutableBufferPointer(start: ptr, count: samples.count)
        _ = dest.initialize(from: samples)
        enqueue(controlRing, Command(
            kind: .swap, track: Int32(track), velocity: 0, gain: 0, pan: 0,
            atSample: 0, fadeFrames: 0, sampleCount: Int32(samples.count),
            samplePtr: ptr, chokeGroup: -1
        ))
    }

    func drainRetired() {
        while true {
            let tail = retiredTail.load(ordering: .relaxed)
            let head = retiredHead.load(ordering: .acquiring)
            if tail == head { return }
            let item = retired[tail & Self.ringMask]
            if let ptr = item.ptr, item.count > 0 {
                ptr.deinitialize(count: item.count)
                ptr.deallocate()
            }
            retiredTail.store(tail + 1, ordering: .releasing)
        }
    }

    func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard buffers.count >= 2,
              let leftRaw = buffers[0].mData,
              let rightRaw = buffers[1].mData else { return }
        let left = leftRaw.assumingMemoryBound(to: Float.self)
        let right = rightRaw.assumingMemoryBound(to: Float.self)
        for index in 0..<frameCount {
            left[index] = 0
            right[index] = 0
        }

        let blockStart = frameClock.load(ordering: .relaxed)
        var blockPeak: Float = 0
        // Stop fade: read once per block, not once per frame.
        let fade = pendingFade.exchange(0, ordering: .acquiringAndReleasing)
        if fade > 0 {
            for index in 0..<Self.voiceCount where voices[index].active {
                voices[index].chokeLength = fade
                voices[index].chokeRemaining = fade
            }
        }
        let word = sidechainWord.load(ordering: .acquiring)
        sidechain = SidechainParams(packed: word)
        var panPlanned = false
        for frame in 0..<frameCount {
            let absolute = blockStart + Int64(frame)
            drain(controlRing, absolute: absolute, blockStart: blockStart)
            drain(sequencerRing, absolute: absolute, blockStart: blockStart)
            if !panPlanned {
                // After frame 0's commands, so a setGain at the block start ramps this block.
                planPan(frameCount: frameCount)
                panPlanned = true
            }
            duckGain = sidechain.enabled ? sidechainEnvelope.next() : 1
            mix(frame: frame, left: left, right: right)
            blockPeak = max(blockPeak, abs(left[frame]), abs(right[frame]))
            smooth()
        }
        let held = Float(bitPattern: peakBits.load(ordering: .relaxed))
        if blockPeak > held {
            peakBits.store(blockPeak.bitPattern, ordering: .releasing)
        }
        frameClock.store(blockStart + Int64(frameCount), ordering: .releasing)
        activeCounter.store(countActive(), ordering: .releasing)
    }

    private func apply(_ command: Command, absolute: Int64, blockStart: Int64) {
        switch command.kind {
        case .trigger:
            if command.checkGeneration,
               Int(command.generation) != acceptedGeneration.load(ordering: .acquiring) {
                return
            }
            if command.atSample > 0, command.atSample < blockStart {
                _ = lateCounter.wrappingAdd(1, ordering: .relaxed)
            }
            guard let ptr = slotPtr[Int(command.track)], slotCount[Int(command.track)] > 0 else { return }
            if command.chokeGroup >= 0 {
                choke(group: command.chokeGroup)
            }
            startVoice(
                track: command.track,
                velocity: command.velocity,
                choke: command.chokeGroup,
                ptr: ptr,
                count: slotCount[Int(command.track)]
            )
            if sidechain.enabled, Int(command.track) == sidechain.source {
                sidechainEnvelope.trigger(depth: sidechain.depth(velocity: command.velocity), releaseMs: sidechain.releaseMs)
            }
        case .setGain:
            let track = Int(command.track)
            targetGain[track] = command.gain
            targetPan[track] = command.pan
        case .swap:
            let track = Int(command.track)
            let old = slotPtr[track]
            let oldCount = slotCount[track]
            slotPtr[track] = command.samplePtr
            slotCount[track] = Int(command.sampleCount)
            if let old, !stillUsed(old) {
                retire(old, count: oldCount)
            }
        }
    }

    private func choke(group: Int32) {
        for index in 0..<Self.voiceCount {
            if voices[index].active && voices[index].chokeGroup == group {
                voices[index].chokeLength = chokeFadeFrames
                voices[index].chokeRemaining = chokeFadeFrames
            }
        }
    }

    private func startVoice(
        track: Int32,
        velocity: Float,
        choke: Int32,
        ptr: UnsafeMutablePointer<Float>,
        count: Int
    ) {
        let slot = chooseSlot(track: track)
        let steal = voices[slot].pendingSteal
        // One steal tail per slot. The previous tail goes back through the retire ring.
        if let oldTail = voices[slot].tailPtr {
            let count = voices[slot].tailCount
            let tailTrack = voices[slot].tailTrack
            voices[slot].tailPtr = nil
            voices[slot].tailRemaining = 0
            retireIfOrphan(oldTail, count: count, track: tailTrack)
        }
        if voices[slot].active {
            voices[slot].tailPtr = voices[slot].samplePtr
            voices[slot].tailIndex = voices[slot].sampleIndex
            voices[slot].tailCount = voices[slot].sampleCount
            voices[slot].tailVelocity = voices[slot].velocity
            voices[slot].tailTrack = voices[slot].track
            voices[slot].tailRemaining = steal
            voices[slot].tailLength = steal
            voices[slot].samplePtr = nil
        } else if let old = voices[slot].samplePtr {
            let count = voices[slot].sampleCount
            let oldTrack = voices[slot].track
            voices[slot].samplePtr = nil
            retireIfOrphan(old, count: count, track: oldTrack)
        }
        voices[slot].active = true
        voices[slot].track = track
        voices[slot].samplePtr = ptr
        voices[slot].sampleCount = count
        voices[slot].sampleIndex = 0
        voices[slot].velocity = velocity
        voices[slot].chokeGroup = choke
        voices[slot].chokeRemaining = 0
        voices[slot].chokeLength = 0
        voices[slot].pendingSteal = 0
        voices[slot].startOrder = orderCounter.load(ordering: .relaxed)
        orderCounter.store(voices[slot].startOrder + 1, ordering: .relaxed)
    }

    private func chooseSlot(track: Int32) -> Int {
        var free = -1
        var oldest = 0
        var oldestOrder = Int64.max
        var oldestTrack = -1
        var oldestTrackOrder = Int64.max
        var trackHits = 0
        for index in 0..<Self.voiceCount {
            if !voices[index].active {
                if free < 0 { free = index }
                continue
            }
            if voices[index].startOrder < oldestOrder {
                oldestOrder = voices[index].startOrder
                oldest = index
            }
            if voices[index].track == track {
                trackHits += 1
                if voices[index].startOrder < oldestTrackOrder {
                    oldestTrackOrder = voices[index].startOrder
                    oldestTrack = index
                }
            }
        }
        if trackHits >= VoiceEngine.maxVoicesPerTrack, oldestTrack >= 0 {
            voices[oldestTrack].pendingSteal = trackStealFrames
            return oldestTrack
        }
        if free >= 0 { return free }
        voices[oldest].pendingSteal = poolStealFrames
        return oldest
    }

    private func mix(frame: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        for index in 0..<Self.voiceCount {
            if voices[index].tailRemaining > 0,
               let ptr = voices[index].tailPtr,
               voices[index].tailIndex < voices[index].tailCount {
                let scale = Float(voices[index].tailRemaining) / Float(max(voices[index].tailLength, 1))
                let sample = ptr[voices[index].tailIndex] * voices[index].tailVelocity * scale
                add(sample, track: Int(voices[index].tailTrack), frame: frame, left: left, right: right)
                voices[index].tailIndex += 1
                voices[index].tailRemaining -= 1
                if voices[index].tailRemaining == 0 {
                    retireIfOrphan(voices[index].tailPtr, count: voices[index].tailCount, track: voices[index].tailTrack)
                    voices[index].tailPtr = nil
                }
            }

            guard voices[index].active,
                  let ptr = voices[index].samplePtr,
                  voices[index].sampleIndex < voices[index].sampleCount else { continue }

            var sample = ptr[voices[index].sampleIndex] * voices[index].velocity
            var ended = false
            if voices[index].chokeLength > 0 {
                let scale = Float(max(voices[index].chokeRemaining, 0)) / Float(voices[index].chokeLength)
                sample *= scale
                voices[index].chokeRemaining -= 1
                if voices[index].chokeRemaining <= 0 {
                    endVoice(index)
                    ended = true
                }
            }
            add(sample, track: Int(voices[index].track), frame: frame, left: left, right: right)
            if !ended {
                voices[index].sampleIndex += 1
                if voices[index].sampleIndex >= voices[index].sampleCount {
                    endVoice(index)
                }
            }
        }
    }

    private func add(
        _ sample: Float,
        track: Int,
        frame: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        var gain = smoothGain[track]
        if duckGain < 1, sidechain.ducks(track: track) { gain *= duckGain }
        let f = Float(frame)
        left[frame] += sample * gain * (panL[track] + panStepL[track] * f)
        right[frame] += sample * gain * (panR[track] + panStepR[track] * f)
    }

    /// Pan trig once per track per block: the smoothed pan at the block end is known in
    /// closed form, and the L/R coefficients ramp linearly across the block (no zipper).
    private func planPan(frameCount: Int) {
        let keep = Float(pow(Double(1 - gainAlpha), Double(frameCount)))
        let n = Float(max(frameCount, 1))
        for track in 0..<Self.slotCount {
            let start = smoothPan[track]
            var end = targetPan[track] + (start - targetPan[track]) * keep
            if abs(end - targetPan[track]) < 1e-6 { end = targetPan[track] }
            let a0 = (start + 1) * Float.pi / 4
            let a1 = (end + 1) * Float.pi / 4
            panL[track] = cos(a0)
            panR[track] = sin(a0)
            panStepL[track] = (cos(a1) - panL[track]) / n
            panStepR[track] = (sin(a1) - panR[track]) / n
            smoothPan[track] = end
        }
    }

    /// Gain stays a per-frame one-pole (cheap arithmetic, no trig).
    private func smooth() {
        for track in 0..<Self.slotCount {
            smoothGain[track] += gainAlpha * (targetGain[track] - smoothGain[track])
            if abs(smoothGain[track]) < 1e-15 { smoothGain[track] = 0 }
        }
    }

    private func countActive() -> Int {
        var count = 0
        for index in 0..<Self.voiceCount where voices[index].active {
            count += 1
        }
        return count
    }

    private func endVoice(_ index: Int) {
        voices[index].active = false
        let ptr = voices[index].samplePtr
        let count = voices[index].sampleCount
        let track = voices[index].track
        voices[index].samplePtr = nil
        retireIfOrphan(ptr, count: count, track: track)
    }

    private func stillUsed(_ ptr: UnsafeMutablePointer<Float>) -> Bool {
        for index in 0..<Self.voiceCount {
            if voices[index].samplePtr == ptr || voices[index].tailPtr == ptr { return true }
        }
        return false
    }

    private func retireIfOrphan(_ ptr: UnsafeMutablePointer<Float>?, count: Int, track: Int32) {
        guard let ptr, count > 0 else { return }
        if slotPtr[Int(track)] == ptr { return }
        if stillUsed(ptr) { return }
        retire(ptr, count: count)
    }

    private func retire(_ ptr: UnsafeMutablePointer<Float>, count: Int) {
        let head = retiredHead.load(ordering: .relaxed)
        let tail = retiredTail.load(ordering: .acquiring)
        if head - tail >= Self.ringCapacity { return }
        retired[head & Self.ringMask] = Retired(ptr: ptr, count: count)
        retiredHead.store(head + 1, ordering: .releasing)
    }

    private func enqueue(_ ring: CommandRing, _ command: Command) {
        if !ring.push(command) {
            _ = lateCounter.wrappingAdd(1, ordering: .relaxed)
        }
    }

    /// Applies every due command of one lane. A future trigger only holds back its own lane.
    private func drain(_ ring: CommandRing, absolute: Int64, blockStart: Int64) {
        while let command = ring.peek() {
            if command.kind == .trigger && command.atSample > absolute { break }
            ring.pop()
            _ = appliedCounter.wrappingAdd(1, ordering: .relaxed)
            apply(command, absolute: absolute, blockStart: blockStart)
        }
    }
}

/// Lock-free single-producer / single-consumer command ring.
/// Exactly one thread may call `push`; only the render thread calls `peek`/`pop`.
nonisolated final class CommandRing: @unchecked Sendable {
    private let capacity: Int
    private let mask: Int
    private let slots: UnsafeMutablePointer<Command>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    init(capacity: Int) {
        precondition(capacity > 0 && capacity & (capacity - 1) == 0)
        self.capacity = capacity
        mask = capacity - 1
        slots = .allocate(capacity: capacity)
        slots.initialize(repeating: Command(), count: capacity)
    }

    deinit {
        slots.deinitialize(count: capacity)
        slots.deallocate()
    }

    @discardableResult
    func push(_ command: Command) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        if h - t >= capacity { return false }
        slots[h & mask] = command
        head.store(h + 1, ordering: .releasing)
        return true
    }

    func peek() -> Command? {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        if t == h { return nil }
        return slots[t & mask]
    }

    func pop() {
        let t = tail.load(ordering: .relaxed)
        tail.store(t + 1, ordering: .releasing)
    }
}

nonisolated private struct Voice {
    var active = false
    var track: Int32 = 0
    var samplePtr: UnsafeMutablePointer<Float>?
    var sampleCount = 0
    var sampleIndex = 0
    var velocity: Float = 1
    var chokeGroup: Int32 = -1
    var chokeRemaining = 0
    var chokeLength = 0
    var startOrder: Int64 = 0
    var pendingSteal = 0
    var tailPtr: UnsafeMutablePointer<Float>?
    var tailIndex = 0
    var tailCount = 0
    var tailVelocity: Float = 0
    var tailTrack: Int32 = 0
    var tailRemaining = 0
    var tailLength = 0
}

nonisolated enum CommandKind: Int32 {
    case trigger = 0
    // 1 was stopAll; stop now goes through pendingFade.
    case setGain = 2
    case swap = 3
}

nonisolated struct Command {
    var kind: CommandKind = .trigger
    var track: Int32 = 0
    var velocity: Float = 0
    var gain: Float = 0
    var pan: Float = 0
    var atSample: Int64 = 0
    var fadeFrames: Int32 = 0
    var sampleCount: Int32 = 0
    var samplePtr: UnsafeMutablePointer<Float>?
    var chokeGroup: Int32 = -1
    var generation: Int32 = 0
    var checkGeneration: Bool = false
}

nonisolated private struct Retired {
    var ptr: UnsafeMutablePointer<Float>?
    var count = 0
}
