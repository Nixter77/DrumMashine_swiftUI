import Foundation

/// One factory rhythm. Grids, tempo, swing, and kit overrides live only in this file.
nonisolated struct FactoryPatternSpec: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var genre: String
    var bpm: Double
    var swing: Double
    /// `FactoryKits` id name, for example `kit.909`.
    var kitID: String
    /// Track index to a library filename. Replaces that pad of the kit.
    var trackOverrides: [Int: String]
    /// Track index to 16 symbols: `X` `x` `g` `-`. Missing tracks are empty.
    var rows: [Int: String]
}

/// Forty factory rhythms. `makePattern` copies the kit, then applies overrides.
enum FactoryPatterns {
    nonisolated static func all() -> [FactoryPatternSpec] { specs }

    @MainActor
    static func makePattern(_ spec: FactoryPatternSpec) -> DrumPattern {
        let library = SoundLibraryManager.shared.availableSounds
        let kit = FactoryKits.all().first {
            $0.id == SoundLibraryManager.factoryID(filename: spec.kitID)
        }
        let sounds: [SoundPreset] = (0..<8).map { index in
            if let filename = spec.trackOverrides[index],
               let preset = library.first(where: { $0.filename == filename }) {
                return preset
            }
            if let kit, kit.sounds.indices.contains(index) {
                return kit.sounds[index]
            }
            return SoundLibraryManager.shared.defaultPreset(forTrackIndex: index)
        }
        var tracks: [SequencerTrack] = sounds.map { sound in
            var track = SequencerTrack(soundPreset: sound, stepsCount: 16)
            track.volume = 1
            track.pan = 0
            for step in track.steps.indices {
                track.steps[step].probability = 1
            }
            return track
        }
        for (index, row) in spec.rows where tracks.indices.contains(index) {
            for (stepIndex, symbol) in row.enumerated() where tracks[index].steps.indices.contains(stepIndex) {
                let hit = hit(for: symbol)
                tracks[index].steps[stepIndex].isActive = hit.active
                tracks[index].steps[stepIndex].velocity = hit.velocity
                tracks[index].steps[stepIndex].probability = 1
            }
        }
        var pattern = DrumPattern(
            name: spec.name,
            tracks: tracks,
            bpm: spec.bpm,
            swing: spec.swing,
            stepCount: .sixteen
        )
        pattern.id = SoundLibraryManager.factoryID(filename: "pattern.\(spec.id)")
        return pattern
    }

    /// The audible 16-step grid matches this rhythm. Velocity counts only on hits.
    @MainActor
    static func matchesLoadedGrid(
        tracks: [SequencerTrack],
        stepCount: StepCount,
        spec: FactoryPatternSpec
    ) -> Bool {
        guard stepCount == .sixteen else { return false }
        let pattern = makePattern(spec)
        guard tracks.count >= 8 else { return false }
        for index in 0..<8 {
            let live = tracks[index].steps
            let wanted = pattern.tracks[index].steps
            for step in 0..<16 {
                let liveStep = live.indices.contains(step) ? live[step] : SequencerStep()
                guard wanted.indices.contains(step) else { return false }
                if liveStep.isActive != wanted[step].isActive { return false }
                if liveStep.isActive && liveStep.velocity != wanted[step].velocity { return false }
            }
        }
        return true
    }

    @MainActor
    static func kitName(for spec: FactoryPatternSpec) -> String {
        let id = SoundLibraryManager.factoryID(filename: spec.kitID)
        return FactoryKits.all().first { $0.id == id }?.name ?? spec.kitID
    }

    private nonisolated static func hit(for symbol: Character) -> (active: Bool, velocity: Float) {
        switch symbol {
        case "X": return (true, 1)
        case "x": return (true, 0.75)
        case "g": return (true, 0.4)
        default: return (false, 0)
        }
    }

    private nonisolated static let specs: [FactoryPatternSpec] = [
        spec("house_classic", "House Classic", "House", 124, 10, "kit.909", [7: "oh_909"], [
            0: "X---X---X---X---",
            2: "-g-g-g-g-g-g-g-g",
            3: "----X-------X---",
            7: "--x---x---x---x-"
        ]),
        spec("house_deep", "Deep House", "House", 122, 30, "kit.lofi", [7: "perc_shaker"], [
            0: "X---X---X---X---",
            2: "--x---x---x---x-",
            3: "----x-------x---",
            7: "-gxg-gxg-gxg-gxg"
        ]),
        spec("house_jackin", "Jackin' House", "House", 126, 20, "kit.909", [7: "oh_909"], [
            0: "X---X---X---X---",
            2: "-g-g-g-g-g-g-g-g",
            3: "----X--g----X---",
            7: "--x---x---x---x-"
        ]),
        spec("techno_drive", "Techno Drive", "Techno", 130, 0, "kit.909", [7: "oh_909"], [
            0: "X---X---X---X---",
            2: "xg-gxg-gxg-gxg-g",
            3: "----X-------X---",
            7: "--x---x---x---x-"
        ]),
        spec("techno_minimal", "Minimal Techno", "Techno", 126, 15, "kit.909", [:], [
            0: "X---X---X---X---",
            2: "--x---x---x---x-",
            3: "----x-------x---",
            7: "---x--x----x-x--"
        ]),
        spec("techno_industrial", "Industrial Techno", "Techno", 138, 0, "kit.909", [0: "kick_dist"], [
            0: "X---X---X---X-x-",
            2: "gxgxgxgxgxgxgxgx",
            3: "----X-------X---",
            5: "--x---x---x---x-"
        ]),
        spec("hiphop_boombap", "Boom Bap", "Hip-Hop", 90, 55, "kit.acoustic", [:], [
            0: "X-----x---X--x--",
            1: "----X--g----X---",
            2: "x-x-x-x-x-x-x-x-"
        ]),
        spec("hiphop_lazy", "Lazy Hip-Hop", "Hip-Hop", 85, 60, "kit.lofi", [:], [
            0: "X-------xx------",
            1: "----X-------X---",
            2: "x-xgx-xgx-xgx-xg",
            3: "------------x---"
        ]),
        spec("hiphop_808", "808 Hip-Hop", "Hip-Hop", 95, 20, "kit.808", [:], [
            0: "X--x---x--X-----",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-",
            7: "-------x--------"
        ]),
        spec("hiphop_westcoast", "West Coast", "Hip-Hop", 94, 25, "kit.808", [:], [
            0: "X------x-xX-----",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-",
            3: "----X-------X---"
        ]),
        spec("trap_basic", "Trap", "Trap", 140, 0, "kit.trap", [:], [
            0: "X-----x---x-----",
            1: "--------X-------",
            3: "--------X-------",
            2: "x-x-x-x-x-xgxgx-"
        ]),
        spec("trap_drill", "Drill", "Trap", 142, 0, "kit.trap", [:], [
            0: "X-----x--x----x-",
            1: "--------X------g",
            2: "x--x--x-x--x--x-"
        ]),
        spec("trap_bounce", "Trap Bounce", "Trap", 150, 0, "kit.trap", [:], [
            0: "X--x------x--x--",
            1: "--------X-------",
            2: "xgxgx-x-xgxgx-xx"
        ]),
        spec("dnb_twostep", "DnB Two-Step", "Drum & Bass", 174, 0, "kit.acoustic", [:], [
            0: "X---------X-----",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-"
        ]),
        spec("dnb_roller", "DnB Roller", "Drum & Bass", 172, 0, "kit.acoustic", [:], [
            0: "X-----x---x-----",
            1: "----X--g-g--X--g",
            2: "x-gxx-gxx-gxx-gx"
        ]),
        spec("dnb_jungle", "Jungle", "Drum & Bass", 168, 10, "kit.acoustic", [:], [
            0: "X---------x-x---",
            1: "----X--g-x--X--g",
            2: "x-x-x-x-x-x-x-x-"
        ]),
        spec("rock_basic", "Rock Beat", "Rock", 110, 0, "kit.acoustic", [:], [
            0: "X-------X-X-----",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-",
            6: "X---------------"
        ]),
        spec("rock_halftime", "Half-Time Rock", "Rock", 90, 0, "kit.acoustic", [:], [
            0: "X-------X--x----",
            1: "--------X-------",
            5: "x-x-x-x-x-x-x-x-",
            6: "X---------------"
        ]),
        spec("rock_punk", "Punk", "Rock", 170, 0, "kit.acoustic", [:], [
            0: "X---X-x-X---X-x-",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-",
            6: "X---------------"
        ]),
        spec("funk_basic", "Funk", "Funk", 100, 15, "kit.acoustic", [:], [
            0: "X-x-------X--x--",
            1: "----X--g-g--X-g-",
            2: "xgxgxgxgxgxgxgxg"
        ]),
        spec("funk_disco", "Disco", "Funk", 118, 0, "kit.acoustic", [7: "oh_acoustic"], [
            0: "X---X---X---X---",
            1: "----X-------X---",
            2: "x--gx--gx--gx--g",
            7: "--x---x---x---x-"
        ]),
        spec("funk_break", "Funky Break", "Funk", 96, 20, "kit.acoustic", [7: "oh_acoustic"], [
            0: "X-x---x---x--x--",
            1: "----X--g-g-gX--g",
            2: "x-x-x-x-x-x-x---",
            7: "-------------x--"
        ]),
        spec("reggaeton_dembow", "Dembow", "Reggaeton", 95, 0, "kit.808", [:], [
            0: "X---X---X---X---",
            1: "---x--x----x--x-",
            2: "g-g-g-g-g-g-g-g-"
        ]),
        spec("reggaeton_perreo", "Perreo", "Reggaeton", 98, 0, "kit.808", [7: "perc_rim_808"], [
            0: "X---X---X---X---",
            1: "---x--x----x--x-",
            3: "------X-------X-",
            7: "--g---g---g---g-"
        ]),
        spec("reggaeton_moombah", "Moombahton", "Reggaeton", 108, 0, "kit.808", [:], [
            0: "X---X---X---X---",
            1: "---x--x----x--x-",
            2: "--x---x---x---x-",
            7: "-------x-------x"
        ]),
        spec("lofi_chill", "Lo-Fi Chill", "Lo-Fi", 78, 60, "kit.lofi", [:], [
            0: "X-------x-x-----",
            1: "----X-------X---",
            2: "x-xgx-xgx-xgx-xg"
        ]),
        spec("lofi_jazzy", "Lo-Fi Jazzy", "Lo-Fi", 84, 65, "kit.lofi", [:], [
            0: "X------x--x-----",
            1: "----X-------X--g",
            2: "----g-------g---",
            5: "x---x--xx---x--x"
        ]),
        spec("lofi_dusty", "Dusty Lo-Fi", "Lo-Fi", 72, 55, "kit.lofi", [7: "perc_shaker"], [
            0: "X---------x-----",
            1: "----X-------X---",
            2: "g-x-g-x-g-x-g-x-",
            7: "-g-g-g-g-g-g-g-g"
        ]),
        spec("afro_basic", "Afrobeats", "Afrobeats", 104, 10, "kit.acoustic", [7: "perc_conga_808"], [
            0: "X--x----X--x----",
            2: "x-gxx-gxx-gxx-gx",
            3: "----X-------X---",
            7: "---x--x----x--x-"
        ]),
        spec("amapiano_log", "Amapiano", "Amapiano", 112, 25, "kit.808", [4: "tom_808_low", 7: "perc_shaker"], [
            0: "X-------X-------",
            3: "----X-------X---",
            4: "---x--x-x-----x-",
            7: "xgggxgggxgggxggg"
        ]),
        spec("dancehall_riddim", "Dancehall", "Dancehall", 100, 0, "kit.808", [:], [
            0: "X-----X-X-----X-",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-"
        ]),
        spec("reggae_onedrop", "One Drop", "Reggae", 76, 30, "kit.acoustic", [1: "snare_rimshot"], [
            0: "--------X-------",
            1: "--------X-------",
            2: "x-x-x-x-x-x-x-x-"
        ]),
        spec("bossa_nova", "Bossa Nova", "Bossa Nova", 130, 0, "kit.acoustic", [7: "perc_clave"], [
            0: "X--xX--xX--xX--x",
            2: "x-x-x-x-x-x-x-x-",
            7: "x--x--x---x--x--"
        ]),
        spec("ukg_2step", "UK Garage 2-Step", "UK Garage", 132, 35, "kit.909", [:], [
            0: "X-----x---x-----",
            2: "-gxg-gxg-gxg-gxg",
            3: "----X-------X---",
            7: "--x--x-----x--x-"
        ]),
        spec("breakbeat_bigbeat", "Big Beat", "Breakbeat", 112, 10, "kit.acoustic", [:], [
            0: "X-x-------xx----",
            1: "----X--g-g--X--g",
            2: "x-x-x-x-x-x-x-x-"
        ]),
        spec("electro_808", "Electro", "Electro", 128, 0, "kit.808", [:], [
            0: "X-----x---X---x-",
            2: "x-x-x-x-x-x-x-x-",
            3: "----X-------X---",
            7: "x--x--x---x--x--"
        ]),
        spec("dubstep_halfstep", "Dubstep", "Dubstep", 140, 0, "kit.909", [0: "kick_dist"], [
            0: "X---------x-----",
            1: "--------X-------",
            2: "x-g-x-g-x-g-x-g-",
            3: "--------X-------"
        ]),
        spec("synthwave", "Synthwave", "Synthwave", 100, 0, "kit.808", [:], [
            0: "X-------X-------",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-",
            3: "----X-------X---"
        ]),
        spec("jazz_swing", "Jazz Swing", "Jazz", 120, 70, "kit.acoustic", [:], [
            0: "g-----------g---",
            1: "------g----g----",
            2: "----g-------g---",
            5: "x---x--xx---x--x"
        ]),
        spec("blues_shuffle", "Blues Shuffle", "Blues", 96, 75, "kit.acoustic", [:], [
            0: "X-------X-------",
            1: "----X-------X---",
            2: "x-x-x-x-x-x-x-x-"
        ])
    ]

    private nonisolated static func spec(
        _ id: String,
        _ name: String,
        _ genre: String,
        _ bpm: Double,
        _ swing: Double,
        _ kitID: String,
        _ trackOverrides: [Int: String],
        _ rows: [Int: String]
    ) -> FactoryPatternSpec {
        FactoryPatternSpec(
            id: id,
            name: name,
            genre: genre,
            bpm: bpm,
            swing: swing,
            kitID: kitID,
            trackOverrides: trackOverrides,
            rows: rows
        )
    }
}
