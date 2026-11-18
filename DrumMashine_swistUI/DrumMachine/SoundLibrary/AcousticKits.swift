import Foundation

/// Twelve synthesized acoustic kits. Filenames `ac_<slug>_<voice>` are stable.
/// The original five `FactoryKits` are not modified.
nonisolated enum AcousticKits {
    static let names = [
        "Studio Dry", "Jazz Club 60s", "Brushes Ballad", "Funk Tight 70s",
        "Rock Big Room", "Vintage 60s Soul", "Vintage 70s Dead", "Fusion Bright",
        "Hip-Hop Breaks", "Latin Percussion", "Cajon Unplugged", "Orchestral"
    ]

    static let slugs = [
        "studio-dry", "jazz-club-60s", "brushes-ballad", "funk-tight-70s",
        "rock-big-room", "vintage-60s-soul", "vintage-70s-dead", "fusion-bright",
        "hiphop-breaks", "latin-percussion", "cajon-unplugged", "orchestral"
    ]

    static func presets() -> [SoundPreset] {
        kits().flatMap(\.sounds)
    }

    static func kits() -> [DrumKit] {
        definitions.map { definition in
            let sounds = definition.slots.map { slot in
                make(definition, slot)
            }
            return DrumKit(
                id: SoundLibraryManager.factoryID(filename: "kit.ac.\(definition.slug)"),
                name: definition.name,
                sounds: sounds,
                mic: definition.mic,
                dynamicsDefault: definition.dynamics,
                character: definition.character,
                accentAmount: definition.accent
            )
        }
    }

    static func kitID(slug: String) -> String { "kit.ac.\(slug)" }

    // MARK: - Definitions

    private nonisolated struct Slot {
        var suffix: String
        var title: String
        var voice: SoundPreset.VoiceKind
        var category: SoundPreset.SoundCategory
        var style: FactoryStyle
        var volume: Float
        var decay: Float
        var pitch: Float = 0
        var choke: Int? = nil
        var dynamics: Dynamics
        var articulations: [ArticulationSpec]
        var synth: SynthParams
    }

    private nonisolated struct Definition {
        var name: String
        var slug: String
        var character: String
        var accent: Double
        var mic: MicMix
        var dynamics: Dynamics
        var scale: Float
        var lofi: Double?
        var slots: [Slot]
    }

    private static let definitions: [Definition] = [
        studio(), jazz(), brushes(), funk(), rock(), soul(), dead(), fusion(),
        hiphop(), latin(), cajon(), orchestral()
    ]

    private static func studio() -> Definition {
        definition(
            "Studio Dry", "studio-dry",
            "Современный поп и рок: сухо и близко.",
            accent: 0.2,
            mic: mic(1.0, 0.3, 0.1, .small, tone: 0.4),
            kick: kick(55, damp: 0.6, beater: 0.25, decay: 0.28, pitch: 0.6, bright: 0.5),
            snare: snare(200, wires: 0.7, decay: 0.2, bright: 0.55),
            hat: hat(decay: 0.06, scale: 1.05, bright: 0.62),
            clap: clap(decay: 0.16, group: true),
            tom: tom(high: 196, mid: 140, floor: 90, decay: 0.32, damp: 0.45),
            ride: ride(decay: 0.55, scale: 1.0, rivets: 0.05, bright: 0.4),
            crash: crash(decay: 0.5, recipe: .crash, bright: 0.5),
            perc: perc(title: "Tambourine", recipe: .tambourine, f0: 2400, decay: 0.18, volume: 0.3)
        )
    }

    private static func jazz() -> Definition {
        definition(
            "Jazz Club 60s", "jazz-club-60s",
            "Малый кик, открытые томы, мягкая комната.",
            accent: 0.15,
            mic: mic(0.7, 0.6, 0.3, .medium, tone: 0.2),
            kick: kick(70, damp: 0.1, beater: 0.2, decay: 0.48, pitch: 0.8, bright: 0.35),
            snare: snare(240, wires: 0.5, decay: 0.24, bright: 0.4),
            hat: hat(decay: 0.07, scale: 0.82, bright: 0.28),
            clap: snapSlot(title: "Finger Snap", decay: 0.07, pitch: 3),
            tom: tom(high: 240, mid: 180, floor: 130, decay: 0.46, damp: 0.15),
            ride: ride(decay: 0.7, scale: 0.95, rivets: 0.85, bright: 0.35),
            crash: crash(decay: 0.42, recipe: .crash, bright: 0.3),
            perc: perc(title: "Shaker", recipe: .shaker, f0: 6000, decay: 0.12, volume: 0.3)
        )
    }

    private static func brushes() -> Definition {
        definition(
            "Brushes Ballad", "brushes-ballad",
            "Щётки, тихий клик, средний зал.",
            accent: 0.12,
            mic: mic(0.6, 0.6, 0.4, .medium, tone: 0.15),
            scale: 0.7,
            kick: kick(58, damp: 0.45, beater: 0.08, decay: 0.34, pitch: 0.3, bright: 0.22),
            snare: brushesSnare(f0: 190),
            hat: hat(decay: 0.045, scale: 0.75, bright: 0.2, pedalLead: true),
            clap: snapSlot(title: "Brush Snap", decay: 0.18, pitch: -5),
            tom: malletToms(),
            ride: brushRide(),
            crash: crash(decay: 0.28, recipe: .splash, bright: 0.25, volume: 0.4),
            perc: perc(title: "Shaker Egg", recipe: .shaker, f0: 4200, decay: 0.1, volume: 0.28)
        )
    }

    private static func funk() -> Definition {
        definition(
            "Funk Tight 70s", "funk-tight-70s",
            "Сухой фанк: мёртвый кик и хлёсткий малый.",
            accent: 0.28,
            mic: mic(1.0, 0.2, 0.05, .small, tone: 0.35),
            kick: kick(52, damp: 0.9, beater: 0.72, decay: 0.14, pitch: 0.35, bright: 0.48, port: true),
            snare: snare(260, wires: 0.9, decay: 0.12, bright: 0.7),
            hat: hat(decay: 0.05, scale: 0.92, bright: 0.55),
            clap: clap(decay: 0.1, group: false),
            tom: tom(high: 220, mid: 160, floor: 110, decay: 0.16, damp: 0.8),
            ride: ride(decay: 0.4, scale: 1.1, rivets: 0.1, bright: 0.6),
            crash: crash(decay: 0.32, recipe: .crash, bright: 0.55),
            perc: perc(title: "Cowbell", recipe: .cowbell, f0: 587, decay: 0.22, volume: 0.55)
        )
    }

    private static func rock() -> Definition {
        definition(
            "Rock Big Room", "rock-big-room",
            "Большая комната, громкий рок.",
            accent: 0.32,
            mic: mic(0.8, 0.6, 0.9, .large, tone: 0.45),
            kick: kick(48, damp: 0.28, beater: 0.95, decay: 0.42, pitch: 1.3, bright: 0.72, port: false),
            snare: snare(180, wires: 1.0, decay: 0.22, bright: 0.68),
            hat: hat(decay: 0.075, scale: 0.7, bright: 0.4),
            clap: clap(decay: 0.2, group: true),
            tom: tom(high: 150, mid: 100, floor: 70, decay: 0.5, damp: 0.2),
            ride: ride(decay: 0.8, scale: 0.85, rivets: 0.15, bright: 0.55),
            crash: crash(decay: 0.48, recipe: .crash, bright: 0.6, pitch: 2, scale: 1.25),
            perc: perc(title: "Tambourine Hit", recipe: .tambourine, f0: 2800, decay: 0.16, volume: 0.34)
        )
    }

    private static func soul() -> Definition {
        definition(
            "Vintage 60s Soul", "vintage-60s-soul",
            "Бумажный малый, мало низа, тёплая комната.",
            accent: 0.18,
            mic: mic(0.6, 0.7, 0.4, .medium, tone: -0.5),
            kick: kick(62, damp: 0.55, beater: 0.3, decay: 0.22, pitch: 0.4, bright: 0.32),
            snare: snare(210, wires: 0.85, decay: 0.18, bright: 0.3),
            hat: hat(decay: 0.12, scale: 0.55, bright: 0.15),
            clap: clap(decay: 0.18, group: true),
            tom: tom(high: 210, mid: 150, floor: 96, decay: 0.58, damp: 0.2),
            ride: ride(decay: 0.6, scale: 0.8, rivets: 0.2, bright: 0.25),
            crash: crash(decay: 0.62, recipe: .crash, bright: 0.28, pitch: -2, scale: 0.8),
            perc: perc(title: "Tambourine Shake", recipe: .tambourine, f0: 2200, decay: 0.28, volume: 0.32)
        )
    }

    private static func dead() -> Definition {
        definition(
            "Vintage 70s Dead", "vintage-70s-dead",
            "Полотенца: очень сухо, почти без комнаты.",
            accent: 0.16,
            mic: mic(1.0, 0.1, 0.0, .small, tone: -0.2),
            kick: kick(50, damp: 1.0, beater: 0.4, decay: 0.12, pitch: 0.25, bright: 0.2, port: true),
            snare: snare(190, wires: 0.35, decay: 0.1, bright: 0.22),
            hat: hat(decay: 0.09, scale: 0.58, bright: 0.12),
            clap: snapSlot(title: "Dead Snap", decay: 0.05, pitch: -2),
            tom: tom(high: 160, mid: 118, floor: 86, decay: 0.14, damp: 0.8),
            ride: ride(decay: 0.3, scale: 0.9, rivets: 0, bright: 0.2),
            crash: crash(decay: 0.3, recipe: .crash, bright: 0.22),
            perc: perc(title: "Dry Shaker", recipe: .shaker, f0: 5000, decay: 0.08, volume: 0.28)
        )
    }

    private static func fusion() -> Definition {
        definition(
            "Fusion Bright", "fusion-bright",
            "Яркий строй, быстрые сбивки.",
            accent: 0.24,
            mic: mic(0.9, 0.5, 0.2, .small, tone: 0.7),
            kick: kick(62, damp: 0.35, beater: 0.9, decay: 0.2, pitch: 0.9, bright: 0.78),
            snare: snare(280, wires: 0.75, decay: 0.11, bright: 0.8),
            hat: hat(decay: 0.032, scale: 1.6, bright: 0.9),
            clap: clap(decay: 0.09, group: false),
            tom: tom(high: 260, mid: 190, floor: 140, decay: 0.2, damp: 0.3),
            ride: ride(decay: 0.5, scale: 1.2, rivets: 0.2, bright: 0.8),
            crash: crash(decay: 0.36, recipe: .splash, bright: 0.75, volume: 0.48),
            perc: perc(title: "Agogo", recipe: .agogo, f0: 980, decay: 0.2, volume: 0.5)
        )
    }

    private static func hiphop() -> Definition {
        definition(
            "Hip-Hop Breaks", "hiphop-breaks",
            "Запиленный акустический брейк.",
            accent: 0.22,
            mic: mic(0.7, 0.5, 0.6, .medium, tone: -0.6),
            lofi: 0.22,
            kick: kick(52, damp: 0.5, beater: 0.35, decay: 0.3, pitch: 0.45, bright: 0.3),
            snare: snare(175, wires: 0.8, decay: 0.2, bright: 0.35, pitchSemis: -1),
            hat: hat(decay: 0.07, scale: 0.88, bright: 0.3),
            clap: clap(decay: 0.16, group: true),
            tom: tom(high: 130, mid: 95, floor: 68, decay: 0.34, damp: 0.4),
            ride: ride(decay: 0.45, scale: 0.75, rivets: 0.1, bright: 0.22),
            crash: crash(decay: 0.26, recipe: .china, bright: 0.35, pitch: -4, scale: 0.7),
            perc: perc(title: "Break Tambourine", recipe: .tambourine, f0: 2000, decay: 0.2, volume: 0.32)
        )
    }

    private static func latin() -> Definition {
        definition(
            "Latin Percussion", "latin-percussion",
            "Конги, бонго, тимбалес и шейкер.",
            accent: 0.2,
            mic: mic(0.8, 0.5, 0.3, .medium, tone: 0.35),
            style: .percussion,
            kick: cajonBass(decay: 0.26, f0: 78),
            snare: timbaleSnare(),
            hat: shakerHat(),
            clap: clap(decay: 0.14, group: true),
            tom: congas(),
            ride: cowbellRide(),
            crash: crash(decay: 0.72, recipe: .crash, bright: 0.6, pitch: 4, scale: 1.4),
            perc: bongoPerc()
        )
    }

    private static func cajon() -> Definition {
        definition(
            "Cajon Unplugged", "cajon-unplugged",
            "Кахон у костра, близко и сухо.",
            accent: 0.18,
            mic: mic(0.8, 0.4, 0.4, .small, tone: 0.1),
            kick: cajonBass(decay: 0.22, f0: 72),
            snare: cajonSlap(),
            hat: shakerHat(egg: true),
            clap: snapSlot(title: "Finger Snap", decay: 0.1, pitch: 8),
            tom: djembeToms(),
            ride: perc(title: "Tambourine Shake", recipe: .tambourine, f0: 2100, decay: 0.24, volume: 0.34, voice: .ride, category: .cymbals),
            crash: crash(decay: 0.3, recipe: .splash, bright: 0.3, volume: 0.42),
            perc: clavesPerc()
        )
    }

    private static func orchestral() -> Definition {
        definition(
            "Orchestral", "orchestral",
            "Концертная перкуссия, большой зал.",
            accent: 0.26,
            mic: mic(0.4, 0.8, 0.9, .hall, tone: 0.25),
            scale: 0.7,
            kick: orchestralBass(),
            snare: concertSnare(),
            hat: hat(decay: 0.034, scale: 1.85, bright: 0.3),
            clap: snapSlot(title: "Finger Snap", decay: 0.14, pitch: -8),
            tom: timpani(),
            ride: suspended(),
            crash: crash(decay: 0.85, recipe: .crash, bright: 0.4, pitch: -3, scale: 0.72),
            perc: trianglePerc()
        )
    }

    // MARK: - Slot builders

    private static func definition(
        _ name: String,
        _ slug: String,
        _ character: String,
        accent: Double,
        mic: MicMix,
        scale: Float = 1,
        lofi: Double? = nil,
        style: FactoryStyle = .acoustic,
        kick: Slot,
        snare: Slot,
        hat: Slot,
        clap: Slot,
        tom: Slot,
        ride: Slot,
        crash: Slot,
        perc: Slot
    ) -> Definition {
        var slots = [kick, snare, hat, clap, tom, ride, crash, perc]
        if style == .percussion {
            for index in slots.indices { slots[index].style = .percussion }
        }
        return Definition(
            name: name, slug: slug, character: character, accent: accent,
            mic: mic,
            dynamics: Dynamics(curve: .db(range: 30, shape: 1), layers: 4, roundRobin: 2, brightness: 0.45, pitch: 0.8, decay: 0.3),
            scale: scale, lofi: lofi, slots: slots
        )
    }

    private static func mic(
        _ close: Double, _ overhead: Double, _ room: Double,
        _ size: RoomSize, tone: Double
    ) -> MicMix {
        MicMix(close: close, overhead: overhead, room: room, roomTone: tone, roomSize: size)
    }

    private static func dyn(
        _ range: Double, bright: Double, pitch: Double, decay: Double, noise: Double = 0.25
    ) -> Dynamics {
        Dynamics(
            curve: .db(range: range, shape: 1),
            layers: 4, roundRobin: 2,
            brightness: bright, transient: 0.55,
            pitch: pitch, decay: decay, noise: noise, rrDetune: 15
        )
    }

    private static func art(
        _ name: String, _ tag: String, _ recipe: AcousticRecipe,
        f0: Double? = nil, decay: Double? = nil, wires: Double? = nil
    ) -> ArticulationSpec {
        ArticulationSpec(name: name, tag: tag.isEmpty ? nil : tag, recipe: recipe, f0: f0, decayScale: decay, wires: wires)
    }

    private static func kick(
        _ f0: Double, damp: Double, beater: Double, decay: Float,
        pitch: Double, bright: Double, port: Bool = false
    ) -> Slot {
        Slot(
            suffix: "kick", title: "Kick", voice: .kick, category: .kick,
            style: .acoustic, volume: 0.95, decay: decay,
            dynamics: dyn(20, bright: bright, pitch: pitch, decay: 0.35, noise: 0.15),
            articulations: [
                art("Beater", "", .membraneKick, f0: f0),
                art("Soft", "1", .membraneKick, f0: f0, decay: 1.15)
            ],
            synth: .init(membrane: .init(f0: f0, damping: damp, beater: beater, port: port))
        )
    }

    private static func snare(_ f0: Double, wires: Double, decay: Float, bright: Double, pitchSemis: Float = 0) -> Slot {
        Slot(
            suffix: "snare", title: "Snare", voice: .snare, category: .snare,
            style: .acoustic, volume: 1, decay: decay, pitch: pitchSemis,
            dynamics: dyn(30, bright: bright, pitch: 1.2, decay: 0.4, noise: wires),
            articulations: [
                art("Center", "", .snareCenter, f0: f0, wires: wires),
                art("Rimshot", "r", .snareRimshot, f0: f0 * 1.05, wires: min(1, wires + 0.1)),
                art("Cross-stick", "s", .snareCrossStick, f0: 200, wires: 0)
            ],
            synth: .init(snareModel: .init(f0: f0, wires: wires, buzz: 0.35))
        )
    }

    private static func brushesSnare(f0: Double) -> Slot {
        Slot(
            suffix: "snare", title: "Brushes", voice: .snare, category: .snare,
            style: .acoustic, volume: 1, decay: 0.4,
            dynamics: dyn(26, bright: 0.3, pitch: 0.4, decay: 0.2, noise: 0.45),
            articulations: [
                art("Tap", "", .brushTap, f0: f0),
                art("Swirl", "1", .brushSwirl, f0: f0),
                art("Slap", "2", .brushSlap, f0: f0)
            ],
            synth: .init(snareModel: .init(f0: f0, wires: 0.1, buzz: 0))
        )
    }

    private static func hat(decay: Float, scale: Double, bright: Double, pedalLead: Bool = false) -> Slot {
        let closed = art("Closed", "", pedalLead ? .hatPedal : .hatClosed, decay: 1)
        let open = art("Open", "o", .hatOpen, decay: 1)
        let pedal = art("Pedal", "p", .hatPedal, decay: 0.8)
        let half = art("Half-open", "h", .hatHalfOpen, decay: 1)
        return Slot(
            suffix: "hat", title: "Hat", voice: .closedHat, category: .hihat,
            style: .acoustic, volume: 0.45, decay: decay, choke: 1,
            dynamics: dyn(22, bright: bright, pitch: 0.6, decay: 0.25, noise: 0.35),
            articulations: [closed, open, pedal, half],
            synth: .init(metal: .init(scale: scale, rivets: bright > 0.6 ? 0.2 : 0.05))
        )
    }

    private static func shakerHat(egg: Bool = false) -> Slot {
        Slot(
            suffix: "hat", title: egg ? "Shaker Egg" : "Shaker",
            voice: .closedHat, category: .hihat,
            style: .percussion, volume: 0.32, decay: egg ? 0.08 : 0.12,
            choke: 1,
            dynamics: dyn(18, bright: 0.4, pitch: 0.2, decay: 0.15, noise: 0.7),
            articulations: [
                art("Shake", "", .shaker, f0: egg ? 4800 : 6200),
                art("Accent", "1", .shaker, f0: egg ? 5200 : 7000, decay: 0.7)
            ],
            synth: .init()
        )
    }

    private static func clap(decay: Float, group: Bool) -> Slot {
        Slot(
            suffix: "clap", title: group ? "Group Clap" : "Acoustic Clap",
            voice: .clap, category: .percussion,
            style: .acoustic, volume: 0.7, decay: decay,
            dynamics: dyn(24, bright: 0.5, pitch: 0.4, decay: 0.2, noise: 0.6),
            articulations: [
                art(group ? "Group" : "Single", "", .clap),
                art("Tight", "1", .clap, decay: 0.65)
            ],
            synth: .init()
        )
    }

    private static func snapSlot(title: String, decay: Float = 0.08, pitch: Float = 0) -> Slot {
        Slot(
            suffix: "clap", title: title, voice: .clap, category: .percussion,
            style: .acoustic, volume: 0.62, decay: decay, pitch: pitch,
            dynamics: dyn(20, bright: 0.45, pitch: 0.3, decay: 0.1, noise: 0.4),
            articulations: [
                art("Snap", "", .snap),
                art("Group", "1", .clap, decay: 1.2)
            ],
            synth: .init()
        )
    }

    private static func tom(high: Double, mid: Double, floor: Double, decay: Float, damp: Double) -> Slot {
        Slot(
            suffix: "tom", title: "Toms", voice: .tom, category: .percussion,
            style: .acoustic, volume: 0.85, decay: decay,
            dynamics: dyn(24, bright: 0.5, pitch: 1.4, decay: 0.4, noise: 0.12),
            articulations: [
                art("High", "", .membraneTom, f0: high),
                art("High", "1", .membraneTom, f0: high),
                art("Mid", "2", .membraneTom, f0: mid),
                art("Floor", "3", .membraneTom, f0: floor)
            ],
            synth: .init(membrane: .init(f0: high, damping: damp, beater: 0.55, port: false))
        )
    }

    private static func malletToms() -> Slot {
        var slot = tom(high: 210, mid: 150, floor: 100, decay: 0.36, damp: 0.25)
        slot.title = "Mallet Toms"
        slot.synth.membrane?.beater = 0.15
        return slot
    }

    private static func congas() -> Slot {
        Slot(
            suffix: "tom", title: "Congas", voice: .tom, category: .percussion,
            style: .percussion, volume: 0.6, decay: 0.28,
            dynamics: dyn(22, bright: 0.55, pitch: 0.8, decay: 0.3, noise: 0.2),
            articulations: [
                art("Quinto", "", .conga, f0: 280),
                art("Quinto", "1", .conga, f0: 280),
                art("Conga", "2", .conga, f0: 220),
                art("Tumba", "3", .conga, f0: 170),
                art("Slap", "slap", .conga, f0: 310)
            ],
            synth: .init(hand: .init(f0: 230, slap: 0.2))
        )
    }

    private static func djembeToms() -> Slot {
        Slot(
            suffix: "tom", title: "Djembe", voice: .tom, category: .percussion,
            style: .acoustic, volume: 0.7, decay: 0.3,
            dynamics: dyn(22, bright: 0.5, pitch: 0.7, decay: 0.3, noise: 0.25),
            articulations: [
                art("Tone", "", .djembe, f0: 330),
                art("Bass", "bass", .djembe, f0: 70),
                art("Tone", "2", .djembe, f0: 330),
                art("Slap", "slap", .djembe, f0: 400)
            ],
            synth: .init(hand: .init(f0: 330, slap: 0.3))
        )
    }

    private static func timpani() -> Slot {
        Slot(
            suffix: "tom", title: "Timpani", voice: .tom, category: .percussion,
            style: .acoustic, volume: 0.85, decay: 0.7,
            dynamics: dyn(22, bright: 0.35, pitch: 1.6, decay: 0.45, noise: 0.08),
            articulations: [
                art("Mid", "", .timpani, f0: 110),
                art("High", "1", .timpani, f0: 140),
                art("Mid", "2", .timpani, f0: 98),
                art("Low", "3", .timpani, f0: 74)
            ],
            synth: .init(membrane: .init(f0: 110, damping: 0.2, beater: 0.4, port: false))
        )
    }

    private static func ride(decay: Float, scale: Double, rivets: Double, bright: Double) -> Slot {
        Slot(
            suffix: "ride", title: "Ride", voice: .ride, category: .cymbals,
            style: .acoustic, volume: 0.35, decay: decay,
            dynamics: dyn(26, bright: bright, pitch: 0.4, decay: 0.3, noise: 0.3),
            articulations: [
                art("Bow", "", .rideBow),
                art("Bell", "b", .rideBell),
                art("Edge", "2", .rideEdge)
            ],
            synth: .init(metal: .init(scale: scale, rivets: rivets))
        )
    }

    private static func brushRide() -> Slot {
        var slot = ride(decay: 0.5, scale: 0.7, rivets: 0.4, bright: 0.25)
        slot.title = "Brush Ride"
        slot.volume = 0.3
        slot.articulations[0] = art("Bow", "", .rideBow, decay: 0.7)
        return slot
    }

    private static func cowbellRide() -> Slot {
        Slot(
            suffix: "ride", title: "Cowbell", voice: .ride, category: .cymbals,
            style: .percussion, volume: 0.5, decay: 0.24,
            dynamics: dyn(20, bright: 0.5, pitch: 0.3, decay: 0.15, noise: 0.15),
            articulations: [
                art("Bell", "", .cowbell, f0: 587),
                art("High", "b", .cowbell, f0: 740)
            ],
            synth: .init()
        )
    }

    private static func suspended() -> Slot {
        Slot(
            suffix: "ride", title: "Suspended", voice: .ride, category: .cymbals,
            style: .acoustic, volume: 0.4, decay: 0.6,
            dynamics: dyn(26, bright: 0.4, pitch: 0.3, decay: 0.35, noise: 0.25),
            articulations: [
                art("Roll", "", .suspendedCymbal),
                art("Bell", "b", .rideBell)
            ],
            synth: .init(metal: .init(scale: 0.9, rivets: 0.1))
        )
    }

    private static func crash(
        decay: Float, recipe: AcousticRecipe, bright: Double,
        volume: Float = 0.55, pitch: Float = 0, scale: Double = 1
    ) -> Slot {
        Slot(
            suffix: "crash", title: recipe == .splash ? "Splash" : (recipe == .china ? "China" : "Crash"),
            voice: .crash, category: .cymbals,
            style: .acoustic, volume: volume, decay: decay, pitch: pitch,
            dynamics: dyn(26, bright: bright, pitch: 0.5, decay: 0.35, noise: 0.35),
            articulations: [
                art("Crash", "", recipe),
                art("Wash", "1", recipe, decay: 1.15)
            ],
            synth: .init(metal: .init(scale: scale, rivets: 0.05))
        )
    }

    private static func perc(
        title: String, recipe: AcousticRecipe, f0: Double, decay: Float, volume: Float,
        voice: SoundPreset.VoiceKind = .perc, category: SoundPreset.SoundCategory = .percussion
    ) -> Slot {
        Slot(
            suffix: voice == .ride ? "ride" : "perc",
            title: title, voice: voice, category: category,
            style: .percussion, volume: volume, decay: decay,
            dynamics: dyn(22, bright: 0.45, pitch: 0.3, decay: 0.2, noise: 0.4),
            articulations: [
                art(title, "", recipe, f0: f0),
                art("Mute", "1", recipe, f0: f0, decay: 0.45)
            ],
            synth: .init()
        )
    }

    private static func cajonBass(decay: Float, f0: Double) -> Slot {
        Slot(
            suffix: "kick", title: "Cajon Bass", voice: .kick, category: .kick,
            style: .acoustic, volume: 0.9, decay: decay,
            dynamics: dyn(18, bright: 0.4, pitch: 0.5, decay: 0.25, noise: 0.3),
            articulations: [
                art("Bass", "", .cajon, f0: f0),
                art("Bass", "1", .cajon, f0: f0 * 0.9)
            ],
            synth: .init(hand: .init(f0: f0, slap: 0.1))
        )
    }

    private static func cajonSlap() -> Slot {
        Slot(
            suffix: "snare", title: "Cajon Slap", voice: .snare, category: .snare,
            style: .acoustic, volume: 0.85, decay: 0.12,
            dynamics: dyn(24, bright: 0.6, pitch: 0.4, decay: 0.2, noise: 0.5),
            articulations: [
                art("Slap", "slap", .cajon, f0: 180),
                art("Tip", "tip", .cajon, f0: 220)
            ],
            synth: .init(hand: .init(f0: 180, slap: 0.2))
        )
    }

    private static func timbaleSnare() -> Slot {
        Slot(
            suffix: "snare", title: "Timbale", voice: .snare, category: .snare,
            style: .percussion, volume: 0.8, decay: 0.18,
            dynamics: dyn(22, bright: 0.6, pitch: 0.7, decay: 0.25, noise: 0.2),
            articulations: [
                art("Open", "", .timbale, f0: 420),
                art("Paila", "paila", .timbale, f0: 640)
            ],
            synth: .init(hand: .init(f0: 420, slap: 0.2))
        )
    }

    private static func orchestralBass() -> Slot {
        Slot(
            suffix: "kick", title: "Bass Drum", voice: .kick, category: .kick,
            style: .acoustic, volume: 0.95, decay: 0.55,
            dynamics: dyn(18, bright: 0.3, pitch: 0.8, decay: 0.4, noise: 0.1),
            articulations: [
                art("Soft", "", .orchestralBass, f0: 48),
                art("Hard", "1", .orchestralBass, f0: 46, decay: 1.1)
            ],
            synth: .init(membrane: .init(f0: 48, damping: 0.25, beater: 0.35, port: false))
        )
    }

    private static func concertSnare() -> Slot {
        Slot(
            suffix: "snare", title: "Concert Snare", voice: .snare, category: .snare,
            style: .acoustic, volume: 1, decay: 0.36, pitch: -3,
            dynamics: dyn(28, bright: 0.55, pitch: 0.6, decay: 0.3, noise: 0.7),
            articulations: [
                art("Center", "", .concertSnare, f0: 220, wires: 0.8),
                art("Rim", "r", .snareRimshot, f0: 240, wires: 0.4)
            ],
            synth: .init(snareModel: .init(f0: 220, wires: 0.8, buzz: 0.2))
        )
    }

    private static func bongoPerc() -> Slot {
        Slot(
            suffix: "perc", title: "Bongo", voice: .perc, category: .percussion,
            style: .percussion, volume: 0.58, decay: 0.16,
            dynamics: dyn(20, bright: 0.55, pitch: 0.5, decay: 0.2, noise: 0.15),
            articulations: [
                art("Macho", "", .bongo, f0: 460),
                art("Hembra", "1", .bongo, f0: 340),
                art("Guiro", "2", .guiro, f0: 900),
                art("Clave", "3", .wood, f0: 2100)
            ],
            synth: .init(hand: .init(f0: 460, slap: 0.15))
        )
    }

    private static func clavesPerc() -> Slot {
        Slot(
            suffix: "perc", title: "Claves", voice: .perc, category: .percussion,
            style: .percussion, volume: 0.55, decay: 0.1,
            dynamics: dyn(18, bright: 0.4, pitch: 0.2, decay: 0.1, noise: 0.1),
            articulations: [
                art("Clave", "", .wood, f0: 2400),
                art("Woodblock", "1", .wood, f0: 880)
            ],
            synth: .init()
        )
    }

    private static func trianglePerc() -> Slot {
        Slot(
            suffix: "perc", title: "Triangle", voice: .perc, category: .percussion,
            style: .percussion, volume: 0.4, decay: 0.5,
            dynamics: dyn(22, bright: 0.6, pitch: 0.2, decay: 0.3, noise: 0.05),
            articulations: [
                art("Open", "", .triangle, f0: 1200),
                art("Mute", "mute", .triangle, f0: 1200, decay: 0.25)
            ],
            synth: .init()
        )
    }

    private static func make(_ definition: Definition, _ slot: Slot) -> SoundPreset {
        let filename = "ac_\(definition.slug)_\(slot.suffix)"
        var preset = SoundPreset(
            id: SoundLibraryManager.factoryID(filename: filename),
            name: "\(definition.name) \(slot.title)",
            filename: filename,
            category: slot.category,
            origin: .factory
        )
        preset.voice = slot.voice
        preset.style = slot.style
        preset.volume = min(1, slot.volume * definition.scale)
        preset.decay = slot.decay
        preset.pitch = slot.pitch
        preset.attack = 0
        preset.sustain = 0
        preset.release = 0.02
        preset.chokeGroup = slot.choke
        preset.dynamics = slot.dynamics
        preset.articulations = slot.articulations
        preset.mic = definition.mic
        var synth = slot.synth
        if let lofi = definition.lofi {
            synth.lofi = .init(saturation: lofi)
        }
        preset.synth = synth
        return preset
    }
}
