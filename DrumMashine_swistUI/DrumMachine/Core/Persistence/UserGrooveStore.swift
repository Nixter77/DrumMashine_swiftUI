import Foundation
import Observation
import os

/// `user_grooves.json` next to the patterns. Small file, written straight away.
@MainActor
@Observable
final class UserGrooveStore {
    static let version = 1
    static let fileName = "user_grooves"
    private static let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "persistence")

    static let shared = UserGrooveStore(directory: PatternManager.shared.directory)

    private let store: PersistenceStore
    private(set) var grooves: [GrooveTemplate] = []
    private var writesBlocked = false

    init(directory: URL) {
        store = PersistenceStore(directory: directory)
        do {
            switch try store.read(Self.fileName, as: [GrooveTemplate].self, maximumVersion: Self.version) {
            case .missing: grooves = []
            case .loaded(let v): grooves = v.map { $0.normalized() }
            case .recovered(let v, let note):
                grooves = v.map { $0.normalized() }
                Self.logger.error("\(note, privacy: .public)")
            }
        } catch let error as PersistenceError where error.isNewerVersion {
            writesBlocked = true
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
        } catch {
            Self.logger.error("Could not read user grooves: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Unique name among factory and user grooves: "Мой грув", "Мой грув 2", …
    func uniqueName(_ base: String) -> String {
        let taken = Set((FactoryGrooves.all + grooves).map(\.name))
        if !taken.contains(base) { return base }
        var n = 2
        while taken.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    @discardableResult
    func add(_ groove: GrooveTemplate) -> GrooveTemplate {
        var g = groove.normalized()
        g.name = uniqueName(g.name)
        grooves.append(g)
        write()
        return g
    }

    func delete(id: String) {
        grooves.removeAll { $0.id == id }
        write()
    }

    private func write() {
        guard !writesBlocked else { return }
        do { try store.write(grooves, name: Self.fileName, version: Self.version) }
        catch { Self.logger.error("Could not save user grooves: \(error.localizedDescription, privacy: .public)") }
    }
}
