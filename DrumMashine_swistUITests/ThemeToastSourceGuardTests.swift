import Foundation
import Testing

/// CUT_9 IN-3: source-scan guard so P3-1 (.id theme rebuild) and P3-5 (asyncAfter toasts) don't come back.
struct ThemeToastSourceGuardTests {
    private static let appRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DrumMashine_swistUI/DrumMachine")

    private func swiftFiles() throws -> [URL] {
        let e = FileManager.default.enumerator(at: Self.appRoot, includingPropertiesForKeys: nil)
        var out: [URL] = []
        while let u = e?.nextObject() as? URL { if u.pathExtension == "swift" { out.append(u) } }
        return out
    }

    private func source(_ rel: String) throws -> String {
        try String(contentsOf: Self.appRoot.appendingPathComponent(rel), encoding: .utf8)
    }

    @Test func scanFindsAppSources() throws {
        #expect(try swiftFiles().count > 20)
    }

    @Test func noThemeIdRebuildAnywhere() throws {
        var hits: [String] = []
        for f in try swiftFiles() {
            // Code lines only; doc comments may mention the old pattern.
            let s = try String(contentsOf: f, encoding: .utf8)
                .split(separator: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for needle in [".id(theme", ".id(ThemeStore", ".id(style"] where s.contains(needle) {
                hits.append("\(f.lastPathComponent): \(needle)")
            }
        }
        #expect(hits.isEmpty, "found: \(hits)")
    }

    @Test(arguments: [
        "Features/Sequencer/PatternSlotsView.swift",
        "Features/SoundLibrary/SoundLibraryView.swift",
    ])
    func toastUsesCancellableTask(_ rel: String) throws {
        let s = try source(rel)
        #expect(!s.contains("asyncAfter"))
        #expect(s.contains(".task(id: flashToken)"))
        #expect(s.contains("guard !Task.isCancelled"))
        #expect(s.contains("flashToken &+= 1"))
    }
}
