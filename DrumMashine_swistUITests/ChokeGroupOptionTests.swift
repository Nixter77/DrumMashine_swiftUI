import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_12 IN-4: choke picker / pad badge model.
@MainActor
struct ChokeGroupOptionTests {
    @Test func nilMapsToOff() {
        #expect(ChokeGroupOption(preset: nil) == .off)
        #expect(ChokeGroupOption.off.presetValue == nil)
        #expect(ChokeGroupOption.off.badge == nil)
    }

    @Test func groupsOneToFourRoundtrip() {
        let expected: [ChokeGroupOption] = [.g1, .g2, .g3, .g4]
        for n in 1...4 {
            let option = ChokeGroupOption(preset: n)
            #expect(option == expected[n - 1])
            #expect(option.presetValue == n)
        }
        #expect(ChokeGroupOption.allCases.map(\.presetValue) == [nil, 1, 2, 3, 4])
    }

    @Test func badgeStrings() {
        #expect(ChokeGroupOption.allCases.map(\.badge) == [nil, "C1", "C2", "C3", "C4"])
        let odd = ChokeGroupOption(preset: 7)
        #expect(odd.presetValue == 7)
        #expect(odd.badge == "C7")
        #expect(ChokeGroupOption.options(including: odd).count == 6)
        #expect(ChokeGroupOption.options(including: .g2).count == 5)
    }

    @Test func soundPresetCodableRoundtrip() throws {
        var preset = SoundLibraryManager.shared.defaultPreset(forTrackIndex: 2)
        for value in [3, nil] as [Int?] {
            preset.chokeGroup = value
            let data = try JSONEncoder().encode(preset)
            let decoded = try JSONDecoder().decode(SoundPreset.self, from: data)
            #expect(decoded.chokeGroup == value)
            #expect(ChokeGroupOption(preset: decoded.chokeGroup).presetValue == value)
        }
    }

    @Test func factoryHatsAreGroupOne() {
        let hats = (FactoryPresets.additional() + AcousticKit.presets())
            .filter { $0.resolvedVoice == .closedHat || $0.resolvedVoice == .openHat }
        #expect(hats.count >= 12)
        for hat in hats {
            let option = ChokeGroupOption(preset: hat.chokeGroup)
            #expect(option == .g1, "\(hat.name)")
            #expect(option.badge == "C1")
        }
        let ch808 = try? #require(hats.first { $0.name == "CH 808" })
        #expect(ChokeGroupOption(preset: ch808?.chokeGroup).badge == "C1")
    }
}
