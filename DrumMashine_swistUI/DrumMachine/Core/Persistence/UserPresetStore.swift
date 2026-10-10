import Foundation
import Observation
import os

/// `user_presets.json` next to the patterns. The app uses `shared`. A test builds another instance.
@MainActor
@Observable
final class UserPresetStore {
    static let version = 1
    static let fileName = "user_presets"

    private static let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "persistence")

    static let shared = UserPresetStore(directory: PatternManager.shared.directory)

    static func flush() { shared.flush() }

    private let store: PersistenceStore
    private(set) var presets: [SoundPreset] = []
    private var saveTask: Task<Void, Never>?
    private var savePending = false
    private var writesBlocked = false

    init(directory: URL) {
        store = PersistenceStore(directory: directory)
        load()
    }

    func preset(id: UUID) -> SoundPreset? {
        presets.first { $0.id == id }
    }

    func replaceAll(_ next: [SoundPreset]) {
        guard !writesBlocked else { return }
        presets = next
        scheduleSave()
    }

    func addMissing(_ incoming: [SoundPreset]) {
        guard !writesBlocked else { return }
        for preset in incoming where !presets.contains(where: { $0.id == preset.id }) {
            presets.append(preset)
        }
        scheduleSave()
    }

    func save(_ preset: SoundPreset) {
        guard !writesBlocked else { return }
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
        } else {
            presets.append(preset)
        }
        scheduleSave()
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].name = trimmed
        scheduleSave()
    }

    func delete(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        presets.removeAll { $0.id == id }
        scheduleSave()
        guard case .sample(let fileName, _) = preset.source else { return }
        guard !sampleIsReferenced(fileName) else { return }
        let url = store.directory
            .appendingPathComponent("Samples", isDirectory: true)
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// A new user preset. The pad that already holds a copy is left alone.
    @discardableResult
    func duplicate(id: UUID) -> SoundPreset? {
        guard let source = presets.first(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " копия"
        copy.origin = .user
        copy.basedOn = source.basedOn ?? source.id
        presets.append(copy)
        scheduleSave()
        return copy
    }

    /// A user copy of any preset, including one that is not already in this store.
    @discardableResult
    func saveCopy(of source: SoundPreset) -> SoundPreset? {
        guard !writesBlocked else { return nil }
        var copy = source
        copy.id = UUID()
        copy.name = source.name + " копия"
        copy.origin = .user
        copy.basedOn = source.id
        presets.append(copy)
        scheduleSave()
        return copy
    }

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

    func flush() {
        guard savePending, !writesBlocked else { return }
        saveTask?.cancel()
        saveTask = nil
        writeNow()
    }

    private func load() {
        do {
            switch try store.read(Self.fileName, as: [SoundPreset].self, maximumVersion: Self.version) {
            case .missing:
                presets = []
            case .loaded(let value):
                presets = value
            case .recovered(let value, let note):
                presets = value
                Self.logger.error("\(note, privacy: .public)")
            }
        } catch let error as PersistenceError where error.isNewerVersion {
            writesBlocked = true
            presets = []
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
        } catch {
            presets = []
            Self.logger.error("Could not read user presets: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeNow() {
        guard !writesBlocked else { return }
        savePending = false
        do {
            try store.write(presets, name: Self.fileName, version: Self.version)
        } catch {
            savePending = true
            Self.logger.error("Could not save user presets: \(error.localizedDescription, privacy: .public)")
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

    /// Pads, pattern slots, kits, and other user presets. The file stays while any of them use it.
    private func sampleIsReferenced(_ fileName: String) -> Bool {
        if presets.contains(where: { Self.sampleFileName($0) == fileName }) { return true }
        let directory = store.directory.standardizedFileURL
        if directory == PatternManager.shared.directory.standardizedFileURL {
            if PatternManager.shared.patterns.contains(where: { pattern in
                pattern.tracks.contains { Self.sampleFileName($0.soundPreset) == fileName }
            }) { return true }
            if KitStore.shared.kits.contains(where: { kit in
                kit.sounds.contains { Self.sampleFileName($0) == fileName }
            }) { return true }
            if SessionStore.shared.current().tracks.contains(where: {
                Self.sampleFileName($0.soundPreset) == fileName
            }) { return true }
            return false
        }
        return diskReferences(fileName)
    }

    private func diskReferences(_ fileName: String) -> Bool {
        let reader = PersistenceStore(directory: store.directory)
        if case .loaded(let library) = try? reader.read(
            "patterns",
            as: PatternLibrary.self,
            maximumVersion: PersistenceStore.patternsVersion
        ) {
            if library.patterns.contains(where: { pattern in
                pattern.tracks.contains { Self.sampleFileName($0.soundPreset) == fileName }
            }) { return true }
        }
        if case .loaded(let session) = try? reader.read(
            SessionStore.fileName,
            as: SessionState.self,
            maximumVersion: SessionStore.version
        ) {
            if session.tracks.contains(where: { Self.sampleFileName($0.soundPreset) == fileName }) {
                return true
            }
        }
        if case .loaded(let kits) = try? reader.read("user_kits", as: [DrumKit].self, maximumVersion: 1) {
            if kits.contains(where: { kit in kit.sounds.contains { Self.sampleFileName($0) == fileName } }) {
                return true
            }
        }
        return false
    }

    private static func sampleFileName(_ preset: SoundPreset) -> String? {
        if case .sample(let fileName, _) = preset.source { return fileName }
        return nil
    }
}
