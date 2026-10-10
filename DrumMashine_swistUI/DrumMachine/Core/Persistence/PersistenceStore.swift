import Foundation
import Observation
import os

/// The banner reads this. Every store reports here, and each store also keeps its own `lastError`.
@MainActor
@Observable
final class PersistenceAlerts {
    static let shared = PersistenceAlerts()

    private(set) var lastError: PersistenceError?
    private(set) var fileURL: URL?
    private(set) var isDismissed = false
    private let logger = Logger(subsystem: "Home.DrumMashine-swistUI", category: "persistence")

    var isVisible: Bool { lastError != nil && !isDismissed }

    func report(_ error: PersistenceError, url: URL) {
        lastError = error
        fileURL = url
        isDismissed = false
        logger.error("\(error.localizedDescription, privacy: .public)")
    }

    func dismiss() {
        isDismissed = true
    }

    func clear(file: String?) {
        guard file == nil || lastError?.file == file else { return }
        lastError = nil
        fileURL = nil
        isDismissed = false
    }

    func text(for error: PersistenceError) -> String {
        let noun: String
        switch error.file {
        case "patterns": noun = "паттерны"
        case "session": noun = "сессию"
        case "user_presets": noun = "пресеты"
        case "user_kits": noun = "киты"
        case "effect_scenes": noun = "сцены"
        default: noun = error.file
        }
        let verb = error.operation == .write ? "сохранить" : "прочитать"
        return "Не удалось \(verb) \(noun): \(error.reason). Данные в памяти не потеряны, попробуйте ещё раз"
    }
}

/// Application Support/DrumMachine. Each document is `{ version, savedAt, payload }`.
@MainActor
struct PersistenceStore {
    static let patternsVersion = 1
    #if DEBUG
    /// The next write throws once. The Debug menu uses this to show the banner.
    static var debugFailNextWrite = false
    #endif

    let directory: URL
    private let setupError: Error?
    private let errors = PersistenceErrorState()

    var lastError: PersistenceError? { errors.lastError }

    init(directory: URL) {
        self.directory = directory
        let samples = directory.appendingPathComponent("Samples", isDirectory: true)
        let backups = directory.appendingPathComponent("Backups", isDirectory: true)
        var caught: Error?
        for folder in [directory, samples, backups] {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                caught = error
                break
            }
        }
        self.setupError = caught
    }

    var samplesDirectory: URL {
        directory.appendingPathComponent("Samples", isDirectory: true)
    }

    var backupsDirectory: URL {
        directory.appendingPathComponent("Backups", isDirectory: true)
    }

    func fileURL(_ name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    /// `nil` payload means the file is not there yet. A newer version is thrown and the file is left as it is.
    func read<Payload: Codable>(
        _ name: String,
        as type: Payload.Type,
        maximumVersion: Int
    ) throws -> PersistenceRead<Payload> {
        if let setupError {
            throw record(.failed(operation: .read, file: name, reason: setupError.localizedDescription))
        }
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            clearError(file: name)
            return .missing
        }
        do {
            let data = try Data(contentsOf: url)
            let payload: Payload = try decode(data, name: name, maximumVersion: maximumVersion)
            clearError(file: name)
            return .loaded(payload)
        } catch let error as PersistenceError where error.isNewerVersion {
            throw record(error)
        } catch {
            let reason = error.localizedDescription
            try quarantine(url, name: name)
            do {
                if let backup = try readBackup(name, as: type, maximumVersion: maximumVersion) {
                    let note = "Read \(name).json from the backup. \(reason)"
                    _ = record(.failed(operation: .read, file: name, reason: note))
                    return .recovered(backup, note: note)
                }
            } catch let error as PersistenceError where error.isNewerVersion {
                throw record(error)
            } catch {
                throw record(.unreadable(file: name, reason: error.localizedDescription))
            }
            throw record(.unreadable(file: name, reason: reason))
        }
    }

    func write<Payload: Codable>(_ payload: Payload, name: String, version: Int) throws {
        if let setupError {
            throw record(.failed(operation: .write, file: name, reason: setupError.localizedDescription))
        }
        #if DEBUG
        if Self.debugFailNextWrite {
            Self.debugFailNextWrite = false
            throw record(.failed(operation: .write, file: name, reason: "simulated save error"))
        }
        #endif
        let url = fileURL(name)
        let envelope = PersistenceEnvelope(version: version, savedAt: Date(), payload: payload)
        let data: Data
        do {
            data = try Self.encoder.encode(envelope)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: url.path) {
                let backup = url.appendingPathExtension("bak")
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.removeItem(at: backup)
                }
                try fileManager.copyItem(at: url, to: backup)
            }
            try data.write(to: url, options: .atomic)
        } catch let error as PersistenceError {
            throw record(error)
        } catch {
            throw record(.failed(operation: .write, file: name, reason: error.localizedDescription))
        }
        clearError(file: name)
    }

    @discardableResult
    private func record(_ error: PersistenceError) -> PersistenceError {
        errors.lastError = error
        PersistenceAlerts.shared.report(error, url: fileURL(error.file))
        return error
    }

    private func clearError(file: String) {
        if errors.lastError?.file == file {
            errors.lastError = nil
        }
        PersistenceAlerts.shared.clear(file: file)
    }

    private func readBackup<Payload: Codable>(
        _ name: String,
        as type: Payload.Type,
        maximumVersion: Int
    ) throws -> Payload? {
        let backup = fileURL(name).appendingPathExtension("bak")
        guard FileManager.default.fileExists(atPath: backup.path) else { return nil }
        let data = try Data(contentsOf: backup)
        return try decode(data, name: name, maximumVersion: maximumVersion)
    }

    private func decode<Payload: Codable>(_ data: Data, name: String, maximumVersion: Int) throws -> Payload {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = json as? [String: Any] else {
            throw PersistenceError.unreadable(file: name, reason: "not an object")
        }
        guard let version = object["version"] as? Int else {
            throw PersistenceError.unreadable(file: name, reason: "missing version")
        }
        guard version <= maximumVersion else {
            throw PersistenceError.newerVersion(file: name, version: version)
        }
        return try Self.decoder.decode(PersistenceEnvelope<Payload>.self, from: data).payload
    }

    /// Moves an unreadable file aside. The original path is then free for a later save.
    private func quarantine(_ url: URL, name: String) throws {
        let stamp = Self.stamp.string(from: Date())
        let destination = directory.appendingPathComponent("\(name).corrupt-\(stamp).json")
        try FileManager.default.moveItem(at: url, to: destination)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys]
        #if DEBUG
        formatting.insert(.prettyPrinted)
        #endif
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmssSSS"
        return formatter
    }()
}

nonisolated enum PersistenceRead<Payload> {
    case missing
    case loaded(Payload)
    case recovered(Payload, note: String)
}

nonisolated struct PersistenceEnvelope<Payload: Codable>: Codable {
    var version: Int
    var savedAt: Date
    var payload: Payload
}

nonisolated enum PersistenceOperation: String, Sendable, Equatable {
    case read
    case write
}

@MainActor
final class PersistenceErrorState {
    var lastError: PersistenceError?
}

nonisolated enum PersistenceError: LocalizedError, Equatable {
    case newerVersion(file: String, version: Int)
    case unreadable(file: String, reason: String)
    case failed(operation: PersistenceOperation, file: String, reason: String)

    var isNewerVersion: Bool {
        if case .newerVersion = self { return true }
        return false
    }

    var operation: PersistenceOperation {
        switch self {
        case .newerVersion, .unreadable:
            return .read
        case .failed(let operation, _, _):
            return operation
        }
    }

    var file: String {
        switch self {
        case .newerVersion(let file, _), .unreadable(let file, _), .failed(_, let file, _):
            return file
        }
    }

    /// The part shown after the colon in the banner.
    var reason: String {
        switch self {
        case .newerVersion(let file, let version):
            return "\(file).json is version \(version), which this app cannot read"
        case .unreadable(_, let reason), .failed(_, _, let reason):
            return reason
        }
    }

    var errorDescription: String? {
        switch self {
        case .newerVersion, .failed:
            return reason
        case .unreadable(let file, let reason):
            return "\(file).json could not be read (\(reason))"
        }
    }
}
