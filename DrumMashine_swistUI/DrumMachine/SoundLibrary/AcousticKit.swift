import Foundation

/// Finds sample files shipped in the app bundle.
nonisolated enum BundledSamples {
    private final class Token {}

    static func url(for fileName: String) -> URL? {
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        for bundle in [Bundle.main, Bundle(for: Token.self)] + Bundle.allBundles {
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "AcousticKit") { return url }
        }
        return nil
    }
}

/// Real acoustic drums from "Big Rusty Drums" by Karoryfer Samples (CC0 1.0).
/// See Resources/AcousticKit/AcousticKit_CREDITS.txt.
/// Buffers are rendered off the audio thread like every other preset.
nonisolated enum AcousticKit {
    struct Piece {
        var name: String
        var file: String
        var category: SoundPreset.SoundCategory
        var voice: SoundPreset.VoiceKind
        var volume: Float = 1
        var choke: Int? = nil
    }

    static let pieces: [Piece] = [
        Piece(name: "Real Kick", file: "acoustic_kick", category: .kick, voice: .kick),
        Piece(name: "Real Snare", file: "acoustic_snare", category: .snare, voice: .snare),
        Piece(name: "Real Snare Ghost", file: "acoustic_snare_ghost", category: .snare, voice: .snare, volume: 0.35),
        Piece(name: "Real Rimshot", file: "acoustic_rimshot", category: .snare, voice: .snare),
        Piece(name: "Real Sidestick", file: "acoustic_sidestick", category: .snare, voice: .snare, volume: 0.8),
        Piece(name: "Real Brush Snare", file: "acoustic_snare_brush", category: .snare, voice: .snare, volume: 0.7),
        Piece(name: "Real Hat Closed", file: "acoustic_hat_closed", category: .hihat, voice: .closedHat, volume: 0.8, choke: 1),
        Piece(name: "Real Hat Open", file: "acoustic_hat_open", category: .hihat, voice: .openHat, volume: 0.8, choke: 1),
        Piece(name: "Real Tom High", file: "acoustic_tom_high", category: .percussion, voice: .tom),
        Piece(name: "Real Tom Mid", file: "acoustic_tom_mid", category: .percussion, voice: .tom),
        Piece(name: "Real Tom Floor", file: "acoustic_tom_floor", category: .percussion, voice: .tom),
        Piece(name: "Real Ride", file: "acoustic_ride", category: .cymbals, voice: .ride, volume: 0.8),
        Piece(name: "Real Crash", file: "acoustic_crash", category: .cymbals, voice: .crash, volume: 0.8),
    ]

    static func presets() -> [SoundPreset] {
        pieces.map { piece in
            let filename = "real_\(piece.file)"
            var preset = SoundPreset(
                id: SoundLibraryManager.factoryID(filename: filename),
                name: piece.name,
                filename: filename,
                category: piece.category,
                origin: .factory
            )
            preset.voice = piece.voice
            preset.source = .bundled(fileName: "\(piece.file).wav")
            preset.style = .acoustic
            preset.volume = piece.volume
            preset.chokeGroup = piece.choke
            preset.attack = 0
            preset.decay = 0
            preset.sustain = 1
            preset.release = 0
            return preset
        }
    }
}

extension SoundLibraryManager {
    /// Library tab contents: one voice, optionally one style (nil = all styles).
    func presets(for voice: SoundPreset.VoiceKind, style: FactoryStyle?) -> [SoundPreset] {
        availableSounds.filter { $0.resolvedVoice == voice && (style == nil || $0.style == style) }
    }

    /// Sounds offered by a track's sound picker: its own voice family (both hats on the hat track).
    func presets(forTrackVoice voice: SoundPreset.VoiceKind) -> [SoundPreset] {
        let family: Set<SoundPreset.VoiceKind> = (voice == .closedHat || voice == .openHat)
            ? [.closedHat, .openHat] : [voice]
        return availableSounds.filter { family.contains($0.resolvedVoice) }
    }
}
