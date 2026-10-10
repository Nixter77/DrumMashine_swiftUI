import Foundation
import Observation

// MARK: - Record Mode
enum RecordMode: String, CaseIterable {
    case off = "OFF"
    case overdub = "OVERDUB"
    case replace = "REPLACE"
}

// MARK: - Step Count options
nonisolated enum StepCount: Int, CaseIterable, Codable, Equatable {
    case eight = 8
    case sixteen = 16
    case thirtyTwo = 32
    
    var label: String {
        switch self {
        case .eight: return "8"
        case .sixteen: return "16"
        case .thirtyTwo: return "32"
        }
    }
}

/// Tap tempo from a monotonic timeline. The median uses the last four intervals.
nonisolated struct TapTempo {
    private var times: [Double] = []

    /// BPM after this tap, or nil when there is not yet a positive interval.
    mutating func register(at seconds: Double) -> Double? {
        if let last = times.last, seconds - last > 2 || seconds < last {
            times.removeAll()
        }
        times.append(seconds)
        if times.count > 5 {
            times.removeFirst(times.count - 5)
        }
        let intervals = zip(times, times.dropFirst()).map { earlier, later in later - earlier }
        guard let gap = Self.median(intervals), gap > 0 else { return nil }
        return 60 / gap
    }

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

/// The one live sequencer of the app. Created lazily on first use, outside any view
/// init, so the theme's `.id` rebuild (or a re-run of the App body) never makes another.
enum AppSequencer {
    static let shared: SequencerEngine = {
        let engine = SequencerEngine(session: SessionStore.load())
        engine.becomeDeviceChangeOwner()
        return engine
    }()
}

// MARK: - SequencerEngine (drift-compensated, with swing, mute/solo, recording)
@Observable
class SequencerEngine {
    var tracks: [SequencerTrack] = [] {
        didSet { publishSnapshot() }
    }
    /// Stored value. The public setter clamps, so `didSet` never writes `bpm` again.
    private var bpmValue: Double = 120
    var bpm: Double {
        get { bpmValue }
        set {
            let clamped = min(300, max(40, newValue))
            guard clamped != bpmValue else { return }
            bpmValue = clamped
            publishSnapshot()
            // Reads bpmValue. Must not assign `bpm` (that re-enters this setter).
            AudioEngineManager.shared.retimeSyncedDelay(bpm: clamped)
        }
    }
    
    var isPlaying: Bool = false
    var currentStep: Int = 0
    
    // Step count: 8, 16, or 32 steps
    var stepCount: StepCount = .sixteen {
        didSet {
            // Ensure all tracks have enough steps
            let count = stepCount.rawValue
            for i in 0..<tracks.count {
                while tracks[i].steps.count < count {
                    tracks[i].steps.append(SequencerStep())
                }
            }
            // Clamp currentStep
            if currentStep >= count { currentStep = 0 }
            publishSnapshot()
        }
    }
    
    // Swing: 0% = straight, 50% = triplet feel, 100% = dotted
    var swing: Double = 0.0 {
        didSet {
            let clamped = max(0, min(100, swing))
            if clamped != swing { swing = clamped }
            publishSnapshot()
        }
    }
    
    // Humanize: adds subtle random timing offset (0 = off, 100 = max groove)
    var humanize: Double = 0.0 {
        didSet {
            let clamped = max(0, min(100, humanize))
            if clamped != humanize { humanize = clamped }
            publishSnapshot()
        }
    }
    
    // Groove Quantize: non-destructive timing/velocity feel applied at playback.
    var grooveSettings = GrooveSettings() {
        didSet { if grooveSettings != oldValue { publishSnapshot() } }
    }

    /// Factory grooves first, then the user's.
    var availableGrooves: [GrooveTemplate] { FactoryGrooves.all + UserGrooveStore.shared.grooves }

    var activeGroove: GrooveTemplate? {
        availableGrooves.first { $0.id == grooveSettings.grooveID }
    }

    // MARK: Fill
    /// FILL held in the UI.
    var fillHeld = false { didSet { if fillHeld != oldValue { publishSnapshot() } } }
    /// Key F: one fill at the end of the current loop, then off.
    var fillOnce = false { didSet { if fillOnce != oldValue { publishSnapshot() } } }
    /// 0 = off, otherwise a fill at the end of every Nth loop.
    var autoFillEvery: Int = UserDefaults.standard.integer(forKey: "autoFillEvery") {
        didSet { UserDefaults.standard.set(autoFillEvery, forKey: "autoFillEvery"); updateAutoFill() }
    }
    var fillStyle: FillStyle = FillStyle(rawValue: UserDefaults.standard.string(forKey: "fillStyle") ?? "") ?? .snareRoll {
        didSet { UserDefaults.standard.set(fillStyle.rawValue, forKey: "fillStyle"); if isFillActive { publishSnapshot() } }
    }
    @ObservationIgnored private var loopsPlayed = 0
    private(set) var autoFillActive = false
    var isFillActive: Bool { fillHeld || fillOnce || autoFillActive }

    private func updateAutoFill() {
        let next = autoFillEvery > 0 && isPlaying && (loopsPlayed + 1) % autoFillEvery == 0
        if next != autoFillActive { autoFillActive = next; publishSnapshot() }
    }

    /// Heard playhead wrapped to step 0.
    private func loopWrapped() {
        loopsPlayed += 1
        if fillOnce { fillOnce = false }
        updateAutoFill()
    }

    // Recording
    var recordMode: RecordMode = .off

    /// Set by «Загрузить кит». A later pad edit appends `*`. A pattern load clears it.
    var loadedKitName: String?
    var loadedKitEdited = false

    var kitBadge: String? {
        guard let loadedKitName else { return nil }
        return loadedKitEdited ? "\(loadedKitName)*" : loadedKitName
    }
    
    private let scheduler: SequencerScheduler
    @ObservationIgnored private(set) var playheadTask: Task<Void, Never>?
    /// Pattern apply assigns several fields. Publish the scheduler snapshot once, at the end.
    @ObservationIgnored private var suppressSnapshot = false
    /// Launch publishes one snapshot. That publish must not write session.json.
    @ObservationIgnored private var suppressSessionSave = false
    
    // Tap tempo. ContinuousClock does not jump when the wall clock does.
    private var taps = TapTempo()
    private let tapClock = ContinuousClock()
    private var tapOrigin: ContinuousClock.Instant?
    
    // Choke group map (per sound category)
    // HiHat closed (index 2) and Ride (index 5) are in group 1
    private let chokeGroups: [Int: Int] = [2: 1, 5: 1]
    
    /// `session` nil, or a session with no tracks, uses the library defaults. Playback stays stopped.
    init(session: SessionState? = nil) {
        let audio = AudioEngineManager.shared
        scheduler = SequencerScheduler(
            voiceEngine: audio.voiceEngineForScheduler(),
            sampleRate: audio.outputSampleRate
        )
        suppressSessionSave = true
        let library = SoundLibraryManager.shared
        if let session, !session.tracks.isEmpty {
            bpmValue = min(300, max(40, session.bpm))
            swing = min(100, max(0, session.swing))
            humanize = min(100, max(0, session.humanize))
            grooveSettings = session.groove
            stepCount = session.stepCount
        }
        let count = stepCount.rawValue
        var built: [SequencerTrack] = []
        built.reserveCapacity(8)
        for index in 0..<8 {
            let source = session?.tracks
            if let source, index < source.count {
                var track = source[index]
                while track.steps.count < count {
                    track.steps.append(SequencerStep())
                }
                built.append(track)
            } else {
                built.append(SequencerTrack(
                    soundPreset: library.defaultPreset(forTrackIndex: index),
                    stepsCount: count
                ))
            }
        }
        tracks = built
        for (index, track) in tracks.enumerated() {
            audio.setTrackVolume(track.volume, trackIndex: index)
            audio.setTrackPan(track.pan, trackIndex: index)
        }
        publishSnapshot()
        suppressSessionSave = false
    }

    /// The engine stops itself on an output-device change. Keep the musical step and
    /// retarget this scheduler once the voice engine has been rebuilt.
    /// Called once, by the app-level owner (`AppSequencer`). Other instances (tests,
    /// previews, snapshot views) never take the handlers over.
    func becomeDeviceChangeOwner() {
        AudioEngineManager.shared.setDeviceChangeHandlers(
            owner: self,
            suspend: { [weak self] in
                guard let self else { return (wasPlaying: false, step: 0) }
                let checkpoint = self.scheduler.checkpointAndPause()
                return (wasPlaying: checkpoint.wasPlaying, step: checkpoint.step)
            },
            resume: { [weak self] engine, rate, step, wasPlaying in
                self?.resumeAfterDeviceChange(
                    voiceEngine: engine,
                    sampleRate: rate,
                    step: step,
                    wasPlaying: wasPlaying
                )
            }
        )
    }

    private func resumeAfterDeviceChange(
        voiceEngine: VoiceEngine,
        sampleRate: Double,
        step: Int,
        wasPlaying: Bool
    ) {
        scheduler.retarget(voiceEngine: voiceEngine, sampleRate: sampleRate)
        guard wasPlaying, isPlaying else {
            if !wasPlaying { isPlaying = false }
            return
        }
        let audio = AudioEngineManager.shared
        scheduler.resume(
            atStep: step,
            frame: audio.renderedFrames,
            ioBufferFrames: audio.renderQuantum
        )
        print("🔁 Sequencer resumed at step \(step)")
    }
    
    // MARK: - Playback Control
    
    func togglePlayPause() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }
    
    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        currentStep = 0
        loopsPlayed = 0
        autoFillActive = autoFillEvery == 1
        publishSnapshot()
        let audio = AudioEngineManager.shared
        scheduler.begin(at: audio.renderedFrames, ioBufferFrames: audio.renderQuantum, timer: true)
        startPlayhead()
    }
    
    func stop() {
        isPlaying = false
        currentStep = 0
        fillOnce = false
        autoFillActive = false
        scheduler.stop()
        playheadTask?.cancel()
        playheadTask = nil
    }

    /// Scheduler snapshots published so far. Test hook for batching (#9).
    @ObservationIgnored private(set) var snapshotPublishCount = 0

    private func publishSnapshot() {
        if suppressSnapshot { return }
        snapshotPublishCount += 1
        let count = stepCount.rawValue
        // While FILL is active the end of the loop plays the fill instead of the pattern (pattern untouched).
        let fill: [[Float?]]? = isFillActive
            ? FillGenerator.apply(fillStyle,
                                  base: tracks.map { t in t.steps.prefix(count).map { $0.isActive ? $0.velocity : nil } },
                                  stepCount: count)
            : nil
        let snapTracks: [TrackSnapshot] = tracks.enumerated().map { index, track in
            let steps = track.steps.prefix(count).enumerated().map { s, step in
                if let fill, index < fill.count, s < fill[index].count {
                    let v = fill[index][s]
                    return StepSnapshot(isActive: v != nil, velocity: v ?? step.velocity,
                                        probability: v == nil ? 1 : (s >= FillGenerator.regionStart(stepCount: count) ? 1 : step.probability))
                }
                return StepSnapshot(isActive: step.isActive, velocity: step.velocity, probability: step.probability)
            }
            return TrackSnapshot(
                steps: Array(steps),
                isMuted: track.isMuted,
                isSolo: track.isSolo,
                volume: track.volume,
                pan: track.pan,
                chokeGroup: track.soundPreset.chokeGroup ?? chokeGroups[index] ?? -1
            )
        }
        scheduler.replace(PatternSnapshot(
            tracks: snapTracks,
            stepCount: count,
            bpm: bpm,
            swing: swing,
            humanize: humanize,
            groove: GrooveSnapshot(template: activeGroove, settings: grooveSettings)
        ))
        if !suppressSessionSave {
            SessionStore.noteSequencer(self)
            PatternManager.shared.updateActive(from: self)
        }
    }

    /// Runs only while playing (started by play(), cancelled by stop()).
    /// The step index follows the audio clock, not the schedule window.
    private func startPlayhead() {
        playheadTask?.cancel()
        playheadTask = Task { @MainActor [weak self] in
            // Ends as soon as the engine is gone; it does not spin on a nil self.
            while !Task.isCancelled, let self {
                self.refreshPlayhead()
                // UI poll only (lock-free reads; currentStep changes once per step).
                // 16 ms = one 60 Hz frame; faster polling cannot be seen.
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }

    private func refreshPlayhead() {
        guard isPlaying else { return }
        let position = scheduler.transport()
        guard position.isPlaying else { return }
        let heard = AudioEngineManager.shared.renderedFrames - Int64(AudioEngineManager.shared.outputLatencyFrames)
        let step = position.stepIndex(at: heard)
        if step != currentStep {
            if step < currentStep { loopWrapped() }
            currentStep = step
        }
    }
    
    // MARK: - Recording
    
    /// `atStep` overrides the clock. Pads pass nil, so the hit lands on the step the listener hears.
    @MainActor
    func recordPadHit(trackIndex: Int, velocity: Float, atStep: Int? = nil) {
        guard recordMode != .off, isPlaying else { return }
        guard trackIndex >= 0 && trackIndex < tracks.count else { return }

        let step = atStep ?? heardRecordStep()
        guard step >= 0, step < tracks[trackIndex].steps.count else { return }
        
        // Edit a copy and assign once: one snapshot and one save per hit.
        var track = tracks[trackIndex]
        switch recordMode {
        case .overdub:
            track.steps[step].isActive = true
            track.steps[step].velocity = velocity
        case .replace:
            for i in 0..<track.steps.count {
                track.steps[i].isActive = false
            }
            track.steps[step].isActive = true
            track.steps[step].velocity = velocity
        case .off:
            return
        }
        tracks[trackIndex] = track
    }

    /// Nearest grid step at the output, not the playhead. The playhead floors.
    private func heardRecordStep() -> Int {
        let heard = AudioEngineManager.shared.renderedFrames
            - Int64(AudioEngineManager.shared.outputLatencyFrames)
        return scheduler.transport().nearestStepIndex(at: heard)
    }

    /// Installs an imported session. Playback stays where it was; the caller does not start it.
    func adopt(_ session: SessionState) {
        suppressSnapshot = true
        suppressSessionSave = true
        if !session.tracks.isEmpty {
            let count = session.stepCount.rawValue
            var loaded = session.tracks
            for index in loaded.indices {
                while loaded[index].steps.count < count {
                    loaded[index].steps.append(SequencerStep())
                }
            }
            tracks = loaded
            bpmValue = min(300, max(40, session.bpm))
            let nextSwing = min(100, max(0, session.swing))
            if swing != nextSwing { swing = nextSwing }
            let nextHumanize = min(100, max(0, session.humanize))
            if humanize != nextHumanize { humanize = nextHumanize }
            if grooveSettings != session.groove { grooveSettings = session.groove }
            if stepCount != session.stepCount { stepCount = session.stepCount }
        }
        suppressSnapshot = false
        suppressSessionSave = false
        let audio = AudioEngineManager.shared
        audio.effectsChain = session.effectsChain
        audio.setMasterVolume(session.masterVolume)
        audio.limiterEnabled = session.limiterEnabled
        audio.updateEffects()
        for (index, track) in tracks.enumerated() {
            audio.loadSound(preset: track.soundPreset, forTrack: index)
            audio.setTrackVolume(track.volume, trackIndex: index)
            audio.setTrackPan(track.pan, trackIndex: index)
        }
        loadedKitName = nil
        loadedKitEdited = false
        publishSnapshot()
    }

    /// Replaces the eight pad sounds and leaves the grid, mute, and gains alone.
    func loadKit(_ kit: DrumKit, undoManager: UndoManager?) {
        let previousSounds = tracks.map(\.soundPreset)
        let previousName = loadedKitName
        let previousEdited = loadedKitEdited
        if let undoManager {
            undoManager.registerUndo(withTarget: self) { engine in
                MainActor.assumeIsolated {
                    engine.installSounds(previousSounds, kitName: previousName, edited: previousEdited)
                }
            }
            undoManager.setActionName("Загрузить кит")
        }
        let sounds = (0..<tracks.count).map { index -> SoundPreset in
            guard index < kit.sounds.count else { return tracks[index].soundPreset }
            return kit.sounds[index]
        }
        installSounds(sounds, kitName: kit.name, edited: false)
    }

    func notePadSoundEdited() {
        guard loadedKitName != nil else { return }
        loadedKitEdited = true
    }

    /// Pad for this voice. Closed and open hats share pad 2. FX is the first FX track, or nil.
    func trackIndex(for voice: SoundPreset.VoiceKind) -> Int? {
        let fixed: Int?
        switch voice {
        case .kick: fixed = 0
        case .snare: fixed = 1
        case .closedHat, .openHat: fixed = 2
        case .clap: fixed = 3
        case .tom: fixed = 4
        case .ride: fixed = 5
        case .crash: fixed = 6
        case .perc: fixed = 7
        case .fx:
            return tracks.firstIndex { $0.soundPreset.resolvedVoice == .fx }
        }
        guard let fixed, tracks.indices.contains(fixed) else { return nil }
        return fixed
    }

    /// Copy onto the pad of the same voice. An FX preset with no FX track changes nothing.
    @discardableResult
    func assignToMatchingVoice(_ preset: SoundPreset) -> Int? {
        guard let index = trackIndex(for: preset.resolvedVoice) else { return nil }
        assign(preset, toTrack: index)
        return index
    }

    func assign(_ preset: SoundPreset, toTrack index: Int) {
        guard tracks.indices.contains(index) else { return }
        var copy = preset
        copy.basedOn = preset.id
        tracks[index].soundPreset = copy
        notePadSoundEdited()
        AudioEngineManager.shared.loadSound(preset: copy, forTrack: index)
    }

    func markKitSaved(named name: String) {
        loadedKitName = name
        loadedKitEdited = false
    }

    private func installSounds(_ sounds: [SoundPreset], kitName: String?, edited: Bool) {
        suppressSnapshot = true
        for index in tracks.indices where index < sounds.count {
            tracks[index].soundPreset = sounds[index]
        }
        suppressSnapshot = false
        loadedKitName = kitName
        loadedKitEdited = edited
        publishSnapshot()
        let audio = AudioEngineManager.shared
        for (index, track) in tracks.enumerated() {
            audio.loadSound(preset: track.soundPreset, forTrack: index)
        }
    }

    /// Pads every track to at least 32 steps, restores the pattern length, and sends sounds and gains.
    func apply(pattern: DrumPattern) {
        let resolved = pattern.resolvedStepCount
        let paddedCount = max(resolved.rawValue, StepCount.thirtyTwo.rawValue)
        var loaded = pattern.tracks
        for index in loaded.indices {
            while loaded[index].steps.count < paddedCount {
                loaded[index].steps.append(SequencerStep())
            }
        }

        suppressSnapshot = true
        tracks = loaded
        bpm = pattern.bpm
        swing = pattern.swing
        stepCount = resolved
        suppressSnapshot = false
        publishSnapshot()

        let audio = AudioEngineManager.shared
        for (index, track) in tracks.enumerated() {
            audio.loadSound(preset: track.soundPreset, forTrack: index)
            audio.setTrackVolume(track.volume, trackIndex: index)
            audio.setTrackPan(track.pan, trackIndex: index)
        }
        loadedKitName = nil
        loadedKitEdited = false
    }

    /// Writes hit and velocity from `pattern` and leaves sounds, gains, tempo, and swing.
    func replaceStepGrid(from pattern: DrumPattern) {
        suppressSnapshot = true
        for index in tracks.indices where index < pattern.tracks.count {
            let source = pattern.tracks[index].steps
            for step in tracks[index].steps.indices where step < source.count {
                tracks[index].steps[step].isActive = source[step].isActive
                tracks[index].steps[step].velocity = source[step].velocity
            }
        }
        suppressSnapshot = false
        publishSnapshot()
    }
    
    // MARK: - Tap Tempo
    
    func tapTempo() {
        let now = tapClock.now
        let origin = tapOrigin ?? now
        tapOrigin = origin
        if let next = taps.register(at: TapTempo.seconds(origin.duration(to: now))) {
            bpm = next
        }
    }
    
    // MARK: - Track Control
    
    func toggleMute(trackIndex: Int) {
        guard trackIndex >= 0 && trackIndex < tracks.count else { return }
        tracks[trackIndex].isMuted.toggle()
    }
    
    func toggleSolo(trackIndex: Int) {
        guard trackIndex >= 0 && trackIndex < tracks.count else { return }
        tracks[trackIndex].isSolo.toggle()
    }
    
    // MARK: - Pattern Operations
    
    func clearPattern() {
        var copy = tracks
        for trackIndex in copy.indices {
            for stepIndex in copy[trackIndex].steps.indices {
                copy[trackIndex].steps[stepIndex].isActive = false
            }
        }
        tracks = copy
    }
    
    func randomizePattern(density: Double = 0.3) {
        var copy = tracks
        for trackIndex in copy.indices {
            for stepIndex in copy[trackIndex].steps.indices {
                copy[trackIndex].steps[stepIndex].isActive = Double.random(in: 0...1) < density
                copy[trackIndex].steps[stepIndex].velocity = Float.random(in: 0.5...1.0)
            }
        }
        tracks = copy
    }
}
