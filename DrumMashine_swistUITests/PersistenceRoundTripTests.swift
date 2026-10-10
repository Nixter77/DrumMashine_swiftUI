import Foundation
import Testing
@testable import DrumMashine_swistUI

/// Save, then load through new store instances.
/// Every stored field has to be set off its default in `filledSession()` and `filledSlots()`.
@MainActor
struct PersistenceRoundTripTests {
    @Test func restartThroughNewStoresRestoresSessionAndPatterns() throws {
        let fixture = try RoundTripFixture()
        defer { fixture.remove() }
        let state = filledSession()
        let slots = filledSlots(session: state)
        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        manager.replaceSlots(slots)
        manager.activePatternIndex = 1
        manager.flushSave()
        let session = SessionStore(directory: fixture.directory, patterns: manager)
        session.replace(state)
        session.flush()
        let savedPreset = userSnare()
        let presetStore = UserPresetStore(directory: fixture.directory)
        presetStore.save(savedPreset)
        presetStore.flush()
        var kitSound = savedPreset
        kitSound.decay = 0.25
        let savedKit = DrumKit(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555555")!,
            name: "Мой кит",
            sounds: [kitSound]
        )
        let kitStore = KitStore(directory: fixture.directory)
        kitStore.save(savedKit)
        kitStore.flush()

        let store = PersistenceStore(directory: fixture.directory)
        guard case .loaded(let sessionFile) = try store.read(
            SessionStore.fileName,
            as: SessionState.self,
            maximumVersion: SessionStore.version
        ) else {
            Issue.record("session.json did not load")
            return
        }
        guard case .loaded(let patternFile) = try store.read(
            "patterns",
            as: PatternLibrary.self,
            maximumVersion: PersistenceStore.patternsVersion
        ) else {
            Issue.record("patterns.json did not load")
            return
        }
        #expect(sessionFile == state)
        #expect(patternFile.patterns == manager.patterns)
        #expect(patternFile.activePatternIndex == manager.activePatternIndex)

        let restartedPatterns = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        let restartedSession = SessionStore(directory: fixture.directory, patterns: restartedPatterns)
        let loaded = try #require(restartedSession.load())
        #expect(loaded == state)
        #expect(loaded.bpm == 133)
        #expect(loaded.swing == 55)
        #expect(loaded.humanize == 20)
        #expect(loaded.stepCount == .thirtyTwo)
        #expect(loaded.activePatternIndex == 1)
        #expect(loaded.masterVolume == 0.6)
        #expect(loaded.limiterEnabled == false)
        #expect(loaded.libraryInspectorOpen == false)
        #expect(loaded.effectsChain.reverb.isOn)
        #expect(loaded.effectsChain.reverb.room == .largeHall)
        #expect(loaded.effectsChain.reverb.wetDryMix == 0.35)
        #expect(loaded.tracks[0].steps[0].isActive)
        #expect(loaded.tracks[0].steps[0].velocity == 0.5)
        #expect(loaded.tracks[0].steps[7].isActive)
        #expect(loaded.tracks[0].steps[31].isActive)
        #expect(loaded.tracks[1].soundPreset.pitch == 3)
        #expect(loaded.tracks[1].soundPreset.attack == 0.002)
        #expect(loaded.tracks[1].soundPreset.decay == 0.25)
        #expect(loaded.tracks[1].soundPreset.sustain == 0)
        #expect(loaded.tracks[1].soundPreset.release == 0.12)
        #expect(loaded.tracks[2].isMuted)
        #expect(loaded.tracks[3].pan == -0.4)
        #expect(restartedPatterns.patterns == manager.patterns)
        #expect(restartedPatterns.patterns[0] != restartedPatterns.patterns[1])
        #expect(restartedPatterns.activePatternIndex == 1)
        #expect(fixture.defaults.data(forKey: PatternManager.storageKey) == nil)
        let tone = fixture.directory.appendingPathComponent("tone.wav")
        try SampleTone.write(to: tone)
        let imported = try SampleImporter.importFile(tone, voice: .perc, into: fixture.directory)
        presetStore.save(imported)
        presetStore.flush()

        let restartedPresets = UserPresetStore(directory: fixture.directory)
        #expect(restartedPresets.presets == [savedPreset, imported])
        let sampleRoot = fixture.directory.appendingPathComponent("Samples", isDirectory: true)
        let played = DrumSynthesizer.samples(for: imported, sampleRate: 48_000, sampleRoot: sampleRoot)
        #expect(played.contains { abs($0) > 0.1 })
        #expect(played.last == 0)
        #expect(restartedPresets.presets[0].origin == .user)
        #expect(restartedPresets.presets[0].basedOn == savedPreset.basedOn)
        #expect(restartedPresets.presets[0].decay == 0.5)
        let restartedKits = KitStore(directory: fixture.directory)
        #expect(restartedKits.kits == [savedKit])
        #expect(restartedKits.kits[0].sounds[0].decay == 0.25)
    }

    @Test func flushWritesTheLatestEditWithoutWaitingForTheDebounce() throws {
        let fixture = try RoundTripFixture()
        defer { fixture.remove() }
        var state = filledSession()
        var slots = filledSlots(session: state)
        let manager = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        manager.replaceSlots(slots)
        manager.flushSave()
        let session = SessionStore(directory: fixture.directory, patterns: manager)
        session.replace(state)
        session.flush()

        state.bpm = 141
        state.tracks[0].steps[2].isActive = true
        state.tracks[0].steps[2].velocity = 0.5
        slots[1] = DrumPattern(
            name: "B",
            tracks: state.tracks,
            bpm: state.bpm,
            swing: state.swing,
            stepCount: state.stepCount
        )
        slots[1].tracks[0].steps[4].isActive = true
        manager.replaceSlots(slots)
        manager.flushSave()
        session.replace(state)
        session.flush()

        let restartedPatterns = PatternManager(defaults: fixture.defaults, directory: fixture.directory)
        let restartedSession = SessionStore(directory: fixture.directory, patterns: restartedPatterns)
        let loaded = try #require(restartedSession.load())
        #expect(loaded.bpm == 141)
        #expect(loaded.tracks[0].steps[2].isActive)
        #expect(loaded.tracks[0].steps[2].velocity == 0.5)
        #expect(restartedPatterns.patterns[1].tracks[0].steps[4].isActive)
        #expect(restartedPatterns.patterns[1].bpm == 141)
    }
}

@MainActor
private struct RoundTripFixture {
    let suite: String
    let directory: URL
    let defaults: UserDefaults

    init() throws {
        suite = "DrumMachineRoundTrip-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suite, isDirectory: true)
    }

    func remove() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

private func filledSession() -> SessionState {
    var state = SessionState(
        tracks: liveTracks(),
        bpm: 133,
        swing: 55,
        humanize: 20,
        stepCount: .thirtyTwo,
        activePatternIndex: 1,
        effectsChain: filledEffects(),
        masterVolume: 0.6,
        limiterEnabled: false,
        libraryInspectorOpen: false
    )
    state.tracks[0].steps[0].probability = 0.5
    return state
}

private func filledSlots(session: SessionState) -> [DrumPattern] {
    var slotATracks = session.tracks
    for index in slotATracks[0].steps.indices {
        slotATracks[0].steps[index].isActive = false
        slotATracks[0].steps[index].velocity = 0.8
    }
    slotATracks[0].steps[3].isActive = true
    slotATracks[0].steps[3].velocity = 0.5
    return [
        DrumPattern(name: "A", tracks: slotATracks, bpm: 90, swing: 10, stepCount: .thirtyTwo),
        DrumPattern(name: "B", tracks: session.tracks, bpm: session.bpm, swing: session.swing, stepCount: .thirtyTwo),
        DrumPattern(name: "C", tracks: liveTracks(), bpm: 100, swing: 5, stepCount: .eight),
        DrumPattern(name: "D", tracks: liveTracks(), bpm: 110, swing: 15, stepCount: .sixteen)
    ]
}

private func liveTracks() -> [SequencerTrack] {
    let kick = SequencerTrack(soundPreset: preset(1, "Kick", "kick_808", .kick), stepsCount: 32)
    var tracks = [
        kick,
        SequencerTrack(soundPreset: snarePreset(), stepsCount: 32),
        SequencerTrack(soundPreset: hatPreset(), stepsCount: 32),
        SequencerTrack(soundPreset: preset(4, "Clap", "clap_808", .percussion), stepsCount: 32),
        SequencerTrack(soundPreset: preset(5, "Tom", "tom_low", .percussion), stepsCount: 32),
        SequencerTrack(soundPreset: preset(6, "Ride", "ride_bell", .cymbals), stepsCount: 32),
        SequencerTrack(soundPreset: preset(7, "Crash", "crash_long", .cymbals), stepsCount: 32),
        SequencerTrack(soundPreset: preset(8, "Perc", "perc_conga", .percussion), stepsCount: 32)
    ]
    tracks[0].volume = 0.75
    for step in [0, 7, 31] {
        tracks[0].steps[step].isActive = true
        tracks[0].steps[step].velocity = 0.5
    }
    tracks[2].isMuted = true
    tracks[3].pan = -0.4
    tracks[4].isSolo = true
    return tracks
}

private func snarePreset() -> SoundPreset {
    var preset = preset(2, "Snare", "snare_808", .snare)
    preset.volume = 0.5
    preset.pan = 0.25
    preset.pitch = 3
    preset.attack = 0.002
    preset.decay = 0.25
    preset.sustain = 0
    preset.release = 0.12
    return preset
}

private func hatPreset() -> SoundPreset {
    var preset = preset(3, "Hat", "hh_closed", .hihat)
    preset.chokeGroup = 1
    return preset
}

private func preset(
    _ suffix: Int,
    _ name: String,
    _ filename: String,
    _ category: SoundPreset.SoundCategory
) -> SoundPreset {
    SoundPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-\(String(repeating: "0", count: 11))\(suffix)")!,
        name: name,
        filename: filename,
        category: category
    )
}

private func userSnare() -> SoundPreset {
    var preset = SoundPreset(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        name: "Мой снейр",
        filename: "snare_808",
        category: .snare,
        origin: .user,
        basedOn: UUID(uuidString: "44444444-4444-4444-4444-444444444444")
    )
    preset.pitch = 4
    preset.attack = 0
    preset.decay = 0.5
    preset.sustain = 0.25
    preset.release = 0.125
    preset.volume = 0.5
    preset.pan = -0.5
    return preset
}

private func filledEffects() -> EffectsChain {
    var chain = EffectsChain()
    chain.reverb.isOn = true
    chain.reverb.wetDryMix = 0.35
    chain.reverb.room = .largeHall
    chain.delay.isOn = true
    chain.delay.wetDryMix = 0.25
    chain.delay.delayTime = 0.5
    chain.delay.feedback = 25
    chain.delay.lowPassCutoff = 12_000
    chain.distortion.isOn = true
    chain.distortion.wetDryMix = 0.5
    chain.distortion.preGain = -8
    chain.eq.isOn = true
    chain.eq.low = 3
    chain.eq.mid = -3
    chain.eq.high = 6
    return chain
}
