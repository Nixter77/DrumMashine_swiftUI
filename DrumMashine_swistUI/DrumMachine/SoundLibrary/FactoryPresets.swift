import Foundation

/// The 51 presets added in D-2. Filenames are the stable factory ids.
/// Numbers are starting points; the ear check is still for nixter.
nonisolated enum FactoryPresets {
    static func additional() -> [SoundPreset] {
        kicks + snares + closedHats + openHats + claps + toms + rides + crashes + percs
    }

    private static var kicks: [SoundPreset] {
        [
            make("Kick 909", "kick_909", .kick, .kick, .style909, decay: 0.30, synth: SynthParams(kick: .init(startHz: 230, endHz: 52, sweep: 0.035, click: 0.9, drive: 2.2))),
            make("Kick 808 Long", "kick_808_long", .kick, .kick, .classic808, decay: 0.90, synth: SynthParams(kick: .init(startHz: 120, endHz: 45, sweep: 0.06, click: 0.15, drive: 1.2))),
            make("Kick Acoustic", "kick_acoustic", .kick, .kick, .acoustic, decay: 0.22, synth: SynthParams(kick: .init(startHz: 110, endHz: 62, sweep: 0.025, click: 0.7, drive: 1.1, noise: 0.25))),
            make("Kick Lo-Fi", "kick_lofi", .kick, .kick, .lofi, decay: 0.35, synth: SynthParams(kick: .init(startHz: 150, endHz: 50, sweep: 0.08, click: 0.5, drive: 1.5), lofi: .init(bitDepth: 8, downsample: 3))),
            make("Kick Distorted", "kick_dist", .kick, .kick, .classic808, decay: 0.40, synth: SynthParams(kick: .init(startHz: 180, endHz: 50, sweep: 0.05, drive: 4.0))),
            make("Kick Trap Sub", "kick_trap_sub", .kick, .kick, .trap, decay: 1.20, pitch: -2, synth: SynthParams(kick: .init(startHz: 90, endHz: 38, sweep: 0.12, click: 0.1, drive: 1.3))),
        ]
    }

    private static var snares: [SoundPreset] {
        [
            make("Snare 909", "snare_909", .snare, .snare, .style909, decay: 0.20, synth: snare(190, 340, body: 0.07, hp: 1800, noise: 1.0)),
            make("Snare 808 Snappy", "snare_808_snappy", .snare, .snare, .classic808, decay: 0.15, synth: snare(238, 476, body: 0.12, hp: 2500, noise: 0.9)),
            make("Snare Acoustic", "snare_acoustic", .snare, .snare, .acoustic, decay: 0.30, synth: snare(200, 290, body: 0.09, hp: 600, noise: 0.7)),
            make("Snare Lo-Fi", "snare_lofi", .snare, .snare, .lofi, decay: 0.32, synth: snare(140, 220, body: 0.22, hp: 500, noise: 0.45, lofi: .init(bitDepth: 8, downsample: 4))),
            make("Snare Rimshot", "snare_rimshot", .snare, .snare, .classic808, decay: 0.06, synth: snare(400, 1700, body: 0.02, hp: 3000, noise: 0.25)),
            make("Snare Trap", "snare_trap", .snare, .snare, .trap, decay: 0.12, pitch: 2, synth: snare(210, 420, body: 0.05, hp: 3500, noise: 1.0)),
        ]
    }

    private static var closedHats: [SoundPreset] {
        [
            make("CH 808", "ch_808", .hihat, .closedHat, .classic808, decay: 0.04, choke: 1, synth: hat(hp: 7000, band: 9000, q: 0.7, open: false)),
            make("CH 909", "ch_909", .hihat, .closedHat, .style909, decay: 0.035, choke: 1, synth: hat(hp: 9000, band: 11000, q: 1.2, open: false, noise: 0.4)),
            make("CH Acoustic", "ch_acoustic", .hihat, .closedHat, .acoustic, decay: 0.09, choke: 1, synth: hat(hp: 2800, band: 4200, q: 0.35, open: false, noise: 0.85)),
            make("CH Lo-Fi", "ch_lofi", .hihat, .closedHat, .lofi, decay: 0.05, choke: 1, synth: hat(hp: 7000, band: 9000, q: 0.7, open: false, lofi: .init(bitDepth: 8, downsample: 3))),
            make("CH Trap Tick", "ch_trap_tick", .hihat, .closedHat, .trap, decay: 0.02, choke: 1, synth: hat(hp: 10000, band: 12000, q: 1.0, open: false)),
        ]
    }

    private static var openHats: [SoundPreset] {
        [
            make("OH 808", "oh_808", .hihat, .openHat, .classic808, decay: 0.45, choke: 1, synth: hat(hp: 7000, band: 9000, q: 0.7, open: true)),
            make("OH 909", "oh_909", .hihat, .openHat, .style909, decay: 0.50, choke: 1, synth: hat(hp: 9000, band: 11000, q: 1.2, open: true, noise: 0.4)),
            make("OH Acoustic", "oh_acoustic", .hihat, .openHat, .acoustic, decay: 0.55, choke: 1, synth: hat(hp: 2800, band: 4200, q: 0.35, open: true, noise: 0.85)),
            make("OH Lo-Fi", "oh_lofi", .hihat, .openHat, .lofi, decay: 0.40, choke: 1, synth: hat(hp: 7000, band: 9000, q: 0.7, open: true, lofi: .init(bitDepth: 8))),
            make("OH Half", "oh_half", .hihat, .openHat, .classic808, decay: 0.22, choke: 1, synth: hat(hp: 8000, band: 10000, q: 0.8, open: true)),
        ]
    }

    private static var claps: [SoundPreset] {
        [
            make("Clap 909", "clap_909", .percussion, .clap, .style909, decay: 0.20, synth: clap(bursts: 4, spacing: 0.010, hp: 900, lp: 3000, tail: 0.5)),
            make("Clap 808 Wide", "clap_808_wide", .percussion, .clap, .classic808, decay: 0.35, synth: clap(bursts: 3, spacing: 0.015, hp: 700, lp: 2200, tail: 0.6)),
            make("Clap Real Hands", "clap_real", .percussion, .clap, .acoustic, decay: 0.12, synth: clap(bursts: 2, spacing: 0.008, hp: 1000, lp: 4000, tail: 0.2)),
            make("Clap Lo-Fi", "clap_lofi", .percussion, .clap, .lofi, decay: 0.25, synth: clap(bursts: 3, spacing: 0.015, hp: 700, lp: 2200, tail: 0.6, lofi: .init(bitDepth: 8, downsample: 2))),
            make("Finger Snap", "clap_snap", .percussion, .clap, .acoustic, decay: 0.05, synth: clap(bursts: 1, spacing: 0.012, hp: 2000, lp: 6000, tail: 0.1)),
        ]
    }

    private static var toms: [SoundPreset] {
        [
            make("Tom 808 Low", "tom_808_low", .percussion, .tom, .classic808, decay: 0.50, synth: tom(120, 70, sweep: 0.06)),
            make("Tom 808 Mid", "tom_808_mid", .percussion, .tom, .classic808, decay: 0.40, synth: tom(180, 105, sweep: 0.06)),
            make("Tom 808 High", "tom_808_high", .percussion, .tom, .classic808, decay: 0.35, synth: tom(260, 150, sweep: 0.06)),
            make("Tom 909", "tom_909", .percussion, .tom, .style909, decay: 0.30, synth: tom(260, 120, sweep: 0.03, stick: 0.3)),
            make("Tom Acoustic Floor", "tom_acoustic_floor", .percussion, .tom, .acoustic, decay: 0.60, synth: tom(110, 82, sweep: 0.02, stick: 0.15)),
            make("Tom Lo-Fi", "tom_lofi", .percussion, .tom, .lofi, decay: 0.55, synth: tom(140, 80, sweep: 0.09, stick: 0.4, lofi: .init(bitDepth: 8, downsample: 4))),
        ]
    }

    /// Ride sizzle and crash decay are shorter than the first table so the buffer stays within 4 s.
    private static var rides: [SoundPreset] {
        [
            make("Ride 909", "ride_909", .cymbals, .ride, .style909, decay: 1.5, synth: ride(ping: 4200, mod: 650, pingLevel: 0.5, sizzle: 0.5, tau: 0.55)),
            make("Ride 808", "ride_808", .cymbals, .ride, .classic808, decay: 1.0, synth: ride(ping: 3500, mod: 540, pingLevel: 0.6, sizzle: 0.3, tau: 0.42)),
            make("Ride Acoustic Dry", "ride_acoustic_dry", .cymbals, .ride, .acoustic, decay: 1.2, synth: ride(ping: 5200, pingLevel: 0.7, sizzle: 0.3, tau: 0.50)),
            make("Ride Bell Bright", "ride_bell_bright", .cymbals, .ride, .classic808, decay: 1.0, synth: ride(ping: 6500, pingLevel: 0.9, sizzle: 0.2, tau: 0.36)),
            make("Ride Lo-Fi", "ride_lofi", .cymbals, .ride, .lofi, decay: 0.7, synth: ride(ping: 2800, mod: 400, pingLevel: 0.35, sizzle: 0.65, tau: 0.28, lofi: .init(bitDepth: 8, downsample: 4))),
        ]
    }

    private static var crashes: [SoundPreset] {
        [
            make("Crash 909", "crash_909", .cymbals, .crash, .style909, decay: 1.05, synth: crash(340, mod: 470, index: 6, mix: 0.25, hp: 3000)),
            make("Crash 808", "crash_808", .cymbals, .crash, .classic808, decay: 1.0, synth: crash(300, mod: 412, index: 4, mix: 0.4, hp: 2500)),
            make("Crash Acoustic 18\"", "crash_acoustic_18", .cymbals, .crash, .acoustic, decay: 1.14, synth: crash(260, mod: 388, index: 7, mix: 0.3, hp: 1500)),
            make("Crash Short", "crash_short", .cymbals, .crash, .style909, decay: 0.4, synth: crash(340, mod: 470, index: 6, mix: 0.25, hp: 3000)),
            make("Crash Lo-Fi", "crash_lofi", .cymbals, .crash, .lofi, decay: 0.55, synth: crash(180, mod: 260, index: 9, mix: 0.6, hp: 900, lofi: .init(bitDepth: 8, downsample: 4))),
        ]
    }

    private static var percs: [SoundPreset] {
        [
            make("Cowbell 808", "perc_cowbell_808", .percussion, .perc, .classic808, decay: 0.35, synth: SynthParams(perc: .init(mode: .cowbell, carrierHz: 540, secondHz: 800, bandHz: 2640, bandQ: 1.5))),
            make("Rimshot 808", "perc_rim_808", .percussion, .perc, .classic808, decay: 0.05, synth: SynthParams(perc: .init(mode: .fm, carrierHz: 1700, ratio: 1.0, index: 1))),
            make("Clave", "perc_clave", .percussion, .perc, .acoustic, decay: 0.06, synth: SynthParams(perc: .init(mode: .fm, carrierHz: 2500, ratio: 1.0, index: 0.5))),
            make("Woodblock", "perc_woodblock", .percussion, .perc, .acoustic, decay: 0.08, synth: SynthParams(perc: .init(mode: .fm, carrierHz: 1000, ratio: 1.43, index: 3))),
            make("Conga High 808", "perc_conga_808", .percussion, .perc, .classic808, decay: 0.20, synth: SynthParams(perc: .init(mode: .fm, carrierHz: 370, ratio: 1.0, index: 0.8, indexDecay: 40))),
            make("Shaker Real", "perc_shaker", .percussion, .perc, .acoustic, decay: 0.08, attack: 0.01, synth: SynthParams(perc: .init(mode: .noise, bandHz: 6000, bandQ: 1.5))),
            make("Tambourine", "perc_tambourine", .percussion, .perc, .acoustic, decay: 0.18, synth: SynthParams(perc: .init(mode: .noise, bandHz: 7500, bandQ: 2.0, bursts: 2, spacing: 0.015))),
            make("Triangle", "perc_triangle", .percussion, .perc, .acoustic, decay: 1.0, synth: SynthParams(perc: .init(mode: .fm, carrierHz: 4200, ratio: 2.7, index: 0.2))),
        ]
    }

    private static func snare(
        _ tone1: Double,
        _ tone2: Double,
        body: Double,
        hp: Double,
        noise: Double,
        lofi: SynthParams.LoFi? = nil
    ) -> SynthParams {
        SynthParams(
            snare: .init(tone1Hz: tone1, tone2Hz: tone2, bodyTau: body, noiseHPHz: hp, noiseLevel: noise),
            lofi: lofi
        )
    }

    private static func hat(
        hp: Double,
        band: Double,
        q: Double,
        open: Bool,
        noise: Double? = nil,
        lofi: SynthParams.LoFi? = nil
    ) -> SynthParams {
        SynthParams(hat: .init(open: open, hpHz: hp, bandHz: band, bandQ: q, noiseMix: noise), lofi: lofi)
    }

    private static func clap(
        bursts: Int,
        spacing: Double,
        hp: Double,
        lp: Double,
        tail: Double,
        lofi: SynthParams.LoFi? = nil
    ) -> SynthParams {
        SynthParams(clap: .init(bursts: bursts, spacing: spacing, hpHz: hp, lpHz: lp, tailLevel: tail), lofi: lofi)
    }

    private static func tom(
        _ start: Double,
        _ end: Double,
        sweep: Double,
        stick: Double? = nil,
        lofi: SynthParams.LoFi? = nil
    ) -> SynthParams {
        SynthParams(tom: .init(startHz: start, endHz: end, sweep: sweep, stickNoise: stick), lofi: lofi)
    }

    private static func ride(
        ping: Double,
        mod: Double? = nil,
        pingLevel: Double,
        sizzle: Double,
        tau: Double,
        lofi: SynthParams.LoFi? = nil
    ) -> SynthParams {
        SynthParams(
            ride: .init(pingHz: ping, pingModHz: mod, pingLevel: pingLevel, sizzleLevel: sizzle, sizzleTau: tau),
            lofi: lofi
        )
    }

    private static func crash(
        _ carrier: Double,
        mod: Double,
        index: Double,
        mix: Double,
        hp: Double,
        lofi: SynthParams.LoFi? = nil
    ) -> SynthParams {
        SynthParams(
            crash: .init(carrierHz: carrier, modHz: mod, index: index, fmMix: mix, hpHz: hp),
            lofi: lofi
        )
    }

    private static func make(
        _ name: String,
        _ filename: String,
        _ category: SoundPreset.SoundCategory,
        _ voice: SoundPreset.VoiceKind,
        _ style: FactoryStyle,
        decay: Float,
        pitch: Float = 0,
        attack: Float = 0.001,
        choke: Int? = nil,
        synth: SynthParams
    ) -> SoundPreset {
        var preset = SoundPreset(
            id: SoundLibraryManager.factoryID(filename: filename),
            name: name,
            filename: filename,
            category: category,
            origin: .factory
        )
        preset.attack = attack
        preset.decay = decay
        preset.sustain = 0
        preset.release = decay * 0.3
        preset.pitch = pitch
        preset.chokeGroup = choke
        preset.voice = voice
        preset.synth = synth
        preset.style = style
        return preset
    }
}
