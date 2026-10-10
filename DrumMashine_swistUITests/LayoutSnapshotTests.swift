import AppKit
import SwiftUI
import Testing
@testable import DrumMashine_swistUI

/// Renders the window contents at the three sizes from A-5. The sandbox cannot write `/tmp`,
/// so the files land in the app container temp folder. The test log prints each path.
@MainActor
struct LayoutSnapshotTests {
    @Test func layoutSnapshotsWriteThreeSizes() throws {
        let sizes: [(CGFloat, CGFloat)] = [(1100, 720), (1440, 900), (1920, 1080)]
        for (width, height) in sizes {
            let url = try writeSnapshot(width: width, height: height, patterns: false)
            let line = "A-5 layout snapshot \(url.path)\n"
            try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
            let bytes = try Data(contentsOf: url)
            #expect(bytes.count > 1000)
        }
    }

    /// E-3: the library inspector is open on PATTERNS at the minimum window.
    @Test func patternsPageSnapshotAtMinimumSize() throws {
        let url = try writeSnapshot(width: 1100, height: 720, patterns: true)
        let line = "E-3 patterns snapshot \(url.path)\n"
        try? FileHandle.standardError.write(contentsOf: Data(line.utf8))
        let bytes = try Data(contentsOf: url)
        #expect(bytes.count > 1000)
    }

    private func writeSnapshot(width: CGFloat, height: CGFloat, patterns: Bool) throws -> URL {
        // The patterns page sits in the inspector. The 1100-wide columns stay intact beside it.
        let canvasWidth = patterns ? width + AppLayout.libraryInspectorIdeal : width
        let content = MainLayoutView(
            showsLayoutForSnapshot: true,
            snapshotShowsPatterns: patterns
        )
            .frame(width: canvasWidth, height: height)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: canvasWidth, height: height)
        guard let image = renderer.cgImage else {
            throw LayoutSnapshotError.empty
        }
        #expect(CGFloat(image.width) >= canvasWidth - 1)
        #expect(CGFloat(image.height) >= height - 1)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw LayoutSnapshotError.encode
        }
        let name = patterns
            ? "drum_patterns_\(Int(width))x\(Int(height)).png"
            : "drum_layout_\(Int(width))x\(Int(height)).png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try png.write(to: url, options: .atomic)
        return url
    }
}

private enum LayoutSnapshotError: Error {
    case empty
    case encode
}
