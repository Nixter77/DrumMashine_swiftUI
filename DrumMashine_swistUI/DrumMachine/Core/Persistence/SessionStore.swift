import Foundation
import os

/// Live musical state. Playback is not included: the app always starts stopped.
nonisolated struct SessionState: Codable, Equatable, Sendable {
    var tracks: [SequencerTrack]
    var bpm: Double
    var swing: Double
    var humanize: Double
    var groove: GrooveSettings = GrooveSettings()
    var stepCount: StepCount
    var activePatternIndex: Int
    var effectsChain: EffectsChain
    var masterVolume: Float
    var limiterEnabled: Bool
    var libraryInspectorOpen: Bool

    init(
        tracks: [SequencerTrack],
        bpm: Double = 120,
        swing: Double = 0,
        humanize: Double = 0,
        stepCount: StepCount = .sixteen,
        activePatternIndex: Int = 0,
        effectsChain: EffectsChain = EffectsChain(),
        masterVolume: Float = 0.85,
        limiterEnabled: Bool = true,
        libraryInspectorOpen: Bool = true
    ) {
        self.tracks = tracks
        self.bpm = bpm
        self.swing = swing
        self.humanize = humanize
        self.stepCount = stepCount
        self.activePatternIndex = activePatternIndex
        self.effectsChain = effectsChain
        self.masterVolume = masterVolume
        self.limiterEnabled = limiterEnabled
        self.libraryInspectorOpen = libraryInspectorOpen
    }
}

extension SessionState {
    /// Missing keys keep the factory defaults. Tracks stay empty: decoding is not on the main actor.
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tracks = try container.decodeIfPresent([SequencerTrack].self, forKey: .tracks) ?? []
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm) ?? 120
        swing = try container.decodeIfPresent(Double.self, forKey: .swing) ?? 0
        humanize = try container.decodeIfPresent(Double.self, forKey: .humanize) ?? 0
        groove = try container.decodeIfPresent(GrooveSettings.self, forKey: .groove) ?? GrooveSettings()
        stepCount = try container.decodeIfPresent(StepCount.self, forKey: .stepCount) ?? .sixteen
        activePatternIndex = try container.decodeIfPresent(Int.self, forKey: .activePatternIndex) ?? 0
        effectsChain = try container.decodeIfPresent(EffectsChain.self, forKey: .effectsChain) ?? EffectsChain()
        masterVolume = try container.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 0.85
        limiterEnabled = try container.decodeIfPresent(Bool.self, forKey: .limiterEnabled) ?? true
        libraryInspectorOpen = try container.decodeIfPresent(Bool.self, forKey: .libraryInspectorOpen) ?? true
    }

    /// Eight library presets. Used when no session file exists, not the `sound_N` stubs.
    @MainActor
    static func makeDefault() -> SessionState {
        let library = SoundLibraryManager.shared
        let tracks = (0..<8).map { index in
            SequencerTrack(soundPreset: library.defaultPreset(forTrackIndex: index))
        }
        return SessionState(tracks: tracks)
    }
}

/// `session.json` in the same folder as the patterns. Writes are debounced; quit flushes.
/// The app uses `shared`. A test builds another instance on a temporary folder.
@MainActor
final class SessionStore {
    static let version = 1
    static let fileName = "session"

    private static let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "session")

    static let shared: SessionStore = {
        let patterns = PatternManager.shared
        return SessionStore(directory: patterns.directory, patterns: patterns)
    }()

    static func load() -> SessionState? { shared.load() }
    static func scheduleSave() { shared.scheduleSave() }
    static func flush() { shared.flush() }
    static func noteSequencer(_ engine: SequencerEngine) { shared.noteSequencer(engine) }
    static func noteAudio() { shared.noteAudio() }
    static var libraryInspectorOpen: Bool {
        get { shared.libraryInspectorOpen }
        set { shared.libraryInspectorOpen = newValue }
    }

    private let directory: URL
    /// When set, `load()` restores `activePatternIndex` here. The app passes the shared manager.
    private weak var patterns: PatternManager?
    private var didLoad = false
    private var cached: SessionState?
    private var draft: SessionState?
    /// A file newer than this app is left untouched, including on quit.
    private var writesBlocked = false
    private var saveTask: Task<Void, Never>?
    private var savePending = false

    init(directory: URL, patterns: PatternManager? = nil) {
        self.directory = directory
        self.patterns = patterns
    }

    /// Idempotent for this instance. Nil means start from library defaults.
    func load() -> SessionState? {
        if didLoad { return cached }
        didLoad = true
        let store = PersistenceStore(directory: directory)
        do {
            switch try store.read(Self.fileName, as: SessionState.self, maximumVersion: Self.version) {
            case .missing:
                cached = nil
            case .loaded(let state):
                cached = state
                applyActivePatternIndex(state)
            case .recovered(let state, let note):
                cached = state
                Self.logger.error("\(note, privacy: .public)")
                applyActivePatternIndex(state)
            }
        } catch let error as PersistenceError where error.isNewerVersion {
            writesBlocked = true
            cached = nil
            Self.logger.error("Could not read saved session: \(error.localizedDescription, privacy: .public)")
        } catch {
            cached = nil
            Self.logger.error("Could not read saved session: \(error.localizedDescription, privacy: .public)")
        }
        draft = cached ?? SessionState.makeDefault()
        return cached
    }

    /// The draft the window is editing. A missing file uses the library defaults.
    func current() -> SessionState {
        ensureDraft()
        return draft ?? SessionState.makeDefault()
    }

    /// Installs a whole document and schedules the 0.5 s write. `flush()` writes it immediately.
    func replace(_ state: SessionState) {
        didLoad = true
        draft = state
        cached = state
        scheduleSave()
    }

    /// Coalesces sequencer and audio edits. The delay is 0.5 s.
    func scheduleSave() {
        guard !writesBlocked else { return }
        savePending = true
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            writeNow()
        }
    }

    /// Writes immediately. Resign-active, quit, and window close call this.
    func flush() {
        guard savePending, !writesBlocked else { return }
        saveTask?.cancel()
        saveTask = nil
        writeNow()
    }

    /// Grid, tempo, and pad sounds. Effects and the master stay as they are.
    func noteSequencer(_ engine: SequencerEngine) {
        ensureDraft()
        guard !writesBlocked, var state = draft else { return }
        state.tracks = engine.tracks
        state.bpm = engine.bpm
        state.swing = engine.swing
        state.humanize = engine.humanize
        state.groove = engine.grooveSettings
        state.stepCount = engine.stepCount
        if let patterns {
            state.activePatternIndex = patterns.activePatternIndex
        }
        draft = state
        scheduleSave()
    }

    /// Effects, master volume, and the limiter. The grid stays as it is.
    func noteAudio() {
        ensureDraft()
        guard !writesBlocked, var state = draft else { return }
        let audio = AudioEngineManager.shared
        state.effectsChain = audio.effectsChain
        state.masterVolume = audio.masterVolume
        state.limiterEnabled = audio.limiterEnabled
        draft = state
        scheduleSave()
    }

    /// Remembered for the library inspector. Nothing in the window binds this yet.
    var libraryInspectorOpen: Bool {
        get {
            ensureDraft()
            return draft?.libraryInspectorOpen ?? true
        }
        set {
            ensureDraft()
            guard !writesBlocked, var state = draft else { return }
            state.libraryInspectorOpen = newValue
            draft = state
            scheduleSave()
        }
    }

    private func ensureDraft() {
        if !didLoad {
            _ = load()
        }
        if draft == nil {
            draft = SessionState.makeDefault()
        }
    }

    private func applyActivePatternIndex(_ state: SessionState) {
        guard let patterns else { return }
        guard patterns.patterns.indices.contains(state.activePatternIndex) else { return }
        patterns.activePatternIndex = state.activePatternIndex
    }

    private func writeNow() {
        guard !writesBlocked, let draft else { return }
        savePending = false
        let store = PersistenceStore(directory: directory)
        do {
            try store.write(draft, name: Self.fileName, version: Self.version)
        } catch {
            savePending = true
            Self.logger.error("Could not save session: \(error.localizedDescription, privacy: .public)")
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard !Task.isCancelled, savePending, !writesBlocked else { return }
            writeNow()
        }
    }
}
