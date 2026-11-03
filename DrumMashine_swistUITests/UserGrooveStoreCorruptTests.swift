import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_7 IN-4: broken or empty user_grooves.json → [] without crash and without a silent overwrite.
@MainActor
struct UserGrooveStoreCorruptTests {
    @Test(arguments: ["{ not json", ""])
    func brokenFileLoadsEmptyAndIsNotOverwritten(contents: String) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserGrooveCorrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("\(UserGrooveStore.fileName).json")
        let bytes = Data(contents.utf8)
        try bytes.write(to: url)

        let store = UserGrooveStore(directory: dir)
        #expect(store.grooves.isEmpty)

        // The broken bytes are kept aside (quarantined), never replaced by "[]".
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let kept = names.filter { $0.hasPrefix("\(UserGrooveStore.fileName).corrupt-") }
        #expect(kept.count == 1)
        if let name = kept.first {
            #expect(try Data(contentsOf: dir.appendingPathComponent(name)) == bytes)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
