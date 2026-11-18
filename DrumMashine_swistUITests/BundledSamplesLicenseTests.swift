import Foundation
import Testing
@testable import DrumMashine_swistUI

struct BundledSamplesLicenseTests {
    @Test func everyBundledWavIsNamedInACreditsFileThatSaysCC0() throws {
        let kick = try #require(BundledSamples.url(for: "acoustic_kick.wav"))
        let folder = kick.deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let wavs = files.filter { $0.pathExtension.lowercased() == "wav" }
        let credits = files.filter { $0.lastPathComponent.uppercased().contains("CREDITS") }
        #expect(!wavs.isEmpty)
        #expect(!credits.isEmpty)
        var text = ""
        for url in credits {
            let page = try String(contentsOf: url, encoding: .utf8)
            #expect(page.contains("CC0"), "\(url.lastPathComponent)")
            text += page
        }
        for wav in wavs {
            #expect(text.contains(wav.lastPathComponent), "\(wav.lastPathComponent)")
        }
    }
}
