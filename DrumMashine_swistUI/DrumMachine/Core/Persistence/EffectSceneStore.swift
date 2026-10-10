import Foundation
import Observation
import os

/// A named copy of the effect chain. The chain is the values at save time.
nonisolated struct EffectScene: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var chain: EffectsChain
}

/// `effect_scenes.json` next to the patterns. A scene is a name plus an `EffectsChain`.
@MainActor
@Observable
final class EffectSceneStore {
    static let version = 1
    static let fileName = "effect_scenes"

    private static let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "persistence")

    static let shared = EffectSceneStore(directory: PatternManager.shared.directory)

    static func flush() { shared.flush() }

    private let store: PersistenceStore
    private(set) var scenes: [EffectScene] = []
    private var saveTask: Task<Void, Never>?
    private var savePending = false
    private var writesBlocked = false

    init(directory: URL) {
        store = PersistenceStore(directory: directory)
        load()
    }

    /// Empty names are ignored. The copy is independent of later knob moves.
    @discardableResult
    func save(name: String, chain: EffectsChain) -> EffectScene? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !writesBlocked else { return nil }
        let scene = EffectScene(id: UUID(), name: trimmed, chain: chain)
        scenes.append(scene)
        scheduleSave()
        return scene
    }

    func rename(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !writesBlocked else { return }
        guard let index = scenes.firstIndex(where: { $0.id == id }) else { return }
        scenes[index].name = trimmed
        scheduleSave()
    }

    func delete(id: UUID) {
        guard !writesBlocked else { return }
        let before = scenes.count
        scenes.removeAll { $0.id == id }
        guard scenes.count != before else { return }
        scheduleSave()
    }

    /// Drop pending edits and read the file again. Import writes the file itself.
    func reload() {
        saveTask?.cancel()
        saveTask = nil
        savePending = false
        writesBlocked = false
        load()
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
            switch try store.read(Self.fileName, as: [EffectScene].self, maximumVersion: Self.version) {
            case .missing:
                scenes = []
            case .loaded(let value):
                scenes = value
            case .recovered(let value, let note):
                scenes = value
                Self.logger.error("\(note, privacy: .public)")
            }
        } catch let error as PersistenceError where error.isNewerVersion {
            writesBlocked = true
            scenes = []
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
        } catch {
            scenes = []
            Self.logger.error("Could not read effect scenes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeNow() {
        guard !writesBlocked else { return }
        savePending = false
        do {
            try store.write(scenes, name: Self.fileName, version: Self.version)
        } catch {
            savePending = true
            Self.logger.error("Could not save effect scenes: \(error.localizedDescription, privacy: .public)")
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
