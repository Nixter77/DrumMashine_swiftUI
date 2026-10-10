import CryptoKit
import Foundation

// MARK: - Sound Library Manager (10 presets per category, synthesized)
class SoundLibraryManager {
    static let shared = SoundLibraryManager()
    
    private(set) var availableSounds: [SoundPreset] = []
    
    // Categorized lookup for fast access
    private(set) var soundsByCategory: [SoundPreset.SoundCategory: [SoundPreset]] = [:]
    
    /// Internal so a test can build two libraries and compare factory ids.
    init() {
        buildLibrary()
    }
    
    // MARK: - Build Full Library (10 per category)
    private func buildLibrary() {
        var all: [SoundPreset] = []
        
        // ── KICK (10 variants) ──
        all += [
            make("Kick 808",    "kick_808",    .kick,       attack: 0.001, decay: 0.35, sustain: 0.0, release: 0.1, pitch: 0),
            make("Kick Deep",   "kick_deep",   .kick,       attack: 0.001, decay: 0.50, sustain: 0.0, release: 0.15, pitch: -3),
            make("Kick Tight",  "kick_tight",  .kick,       attack: 0.001, decay: 0.18, sustain: 0.0, release: 0.05, pitch: 2),
            make("Kick Punchy", "kick_punchy", .kick,       attack: 0.001, decay: 0.25, sustain: 0.0, release: 0.08, pitch: 1),
            make("Kick Sub",    "kick_sub",    .kick,       attack: 0.002, decay: 0.60, sustain: 0.0, release: 0.2,  pitch: -6),
            make("Kick Hard",   "kick_hard",   .kick,       attack: 0.001, decay: 0.20, sustain: 0.0, release: 0.06, pitch: 4),
            make("Kick Soft",   "kick_soft",   .kick,       attack: 0.003, decay: 0.40, sustain: 0.0, release: 0.12, pitch: -1),
            make("Kick Dry",    "kick_dry",    .kick,       attack: 0.001, decay: 0.15, sustain: 0.0, release: 0.04, pitch: 0),
            make("Kick Boom",   "kick_boom",   .kick,       attack: 0.001, decay: 0.70, sustain: 0.0, release: 0.25, pitch: -8),
            make("Kick Snap",   "kick_snap",   .kick,       attack: 0.001, decay: 0.12, sustain: 0.0, release: 0.03, pitch: 5),
        ]
        
        // ── SNARE (10 variants) ──
        all += [
            make("Snare 808",   "snare_808",   .snare,      attack: 0.001, decay: 0.18, sustain: 0.0, release: 0.08, pitch: 0),
            make("Snare Crack", "snare_crack", .snare,      attack: 0.001, decay: 0.12, sustain: 0.0, release: 0.05, pitch: 3),
            make("Snare Fat",   "snare_fat",   .snare,      attack: 0.002, decay: 0.25, sustain: 0.0, release: 0.10, pitch: -2),
            make("Snare Tight", "snare_tight", .snare,      attack: 0.001, decay: 0.10, sustain: 0.0, release: 0.04, pitch: 2),
            make("Snare Rim",   "snare_rim",   .snare,      attack: 0.001, decay: 0.08, sustain: 0.0, release: 0.03, pitch: 5),
            make("Snare Brush", "snare_brush", .snare,      attack: 0.005, decay: 0.30, sustain: 0.1, release: 0.15, pitch: -1),
            make("Snare Deep",  "snare_deep",  .snare,      attack: 0.001, decay: 0.22, sustain: 0.0, release: 0.09, pitch: -4),
            make("Snare Dry",   "snare_dry",   .snare,      attack: 0.001, decay: 0.14, sustain: 0.0, release: 0.05, pitch: 1),
            make("Snare Snap",  "snare_snap",  .snare,      attack: 0.001, decay: 0.09, sustain: 0.0, release: 0.03, pitch: 4),
            make("Snare Ghost", "snare_ghost", .snare,      attack: 0.002, decay: 0.20, sustain: 0.0, release: 0.08, pitch: 0),
        ]
        
        // ── HI-HAT (10 variants) ──
        all += [
            make("HH Closed",   "hh_closed",   .hihat,      attack: 0.001, decay: 0.05, sustain: 0.0, release: 0.02, pitch: 0),
            make("HH Open",     "hh_open",     .hihat,      attack: 0.001, decay: 0.35, sustain: 0.1, release: 0.15, pitch: 0),
            make("HH Pedal",    "hh_pedal",    .hihat,      attack: 0.001, decay: 0.08, sustain: 0.0, release: 0.03, pitch: -2),
            make("HH Tight",    "hh_tight",    .hihat,      attack: 0.001, decay: 0.04, sustain: 0.0, release: 0.01, pitch: 2),
            make("HH Loose",    "hh_loose",    .hihat,      attack: 0.001, decay: 0.12, sustain: 0.0, release: 0.05, pitch: -1),
            make("HH Crispy",   "hh_crispy",   .hihat,      attack: 0.001, decay: 0.06, sustain: 0.0, release: 0.02, pitch: 3),
            make("HH Dark",     "hh_dark",     .hihat,      attack: 0.001, decay: 0.09, sustain: 0.0, release: 0.04, pitch: -3),
            make("HH Bright",   "hh_bright",   .hihat,      attack: 0.001, decay: 0.07, sustain: 0.0, release: 0.02, pitch: 4),
            make("HH Vintage",  "hh_vintage",  .hihat,      attack: 0.002, decay: 0.10, sustain: 0.0, release: 0.04, pitch: -1),
            make("HH Electronic","hh_elec",    .hihat,      attack: 0.001, decay: 0.06, sustain: 0.0, release: 0.02, pitch: 5),
        ]
        
        // ── PERCUSSION (10 variants) ──
        all += [
            make("Clap 808",    "clap_808",    .percussion, attack: 0.001, decay: 0.12, sustain: 0.0, release: 0.05, pitch: 0),
            make("Clap Tight",  "clap_tight",  .percussion, attack: 0.001, decay: 0.08, sustain: 0.0, release: 0.03, pitch: 2),
            make("Clap Fat",    "clap_fat",    .percussion, attack: 0.002, decay: 0.18, sustain: 0.0, release: 0.07, pitch: -1),
            make("Tom Low",     "tom_low",     .percussion, attack: 0.002, decay: 0.30, sustain: 0.0, release: 0.10, pitch: -5),
            make("Tom Mid",     "tom_mid",     .percussion, attack: 0.002, decay: 0.25, sustain: 0.0, release: 0.08, pitch: -2),
            make("Tom High",    "tom_high",    .percussion, attack: 0.001, decay: 0.20, sustain: 0.0, release: 0.07, pitch: 2),
            make("Conga",       "conga",       .percussion, attack: 0.001, decay: 0.22, sustain: 0.0, release: 0.08, pitch: 3),
            make("Bongo",       "bongo",       .percussion, attack: 0.001, decay: 0.15, sustain: 0.0, release: 0.05, pitch: 5),
            make("Cowbell",     "cowbell",     .percussion, attack: 0.001, decay: 0.40, sustain: 0.1, release: 0.15, pitch: 0),
            make("Shaker",      "shaker",      .percussion, attack: 0.003, decay: 0.10, sustain: 0.0, release: 0.04, pitch: 0),
        ]
        
        // ── CYMBALS (10 variants) ──
        all += [
            make("Ride Bell",   "ride_bell",   .cymbals,    attack: 0.001, decay: 0.50, sustain: 0.2, release: 0.20, pitch: 0),
            make("Ride Edge",   "ride_edge",   .cymbals,    attack: 0.001, decay: 0.70, sustain: 0.3, release: 0.30, pitch: -1),
            make("Crash 14\"",  "crash_14",    .cymbals,    attack: 0.001, decay: 0.80, sustain: 0.4, release: 0.40, pitch: 0),
            make("Crash 16\"",  "crash_16",    .cymbals,    attack: 0.001, decay: 1.00, sustain: 0.5, release: 0.50, pitch: -2),
            make("Crash Thin",  "crash_thin",  .cymbals,    attack: 0.001, decay: 0.60, sustain: 0.3, release: 0.25, pitch: 2),
            make("Splash",      "splash",      .cymbals,    attack: 0.001, decay: 0.25, sustain: 0.1, release: 0.10, pitch: 3),
            make("China",       "china",       .cymbals,    attack: 0.001, decay: 0.90, sustain: 0.4, release: 0.35, pitch: -3),
            make("Stack",       "stack",       .cymbals,    attack: 0.001, decay: 0.15, sustain: 0.0, release: 0.06, pitch: 1),
            make("Ride Jazz",   "ride_jazz",   .cymbals,    attack: 0.002, decay: 0.60, sustain: 0.3, release: 0.25, pitch: -1),
            make("Crash Dark",  "crash_dark",  .cymbals,    attack: 0.001, decay: 1.20, sustain: 0.6, release: 0.60, pitch: -4),
        ]
        
        // ── FX (10 variants) ──
        all += [
            make("Noise Burst", "fx_noise",    .fx,         attack: 0.001, decay: 0.08, sustain: 0.0, release: 0.03, pitch: 0),
            make("Zap",         "fx_zap",      .fx,         attack: 0.001, decay: 0.12, sustain: 0.0, release: 0.05, pitch: 5),
            make("Blip",        "fx_blip",     .fx,         attack: 0.001, decay: 0.06, sustain: 0.0, release: 0.02, pitch: 8),
            make("Laser",       "fx_laser",    .fx,         attack: 0.001, decay: 0.15, sustain: 0.0, release: 0.06, pitch: 10),
            make("Glitch",      "fx_glitch",   .fx,         attack: 0.001, decay: 0.10, sustain: 0.0, release: 0.04, pitch: 0),
            make("Sweep Up",    "fx_sweep_up", .fx,         attack: 0.010, decay: 0.20, sustain: 0.0, release: 0.08, pitch: 0),
            make("Sweep Dn",    "fx_sweep_dn", .fx,         attack: 0.001, decay: 0.20, sustain: 0.0, release: 0.08, pitch: 0),
            make("Vinyl Crk",   "fx_vinyl",    .fx,         attack: 0.001, decay: 0.30, sustain: 0.1, release: 0.10, pitch: 0),
            make("Reverse",     "fx_reverse",  .fx,         attack: 0.050, decay: 0.15, sustain: 0.0, release: 0.05, pitch: 0),
            make("Impact",      "fx_impact",   .fx,         attack: 0.001, decay: 0.25, sustain: 0.0, release: 0.10, pitch: -5),
        ]
        all += FactoryPresets.additional()
        
        availableSounds = all
        
        // Build category map
        for cat in SoundPreset.SoundCategory.allCases {
            soundsByCategory[cat] = all.filter { $0.category == cat }
        }
    }
    
    // MARK: - Factory Helper
    private func make(
        _ name: String,
        _ filename: String,
        _ category: SoundPreset.SoundCategory,
        attack: Float,
        decay: Float,
        sustain: Float,
        release: Float,
        pitch: Float
    ) -> SoundPreset {
        var p = SoundPreset(
            id: Self.factoryID(filename: filename),
            name: name,
            filename: filename,
            category: category,
            origin: .factory
        )
        p.attack = attack
        p.decay = decay
        p.sustain = sustain
        p.release = release
        p.pitch = pitch
        p.voice = SoundPreset.inferredVoice(category: category, filename: filename, decay: decay)
        p.style = .legacy
        return p
    }
    
    // MARK: - Sounds for a specific category
    func sounds(for category: SoundPreset.SoundCategory) -> [SoundPreset] {
        soundsByCategory[category] ?? []
    }
    
    // MARK: - Default preset for a track index (0 kick … 7 perc)
    func defaultPreset(forTrackIndex index: Int) -> SoundPreset {
        let voices: [SoundPreset.VoiceKind] = [
            .kick, .snare, .closedHat, .clap, .tom, .ride, .crash, .perc
        ]
        let voice = voices[min(max(index, 0), voices.count - 1)]
        return availableSounds.first { $0.voice == voice } ?? availableSounds[0]
    }

    /// Same filename, same id. Version 5 and the RFC 4122 variant mark a name-based UUID; the hash is SHA-256.
    nonisolated static func factoryID(filename: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("factory.\(filename)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
