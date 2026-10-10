import AVFoundation
import AudioToolbox
import Foundation
import Observation

/// Apple's peak limiter has attack, decay, and pre-gain, but no ceiling.
/// 0.89 is about −1 dBFS on the main mixer when the unit is already limiting to full scale.
nonisolated enum MasterLimiter {
    static let ceilingGain: Float = 0.89

    static func makeNode() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    static func configure(_ node: AVAudioUnit) {
        let unit = node.audioUnit
        AudioUnitSetParameter(unit, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
        AudioUnitSetParameter(unit, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.050, 0)
        AudioUnitSetParameter(unit, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
    }
}

/// Apple's DynamicsProcessor used as a bus compressor.
nonisolated enum BusCompressor {
    static func makeNode() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    /// amount 0...1 -> headroom 30...1 dB (less headroom squeezes harder).
    static func headroom(amount: Float) -> Float { 30 - min(1, max(0, amount)) * 29 }

    static func apply(_ s: EffectsChain.CompressorSettings, to node: AVAudioUnit) {
        let unit = node.audioUnit
        func set(_ id: AudioUnitParameterID, _ v: Float) {
            AudioUnitSetParameter(unit, id, kAudioUnitScope_Global, 0, v, 0)
        }
        set(kDynamicsProcessorParam_Threshold, min(0, max(-40, s.threshold)))
        set(kDynamicsProcessorParam_HeadRoom, headroom(amount: s.amount))
        set(kDynamicsProcessorParam_AttackTime, min(0.2, max(0.0001, s.attackMs / 1000)))
        set(kDynamicsProcessorParam_ReleaseTime, min(1, max(0.01, s.releaseMs / 1000)))
        set(kDynamicsProcessorParam_OverallGain, min(20, max(0, s.makeup)))
        set(kDynamicsProcessorParam_ExpansionRatio, 1)
        set(kDynamicsProcessorParam_ExpansionThreshold, -100)
    }
}

/// Knob positions are 0...1, except delay feedback which the rack stores as 0...100.
/// Reverb and delay stay at least half dry so a full mix does not erase the hit.
nonisolated enum EffectMapping {
    static func reverbMix(_ mix: Float) -> Float { unit(mix) * 50 }
    static func delayMix(_ mix: Float) -> Float { unit(mix) * 50 }

    static func delayFeedback(_ feedback: Float) -> Float {
        let unit = min(1, max(0, feedback / 100))
        return unit * 85
    }

    static func distortionMix(_ mix: Float) -> Float { unit(mix) * 100 }
    static func distortionPreGain(_ gain: Float) -> Float { min(20, max(-20, gain)) }
    static func eqGain(_ gain: Float) -> Float { min(12, max(-12, gain)) }

    private static func unit(_ mix: Float) -> Float { min(1, max(0, mix)) }
}
#if os(macOS)
import AppKit
#endif

// MARK: - Audio Error Handling
enum AudioError: LocalizedError {
    case engineSetupFailed
    case sampleLoadFailed(String)
    case bufferCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .engineSetupFailed:
            return "Failed to initialize audio engine. Please restart the app."
        case .sampleLoadFailed(let name):
            return "Could not load sound: \(name)"
        case .bufferCreationFailed:
            return "Audio buffer creation failed"
        }
    }
}

// MARK: - AudioEngineManager (AVAudioEngine-based, low-latency)
@MainActor
@Observable
class AudioEngineManager {
    static let shared = AudioEngineManager()
    
    var isPlaying: Bool = false
    var isReady: Bool = false
    var loadingProgress: Double = 0.0
    var errorMessage: String?
    
    /// Master-mix analysis. The tap writes it off the main actor. Views poll `MeterModel`.
    let spectrumAnalyzer = SpectrumAnalyzer()
    
    // AVAudioEngine core
    let engine = AVAudioEngine()
    private var voiceEngine: VoiceEngine!
    private var trackVolumes = [Float](repeating: 1, count: 8)
    private var trackPans = [Float](repeating: 0, count: 8)
    
    // Effects on master bus
    private let reverbNode = AVAudioUnitReverb()
    private let delayNode = AVAudioUnitDelay()
    private let distortionNode = AVAudioUnitDistortion()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 3)
    private let limiterNode = MasterLimiter.makeNode()
    private let compressorNode = BusCompressor.makeNode()
    /// Last settings written to the compressor; unchanged settings are not re-sent.
    private var appliedCompressor: EffectsChain.CompressorSettings?
    /// Skips reloading the reverb algorithm on every mix change. Nil forces a load.
    private var loadedReverbRoom: EffectsChain.ReverbRoom?
    
    // Effects settings. Views that read this redraw; the rest of the window does not.
    var effectsChain = EffectsChain()
    /// Launch applies the graph once. That pass must not write session.json.
    @ObservationIgnored private var suppressSessionSave = true
    
    // Audio format. Sample rate follows the output device, not a fixed 44.1 kHz.
    private var processingFormat: AVAudioFormat!
    private(set) var outputSampleRate: Double = 48_000

    /// Original user recordings. Resynthesis reads these, not a buffer that was already resampled.
    private var sampleRoot: URL {
        PatternManager.shared.directory.appendingPathComponent("Samples", isDirectory: true)
    }
    private var loadedTracks: Set<Int> = []
    /// Preset on each track. A rate change regenerates these. Nil is filled from the library before synthesis.
    private var trackPresets: [SoundPreset?] = Array(repeating: nil, count: 8)
    private var previewPreset: SoundPreset?
    private var previewCache = PreviewSampleCache()
    /// Bumped when the voice engine is replaced so in-flight synthesis cannot install stale buffers.
    private var sampleInstallEpoch = 0
    var masterVolume: Float = 0.85 {
        didSet {
            let clamped = min(MasterLimiter.ceilingGain, max(0, masterVolume))
            if clamped != masterVolume {
                masterVolume = clamped
                return
            }
            engine.mainMixerNode.outputVolume = masterVolume
            guard !suppressSessionSave else { return }
            SessionStore.noteAudio()
        }
    }
    var limiterEnabled = true {
        didSet {
            limiterNode.bypass = !limiterEnabled
            guard !suppressSessionSave else { return }
            SessionStore.noteAudio()
        }
    }
    private var configurationObserver: NSObjectProtocol?
    private var configurationTask: Task<Void, Never>?
    private var configurationEpoch = 0
    /// Ignores the notification that `engine.start()` itself can post.
    private var suppressConfigurationUntil = Date.distantPast
    /// Kept across a burst of notifications so the second recovery still knows the step.
    private var heldTransport: (wasPlaying: Bool, step: Int)?
    
    // Visualizer tap
    private var isTapInstalled = false
    
    private init() {
        let session = SessionStore.load()
        if let session {
            effectsChain = session.effectsChain
            masterVolume = min(MasterLimiter.ceilingGain, max(0, session.masterVolume))
            limiterEnabled = session.limiterEnabled
            for index in 0..<min(8, session.tracks.count) {
                trackPresets[index] = session.tracks[index].soundPreset
            }
        }
        let library = SoundLibraryManager.shared
        for index in trackPresets.indices where trackPresets[index] == nil {
            trackPresets[index] = library.defaultPreset(forTrackIndex: index)
        }
        // Graph build and start are a few milliseconds. Only sample synthesis leaves the main actor.
        setupAudioEngine()
        // didSet does not run while this object is initializing.
        engine.mainMixerNode.outputVolume = masterVolume
        limiterNode.bypass = !limiterEnabled
        // Synthesis runs at a lower QoS and hops back to the main actor.
        // The main actor must not wait on that work: that was the Hang Risk.
        startBackgroundSynthesis()
        suppressSessionSave = false
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        engine.attach(reverbNode)
        engine.attach(delayNode)
        engine.attach(distortionNode)
        engine.attach(eqNode)
        engine.attach(limiterNode)
        engine.attach(compressorNode)
        MasterLimiter.configure(limiterNode)
        configureEQBands()

        distortionNode.loadFactoryPreset(.multiDistortedCubed)
        delayNode.lowPassCutoff = 15000

        installVoiceEngine(sampleRate: hardwareSampleRate())
        let stereoFormat = makeStereoFormat()
        processingFormat = stereoFormat
        connectVoiceChain(format: stereoFormat)
        updateEffects()

        if !startEngineOnce() {
            errorMessage = AudioError.engineSetupFailed.errorDescription
        }
        observeConfigurationChanges()
    }

    /// Output-device changes stop the engine. Notifications arrive in a burst, sometimes
    /// off the main thread, so the rebuild waits 100 ms and then runs on the main actor.
    private func observeConfigurationChanges() {
        guard configurationObserver == nil else { return }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AudioEngineManager.shared.scheduleConfigurationRecovery()
            }
        }
    }

    private func scheduleConfigurationRecovery() {
        guard Date() >= suppressConfigurationUntil else { return }
        configurationEpoch += 1
        let epoch = configurationEpoch
        configurationTask?.cancel()
        configurationTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, epoch == self.configurationEpoch else { return }
            await self.recoverFromConfigurationChange(epoch: epoch)
        }
    }

    /// Rebuild after `AVAudioEngineConfigurationChange`. Tests call this directly.
    func recoverFromConfigurationChange() async {
        configurationEpoch += 1
        await recoverFromConfigurationChange(epoch: configurationEpoch)
    }

    private func recoverFromConfigurationChange(epoch: Int) async {
        let fresh = deviceChangeSuspend?() ?? (wasPlaying: false, step: 0)
        if fresh.wasPlaying {
            heldTransport = fresh
        }
        let transport = heldTransport ?? fresh

        removeVisualizerTap()
        if engine.isRunning {
            engine.stop()
        }
        guard epoch == configurationEpoch else { return }

        let previousRate = outputSampleRate
        let newRate = hardwareSampleRate()
        let rateChanged = abs(newRate - previousRate) > 0.5
        print("🔁 AVAudioEngine configuration change at \(newRate) Hz (was \(previousRate))")
        if rateChanged {
            installVoiceEngine(sampleRate: newRate)
        } else {
            outputSampleRate = newRate
        }

        let format = makeStereoFormat()
        processingFormat = format
        disconnectVoiceChain()
        connectVoiceChain(format: format)
        MasterLimiter.configure(limiterNode)
        distortionNode.loadFactoryPreset(.multiDistortedCubed)
        loadedReverbRoom = nil
        appliedCompressor = nil
        updateEffects()

        let started = await startEngineRetrying(epoch: epoch)
        guard epoch == configurationEpoch else { return }
        guard started else {
            errorMessage = AudioError.engineSetupFailed.errorDescription
            deviceChangeResume?(voiceEngine, outputSampleRate, transport.step, false)
            heldTransport = nil
            return
        }
        errorMessage = nil

        if rateChanged {
            await resynthesizeInstalledBuffers(sampleRate: newRate)
            guard epoch == configurationEpoch else { return }
        } else if isReady {
            installVisualizerTap()
        }

        deviceChangeResume?(voiceEngine, outputSampleRate, transport.step, transport.wasPlaying)
        heldTransport = nil
        print("🔁 Audio configuration recovered at \(outputSampleRate) Hz")
    }

    private func startEngineRetrying(epoch: Int) async -> Bool {
        if startEngineOnce() { return true }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled, epoch == configurationEpoch else { return false }
        if startEngineOnce() { return true }
        print("❌ Audio engine restart failed at \(outputSampleRate) Hz")
        return false
    }

    @discardableResult
    private func startEngineOnce() -> Bool {
        suppressConfigurationUntil = Date().addingTimeInterval(0.2)
        engine.prepare()
        do {
            try engine.start()
            print("✅ AVAudioEngine started at \(outputSampleRate) Hz")
            return true
        } catch {
            print("❌ Audio engine start failed: \(error)")
            return false
        }
    }

    private func makeStereoFormat() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: outputSampleRate, channels: 2)!
    }

    private func installVoiceEngine(sampleRate: Double) {
        if voiceEngine != nil {
            let current = voiceEngine.sourceNode
            engine.disconnectNodeOutput(current)
            if engine.attachedNodes.contains(current) {
                engine.detach(current)
            }
        }
        outputSampleRate = sampleRate
        sampleInstallEpoch += 1
        let created = VoiceEngine(sampleRate: sampleRate)
        engine.attach(created.sourceNode)
        voiceEngine = created
        loadedTracks.removeAll()
        isReady = false
        for index in 0..<trackVolumes.count {
            created.setTrackGain(track: index, gain: trackVolumes[index], pan: trackPans[index])
        }
    }

    /// Effects chain: voices -> Distortion -> Delay -> Reverb -> EQ -> Compressor -> Limiter -> MainMixer.
    private func connectVoiceChain(format: AVAudioFormat) {
        ensureAttached(voiceEngine.sourceNode)
        ensureAttached(distortionNode)
        ensureAttached(delayNode)
        ensureAttached(reverbNode)
        ensureAttached(eqNode)
        ensureAttached(limiterNode)
        ensureAttached(compressorNode)
        engine.connect(voiceEngine.sourceNode, to: distortionNode, format: format)
        engine.connect(distortionNode, to: delayNode, format: format)
        engine.connect(delayNode, to: reverbNode, format: format)
        engine.connect(reverbNode, to: eqNode, format: format)
        engine.connect(eqNode, to: compressorNode, format: format)
        engine.connect(compressorNode, to: limiterNode, format: format)
        engine.connect(limiterNode, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = masterVolume
        limiterNode.bypass = !limiterEnabled
    }

    private func disconnectVoiceChain() {
        disconnectOutputIfNeeded(voiceEngine.sourceNode)
        disconnectOutputIfNeeded(reverbNode)
        disconnectOutputIfNeeded(delayNode)
        disconnectOutputIfNeeded(distortionNode)
        disconnectOutputIfNeeded(eqNode)
        disconnectOutputIfNeeded(compressorNode)
        disconnectOutputIfNeeded(limiterNode)
    }

    /// Low shelf 120 Hz, parametric 1 kHz, high shelf 8 kHz. Gains stay on the model.
    private func configureEQBands() {
        let bands = eqNode.bands
        guard bands.count == 3 else { return }
        bands[0].filterType = .lowShelf
        bands[0].frequency = 120
        bands[0].bypass = false
        bands[1].filterType = .parametric
        bands[1].frequency = 1_000
        bands[1].bandwidth = 1
        bands[1].bypass = false
        bands[2].filterType = .highShelf
        bands[2].frequency = 8_000
        bands[2].bypass = false
    }

    private func applyReverbRoom(_ room: EffectsChain.ReverbRoom) {
        guard loadedReverbRoom != room else { return }
        switch room {
        case .smallRoom: reverbNode.loadFactoryPreset(.smallRoom)
        case .mediumRoom: reverbNode.loadFactoryPreset(.mediumRoom)
        case .largeRoom: reverbNode.loadFactoryPreset(.largeRoom)
        case .mediumHall: reverbNode.loadFactoryPreset(.mediumHall)
        case .largeHall: reverbNode.loadFactoryPreset(.largeHall)
        }
        loadedReverbRoom = room
    }

    private func disconnectOutputIfNeeded(_ node: AVAudioNode) {
        guard engine.attachedNodes.contains(node) else { return }
        guard !engine.outputConnectionPoints(for: node, outputBus: 0).isEmpty else { return }
        engine.disconnectNodeOutput(node)
    }

    private func ensureAttached(_ node: AVAudioNode) {
        if !engine.attachedNodes.contains(node) {
            engine.attach(node)
        }
    }

    private var deviceChangeSuspend: (() -> (wasPlaying: Bool, step: Int))?
    private var deviceChangeResume: ((VoiceEngine, Double, Int, Bool) -> Void)?

    /// The single sequencer that owns the device-change handlers (see `AppSequencer`).
    private(set) var deviceChangeOwner: ObjectIdentifier?

    func setDeviceChangeHandlers(
        owner: AnyObject,
        suspend: @escaping () -> (wasPlaying: Bool, step: Int),
        resume: @escaping (VoiceEngine, Double, Int, Bool) -> Void
    ) {
        deviceChangeOwner = ObjectIdentifier(owner)
        deviceChangeSuspend = suspend
        deviceChangeResume = resume
    }

    var renderedFrames: Int64 { voiceEngine.renderedFrames }

    /// Hardware IO size used as the sequencer lookahead. 512 if the device has not reported one.
    var renderQuantum: Int {
        let frames = Int(engine.outputNode.auAudioUnit.maximumFramesToRender)
        return frames > 0 ? frames : 512
    }

    var outputLatencyFrames: Int {
        let frames = (engine.outputNode.presentationLatency * outputSampleRate).rounded()
        guard frames.isFinite, frames > 0 else { return 0 }
        return Int(frames)
    }

    func voiceEngineForScheduler() -> VoiceEngine { voiceEngine }

    /// Output-device rate. Falls back only when the device has not reported one yet.
    private func hardwareSampleRate() -> Double {
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if rate.isFinite, rate > 0 { return rate }
        return 48_000
    }
    
    // MARK: - Install Audio Tap for Visualizer
    func installVisualizerTap() {
        guard !isTapInstalled else { return }
        
        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        
        // Ensure valid format before installing tap
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("⚠️ Invalid mixer output format, skipping visualizer tap")
            return
        }
        
        let tap = spectrumAnalyzer.makeTapBlock()
        mainMixer.installTap(onBus: 0, bufferSize: 1024, format: format, block: tap)
        isTapInstalled = true
    }
    
    func removeVisualizerTap() {
        guard isTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        isTapInstalled = false
    }
    
    // MARK: - Async Sound Generation
    private func startBackgroundSynthesis() {
        isReady = false
        loadingProgress = 0
        loadedTracks.removeAll()
        let sampleRate = outputSampleRate
        let epoch = sampleInstallEpoch
        let presets = trackPresets
        let sampleRoot = self.sampleRoot
        Task.detached(priority: .userInitiated) {
            for index in presets.indices {
                guard let preset = presets[index] else { continue }
                let samples = DrumSynthesizer.samples(for: preset, sampleRate: sampleRate, sampleRoot: sampleRoot)
                let presetID = preset.id
                let name = preset.name
                await MainActor.run {
                    let manager = AudioEngineManager.shared
                    guard epoch == manager.sampleInstallEpoch else { return }
                    guard abs(manager.outputSampleRate - sampleRate) < 0.5 else { return }
                    guard manager.trackPresets[index]?.id == presetID else { return }
                    manager.installGeneratedBuffer(
                        samples,
                        index: index,
                        name: name,
                        sampleRate: sampleRate
                    )
                }
            }
        }
    }

    private func installGeneratedBuffer(
        _ samples: [Float],
        index: Int,
        name: String,
        sampleRate: Double
    ) {
        voiceEngine.swapSample(track: index, samples: samples)
        print("✅ Generated [\(index)] \(name): \(samples.count) frames")
        markTrackLoaded(index)
    }

    private func markTrackLoaded(_ index: Int) {
        guard index >= 0, index < 8 else { return }
        loadedTracks.insert(index)
        loadingProgress = Double(loadedTracks.count) / 8.0
        guard loadedTracks.count == 8 else { return }
        isReady = true
        print("🎵 Audio engine ready with \(loadedTracks.count) sounds at \(outputSampleRate) Hz")
        installVisualizerTap()
    }

    /// The eight voices are independent. Build them off the main actor so a rate change
    /// finishes inside the one-second recovery window.
    nonisolated private static func buffersForTracks(
        _ presets: [SoundPreset],
        sampleRate: Double,
        sampleRoot: URL
    ) async -> [[Float]] {
        await withTaskGroup(of: (Int, [Float]).self) { group in
            for index in presets.indices {
                let preset = presets[index]
                group.addTask {
                    let samples = DrumSynthesizer.samples(
                        for: preset,
                        sampleRate: sampleRate,
                        sampleRoot: sampleRoot
                    )
                    return (index, samples)
                }
            }
            var buffers = Array(repeating: [Float](), count: presets.count)
            for await (index, samples) in group {
                buffers[index] = samples
            }
            return buffers
        }
    }

    /// Rebuild the eight track buffers and the preview at `sampleRate`.
    private func resynthesizeInstalledBuffers(sampleRate: Double) async {
        let epoch = sampleInstallEpoch
        isReady = false
        loadingProgress = 0
        loadedTracks.removeAll()
        let library = SoundLibraryManager.shared
        for index in trackPresets.indices where trackPresets[index] == nil {
            trackPresets[index] = library.defaultPreset(forTrackIndex: index)
        }
        let presetIDs = trackPresets.map { $0?.id }
        let presets = trackPresets.compactMap { $0 }
        let preview = previewPreset
        let names = ["kick", "snare", "hihat", "clap", "tom", "ride", "crash", "perc"]
        let started = Date()
        let sampleRoot = self.sampleRoot
        let buffers = await Self.buffersForTracks(presets, sampleRate: sampleRate, sampleRoot: sampleRoot)
        guard epoch == sampleInstallEpoch else { return }
        guard abs(outputSampleRate - sampleRate) < 0.5 else { return }
        for index in 0..<8 {
            if trackPresets[index]?.id != presetIDs[index] { continue }
            voiceEngine.swapSample(track: index, samples: buffers[index])
            print("✅ Regenerated [\(index)] \(names[index]): \(buffers[index].count) frames at \(sampleRate) Hz")
            loadedTracks.insert(index)
            loadingProgress = Double(loadedTracks.count) / 8.0
        }
        if let preview {
            let previewSamples = await Task.detached(priority: .userInitiated) {
                DrumSynthesizer.samples(for: preview, sampleRate: sampleRate, sampleRoot: sampleRoot)
            }.value
            guard epoch == sampleInstallEpoch else { return }
            if previewPreset?.id == preview.id {
                voiceEngine.swapSample(track: VoiceEngine.previewTrack, samples: previewSamples)
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        print("🔁 Resynthesized buffers in \(String(format: "%.3f", elapsed)) s at \(sampleRate) Hz")
        guard loadedTracks.count == 8 else { return }
        isReady = true
        print("🎵 Audio engine ready with \(loadedTracks.count) sounds at \(sampleRate) Hz")
        installVisualizerTap()
    }
    
    // MARK: - Trigger Sound
    func trigger(trackIndex: Int, velocity: Float, chokeGroup: Int? = nil) {
        guard isReady else { return }
        voiceEngine.trigger(
            track: trackIndex,
            velocity: velocity,
            chokeGroup: chokeGroup ?? -1,
            atSample: 0
        )
    }
    
    // MARK: - Effects Control
    /// Follows the transport tempo. A manual delay (`syncBeats == nil`) is left alone,
    /// and this does not write the session in that case.
    func retimeSyncedDelay(bpm: Double) {
        guard effectsChain.delay.syncBeats != nil else { return }
        let before = effectsChain.delay.delayTime
        effectsChain.delay.retime(bpm: bpm)
        // Clamped or same tempo: nothing audible changed, do not touch the nodes.
        guard Self.delayTimeChanged(from: before, to: effectsChain.delay.delayTime) else { return }
        updateEffects()
    }

    /// Below this a delayTime write is inaudible but still steps the AU's delay line.
    static let delayTimeEpsilon: Double = 0.001

    static func delayTimeChanged(from old: Double, to new: Double) -> Bool {
        abs(new - old) > delayTimeEpsilon
    }

    func updateEffects() {
        let chain = effectsChain

        applyReverbRoom(chain.reverb.room)
        reverbNode.bypass = !chain.reverb.isOn
        reverbNode.wetDryMix = EffectMapping.reverbMix(chain.reverb.wetDryMix)

        eqNode.bypass = !chain.eq.isOn
        let bands = eqNode.bands
        if bands.count == 3 {
            bands[0].gain = EffectMapping.eqGain(chain.eq.low)
            bands[1].gain = EffectMapping.eqGain(chain.eq.mid)
            bands[2].gain = EffectMapping.eqGain(chain.eq.high)
        }

        delayNode.bypass = !chain.delay.isOn
        delayNode.wetDryMix = EffectMapping.delayMix(chain.delay.wetDryMix)
        // Re-writing an unchanged delayTime still resets AVAudioUnitDelay's line (click).
        if Self.delayTimeChanged(from: delayNode.delayTime, to: chain.delay.delayTime) {
            delayNode.delayTime = chain.delay.delayTime
        }
        delayNode.feedback = EffectMapping.delayFeedback(chain.delay.feedback)
        delayNode.lowPassCutoff = chain.delay.lowPassCutoff

        distortionNode.bypass = !chain.distortion.isOn
        distortionNode.wetDryMix = EffectMapping.distortionMix(chain.distortion.wetDryMix)
        distortionNode.preGain = EffectMapping.distortionPreGain(chain.distortion.preGain)

        compressorNode.bypass = !chain.compressor.isOn
        if chain.compressor != appliedCompressor {
            BusCompressor.apply(chain.compressor, to: compressorNode)
            appliedCompressor = chain.compressor
        }
        guard !suppressSessionSave else { return }
        SessionStore.noteAudio()
    }
    
    func stop() {
        let fade = Int(outputSampleRate * 0.005)
        voiceEngine.stopAll(fadeFrames: fade)
    }
    
    // MARK: - Per-Track Volume & Pan
    func setTrackVolume(_ volume: Float, trackIndex: Int) {
        guard trackIndex >= 0, trackIndex < trackVolumes.count else { return }
        trackVolumes[trackIndex] = max(0, min(1, volume))
        voiceEngine.setTrackGain(track: trackIndex, gain: trackVolumes[trackIndex], pan: trackPans[trackIndex])
    }
    
    func setTrackPan(_ pan: Float, trackIndex: Int) {
        guard trackIndex >= 0, trackIndex < trackPans.count else { return }
        trackPans[trackIndex] = max(-1, min(1, pan))
        voiceEngine.setTrackGain(track: trackIndex, gain: trackVolumes[trackIndex], pan: trackPans[trackIndex])
    }
    
    // MARK: - Sound Library Preview (plays sound without assigning to a track)
    func previewSound(preset: SoundPreset) {
        previewPreset = preset
        let sampleRate = outputSampleRate
        let parameterHash = preset.synthesisHash
        if let cached = previewCache.samples(id: preset.id, parameterHash: parameterHash, sampleRate: sampleRate) {
            playPreview(cached)
            return
        }
        let epoch = sampleInstallEpoch
        let sampleRoot = self.sampleRoot
        Task.detached(priority: .userInitiated) {
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: sampleRate, sampleRoot: sampleRoot)
            await MainActor.run {
                let manager = AudioEngineManager.shared
                guard epoch == manager.sampleInstallEpoch else { return }
                guard abs(manager.outputSampleRate - sampleRate) < 0.5 else { return }
                manager.previewCache.store(samples, id: preset.id, parameterHash: parameterHash, sampleRate: sampleRate)
                guard manager.previewPreset?.id == preset.id,
                      manager.previewPreset?.synthesisHash == parameterHash else { return }
                manager.playPreview(samples)
            }
        }
    }

    private func playPreview(_ samples: [Float]) {
        voiceEngine.swapSample(track: VoiceEngine.previewTrack, samples: samples)
        voiceEngine.trigger(track: VoiceEngine.previewTrack, velocity: 0.85, chokeGroup: -1, atSample: 0)
    }
    
    // MARK: - Load Sound Preset onto a Track
    func loadSound(preset: SoundPreset, forTrack trackIndex: Int) {
        guard trackIndex >= 0, trackIndex < trackPresets.count else { return }
        trackPresets[trackIndex] = preset
        let sampleRate = outputSampleRate
        let epoch = sampleInstallEpoch
        let sampleRoot = self.sampleRoot
        Task.detached(priority: .userInitiated) {
            let samples = DrumSynthesizer.samples(for: preset, sampleRate: sampleRate, sampleRoot: sampleRoot)
            await MainActor.run {
                let manager = AudioEngineManager.shared
                guard epoch == manager.sampleInstallEpoch else { return }
                guard abs(manager.outputSampleRate - sampleRate) < 0.5 else { return }
                guard manager.trackPresets[trackIndex]?.id == preset.id else { return }
                manager.installTrackBuffer(samples, preset: preset, trackIndex: trackIndex)
            }
        }
    }

    private func installTrackBuffer(_ samples: [Float], preset: SoundPreset, trackIndex: Int) {
        voiceEngine.swapSample(track: trackIndex, samples: samples)
        print("🎵 Loaded '\(preset.name)' onto track \(trackIndex)")
        markTrackLoaded(trackIndex)
    }
    
    // MARK: - Master Volume
    func setMasterVolume(_ volume: Float) {
        masterVolume = volume
    }

    func setLimiterEnabled(_ enabled: Bool) {
        limiterEnabled = enabled
    }

    func consumePreLimiterPeak() -> Float {
        voiceEngine.consumePreLimiterPeak()
    }
}

/// Last 16 preview buffers, keyed by preset id and the synthesis hash. A rate change misses.
nonisolated struct PreviewSampleCache {
    private struct Key: Hashable {
        var id: UUID
        var parameterHash: Int
    }

    private var order: [Key] = []
    private var entries: [Key: (sampleRate: Double, samples: [Float])] = [:]
    let limit: Int

    init(limit: Int = 16) {
        self.limit = max(1, limit)
    }

    mutating func store(_ samples: [Float], id: UUID, parameterHash: Int = 0, sampleRate: Double) {
        let key = Key(id: id, parameterHash: parameterHash)
        order.removeAll { $0 == key }
        order.append(key)
        entries[key] = (sampleRate, samples)
        while order.count > limit {
            entries[order.removeFirst()] = nil
        }
    }

    mutating func samples(id: UUID, parameterHash: Int = 0, sampleRate: Double) -> [Float]? {
        let key = Key(id: id, parameterHash: parameterHash)
        guard let entry = entries[key], abs(entry.sampleRate - sampleRate) < 0.5 else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        return entry.samples
    }

    func contains(id: UUID, parameterHash: Int = 0) -> Bool {
        entries[Key(id: id, parameterHash: parameterHash)] != nil
    }
}
