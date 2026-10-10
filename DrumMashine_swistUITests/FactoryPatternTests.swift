import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct FactoryPatternTests {
    @Test func fortyPatternsHaveStableIDsAndLegalGrids() {
        let first = FactoryPatterns.all()
        let second = FactoryPatterns.all()
        #expect(first.count == 40)
        #expect(first.map(\.id) == second.map(\.id))
        #expect(Set(first.map(\.id)).count == 40)
        let allowed = Set("Xxg-")
        let filenames = Set(SoundLibraryManager.shared.availableSounds.map(\.filename))
        let kitIDs = Set(FactoryKits.all().map(\.id))
        for spec in first {
            #expect(kitIDs.contains(SoundLibraryManager.factoryID(filename: spec.kitID)))
            for filename in spec.trackOverrides.values {
                #expect(filenames.contains(filename))
            }
            let kit = FactoryKits.all().first {
                $0.id == SoundLibraryManager.factoryID(filename: spec.kitID)
            }
            let kitFilenames = kit?.sounds.map(\.filename) ?? []
            #expect(kitFilenames.count == 8)
            #expect(kitFilenames.allSatisfy { filenames.contains($0) })
            for row in spec.rows.values {
                #expect(row.count == 16)
                #expect(row.allSatisfy { allowed.contains($0) })
            }
            let made = FactoryPatterns.makePattern(spec)
            let again = FactoryPatterns.makePattern(spec)
            #expect(made.id == again.id)
            #expect(made.id == SoundLibraryManager.factoryID(filename: "pattern.\(spec.id)"))
            #expect(made.name == spec.name)
            #expect(made.bpm == spec.bpm)
            #expect(made.swing == spec.swing)
            #expect(made.stepCount == .sixteen)
            #expect(made.tracks.count == 8)
            #expect(made.tracks.allSatisfy { $0.volume == 1 && $0.pan == 0 })
            #expect(FactoryPatterns.matchesLoadedGrid(
                tracks: made.tracks,
                stepCount: .sixteen,
                spec: spec
            ))
        }
        let genres = first.map(\.genre)
        #expect(genres == [
            "House", "House", "House",
            "Techno", "Techno", "Techno",
            "Hip-Hop", "Hip-Hop", "Hip-Hop", "Hip-Hop",
            "Trap", "Trap", "Trap",
            "Drum & Bass", "Drum & Bass", "Drum & Bass",
            "Rock", "Rock", "Rock",
            "Funk", "Funk", "Funk",
            "Reggaeton", "Reggaeton", "Reggaeton",
            "Lo-Fi", "Lo-Fi", "Lo-Fi",
            "Afrobeats", "Amapiano", "Dancehall", "Reggae", "Bossa Nova", "UK Garage",
            "Breakbeat", "Electro", "Dubstep", "Synthwave", "Jazz", "Blues"
        ])
    }

    @Test func houseClassicAndDnBRollerMatchEverySymbol() throws {
        let house = try #require(FactoryPatterns.all().first { $0.id == "house_classic" })
        let roller = try #require(FactoryPatterns.all().first { $0.id == "dnb_roller" })
        try expectSymbols(house)
        try expectSymbols(roller)
        let housePattern = FactoryPatterns.makePattern(house)
        #expect(housePattern.tracks[7].soundPreset.filename == "oh_909")
        #expect(housePattern.tracks[0].soundPreset.filename == "kick_909")
        #expect(housePattern.bpm == 124)
        #expect(housePattern.swing == 10)
        let rollerPattern = FactoryPatterns.makePattern(roller)
        #expect(rollerPattern.bpm == 172)
        #expect(rollerPattern.swing == 0)
        #expect(rollerPattern.tracks[2].steps[2].isActive)
        #expect(rollerPattern.tracks[2].steps[2].velocity == 0.4)
        #expect(rollerPattern.tracks[2].steps[3].velocity == 0.75)
    }

    private func expectSymbols(_ spec: FactoryPatternSpec) throws {
        let pattern = FactoryPatterns.makePattern(spec)
        for track in 0..<8 {
            let row = spec.rows[track] ?? String(repeating: "-", count: 16)
            #expect(pattern.tracks[track].steps.count == 16)
            for (index, symbol) in row.enumerated() {
                let step = pattern.tracks[track].steps[index]
                #expect(step.probability == 1)
                switch symbol {
                case "X":
                    #expect(step.isActive)
                    #expect(step.velocity == 1)
                case "x":
                    #expect(step.isActive)
                    #expect(step.velocity == 0.75)
                case "g":
                    #expect(step.isActive)
                    #expect(step.velocity == 0.4)
                case "-":
                    #expect(step.isActive == false)
                default:
                    Issue.record("bad symbol \(symbol)")
                }
            }
        }
    }
}
