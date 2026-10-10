import AppKit
import CryptoKit
import Foundation
import Observation
import os

// MARK: - Pattern (snapshot of all 8 tracks)
nonisolated struct DrumPattern: Identifiable, Codable, Sendable, Equatable {
    var id: UUID = UUID()
    var name: String
    var tracks: [SequencerTrack]
    var bpm: Double
    var swing: Double
    /// Absent in saves written before P1-4. Nil means sixteen steps.
    var stepCount: StepCount?

    init(
        name: String,
        tracks: [SequencerTrack],
        bpm: Double = 120,
        swing: Double = 0,
        stepCount: StepCount? = nil
    ) {
        self.name = name
        self.tracks = tracks
        self.bpm = bpm
        self.swing = swing
        self.stepCount = stepCount
    }

    var resolvedStepCount: StepCount { stepCount ?? .sixteen }
}

/// `patterns.json` payload. Older files store a bare array and imply slot A.
nonisolated struct PatternLibrary: Codable, Equatable, Sendable {
    var patterns: [DrumPattern]
    var activePatternIndex: Int

    init(patterns: [DrumPattern], activePatternIndex: Int) {
        self.patterns = patterns
        self.activePatternIndex = activePatternIndex
    }
}

extension PatternLibrary {
    nonisolated init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self), keyed.contains(.patterns) {
            patterns = try keyed.decode([DrumPattern].self, forKey: .patterns)
            activePatternIndex = try keyed.decodeIfPresent(Int.self, forKey: .activePatternIndex) ?? 0
            return
        }
        let single = try decoder.singleValueContainer()
        patterns = try single.decode([DrumPattern].self)
        activePatternIndex = 0
    }
}

extension DrumPattern {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        tracks = try container.decodeIfPresent([SequencerTrack].self, forKey: .tracks) ?? []
        bpm = try container.decodeIfPresent(Double.self, forKey: .bpm) ?? 120
        swing = try container.decodeIfPresent(Double.self, forKey: .swing) ?? 0
        stepCount = try container.decodeIfPresent(StepCount.self, forKey: .stepCount)
    }
}

/// Versioned pattern file. Saves from before this wrapper are a bare JSON array.
nonisolated enum PatternStore {
    static let currentVersion = 1

    nonisolated struct Document: Codable {
        var version: Int
        var patterns: [DrumPattern]
    }

    nonisolated enum StoreError: LocalizedError {
        case unsupportedVersion(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Unsupported pattern file version \(version)"
            case .unreadable:
                return "Pattern file is not a document"
            }
        }
    }

    static func encode(_ patterns: [DrumPattern]) throws -> Data {
        try JSONEncoder().encode(Document(version: currentVersion, patterns: patterns))
    }

    /// Reads the current document, or migrates an unversioned array.
    static func decode(_ data: Data) throws -> [DrumPattern] {
        let json = try JSONSerialization.jsonObject(with: data)
        if json is [Any] {
            return try JSONDecoder().decode([DrumPattern].self, from: data)
        }
        guard let object = json as? [String: Any] else {
            throw StoreError.unreadable
        }
        let version = object["version"] as? Int ?? 0
        guard version >= 1, version <= currentVersion else {
            throw StoreError.unsupportedVersion(version)
        }
        return try JSONDecoder().decode(Document.self, from: data).patterns
    }

    static func isLegacyArray(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return false }
        return json is [Any]
    }
}

/// Hash of the real pattern key. Tests compare it before and after the suite.
nonisolated enum StandardDefaultsProbe {
    static func patternSHA256() -> String {
        let data = UserDefaults.standard.data(forKey: PatternManager.storageKey) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - PatternManager (4 pattern slots, UserDefaults persistence)
@MainActor
@Observable
class PatternManager {
    /// Under XCTest this is an isolated suite and a temporary folder, never the user's defaults.
    static let shared: PatternManager = makeShared()
    
    var patterns: [DrumPattern] = []
    var activePatternIndex: Int = 0
    
    nonisolated static let storageKey = "drum_machine_patterns_v2"
    private let maxPatterns = 4
    private let patternNames = ["A", "B", "C", "D"]
    private let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "patterns")
    private let defaults: UserDefaults
    let directory: URL
    private let store: PersistenceStore
    /// A file newer than this app is left untouched, including on quit.
    private var writesBlocked = false
    private var saveTask: Task<Void, Never>?
    private var savePending = false
    /// Retained so the notifications stay registered for the life of the process.
    private var lifecycleObservers: [any NSObjectProtocol] = []
    /// Set when the file on disk could not be read. The slots stay empty.
    var loadError: String?
    /// The last read or write failure for `patterns.json`. Nil after a successful write.
    var lastError: PersistenceError? { store.lastError }

    init(defaults: UserDefaults, directory: URL) {
        self.defaults = defaults
        self.directory = directory
        self.store = PersistenceStore(directory: directory)
        backupLegacyPatternsIfNeeded()
        loadFromDisk()
    }

    private static func makeShared() -> PatternManager {
        #if DEBUG
        if let directory = debugDataDirectory() {
            // A UI test passes this folder. Its defaults stay off the real pattern key.
            // This wins over the unit-test suite: an explicit folder is the point of the flag.
            let suite = "DrumMachineUI-\(directory.lastPathComponent)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                fatalError("Could not open debug defaults \(suite)")
            }
            let manager = PatternManager(defaults: defaults, directory: directory)
            manager.observeLifecycle()
            return manager
        }
        #endif
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let suite = "DrumMachineTests-\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suite) else {
                fatalError("Could not open isolated test defaults \(suite)")
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(suite, isDirectory: true)
            return PatternManager(defaults: defaults, directory: directory)
        }
        let manager = PatternManager(defaults: .standard, directory: applicationSupportDirectory())
        manager.observeLifecycle()
        return manager
    }

    #if DEBUG
    /// `-DMDataDirectory <path>` replaces the store folder. Release builds ignore it.
    static func debugDataDirectory() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-DMDataDirectory"),
              arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }
    #endif

    static func applicationSupportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DrumMachine", isDirectory: true)
    }
    
    // MARK: - Save current sequencer state into a slot
    /// Writes the live grid into the active slot. Edits and the session share the 0.5 s debounce.
    func updateActive(from sequencer: SequencerEngine) {
        guard patterns.indices.contains(activePatternIndex) else { return }
        let existing = patterns[activePatternIndex]
        var pattern = DrumPattern(
            name: existing.name,
            tracks: sequencer.tracks,
            bpm: sequencer.bpm,
            swing: sequencer.swing,
            stepCount: sequencer.stepCount
        )
        pattern.id = existing.id
        patterns[activePatternIndex] = pattern
        scheduleSave()
    }

    /// Saves the current slot, then loads `slot`. A blank slot keeps the current sounds and an empty grid.
    func selectSlot(_ slot: Int, in sequencer: SequencerEngine) {
        guard patterns.indices.contains(slot), slot != activePatternIndex else { return }
        updateActive(from: sequencer)
        if isBlankSlot(slot) {
            patterns[slot] = blankCopy(of: sequencer, name: patterns[slot].name, id: patterns[slot].id)
        }
        activePatternIndex = slot
        sequencer.apply(pattern: patterns[slot])
        scheduleSave()
    }

    func renameSlot(_ slot: Int, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard patterns.indices.contains(slot), !trimmed.isEmpty else { return }
        patterns[slot].name = trimmed
        scheduleSave()
    }

    func copyActivePattern(to destination: Int, from sequencer: SequencerEngine) {
        guard patterns.indices.contains(destination) else { return }
        updateActive(from: sequencer)
        let source = activePatternIndex
        guard source != destination else { return }
        var copy = patterns[source]
        copy.id = patterns[destination].id
        copy.name = patterns[destination].name
        patterns[destination] = copy
        scheduleSave()
    }

    /// One undo step when the active slot has notes. Empty slots change immediately.
    /// Factory loads pass `registersWhenEmpty` so Cmd+Z restores a blank slot too.
    func performUndoable(
        sequencer: SequencerEngine,
        undoManager: UndoManager?,
        actionName: String,
        registersWhenEmpty: Bool = false,
        _ body: () -> Void
    ) {
        let slot = activePatternIndex
        let canUndo = patterns.indices.contains(slot) && (hasContent(slot: slot) || registersWhenEmpty)
        if canUndo, let undoManager {
            updateActive(from: sequencer)
            let snapshot = patterns[slot]
            undoManager.registerUndo(withTarget: self) { manager in
                MainActor.assumeIsolated {
                    guard manager.patterns.indices.contains(slot) else { return }
                    manager.patterns[slot] = snapshot
                    manager.activePatternIndex = slot
                    sequencer.apply(pattern: snapshot)
                    manager.scheduleSave()
                }
            }
            undoManager.setActionName(actionName)
        }
        body()
    }

    /// Replaces the active slot. `notesOnly` rewrites hits and velocity and leaves the rest.
    func loadFactoryPattern(
        _ spec: FactoryPatternSpec,
        notesOnly: Bool,
        into sequencer: SequencerEngine,
        undoManager: UndoManager?
    ) {
        let wasPlaying = sequencer.isPlaying
        performUndoable(
            sequencer: sequencer,
            undoManager: undoManager,
            actionName: "Load Pattern",
            registersWhenEmpty: true
        ) {
            if notesOnly {
                applyFactoryNotes(spec, to: sequencer)
            } else {
                applyFactoryPattern(spec, to: sequencer)
            }
        }
        if wasPlaying, !sequencer.isPlaying {
            sequencer.play()
        }
    }

    private func applyFactoryPattern(_ spec: FactoryPatternSpec, to sequencer: SequencerEngine) {
        let slot = activePatternIndex
        guard patterns.indices.contains(slot) else { return }
        var pattern = FactoryPatterns.makePattern(spec)
        pattern.id = patterns[slot].id
        pattern.name = patterns[slot].name
        patterns[slot] = pattern
        sequencer.apply(pattern: pattern)
        scheduleSave()
    }

    private func applyFactoryNotes(_ spec: FactoryPatternSpec, to sequencer: SequencerEngine) {
        let slot = activePatternIndex
        guard patterns.indices.contains(slot) else { return }
        let factory = FactoryPatterns.makePattern(spec)
        var pattern = patterns[slot]
        for index in pattern.tracks.indices where index < factory.tracks.count {
            let source = factory.tracks[index].steps
            for step in pattern.tracks[index].steps.indices where step < source.count {
                pattern.tracks[index].steps[step].isActive = source[step].isActive
                pattern.tracks[index].steps[step].velocity = source[step].velocity
            }
        }
        patterns[slot] = pattern
        sequencer.replaceStepGrid(from: pattern)
        scheduleSave()
    }

    func savePattern(from sequencer: SequencerEngine, toSlot slot: Int) {
        guard slot >= 0 && slot < maxPatterns else { return }
        
        let pattern = DrumPattern(
            name: patternNames[slot],
            tracks: sequencer.tracks,
            bpm: sequencer.bpm,
            swing: sequencer.swing,
            stepCount: sequencer.stepCount
        )
        
        if slot < patterns.count {
            patterns[slot] = pattern
        } else {
            // Fill gaps with empty patterns if needed
            while patterns.count < slot {
                patterns.append(makeEmptyPattern(index: patterns.count))
            }
            patterns.append(pattern)
        }
        
        scheduleSave()
    }
    
    /// Copies the live pattern into the next empty slot, or the following slot when all four have steps.
    @discardableResult
    func copyActivePattern(from sequencer: SequencerEngine) -> Int {
        let source = min(max(0, activePatternIndex), maxPatterns - 1)
        var destination = (source + 1) % maxPatterns
        for offset in 1..<maxPatterns {
            let index = (source + offset) % maxPatterns
            if !hasContent(slot: index) {
                destination = index
                break
            }
        }
        savePattern(from: sequencer, toSlot: destination)
        return destination
    }

    // MARK: - Load a pattern slot into the sequencer
    func loadPattern(slot: Int, into sequencer: SequencerEngine) {
        selectSlot(slot, in: sequencer)
    }
    
    // MARK: - Clear a pattern slot
    func clearPattern(slot: Int) {
        guard patterns.indices.contains(slot) else { return }
        var pattern = patterns[slot]
        for track in pattern.tracks.indices {
            for step in pattern.tracks[track].steps.indices {
                pattern.tracks[track].steps[step].isActive = false
            }
        }
        patterns[slot] = pattern
        scheduleSave()
    }

    func clearSlot(_ slot: Int, sequencer: SequencerEngine, undoManager: UndoManager?) {
        guard patterns.indices.contains(slot) else { return }
        if slot == activePatternIndex {
            performUndoable(
                sequencer: sequencer,
                undoManager: undoManager,
                actionName: "Clear Pattern"
            ) {
                sequencer.clearPattern()
            }
            return
        }
        if hasContent(slot: slot), let undoManager {
            let snapshot = patterns[slot]
            undoManager.registerUndo(withTarget: self) { manager in
                MainActor.assumeIsolated {
                    guard manager.patterns.indices.contains(slot) else { return }
                    manager.patterns[slot] = snapshot
                    manager.scheduleSave()
                }
            }
            undoManager.setActionName("Clear Pattern")
        }
        clearPattern(slot: slot)
    }

    /// Replace writes the imported library. Add copies noted patterns into blank slots only.
    func importLibrary(_ library: PatternLibrary, replacing: Bool) {
        if replacing {
            replaceSlots(library.patterns)
            if patterns.indices.contains(library.activePatternIndex) {
                activePatternIndex = library.activePatternIndex
            }
            scheduleSave()
            return
        }
        for pattern in library.patterns {
            let hasNotes = pattern.tracks.contains { track in
                track.steps.contains { $0.isActive }
            }
            guard hasNotes, let slot = patterns.indices.first(where: { isBlankSlot($0) }) else { continue }
            patterns[slot] = pattern
        }
        scheduleSave()
    }

    /// Replaces the slots and schedules a write. The round-trip test flushes this without waiting.
    func replaceSlots(_ patterns: [DrumPattern]) {
        var next = Array(patterns.prefix(maxPatterns))
        while next.count < maxPatterns {
            next.append(makeEmptyPattern(index: next.count))
        }
        self.patterns = next
        scheduleSave()
    }
    
    // MARK: - Check if slot has any active steps
    func hasContent(slot: Int) -> Bool {
        guard slot >= 0 && slot < patterns.count else { return false }
        return patterns[slot].tracks.contains { track in
            track.steps.contains { $0.isActive }
        }
    }
    
    // MARK: - Persistence
    private func scheduleSave() {
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

    /// Writes immediately. Resign-active and quit call this so the debounce cannot drop the last edit.
    func flushSave() {
        guard savePending else { return }
        saveTask?.cancel()
        saveTask = nil
        writeNow()
    }

    private func writeNow() {
        guard !writesBlocked else { return }
        savePending = false
        do {
            try store.write(
                PatternLibrary(patterns: patterns, activePatternIndex: activePatternIndex),
                name: "patterns",
                version: PersistenceStore.patternsVersion
            )
        } catch {
            savePending = true
            let message = "Could not save patterns: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            loadError = message
            scheduleRetry()
        }
    }

    /// The failed write stays pending and is tried again. Quit also flushes.
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

    #if DEBUG
    /// Shows the save banner without touching the user's files beyond one refused write.
    func simulateSaveError() {
        PersistenceStore.debugFailNextWrite = true
        savePending = true
        flushSave()
    }
    #endif

    func reloadFromDisk() {
        loadFromDisk()
    }

    /// One copy of the raw key, before any migration. The key itself stays.
    private func backupLegacyPatternsIfNeeded() {
        guard let data = defaults.data(forKey: Self.storageKey), !data.isEmpty else { return }
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        let fileManager = FileManager.default
        if let existing = try? fileManager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil),
           existing.contains(where: { $0.lastPathComponent.hasPrefix("legacy-patterns-") }) {
            return
        }
        do {
            try fileManager.createDirectory(at: backups, withIntermediateDirectories: true)
            let stamp = Self.backupStamp.string(from: Date())
            let url = backups.appendingPathComponent("legacy-patterns-\(stamp).json")
            try data.write(to: url, options: .atomic)
        } catch {
            let message = "Could not back up patterns: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            loadError = message
        }
    }

    private static let backupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private func loadFromDisk() {
        do {
            switch try store.read(
                "patterns",
                as: PatternLibrary.self,
                maximumVersion: PersistenceStore.patternsVersion
            ) {
            case .missing:
                try migratePatternsFromDefaults()
            case .loaded(let saved):
                applyLoadedLibrary(saved)
                loadError = nil
            case .recovered(let saved, let note):
                applyLoadedLibrary(saved)
                logger.error("\(note, privacy: .public)")
                loadError = note
            }
        } catch let error as PersistenceError where error.isNewerVersion {
            writesBlocked = true
            let message = "Could not read saved patterns: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            loadError = message
            patterns = []
        } catch {
            let message = "Could not read saved patterns: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            loadError = message
            patterns = []
        }

        if patterns.count > maxPatterns {
            patterns = Array(patterns.prefix(maxPatterns))
        }
        while patterns.count < maxPatterns {
            patterns.append(makeEmptyPattern(index: patterns.count))
        }
    }

    /// Copies a legacy UserDefaults document into patterns.json. The key stays.
    private func migratePatternsFromDefaults() throws {
        guard let data = defaults.data(forKey: Self.storageKey), !data.isEmpty else {
            patterns = []
            return
        }
        patterns = try PatternStore.decode(data)
        try store.write(
            PatternLibrary(patterns: patterns, activePatternIndex: activePatternIndex),
            name: "patterns",
            version: PersistenceStore.patternsVersion
        )
        if PatternStore.isLegacyArray(data) {
            logger.info("Migrated the pattern save to version \(PatternStore.currentVersion, privacy: .public)")
        }
        loadError = nil
    }

    /// System notifications arrive on the main thread. Flush there: a queued task would miss quit.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        let names = [
            NSApplication.willResignActiveNotification,
            NSApplication.willTerminateNotification
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
                MainActor.assumeIsolated {
                    PatternManager.shared.flushSave()
                    SessionStore.flush()
                    UserPresetStore.flush()
                    KitStore.flush()
                    EffectSceneStore.flush()
                }
            }
            lifecycleObservers.append(token)
        }
    }
    
    private func applyLoadedLibrary(_ saved: PatternLibrary) {
        patterns = saved.patterns
        if patterns.indices.contains(saved.activePatternIndex) {
            activePatternIndex = saved.activePatternIndex
        }
    }

    /// A factory placeholder at the default tempo, with no notes.
    /// Old files used `sound_N`. New empty slots use the eight library defaults.
    private func isBlankSlot(_ slot: Int) -> Bool {
        guard patterns.indices.contains(slot), !hasContent(slot: slot) else { return false }
        let pattern = patterns[slot]
        guard pattern.bpm == 120, pattern.swing == 0 else { return false }
        let legacy = pattern.tracks.enumerated().allSatisfy { index, track in
            track.soundPreset.filename == "sound_\(index)"
        }
        if legacy { return true }
        let defaults = (0..<8).map { SoundLibraryManager.shared.defaultPreset(forTrackIndex: $0).filename }
        guard pattern.tracks.count == defaults.count else { return false }
        return zip(pattern.tracks, defaults).allSatisfy { track, filename in
            track.soundPreset.filename == filename
        }
    }

    private func blankCopy(of sequencer: SequencerEngine, name: String, id: UUID) -> DrumPattern {
        var pattern = DrumPattern(
            name: name,
            tracks: sequencer.tracks,
            bpm: sequencer.bpm,
            swing: sequencer.swing,
            stepCount: sequencer.stepCount
        )
        pattern.id = id
        for index in pattern.tracks.indices {
            for step in pattern.tracks[index].steps.indices {
                pattern.tracks[index].steps[step].isActive = false
            }
            pattern.tracks[index].isMuted = false
            pattern.tracks[index].isSolo = false
        }
        return pattern
    }

    // MARK: - Factory
    private func makeEmptyPattern(index: Int) -> DrumPattern {
        let tracks = (0..<8).map { i -> SequencerTrack in
            SequencerTrack(soundPreset: SoundLibraryManager.shared.defaultPreset(forTrackIndex: i))
        }
        
        return DrumPattern(
            name: ["A", "B", "C", "D"][min(index, 3)],
            tracks: tracks,
            stepCount: .sixteen
        )
    }
}
