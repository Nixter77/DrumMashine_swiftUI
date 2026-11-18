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

    /// `retireCapacity` only shrinks the retire ring for overflow tests.
    init(sampleRate: Double, retireCapacity: Int = 1024) {
        self.sampleRate = sampleRate
        let mixer = Mixer(sampleRate: sampleRate, retireCapacity: retireCapacity)
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
    /// Old buffers parked by the render thread because the retire ring was full.
    var retireBacklogCount: Int { mixer.retireBacklogCount }
    /// Buffers that could be neither retired nor parked (should stay 0).
    var leakedBufferCount: Int { mixer.leakedBufferCount }

    /// Peak of the voice sum since the last read, before the master limiter.
    func consumePreLimiterPeak() -> Float { mixer.consumePreLimiterPeak() }

    /// Runs one render callback into caller buffers. No audio graph, no allocation of sample storage.
    func renderBlock(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        guard frameCount > 0 else { return }
        let byteCount = UInt32(frameCount * MemoryLayout<Float>.stride)
        let size = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.stride
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.pointee.mNumberBuffers = 2
        let buffers = UnsafeMutableRawPointer(list)
            .advanced(by: MemoryLayout.offset(of: \AudioBufferList.mBuffers)!)
            .bindMemory(to: AudioBuffer.self, capacity: 2)
        buffers[0] = AudioBuffer(
            mNumberChannels: 1, mDataByteSize: byteCount, mData: UnsafeMutableRawPointer(left)
        )
        buffers[1] = AudioBuffer(
            mNumberChannels: 1, mDataByteSize: byteCount, mData: UnsafeMutableRawPointer(right)
        )
        mixer.render(frameCount: frameCount, audioBufferList: list)
    }

    /// Each lane is a single-producer ring. `.sequencer` is written only by the
    /// scheduler queue; `.control` only by the main actor (pads, gains, swaps, preview);
    /// `.midi` only by the CoreMIDI callback. Never write one lane from two threads.
    enum Lane: Sendable { case control, sequencer, midi }

    /// `atSample <= 0` means "now": applied at the start of the next block, never counted late.
    /// MIDI ignores `generation`, same as a pad.
    func trigger(
        track: Int, velocity: Float, chokeGroup: Int, atSample: Int64,
        generation: Int? = nil, lane: Lane = .control, articulation: Int = 0
    ) {
        mixer.trigger(
            track: track,
            velocity: velocity,
            chokeGroup: chokeGroup,
            atSample: atSample,
            generation: lane == .midi ? nil : generation,
            articulation: articulation,
            ring: ring(for: lane)
        )
    }

    private func ring(for lane: Lane) -> CommandRing {
        switch lane {
        case .control: return mixer.controlRing
        case .sequencer: return mixer.sequencerRing
        case .midi: return mixer.midiRing
        }
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
            ring: ring(for: lane)
        )
    }

    /// Sidechain params, one atomic word. Safe from any thread; the render block reads it once per block.
    func setSidechain(_ settings: SidechainSettings) {
        mixer.sidechainWord.store(settings.packed, ordering: .releasing)
    }

    func swapSample(track: Int, samples: [Float]) {
        mixer.swapSample(track: track, samples: samples)
    }

    /// Installs a layer bank on the control lane. The caller may release `bank`;
    /// the engine retains it until no slot, voice, or tail still points into it.
    func swapLayers(track: Int, bank: LayerBank) {
        mixer.swapLayers(track: track, bank: bank)
    }

    /// Returns how many retired buffers were freed.
    @discardableResult
    func drainRetired() -> Int {
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
    private let activeSlots: UnsafeMutablePointer<Int>
    /// One SPSC ring per producer thread; the render thread drains all three.
    let controlRing = CommandRing(capacity: ringCapacity)
    let sequencerRing = CommandRing(capacity: ringCapacity)
    let midiRing = CommandRing(capacity: ringCapacity)
    private let retired: UnsafeMutablePointer<Retired>
    private let retireCapacity: Int
    private let retireMask: Int
    /// Render-thread-only overflow park for the retire ring, preallocated. Entries are
    /// re-offered to the ring at every block start; the main actor frees them from there.
    private let backlog: UnsafeMutablePointer<Retired>
    private static let backlogCapacity = 4096
    private var backlogCount = 0
    private let backlogPublished = Atomic<Int>(0)
    private let leakCounter = Atomic<Int>(0)
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
    /// Render-thread only. True once a smooth() pass changed nothing; cleared by setGain.
    private var gainSettled = false

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
    /// Layer bank installed on each slot. Token 0 is the legacy single buffer.
    private let slotLayer: UnsafeMutablePointer<SlotLayer>
    /// Next round-robin index. 9 slots × 8 articulations. Render thread only.
    private let rrCursor: UnsafeMutablePointer<Int32>

    init(sampleRate: Double, retireCapacity: Int = 1024) {
        precondition(retireCapacity > 0 && retireCapacity & (retireCapacity - 1) == 0)
        self.sampleRate = sampleRate
        self.retireCapacity = retireCapacity
        retireMask = retireCapacity - 1
        backlog = .allocate(capacity: Self.backlogCapacity)
        backlog.initialize(repeating: Retired(), count: Self.backlogCapacity)
        chokeFadeFrames = max(1, Int(0.003 * sampleRate))
        trackStealFrames = chokeFadeFrames
        poolStealFrames = max(1, Int(0.001 * sampleRate))
        gainAlpha = Float(1 - exp(-1.0 / (0.005 * sampleRate)))
        sidechainEnvelope = SidechainEnvelope(sampleRate: sampleRate)

        voices = .allocate(capacity: Self.voiceCount)
        voices.initialize(repeating: Voice(), count: Self.voiceCount)
        activeSlots = .allocate(capacity: Self.voiceCount)
        activeSlots.initialize(repeating: 0, count: Self.voiceCount)
        retired = .allocate(capacity: retireCapacity)
        retired.initialize(repeating: Retired(), count: retireCapacity)
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
        slotLayer = .allocate(capacity: Self.slotCount)
        slotLayer.initialize(repeating: SlotLayer(), count: Self.slotCount)
        rrCursor = .allocate(capacity: Self.slotCount * 8)
        rrCursor.initialize(repeating: 0, count: Self.slotCount * 8)
    }

    deinit {
        drainRetired()
        // deinit runs off the audio thread once the node is gone: free anything still parked.
        for index in 0..<backlogCount {
            freeRetired(backlog[index])
        }
        backlog.deinitialize(count: Self.backlogCapacity)
        backlog.deallocate()
        releaseBanksStillHeld()
        for slot in 0..<Self.slotCount {
            if slotLayer[slot].token == 0, let ptr = slotPtr[slot] {
                ptr.deinitialize(count: slotCount[slot])
                ptr.deallocate()
            }
        }
        slotLayer.deinitialize(count: Self.slotCount)
        slotLayer.deallocate()
        rrCursor.deinitialize(count: Self.slotCount * 8)
        rrCursor.deallocate()
        voices.deinitialize(count: Self.voiceCount)
        voices.deallocate()
        activeSlots.deinitialize(count: Self.voiceCount)
        activeSlots.deallocate()
        retired.deinitialize(count: retireCapacity)
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
        track: Int, velocity: Float, chokeGroup: Int, atSample: Int64,
        generation: Int?, articulation: Int = 0, ring: CommandRing
    ) {
        guard track >= 0, track < Self.slotCount else { return }
        enqueue(ring, Command(
            kind: .trigger, track: Int32(track), velocity: velocity,
            gain: 0, pan: 0, atSample: atSample, fadeFrames: 0,
            sampleCount: 0, samplePtr: nil, chokeGroup: Int32(chokeGroup),
            generation: Int32(generation ?? 0), checkGeneration: generation != nil,
            articulation: Int32(articulation)
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

    func swapLayers(track: Int, bank: LayerBank) {
        guard track >= 0, track < Self.slotCount else { return }
        let retained = Unmanaged.passRetained(bank)
        let token = UInt(bitPattern: retained.toOpaque())
        let command = Command(
            kind: .swapLayers, track: Int32(track), velocity: 0, gain: 0, pan: 0,
            atSample: 0, fadeFrames: 0, sampleCount: 0, samplePtr: nil, chokeGroup: -1,
            bankToken: token
        )
        if !controlRing.push(command) {
            retained.release()
            _ = lateCounter.wrappingAdd(1, ordering: .relaxed)
        }
    }

    @discardableResult
    func drainRetired() -> Int {
        var freed = 0
        while true {
            let tail = retiredTail.load(ordering: .relaxed)
            let head = retiredHead.load(ordering: .acquiring)
            if tail == head { return freed }
            freed += 1
            let item = retired[tail & retireMask]
            freeRetired(item)
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

        flushBacklog()
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
        var segmentStart = 0
        while segmentStart < frameCount {
            // Segment boundary: apply everything due on this frame, control lane first.
            let absolute = blockStart + Int64(segmentStart)
            drain(controlRing, absolute: absolute, blockStart: blockStart)
            drain(sequencerRing, absolute: absolute, blockStart: blockStart)
            drain(midiRing, absolute: absolute, blockStart: blockStart)
            if !panPlanned {
                // After frame 0's commands, so a setGain at the block start ramps this block.
                planPan(frameCount: frameCount)
                panPlanned = true
            }
            // No command can become due before the next boundary, so the hot loop skips drain.
            // Same-sample order is control, then sequencer, then midi.
            let segmentEnd = min(
                nextDueFrame(controlRing, after: segmentStart, blockStart: blockStart, frameCount: frameCount),
                nextDueFrame(sequencerRing, after: segmentStart, blockStart: blockStart, frameCount: frameCount),
                nextDueFrame(midiRing, after: segmentStart, blockStart: blockStart, frameCount: frameCount)
            )
            let activeCount = buildActiveSlots()
            if activeCount == 0 && sidechainEnvelope.isIdle && gainSettled {
                segmentStart = segmentEnd
                continue
            }
            for frame in segmentStart..<segmentEnd {
                duckGain = sidechainEnvelope.isIdle ? 1 : sidechainEnvelope.next()
                if activeCount > 0 {
                    mix(frame: frame, left: left, right: right, activeCount: activeCount)
                    blockPeak = max(blockPeak, abs(left[frame]), abs(right[frame]))
                }
                if !gainSettled { smooth() }
            }
            segmentStart = segmentEnd
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
            let trackIndex = Int(command.track)
            if slotLayer[trackIndex].token != 0 {
                if command.chokeGroup >= 0 {
                    choke(group: command.chokeGroup)
                }
                startLayerVoice(
                    track: command.track,
                    velocity: command.velocity,
                    choke: command.chokeGroup,
                    articulation: command.articulation
                )
            } else {
                guard let ptr = slotPtr[trackIndex], slotCount[trackIndex] > 0 else { return }
                if command.chokeGroup >= 0 {
                    choke(group: command.chokeGroup)
                }
                startVoice(
                    track: command.track,
                    velocity: command.velocity,
                    choke: command.chokeGroup,
                    ptr: ptr,
                    count: slotCount[trackIndex]
                )
            }
            if sidechain.enabled, Int(command.track) == sidechain.source {
                sidechainEnvelope.trigger(depth: sidechain.depth(velocity: command.velocity), releaseMs: sidechain.releaseMs)
            }
        case .setGain:
            let track = Int(command.track)
            targetGain[track] = command.gain
            targetPan[track] = command.pan
            gainSettled = false
        case .swap:
            let track = Int(command.track)
            let old = slotPtr[track]
            let oldCount = slotCount[track]
            let oldToken = slotLayer[track].token
            slotPtr[track] = command.samplePtr
            slotCount[track] = Int(command.sampleCount)
            slotLayer[track] = SlotLayer()
            if let old, !stillUsed(old) {
                retire(old, count: oldCount)
            }
            if oldToken != 0 && !bankReferenced(oldToken) {
                retireBank(oldToken)
            }
        case .swapLayers:
            let track = Int(command.track)
            let old = slotPtr[track]
            let oldCount = slotCount[track]
            let oldToken = slotLayer[track].token
            guard command.bankToken != 0,
                  let raw = UnsafeRawPointer(bitPattern: command.bankToken) else { return }
            let bank = Unmanaged<LayerBank>.fromOpaque(raw).takeUnretainedValue()
            slotPtr[track] = nil
            slotCount[track] = 0
            slotLayer[track] = bank.slotLayer(token: command.bankToken)
            let row = track * 8
            for index in 0..<8 { rrCursor[row + index] = 0 }
            if let old, oldCount > 0, !stillUsed(old) {
                retire(old, count: oldCount)
            }
            if oldToken != 0, oldToken != command.bankToken, !bankReferenced(oldToken) {
                retireBank(oldToken)
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
        count: Int,
        bankToken: UInt = 0,
        layerBPtr: UnsafeMutablePointer<Float>? = nil,
        layerBCount: Int = 0,
        gainA: Float = 1,
        gainB: Float = 0,
        useCurve: Int32 = 0,
        playCount: Int = -1,
        bufferCount: Int = -1
    ) {
        let slot = chooseSlot(track: track)
        let steal = voices[slot].pendingSteal
        // One steal tail per slot. The previous tail goes back through the retire ring.
        if let oldTail = voices[slot].tailPtr {
            let count = voices[slot].tailCount
            let tailTrack = voices[slot].tailTrack
            let tailToken = voices[slot].tailBankToken
            voices[slot].tailPtr = nil
            voices[slot].tailRemaining = 0
            voices[slot].tailLayerBPtr = nil
            voices[slot].tailBankToken = 0
            voices[slot].tailUseCurve = 0
            if tailToken != 0 {
                retireBankIfOrphan(tailToken)
            } else {
                retireIfOrphan(oldTail, count: count, track: tailTrack)
            }
        }
        if voices[slot].active {
            voices[slot].tailPtr = voices[slot].samplePtr
            voices[slot].tailIndex = voices[slot].sampleIndex
            voices[slot].tailCount = voices[slot].sampleCount
            voices[slot].tailVelocity = voices[slot].velocity
            voices[slot].tailTrack = voices[slot].track
            voices[slot].tailRemaining = steal
            voices[slot].tailLength = steal
            voices[slot].tailLayerBPtr = voices[slot].layerBPtr
            voices[slot].tailLayerBCount = voices[slot].layerBCount
            voices[slot].tailGainA = voices[slot].gainA
            voices[slot].tailGainB = voices[slot].gainB
            voices[slot].tailUseCurve = voices[slot].useCurve
            voices[slot].tailBufferCount = voices[slot].bufferCount
            voices[slot].tailBankToken = voices[slot].bankToken
            voices[slot].samplePtr = nil
            voices[slot].layerBPtr = nil
            voices[slot].bankToken = 0
        } else if voices[slot].bankToken != 0 {
            let token = voices[slot].bankToken
            voices[slot].bankToken = 0
            voices[slot].samplePtr = nil
            voices[slot].layerBPtr = nil
            retireBankIfOrphan(token)
        } else if let old = voices[slot].samplePtr {
            let count = voices[slot].sampleCount
            let oldTrack = voices[slot].track
            voices[slot].samplePtr = nil
            retireIfOrphan(old, count: count, track: oldTrack)
        }
        voices[slot].active = true
        voices[slot].track = track
        voices[slot].samplePtr = ptr
        voices[slot].sampleCount = playCount < 0 ? count : playCount
        voices[slot].bufferCount = bufferCount < 0 ? count : bufferCount
        voices[slot].sampleIndex = 0
        voices[slot].velocity = velocity
        voices[slot].chokeGroup = choke
        voices[slot].chokeRemaining = 0
        voices[slot].chokeLength = 0
        voices[slot].pendingSteal = 0
        voices[slot].layerBPtr = layerBPtr
        voices[slot].layerBCount = layerBCount
        voices[slot].gainA = gainA
        voices[slot].gainB = gainB
        voices[slot].useCurve = useCurve
        voices[slot].bankToken = bankToken
        voices[slot].startOrder = orderCounter.load(ordering: .relaxed)
        orderCounter.store(voices[slot].startOrder + 1, ordering: .relaxed)
    }

    /// Picks the layer and an optional crossfade partner. Pointer reads only.
    private func startLayerVoice(track: Int32, velocity: Float, choke: Int32, articulation: Int32) {
        let info = slotLayer[Int(track)]
        let artCount = Int(info.articulationCount)
        let layers = Int(info.layerCount)
        let rrCount = Int(info.roundRobin)
        guard artCount > 0, layers > 0, rrCount > 0,
              let storage = info.storage, let cells = info.cells else { return }
        var art = Int(articulation)
        if art < 0 || art >= artCount { art = 0 }
        let cursorSlot = Int(track) * 8 + min(art, 7)
        var rr = 0
        if rrCount > 1 {
            let cursor = Int(rrCursor[cursorSlot])
            rr = cursor % rrCount
            if rr < 0 { rr = 0 }
            rrCursor[cursorSlot] = Int32((rr + 1) % rrCount)
        }
        let v = min(1, max(0, velocity))
        let artBase = art * layers * rrCount
        var primary = layers - 1
        for layer in 0..<layers {
            if v <= cells[artBase + layer * rrCount].velocityHi {
                primary = layer
                break
            }
        }
        var low = primary
        var high = -1
        let zone: Float = 0.04
        if primary + 1 < layers {
            let boundary = cells[artBase + primary * rrCount].velocityHi
            if v >= boundary - zone && v <= boundary + zone { high = primary + 1 }
        }
        if high < 0, primary > 0 {
            let boundary = cells[artBase + (primary - 1) * rrCount].velocityHi
            if v >= boundary - zone && v <= boundary + zone {
                low = primary - 1
                high = primary
            }
        }
        var weightLow: Float = 1
        var weightHigh: Float = 0
        if high >= 0 {
            let boundary = cells[artBase + low * rrCount].velocityHi
            let t = min(1, max(0, (v - (boundary - zone)) / (zone * 2)))
            // Linear weights. Layers share phase, so equal-power would bump about
            // 3 dB in the middle and the next 0.05 step would fall.
            weightLow = 1 - t
            weightHigh = t
        }
        let cellA = cells[artBase + low * rrCount + rr]
        let ptrA = storage.advanced(by: Int(cellA.offset))
        let countA = Int(cellA.count)
        var gainA = weightLow
        var gainB = weightHigh
        var curveFlag = info.useCurve
        if curveFlag != 0, let curve = info.curve {
            let index = min(127, max(0, Int(v * 127 + 0.5)))
            let gain = curve[index]
            // Buffers are peak-normalized per articulation. Dividing by curve(vRef)
            // makes the next layer quieter at the boundary, so the 0.05 sweep falls.
            gainA = weightLow * gain
            if high >= 0 { gainB = weightHigh * gain }
        }
        var ptrB: UnsafeMutablePointer<Float>? = nil
        var countB = 0
        if high >= 0 {
            let cellB = cells[artBase + high * rrCount + rr]
            ptrB = storage.advanced(by: Int(cellB.offset))
            countB = Int(cellB.count)
        } else if curveFlag == 0 {
            gainA = 1
        }
        if ptrB == nil && curveFlag == 0 { curveFlag = 0 }
        let play = max(countA, countB)
        startVoice(
            track: track,
            velocity: velocity,
            choke: choke,
            ptr: ptrA,
            count: countA,
            bankToken: info.token,
            layerBPtr: ptrB,
            layerBCount: countB,
            gainA: gainA,
            gainB: gainB,
            useCurve: curveFlag,
            playCount: play,
            bufferCount: countA
        )
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

    private func buildActiveSlots() -> Int {
        var count = 0
        for index in 0..<Self.voiceCount {
            if voices[index].active || voices[index].tailRemaining > 0 {
                activeSlots[count] = index
                count += 1
            }
        }
        return count
    }

    private func mix(
        frame: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        activeCount: Int
    ) {
        for slotIdx in 0..<activeCount {
            let index = activeSlots[slotIdx]
            if voices[index].tailRemaining > 0, let ptr = voices[index].tailPtr {
                let scale = Float(voices[index].tailRemaining) / Float(max(voices[index].tailLength, 1))
                if voices[index].tailLayerBPtr == nil && voices[index].tailUseCurve == 0 {
                    if voices[index].tailIndex < voices[index].tailCount {
                        let sample = ptr[voices[index].tailIndex] * voices[index].tailVelocity * scale
                        add(sample, track: Int(voices[index].tailTrack), frame: frame, left: left, right: right)
                        voices[index].tailIndex += 1
                        voices[index].tailRemaining -= 1
                        if voices[index].tailRemaining == 0 {
                            retireIfOrphan(voices[index].tailPtr, count: voices[index].tailCount, track: voices[index].tailTrack)
                            voices[index].tailPtr = nil
                        }
                    }
                } else {
                    var sample: Float = 0
                    if voices[index].tailIndex < voices[index].tailBufferCount {
                        sample = ptr[voices[index].tailIndex] * voices[index].tailGainA
                        if voices[index].tailUseCurve == 0 { sample *= voices[index].tailVelocity }
                    }
                    if let bPtr = voices[index].tailLayerBPtr,
                       voices[index].tailIndex < voices[index].tailLayerBCount {
                        var extra = bPtr[voices[index].tailIndex] * voices[index].tailGainB
                        if voices[index].tailUseCurve == 0 { extra *= voices[index].tailVelocity }
                        sample += extra
                    }
                    add(sample * scale, track: Int(voices[index].tailTrack), frame: frame, left: left, right: right)
                    voices[index].tailIndex += 1
                    voices[index].tailRemaining -= 1
                    if voices[index].tailRemaining == 0 {
                        let token = voices[index].tailBankToken
                        let tailPtr = voices[index].tailPtr
                        let tailCount = voices[index].tailCount
                        let tailTrack = voices[index].tailTrack
                        voices[index].tailPtr = nil
                        voices[index].tailLayerBPtr = nil
                        voices[index].tailBankToken = 0
                        voices[index].tailUseCurve = 0
                        if token != 0 {
                            retireBankIfOrphan(token)
                        } else {
                            retireIfOrphan(tailPtr, count: tailCount, track: tailTrack)
                        }
                    }
                }
            }

            guard voices[index].active, let ptr = voices[index].samplePtr else { continue }
            guard voices[index].sampleIndex < voices[index].sampleCount else { continue }

            var sample: Float
            if voices[index].layerBPtr == nil && voices[index].useCurve == 0 {
                sample = ptr[voices[index].sampleIndex] * voices[index].velocity
            } else {
                sample = 0
                if voices[index].sampleIndex < voices[index].bufferCount {
                    sample = ptr[voices[index].sampleIndex] * voices[index].gainA
                    if voices[index].useCurve == 0 { sample *= voices[index].velocity }
                }
                if let bPtr = voices[index].layerBPtr,
                   voices[index].sampleIndex < voices[index].layerBCount {
                    var extra = bPtr[voices[index].sampleIndex] * voices[index].gainB
                    if voices[index].useCurve == 0 { extra *= voices[index].velocity }
                    sample += extra
                }
            }
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
        if duckGain < 1, track < 8, (sidechain.mask >> UInt8(track)) & 1 == 1 { gain *= duckGain }
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
    /// A pass that changes no bit is a fixed point: every later pass would be a no-op too,
    /// so `gainSettled` skips it until a setGain moves a target (bit-identical output).
    private func smooth() {
        var changed = false
        for track in 0..<Self.slotCount {
            let before = smoothGain[track]
            var next = before + gainAlpha * (targetGain[track] - before)
            if abs(next) < 1e-15 { next = 0 }
            smoothGain[track] = next
            if next.bitPattern != before.bitPattern { changed = true }
        }
        if !changed { gainSettled = true }
    }

    /// First frame after `frame` on which this lane's head command is due, or `frameCount`.
    /// Mirrors `drain`: a non-trigger head (or a trigger already due) is due on the next frame.
    private func nextDueFrame(_ ring: CommandRing, after frame: Int, blockStart: Int64, frameCount: Int) -> Int {
        guard let command = ring.peek() else { return frameCount }
        guard command.kind == .trigger, command.atSample > blockStart + Int64(frame) else {
            return min(frame + 1, frameCount)
        }
        let due = command.atSample - blockStart
        return due >= Int64(frameCount) ? frameCount : Int(due)
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
        let token = voices[index].bankToken
        voices[index].samplePtr = nil
        voices[index].layerBPtr = nil
        voices[index].useCurve = 0
        voices[index].bankToken = 0
        if token != 0 {
            retireBankIfOrphan(token)
        } else {
            retireIfOrphan(ptr, count: count, track: track)
        }
    }

    private func bankReferenced(_ token: UInt) -> Bool {
        if token == 0 { return false }
        for slot in 0..<Self.slotCount where slotLayer[slot].token == token { return true }
        for index in 0..<Self.voiceCount {
            if voices[index].bankToken == token || voices[index].tailBankToken == token { return true }
        }
        return false
    }

    private func retireBankIfOrphan(_ token: UInt) {
        guard token != 0, !bankReferenced(token) else { return }
        retireBank(token)
    }

    private func retireBank(_ token: UInt) {
        guard token != 0 else { return }
        if pushRetired(Retired(token: token)) { return }
        if backlogCount < Self.backlogCapacity {
            backlog[backlogCount] = Retired(token: token)
            backlogCount += 1
            backlogPublished.store(backlogCount, ordering: .releasing)
        } else {
            _ = leakCounter.wrappingAdd(1, ordering: .relaxed)
        }
    }

    /// Main-actor drain and engine teardown. Not called from the render callback.
    private func freeRetired(_ item: Retired) {
        if item.token != 0 {
            if let raw = UnsafeRawPointer(bitPattern: item.token) {
                Unmanaged<LayerBank>.fromOpaque(raw).release()
            }
            return
        }
        if let ptr = item.ptr, item.count > 0 {
            ptr.deinitialize(count: item.count)
            ptr.deallocate()
        }
    }

    /// Engine teardown only. A fixed table so this stays off the render callback's allocator.
    private func releaseBanksStillHeld() {
        let capacity = Self.voiceCount * 2 + Self.slotCount
        let seen = UnsafeMutablePointer<UInt>.allocate(capacity: capacity)
        seen.initialize(repeating: 0, count: capacity)
        var count = 0
        func once(_ token: UInt) {
            guard token != 0 else { return }
            for index in 0..<count where seen[index] == token { return }
            if count < capacity {
                seen[count] = token
                count += 1
            }
            if let raw = UnsafeRawPointer(bitPattern: token) {
                Unmanaged<LayerBank>.fromOpaque(raw).release()
            }
        }
        for index in 0..<Self.voiceCount {
            once(voices[index].bankToken)
            once(voices[index].tailBankToken)
        }
        for slot in 0..<Self.slotCount {
            once(slotLayer[slot].token)
            slotLayer[slot].token = 0
        }
        seen.deinitialize(count: capacity)
        seen.deallocate()
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

    var retireBacklogCount: Int { backlogPublished.load(ordering: .acquiring) }
    var leakedBufferCount: Int { leakCounter.load(ordering: .acquiring) }

    /// Render thread. Never frees: a full ring parks the pointer in the preallocated backlog.
    private func retire(_ ptr: UnsafeMutablePointer<Float>, count: Int) {
        if pushRetired(Retired(ptr: ptr, count: count)) { return }
        if backlogCount < Self.backlogCapacity {
            backlog[backlogCount] = Retired(ptr: ptr, count: count)
            backlogCount += 1
            backlogPublished.store(backlogCount, ordering: .releasing)
        } else {
            _ = leakCounter.wrappingAdd(1, ordering: .relaxed)
        }
    }

    private func pushRetired(_ item: Retired) -> Bool {
        let head = retiredHead.load(ordering: .relaxed)
        let tail = retiredTail.load(ordering: .acquiring)
        if head - tail >= retireCapacity { return false }
        retired[head & retireMask] = item
        retiredHead.store(head + 1, ordering: .releasing)
        return true
    }

    /// Render thread, block start: re-offer parked pointers once the main actor made room.
    private func flushBacklog() {
        guard backlogCount > 0 else { return }
        var moved = 0
        while moved < backlogCount, pushRetired(backlog[moved]) { moved += 1 }
        guard moved > 0 else { return }
        for index in moved..<backlogCount { backlog[index - moved] = backlog[index] }
        backlogCount -= moved
        backlogPublished.store(backlogCount, ordering: .releasing)
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
    var bufferCount = 0
    var layerBPtr: UnsafeMutablePointer<Float>? = nil
    var layerBCount = 0
    var gainA: Float = 1
    var gainB: Float = 0
    var useCurve: Int32 = 0
    var bankToken: UInt = 0
    var tailLayerBPtr: UnsafeMutablePointer<Float>? = nil
    var tailLayerBCount = 0
    var tailGainA: Float = 1
    var tailGainB: Float = 0
    var tailUseCurve: Int32 = 0
    var tailBufferCount = 0
    var tailBankToken: UInt = 0
}

nonisolated enum CommandKind: Int32 {
    case trigger = 0
    // 1 was stopAll; stop now goes through pendingFade.
    case setGain = 2
    case swap = 3
    case swapLayers = 4
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
    var articulation: Int32 = 0
    var bankToken: UInt = 0
}

nonisolated private struct Retired {
    var ptr: UnsafeMutablePointer<Float>?
    var count = 0
    var token: UInt = 0
}
