import Foundation
import Testing

/// CUT_10 IN-4: the grid views must not read the playhead (only PlayheadOverlay redraws per step).
struct StepFlashSourceGuardTests {
    private static let seqDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DrumMashine_swistUI/DrumMachine/Features/Sequencer")

    /// Code of one top-level struct (from `struct Name` to the next top-level `struct`), comments dropped.
    private func structBody(_ name: String, in file: String) throws -> String {
        let s = try String(contentsOf: Self.seqDir.appendingPathComponent(file), encoding: .utf8)
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.hasPrefix("struct \(name)") }) else { return "" }
        var out: [String] = []
        for l in lines[start...] {
            if !out.isEmpty && l.hasPrefix("struct ") { break }
            if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            out.append(l)
        }
        return out.joined(separator: "\n")
    }

    @Test(arguments: [
        ("SequencerTracksView", "SequencerView.swift"),
        ("SequencerRowView", "SequencerView.swift"),
        ("StepButtonView", "StepButtonView.swift"),
    ])
    func gridDoesNotReadPlayhead(_ name: String, _ file: String) throws {
        let body = try structBody(name, in: file)
        #expect(body.count > 200, "struct \(name) not found in \(file)")
        #expect(!body.contains("currentStep"))
        #expect(!body.contains("isPlaying"))
    }
}
