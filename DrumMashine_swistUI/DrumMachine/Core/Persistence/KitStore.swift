import Foundation
import Observation
import os

/// `user_kits.json` next to the patterns. A kit stores copies of the eight pads.
@MainActor
@Observable
final class KitStore {
    static let version = 1
    static let fileName = "user_kits"

    private static let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "persistence")

    static let shared = KitStore(directory: PatternManager.shared.directory)

    static func flush() { shared.flush() }

    private let store: PersistenceStore
    private(set) var kits: [DrumKit] = []
    private var saveTask: Task<Void, Never>?
    private var savePending = false
    private var writesBlocked = false

    init(directory: URL) {
        store = PersistenceStore(directory: directory)
        load()
    }

    func save(_ kit: DrumKit) {
        guard !writesBlocked else { return }
        if let index = kits.firstIndex(where: { $0.id == kit.id }) {
            kits[index] = kit
        } else {
            kits.append(kit)
        }
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
            switch try store.read(Self.fileName, as: [DrumKit].self, maximumVersion: Self.version) {
            case .missing:
                kits = []
            case .loaded(let value):
                kits = value
            case .recovered(let value, let note):
                kits = value
                Self.logger.error("\(note, privacy: .public)")
            }
        } catch let error as PersistenceError where error.isNewerVersion {
            writesBlocked = true
            kits = []
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
        } catch {
            kits = []
            Self.logger.error("Could not read kits: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeNow() {
        guard !writesBlocked else { return }
        savePending = false
        do {
            try store.write(kits, name: Self.fileName, version: Self.version)
        } catch {
            savePending = true
            Self.logger.error("Could not save kits: \(error.localizedDescription, privacy: .public)")
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
