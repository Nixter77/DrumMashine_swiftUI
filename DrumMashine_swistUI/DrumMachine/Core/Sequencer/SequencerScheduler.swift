import Foundation
import Synchronization

nonisolated struct StepSnapshot: Sendable {
    var isActive: Bool
    var velocity: Float
    var probability: Float
}

nonisolated struct TrackSnapshot: Sendable {
    var steps: [StepSnapshot]
    var isMuted: Bool
    var isSolo: Bool
    var volume: Float
    var pan: Float
    var chokeGroup: Int
}

nonisolated struct PatternSnapshot: Sendable {
    var tracks: [TrackSnapshot]
    var stepCount: Int
    var bpm: Double
    var swing: Double
    var humanize: Double
    var groove: GrooveSnapshot = .clean

    static let empty = PatternSnapshot(tracks: [], stepCount: 16, bpm: 120, swing: 0, humanize: 0)
}

nonisolated struct TransportPosition: Sendable {
    var anchor: Int64
    var samplesPerStep: Double
    var stepNumberAtAnchor: Int
    var stepCount: Int
    var isPlaying: Bool

    func stepIndex(at heardFrame: Int64) -> Int {
        guard stepCount > 0, samplesPerStep > 0 else { return 0 }
        if heardFrame < anchor {
            if stepNumberAtAnchor == 0 { return 0 }
            return positiveMod(stepNumberAtAnchor - 1, stepCount)
        }
        let stepsIn = Int((Double(heardFrame - anchor) / samplesPerStep).rounded(.down))
        return positiveMod(stepNumberAtAnchor + stepsIn, stepCount)
    }

    /// Recording quantizes to the nearest step. `stepIndex` stays on the floor for the playhead.
    func nearestStepIndex(at heardFrame: Int64) -> Int {
        guard stepCount > 0, samplesPerStep > 0 else { return 0 }
        let stepsFromAnchor = (Double(heardFrame - anchor) / samplesPerStep).rounded()
        guard stepsFromAnchor.isFinite, let steps = Int(exactly: stepsFromAnchor) else { return 0 }
        return positiveMod(stepNumberAtAnchor + steps, stepCount)
    }
}

/// Sample-accurate step scheduler. Timing state stays on `queue`.
/// The render thread is reached only through `VoiceEngine`'s lock-free ring.
/// `@unchecked Sendable`: the queue owns the clock, the snapshot sits in a `Mutex`,
/// and `VoiceEngine` is shared only via its atomic API.
nonisolated struct SchedulerCheckpoint: Sendable {
    var wasPlaying: Bool
    var step: Int
}

nonisolated final class SequencerScheduler: @unchecked Sendable {
    private(set) var sampleRate: Double
    private var voiceEngine: VoiceEngine
    private let queue: DispatchQueue
    private let snapshot = Mutex(PatternSnapshot.empty)
    private var timer: DispatchSourceTimer?

    private var playing = false
    private var generation = 0
    private var anchor: Int64 = 0
    private var nextK = 0
    private var stepNumberAtAnchor = 0
    private var samplesPerStep: Double = 6_000
    private var appliedBpm: Double = 120
    private var lookaheadFrames: Int64 = 1_440
    private var rng: UInt64 = 0x4D595DF4D0F33173
    private var sentGain = [Float](repeating: .nan, count: 8)
    private var sentPan = [Float](repeating: .nan, count: 8)
    /// Last atSample pushed to the voice ring. The ring is FIFO and stops at the first future
    /// trigger, so pushes must never go backwards in time (groove offsets differ per track).
    private var lastEmitted: Int64 = 0
    /// Per-step trigger scratch, sized once; reused without allocating.
    private var pendingTrack = [Int](repeating: 0, count: 16)
    private var pendingVelocity = [Float](repeating: 0, count: 16)
    private var pendingChoke = [Int](repeating: 0, count: 16)
    private var pendingTime = [Int64](repeating: 0, count: 16)

    private let publishedAnchor = Atomic<Int64>(0)
    private let publishedSamplesBits = Atomic<UInt64>(0)
    private let publishedStepNumber = Atomic<Int>(0)
    private let publishedStepCount = Atomic<Int>(16)
    private let publishedPlaying = Atomic<Int>(0)

    init(voiceEngine: VoiceEngine, sampleRate: Double) {
        self.voiceEngine = voiceEngine
        self.sampleRate = sampleRate
        queue = DispatchQueue(label: "com.drummachine.scheduler", qos: .userInteractive)
    }

    func replace(_ pattern: PatternSnapshot) {
        snapshot.withLock { $0 = pattern }
    }

    func pattern() -> PatternSnapshot {
        snapshot.withLock { $0 }
    }

    func update(_ body: (inout PatternSnapshot) -> Void) {
        snapshot.withLock { body(&$0) }
    }

    func transport() -> TransportPosition {
        TransportPosition(
            anchor: publishedAnchor.load(ordering: .acquiring),
            samplesPerStep: Double(bitPattern: publishedSamplesBits.load(ordering: .acquiring)),
            stepNumberAtAnchor: publishedStepNumber.load(ordering: .acquiring),
            stepCount: publishedStepCount.load(ordering: .acquiring),
            isPlaying: publishedPlaying.load(ordering: .acquiring) != 0
        )
    }

    /// `timer` is false in offline tests, which drive `scheduleDue(now:)` themselves.
    func begin(at frame: Int64, ioBufferFrames: Int, timer: Bool) {
        queue.sync {
            guard !playing else { return }
            let snap = snapshot.withLock { $0 }
            lastEmitted = 0
            playing = true
            let thirtyMs = Int((0.030 * sampleRate).rounded())
            lookaheadFrames = Int64(max(thirtyMs, 2 * max(1, ioBufferFrames)))
            anchor = frame
            stepNumberAtAnchor = 0
            nextK = 0
            appliedBpm = snap.bpm
            samplesPerStep = Self.samplesPerStep(bpm: snap.bpm, sampleRate: sampleRate)
            voiceEngine.setAcceptedGeneration(generation)
            publish(stepCount: snap.stepCount)
            if timer { startTimer() }
            scheduleDueOnQueue(now: frame)
        }
    }

    func stop() {
        queue.sync {
            playing = false
            generation &+= 1
            timer?.cancel()
            timer = nil
            voiceEngine.setAcceptedGeneration(generation)
            let fade = max(1, Int((0.005 * sampleRate).rounded()))
            voiceEngine.stopAll(fadeFrames: fade)
            publishedPlaying.store(0, ordering: .releasing)
        }
    }

    /// Pause the timer and drop triggers already in the ring. The step is the one
    /// sounding at `renderedFrames`, so a device change can start again on that step.
    func checkpointAndPause() -> SchedulerCheckpoint {
        queue.sync {
            let snap = snapshot.withLock { $0 }
            let stepCount = max(snap.stepCount, 1)
            let step: Int
            if playing {
                let position = TransportPosition(
                    anchor: anchor,
                    samplesPerStep: samplesPerStep,
                    stepNumberAtAnchor: stepNumberAtAnchor,
                    stepCount: stepCount,
                    isPlaying: true
                )
                step = position.stepIndex(at: voiceEngine.renderedFrames)
            } else {
                step = 0
            }
            let wasPlaying = playing
            playing = false
            timer?.cancel()
            timer = nil
            generation &+= 1
            voiceEngine.setAcceptedGeneration(generation)
            let fade = max(1, Int((0.005 * sampleRate).rounded()))
            voiceEngine.stopAll(fadeFrames: fade)
            publishedPlaying.store(0, ordering: .releasing)
            return SchedulerCheckpoint(wasPlaying: wasPlaying, step: step)
        }
    }

    /// Point the scheduler at a rebuilt voice engine after the output rate changes.
    func retarget(voiceEngine: VoiceEngine, sampleRate: Double) {
        queue.sync {
            self.voiceEngine = voiceEngine
            self.sampleRate = sampleRate
            sentGain = Array(repeating: .nan, count: sentGain.count)
            sentPan = Array(repeating: .nan, count: sentPan.count)
        }
    }

    /// Continue from `step` at `frame` on the audio clock. `timer` is false in offline tests.
    func resume(atStep step: Int, frame: Int64, ioBufferFrames: Int, timer: Bool = true) {
        queue.sync {
            guard !playing else { return }
            let snap = snapshot.withLock { $0 }
            let count = max(snap.stepCount, 1)
            lastEmitted = 0
            playing = true
            let thirtyMs = Int((0.030 * sampleRate).rounded())
            lookaheadFrames = Int64(max(thirtyMs, 2 * max(1, ioBufferFrames)))
            anchor = frame
            stepNumberAtAnchor = positiveMod(step, count)
            nextK = 0
            appliedBpm = snap.bpm
            samplesPerStep = Self.samplesPerStep(bpm: snap.bpm, sampleRate: sampleRate)
            voiceEngine.setAcceptedGeneration(generation)
            publish(stepCount: count)
            if timer { startTimer() }
            scheduleDueOnQueue(now: frame)
        }
    }

    /// Schedule every step whose grid time falls before `now + lookahead`.
    /// Safe to call from tests when the timer is not running.
    func scheduleDue(now: Int64) {
        queue.sync { scheduleDueOnQueue(now: now) }
    }

    static func samplesPerStep(bpm: Double, sampleRate: Double) -> Double {
        60.0 / max(bpm, 1) / 4.0 * sampleRate
    }

    private func startTimer() {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + .milliseconds(5), repeating: .milliseconds(5), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.scheduleDueOnQueue(now: self.voiceEngine.renderedFrames)
        }
        timer = source
        source.resume()
    }

    private func scheduleDueOnQueue(now: Int64) {
        guard playing, samplesPerStep >= 0.5 else { return }
        let snap = snapshot.withLock { $0 }
        if snap.bpm != appliedBpm {
            reanchor(snap)
        }
        pushGains(snap)
        publishedStepCount.store(max(snap.stepCount, 1), ordering: .releasing)
        let horizon = now + lookaheadFrames
        var budget = 256
        while budget > 0 {
            let stepIndex = stepNumberAtAnchor + nextK
            let grid = anchor + Int64((Double(nextK) * samplesPerStep).rounded())
            var offset = 0.0
            if stepIndex % 2 == 1 {
                offset += (snap.swing / 100.0) * samplesPerStep * 0.5
            }
            // Groove can pull a track early; decide from the earliest possible hit
            // so a deferred step does not consume the RNG.
            // Groove slots follow the pattern step, so 8-step patterns use the same 8 slots every bar.
            let grooveSlot = positiveMod(stepIndex, max(snap.stepCount, 1))
            let grooveSteps = snap.groove.isActive ? snap.groove.timingOffset(step: grooveSlot) : 0
            let earliest = max(-0.45 * samplesPerStep, offset + min(0, grooveSteps * samplesPerStep))
            if grid + Int64(earliest.rounded()) >= horizon {
                break
            }
            if snap.humanize > 0 {
                let depth = (snap.humanize / 100.0) * 0.1 * samplesPerStep
                offset += depth * nextUnitSigned()
            }
            fire(stepIndex: stepIndex, grid: grid, baseOffset: offset, grooveSteps: grooveSteps, now: now, snap: snap)
            nextK += 1
            budget -= 1
        }
    }

    private func reanchor(_ snap: PatternSnapshot) {
        let nextGrid = anchor + Int64((Double(nextK) * samplesPerStep).rounded())
        stepNumberAtAnchor += nextK
        anchor = nextGrid
        nextK = 0
        appliedBpm = snap.bpm
        samplesPerStep = Self.samplesPerStep(bpm: snap.bpm, sampleRate: sampleRate)
        publish(stepCount: snap.stepCount)
    }

    /// Every hit stays within [-0.45, +0.5] step of its grid line. Swing (<= 0.5) is intact,
    /// and a negative groove/humanize pull on step k+1 can no longer land behind step k,
    /// so pushes stay time-ordered across steps (lastEmitted then never has to merge hits).
    @inline(__always) private func clampOffset(_ offset: Double) -> Double {
        min(0.5 * samplesPerStep, max(-0.45 * samplesPerStep, offset))
    }

    private func fire(stepIndex: Int, grid: Int64, baseOffset: Double, grooveSteps: Double, now: Int64, snap: PatternSnapshot) {
        let count = snap.stepCount
        guard count > 0 else { return }
        let groove = snap.groove
        let patternStep = positiveMod(stepIndex, count)
        let plainTime = max(now, grid + Int64(clampOffset(baseOffset).rounded()))
        var grooveTime = plainTime
        var velMul: Float = 1
        if groove.isActive {
            var off = baseOffset + grooveSteps * samplesPerStep
            if groove.randomDepth > 0 { off += groove.randomDepth * samplesPerStep * nextUnitSigned() }
            grooveTime = max(now, grid + Int64(clampOffset(off).rounded()))
            velMul = Float(groove.velocityMul(step: patternStep))
        }
        var pending = 0
        let hasSolo = snap.tracks.contains { $0.isSolo }
        for (index, track) in snap.tracks.enumerated() {
            if track.isMuted { continue }
            if hasSolo && !track.isSolo { continue }
            guard patternStep < track.steps.count else { continue }
            let step = track.steps[patternStep]
            guard step.isActive else { continue }
            if step.probability < 1 {
                if nextUnit01() > Double(step.probability) { continue }
            }
            guard pending < pendingTrack.count else { break }
            let grooved = groove.isActive && groove.isOn(track: index)
            pendingTrack[pending] = index
            pendingVelocity[pending] = grooved ? min(1, max(0, step.velocity * velMul)) : step.velocity
            pendingChoke[pending] = track.chokeGroup
            pendingTime[pending] = grooved ? grooveTime : plainTime
            pending += 1
        }
        // Push in time order (insertion sort, n <= 16) and never behind the previous push.
        if pending > 1 {
            for i in 1..<pending {
                var j = i
                while j > 0 && pendingTime[j - 1] > pendingTime[j] {
                    pendingTime.swapAt(j - 1, j); pendingTrack.swapAt(j - 1, j)
                    pendingVelocity.swapAt(j - 1, j); pendingChoke.swapAt(j - 1, j)
                    j -= 1
                }
            }
        }
        for i in 0..<pending {
            let at = max(pendingTime[i], lastEmitted)
            lastEmitted = at
            voiceEngine.trigger(
                track: pendingTrack[i],
                velocity: pendingVelocity[i],
                chokeGroup: pendingChoke[i],
                atSample: at,
                generation: generation,
                lane: .sequencer
            )
        }
    }

    private func pushGains(_ snap: PatternSnapshot) {
        for (index, track) in snap.tracks.enumerated() where index < sentGain.count {
            if sentGain[index] != track.volume || sentPan[index] != track.pan {
                sentGain[index] = track.volume
                sentPan[index] = track.pan
                voiceEngine.setTrackGain(track: index, gain: track.volume, pan: track.pan, lane: .sequencer)
            }
        }
    }

    private func publish(stepCount: Int) {
        publishedAnchor.store(anchor, ordering: .releasing)
        publishedSamplesBits.store(samplesPerStep.bitPattern, ordering: .releasing)
        publishedStepNumber.store(stepNumberAtAnchor, ordering: .releasing)
        publishedStepCount.store(max(stepCount, 1), ordering: .releasing)
        publishedPlaying.store(playing ? 1 : 0, ordering: .releasing)
    }

    private func nextUnit01() -> Double {
        rng = rng &* 6364136223846793005 &+ 1
        return Double(rng >> 11) / Double(UInt64.max >> 11)
    }

    private func nextUnitSigned() -> Double {
        nextUnit01() * 2 - 1
    }
}

nonisolated private func positiveMod(_ value: Int, _ count: Int) -> Int {
    let mod = value % count
    return mod >= 0 ? mod : mod + count
}
