import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct AcousticCatalogTests {
    private let voices: [SoundPreset.VoiceKind] = [
        .kick, .snare, .closedHat, .clap, .tom, .ride, .crash, .perc
    ]

    @Test func twelveKitsKeepStableNamesAndDoNotCollide() {
        let kits = AcousticKits.kits()
        #expect(kits.count == 12)
        #expect(kits.map(\.name) == AcousticKits.names)
        #expect(FactoryKits.all().count == 5)
        #expect(FactoryKits.all().map(\.name) == ["808", "909", "Acoustic", "Lo-Fi", "Trap"])
        let existing = Set(SoundLibraryManager.shared.availableSounds.map(\.filename))
        let presets = AcousticKits.presets()
        #expect(presets.count == 96)
        #expect(Set(presets.map(\.filename)).count == 96)
        #expect(presets.allSatisfy { existing.contains($0.filename) })
        let legacyNames = Set(FactoryPresets.additional().map(\.filename))
            .union(AcousticKit.presets().map(\.filename))
        #expect(presets.allSatisfy { !legacyNames.contains($0.filename) })
        for kit in kits {
            #expect(kit.sounds.count == 8)
            #expect(kit.sounds.map(\.resolvedVoice) == voices)
            #expect(kit.id == SoundLibraryManager.factoryID(filename: "kit.ac.\(slug(kit.name))"))
            #expect(kit.character?.isEmpty == false)
            #expect(kit.resolvedAccentAmount >= 0 && kit.resolvedAccentAmount <= 0.4)
            #expect(kit.dynamicsDefault != nil)
            #expect(kit.mic != nil)
            for sound in kit.sounds {
                #expect(sound.dynamics != nil, "\(sound.filename) dynamics")
                #expect(sound.articulations?.isEmpty == false, "\(sound.filename) articulations")
                #expect(sound.filename.hasPrefix("ac_"))
            }
        }
        let acousticKicks = SoundLibraryManager.shared.presets(for: .kick, style: .acoustic)
        #expect(acousticKicks.contains { $0.filename == "ac_studio-dry_kick" })
        let perc = SoundLibraryManager.shared.presets(for: .perc, style: .acoustic)
        #expect(perc.contains { $0.style == .percussion && $0.filename == "ac_latin-percussion_perc" })
        let percChip = SoundLibraryManager.shared.presets(for: .kick, style: .percussion)
        #expect(percChip.contains { $0.filename == "ac_latin-percussion_kick" })
        #expect(!percChip.contains { $0.filename == "ac_studio-dry_kick" })
    }

    @Test func micMixMatchesTheKitTable() {
        let kits = Dictionary(uniqueKeysWithValues: AcousticKits.kits().map { ($0.name, $0) })
        expectMic(kits["Studio Dry"], 1, 0.3, 0.1, .small)
        expectMic(kits["Jazz Club 60s"], 0.7, 0.6, 0.3, .medium)
        expectMic(kits["Brushes Ballad"], 0.6, 0.6, 0.4, .medium)
        expectMic(kits["Funk Tight 70s"], 1, 0.2, 0.05, .small)
        expectMic(kits["Rock Big Room"], 0.8, 0.6, 0.9, .large)
        expectMic(kits["Vintage 60s Soul"], 0.6, 0.7, 0.4, .medium, tone: -0.5)
        expectMic(kits["Vintage 70s Dead"], 1, 0.1, 0, .small)
        expectMic(kits["Fusion Bright"], 0.9, 0.5, 0.2, .small)
        expectMic(kits["Hip-Hop Breaks"], 0.7, 0.5, 0.6, .medium, tone: -0.6)
        expectMic(kits["Latin Percussion"], 0.8, 0.5, 0.3, .medium)
        expectMic(kits["Cajon Unplugged"], 0.8, 0.4, 0.4, .small)
        expectMic(kits["Orchestral"], 0.4, 0.8, 0.9, .hall)
        let brushes = kits["Brushes Ballad"]
        #expect(brushes?.sounds[1].volume == Float(0.7))
        let rock = kits["Rock Big Room"]
        #expect(rock?.sounds[1].volume == 1)
    }

    @Test func notationWritesAccentAndArticulation() throws {
        #expect(FactoryPatterns.all().count == 40)
        let acoustic = FactoryPatterns.acoustic()
        #expect(acoustic.count == 12)
        #expect(Set(acoustic.map(\.id)).count == 12)
        #expect(Set(acoustic.map(\.kitID)).count == 12)
        let legacy = PatternNotation.hits(in: "X---x--g--------")
        #expect(legacy.count == 16)
        #expect(legacy[0] == PatternNotation.Hit(active: true, velocity: 1, accent: false, articulation: 0))
        #expect(legacy[4] == PatternNotation.Hit(active: true, velocity: 0.75, accent: false, articulation: 0))
        #expect(legacy[7] == PatternNotation.Hit(active: true, velocity: 0.4, accent: false, articulation: 0))
        let tokens = PatternNotation.hits(in: "A Ar g X1 xo xp xh xb X3")
        #expect(tokens[0].accent && tokens[0].articulation == 0 && tokens[0].velocity == 1)
        #expect(tokens[1].accent && tokens[1].articulation == 1)
        #expect(tokens[2].velocity == 0.4 && tokens[2].articulation == 0)
        #expect(tokens[3].articulation == 1 && tokens[3].accent == false)
        #expect(tokens[4].articulation == 1)
        #expect(tokens[5].articulation == 2)
        #expect(tokens[6].articulation == 3)
        #expect(tokens[7].articulation == 1)
        #expect(tokens[8].articulation == 3 && tokens[8].velocity == 1)

        let funkSpec = try #require(acoustic.first { $0.id == "ac_funk_tight" })
        let funk = FactoryPatterns.makePattern(funkSpec)
        let rim = funk.tracks[1].steps[12]
        #expect(rim.isActive)
        #expect(rim.accent == true)
        #expect(rim.articulation == 1)
        #expect(rim.velocity == 1)
        let ghost = funk.tracks[1].steps[6]
        #expect(ghost.isActive && ghost.velocity == 0.4 && ghost.accent == nil)
        let openHat = funk.tracks[2].steps[7]
        #expect(openHat.articulation == 1 && openHat.velocity == 0.75)
        #expect(funk.tracks[1].soundPreset.filename == "ac_funk-tight-70s_snare")
        #expect(funk.tracks.map(\.soundPreset.resolvedVoice) == voices)

        for spec in acoustic {
            let pattern = FactoryPatterns.makePattern(spec)
            #expect(pattern.tracks.count == 8)
            let wrote = pattern.tracks.contains { track in
                track.steps.contains { $0.accent == true || ($0.articulation ?? 0) != 0 }
            }
            let rows = spec.rows.values.map { PatternNotation.hits(in: $0).count }
            #expect(rows.allSatisfy { $0 == 16 }, "\(spec.id) \(rows)")
            #expect(wrote, "\(spec.id) writes accent or articulation")
            #expect(pattern.tracks.allSatisfy { $0.soundPreset.dynamics != nil })
        }
    }

    @Test func kitPreviewMixStaysOffTheUserPattern() throws {
        let engine = SequencerEngine()
        engine.tracks[0].steps[0].isActive = true
        engine.tracks[0].steps[0].velocity = 0.33
        let before = engine.tracks
        let kit = try #require(AcousticKits.kits().first { $0.name == "Studio Dry" })
        let spec = try #require(FactoryPatterns.acoustic().first { $0.id == "ac_studio_dry" })
        let pattern = FactoryPatterns.makePattern(spec)
        let mix = KitPreview.mix(pattern: pattern, sampleRate: 48_000)
        #expect(mix.contains { $0 != 0 })
        #expect(mix.last == 0)
        #expect(mix.allSatisfy { $0.isFinite })
        let peak = mix.max { abs($0) < abs($1) }.map { abs($0) } ?? 0
        #expect(peak <= 0.5 + 0.001)
        #expect(engine.tracks == before)
        #expect(kit.sounds[0].filename == "ac_studio-dry_kick")
        #expect(pattern.tracks[0].soundPreset.filename == kit.sounds[0].filename)
    }

    private func slug(_ name: String) -> String {
        let pairs = zip(AcousticKits.names, AcousticKits.slugs)
        return pairs.first { $0.0 == name }?.1 ?? ""
    }

    private func expectMic(
        _ kit: DrumKit?,
        _ close: Double,
        _ overhead: Double,
        _ room: Double,
        _ size: RoomSize,
        tone: Double? = nil
    ) {
        let mic = kit?.mic
        #expect(mic?.close == close)
        #expect(mic?.overhead == overhead)
        #expect(mic?.room == room)
        #expect(mic?.roomSize == size)
        if let tone { #expect(mic?.roomTone == tone) }
        #expect(kit?.sounds.first?.mic?.roomSize == size)
    }
}
