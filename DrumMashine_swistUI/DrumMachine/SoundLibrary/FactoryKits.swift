import Foundation

/// Five factory kits. Each pad stores a copy of a factory preset, looked up by filename.
enum FactoryKits {
    @MainActor
    static func all() -> [DrumKit] {
        [
            kit("808", "kit.808", [
                "kick_808_long", "snare_808_snappy", "ch_808", "clap_808_wide",
                "tom_808_mid", "ride_808", "crash_808", "perc_cowbell_808"
            ]),
            kit("909", "kit.909", [
                "kick_909", "snare_909", "ch_909", "clap_909",
                "tom_909", "ride_909", "crash_909", "perc_rim_808"
            ]),
            kit("Acoustic", "kit.acoustic", [
                "kick_acoustic", "snare_acoustic", "ch_acoustic", "clap_real",
                "tom_acoustic_floor", "ride_acoustic_dry", "crash_acoustic_18", "perc_tambourine"
            ]),
            kit("Lo-Fi", "kit.lofi", [
                "kick_lofi", "snare_lofi", "ch_lofi", "clap_lofi",
                "tom_lofi", "ride_lofi", "crash_lofi", "perc_woodblock"
            ]),
            kit("Trap", "kit.trap", [
                "kick_trap_sub", "snare_trap", "ch_trap_tick", "clap_909",
                "tom_808_low", "ride_bell_bright", "crash_short", "perc_shaker"
            ])
        ]
    }

    @MainActor
    private static func kit(_ name: String, _ idName: String, _ filenames: [String]) -> DrumKit {
        let library = SoundLibraryManager.shared.availableSounds
        let sounds = filenames.map { filename in
            library.first { $0.filename == filename } ?? SoundPreset(
                id: UUID(),
                name: filename,
                filename: filename,
                category: .percussion
            )
        }
        return DrumKit(
            id: SoundLibraryManager.factoryID(filename: idName),
            name: name,
            sounds: sounds
        )
    }
}
