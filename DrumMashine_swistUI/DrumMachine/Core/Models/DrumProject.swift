import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

nonisolated extension UTType {
    static var drumproj: UTType { UTType(exportedAs: "home.drummachine.project") }
}

/// One JSON document for a full backup. Kits and samples stay empty until D-3 and D-4.
nonisolated struct ProjectSample: Codable, Equatable, Sendable {
    var fileName: String
    var originalName: String
    var data: Data
}

nonisolated struct DrumProject: Codable, Equatable, Sendable, Identifiable {
    static let formatVersion = 1

    var id: UUID
    var name: String
    var version: Int
    var session: SessionState
    var slots: PatternLibrary
    var userPresets: [SoundPreset]
    var kits: [DrumKit]
    var samples: [ProjectSample]
    var scenes: [EffectScene]

    init(name: String) {
        id = UUID()
        self.name = name
        version = Self.formatVersion
        session = SessionState(tracks: [])
        slots = PatternLibrary(patterns: [], activePatternIndex: 0)
        userPresets = []
        kits = []
        samples = []
        scenes = []
    }

    var swing: Double { session.swing }
    var masterVolume: Float { session.masterVolume }
}

extension DrumProject {
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.formatVersion
        guard storedVersion <= Self.formatVersion else {
            throw PersistenceError.newerVersion(file: "drumproj", version: storedVersion)
        }
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Beat"
        version = storedVersion
        // Missing keys fall back to the same defaults as `init(name:)` (empty session tracks
        // = library sounds; no pattern slots) instead of failing the whole import.
        session = try container.decodeIfPresent(SessionState.self, forKey: .session) ?? SessionState(tracks: [])
        slots = try container.decodeIfPresent(PatternLibrary.self, forKey: .slots)
            ?? PatternLibrary(patterns: [], activePatternIndex: 0)
        userPresets = try container.decodeIfPresent([SoundPreset].self, forKey: .userPresets) ?? []
        kits = try container.decodeIfPresent([DrumKit].self, forKey: .kits) ?? []
        samples = try container.decodeIfPresent([ProjectSample].self, forKey: .samples) ?? []
        scenes = try container.decodeIfPresent([EffectScene].self, forKey: .scenes) ?? []
    }

    nonisolated func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #if DEBUG
        encoder.outputFormatting.insert(.prettyPrinted)
        #endif
        return try encoder.encode(self)
    }

    nonisolated static func decode(_ data: Data) throws -> DrumProject {
        try JSONDecoder().decode(DrumProject.self, from: data)
    }
}

extension DrumProject {
    /// Create from current app state. Swing stays on the sequencer's 0…100 scale.
    @MainActor
    static func fromCurrentState(
        name: String,
        bpm: Double,
        swing: Double,
        tracks: [SequencerTrack],
        patterns: [DrumPattern]
    ) -> DrumProject {
        var project = DrumProject(name: name)
        project.session = SessionState(
            tracks: tracks,
            bpm: bpm,
            swing: swing,
            masterVolume: AudioEngineManager.shared.masterVolume
        )
        project.slots = PatternLibrary(patterns: patterns, activePatternIndex: 0)
        return project
    }

    static var preview: DrumProject {
        var project = DrumProject(name: "My Beat")
        project.session = SessionState(
            tracks: [
                SequencerTrack(soundPreset: SoundPreset(
                    id: UUID(),
                    name: "Test Kick",
                    filename: "kick_01",
                    category: .kick
                ))
            ],
            bpm: 128,
            swing: 55
        )
        return project
    }

    @MainActor
    static func capture(
        name: String,
        patterns: PatternManager,
        session: SessionStore,
        presets: UserPresetStore
    ) -> DrumProject {
        var project = DrumProject(name: name)
        project.session = session.current()
        project.slots = PatternLibrary(patterns: patterns.patterns, activePatternIndex: patterns.activePatternIndex)
        project.userPresets = presets.presets
        project.kits = readKits(in: patterns.directory)
        project.samples = readSamples(in: patterns.directory)
        project.scenes = readScenes(in: patterns.directory)
        return project
    }

    /// Replace writes every store. Add keeps the session and fills only blank slots and new presets.
    @MainActor
    func apply(
        to patterns: PatternManager,
        session: SessionStore,
        presets: UserPresetStore,
        mode: ProjectImportMode
    ) throws {
        if mode == .replace {
            try Self.backup(directory: patterns.directory)
        }
        let store = PersistenceStore(directory: patterns.directory)
        switch mode {
        case .replace:
            patterns.importLibrary(slots, replacing: true)
            session.replace(self.session)
            session.flush()
            presets.replaceAll(userPresets)
            presets.flush()
            try store.write(kits, name: "user_kits", version: 1)
            try store.write(scenes, name: EffectSceneStore.fileName, version: EffectSceneStore.version)
            try Self.writeSamples(samples, to: store.samplesDirectory, replacing: true)
        case .add:
            patterns.importLibrary(slots, replacing: false)
            presets.addMissing(userPresets)
            presets.flush()
            let merged = Self.mergeKits(existing: Self.readKits(in: patterns.directory), incoming: kits)
            try store.write(merged, name: "user_kits", version: 1)
            let mergedScenes = Self.mergeScenes(existing: Self.readScenes(in: patterns.directory), incoming: scenes)
            try store.write(mergedScenes, name: EffectSceneStore.fileName, version: EffectSceneStore.version)
            try Self.writeSamples(samples, to: store.samplesDirectory, replacing: false)
        }
        patterns.flushSave()
    }

    @MainActor
    private static func backup(directory: URL) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = directory
            .appendingPathComponent("Backups", isDirectory: true)
            .appendingPathComponent("project-\(formatter.string(from: Date()))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["patterns.json", "session.json", "user_presets.json", "user_kits.json", "effect_scenes.json"] {
            let source = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent(name))
        }
        let samples = directory.appendingPathComponent("Samples", isDirectory: true)
        let sampleCopy = folder.appendingPathComponent("Samples", isDirectory: true)
        if FileManager.default.fileExists(atPath: samples.path) {
            try FileManager.default.copyItem(at: samples, to: sampleCopy)
        }
    }

    @MainActor
    private static func readKits(in directory: URL) -> [DrumKit] {
        let store = PersistenceStore(directory: directory)
        guard case .loaded(let kits) = try? store.read("user_kits", as: [DrumKit].self, maximumVersion: 1) else {
            return []
        }
        return kits
    }

    @MainActor
    private static func readScenes(in directory: URL) -> [EffectScene] {
        let store = PersistenceStore(directory: directory)
        guard case .loaded(let scenes) = try? store.read(
            EffectSceneStore.fileName,
            as: [EffectScene].self,
            maximumVersion: EffectSceneStore.version
        ) else {
            return []
        }
        return scenes
    }

    private static func mergeScenes(existing: [EffectScene], incoming: [EffectScene]) -> [EffectScene] {
        var merged = existing
        for scene in incoming where !merged.contains(where: { $0.id == scene.id }) {
            merged.append(scene)
        }
        return merged
    }

    private static func mergeKits(existing: [DrumKit], incoming: [DrumKit]) -> [DrumKit] {
        var merged = existing
        for kit in incoming where !merged.contains(where: { $0.id == kit.id }) {
            merged.append(kit)
        }
        return merged
    }

    @MainActor
    private static func readSamples(in directory: URL) -> [ProjectSample] {
        let folder = directory.appendingPathComponent("Samples", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return ProjectSample(fileName: url.lastPathComponent, originalName: url.lastPathComponent, data: data)
        }.sorted { $0.fileName < $1.fileName }
    }

    @MainActor
    private static func writeSamples(_ samples: [ProjectSample], to folder: URL, replacing: Bool) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if replacing {
            let existing = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for url in existing {
                try FileManager.default.removeItem(at: url)
            }
        }
        for sample in samples {
            guard let name = safeSampleName(sample.fileName) else { continue }
            let url = folder.appendingPathComponent(name)
            if !replacing, FileManager.default.fileExists(atPath: url.path) { continue }
            try sample.data.write(to: url, options: .atomic)
        }
    }

    /// Keeps a sample inside the Samples folder. Rejects paths that climb out of it.
    private static func safeSampleName(_ name: String) -> String? {
        let base = (name as NSString).lastPathComponent
        guard base == name, !base.isEmpty, !base.hasPrefix("."), base != ".", base != ".." else { return nil }
        guard !base.contains("/"), !base.contains(":") else { return nil }
        return base
    }
}

enum ProjectImportMode {
    case replace
    case add
}

nonisolated struct DrumProjectFile: FileDocument {
    static var readableContentTypes: [UTType] { [.drumproj] }

    var project: DrumProject

    init(project: DrumProject) {
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        project = try DrumProject.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try project.encoded())
    }
}

/// File menu state. The window presents the exporter and the replace-or-add question.
@MainActor
@Observable
final class ProjectTransfer {
    static let shared = ProjectTransfer()
    static let didImport = Notification.Name("DrumProjectDidImport")

    var exportPresented = false
    var importPresented = false
    var askReplace = false
    var exportDocument = DrumProjectFile(project: DrumProject(name: "Beat"))
    private var pending: DrumProject?

    func beginExport() {
        KitStore.shared.flush()
        EffectSceneStore.flush()
        exportDocument = DrumProjectFile(project: DrumProject.capture(
            name: "Beat",
            patterns: PatternManager.shared,
            session: SessionStore.shared,
            presets: UserPresetStore.shared
        ))
        exportPresented = true
    }

    func receiveImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            report(error.localizedDescription, url: PatternManager.shared.directory)
        case .success(let url):
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                pending = try DrumProject.decode(Data(contentsOf: url))
                askReplace = true
            } catch {
                report(error.localizedDescription, url: url)
            }
        }
    }

    func apply(_ mode: ProjectImportMode) {
        guard let pending else { return }
        KitStore.shared.flush()
        EffectSceneStore.flush()
        do {
            try pending.apply(
                to: PatternManager.shared,
                session: SessionStore.shared,
                presets: UserPresetStore.shared,
                mode: mode
            )
            KitStore.shared.reload()
            EffectSceneStore.shared.reload()
            if mode == .replace {
                NotificationCenter.default.post(name: Self.didImport, object: pending.session)
            }
        } catch {
            report(error.localizedDescription, url: PatternManager.shared.directory)
        }
        self.pending = nil
    }

    private func report(_ reason: String, url: URL) {
        PersistenceAlerts.shared.report(
            .failed(operation: .read, file: "drumproj", reason: reason),
            url: url
        )
    }
}
