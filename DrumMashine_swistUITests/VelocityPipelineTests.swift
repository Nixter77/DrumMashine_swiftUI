import Foundation
import Testing
@testable import DrumMashine_swistUI

struct VelocityDecodeTests {
    @Test func dynamicsRoundTripAndEmptyObjectUsesDefaults() throws {
        let original = Dynamics(
            curve: .db(range: 24, shape: 1.2),
            layers: 6,
            roundRobin: 3,
            brightness: 1.5,
            transient: 2,
            pitch: 0.4,
            decay: 1.1,
            noise: 0.3,
            humanize: 0.05,
            rrDetune: 8
        )
        let decoded = try JSONDecoder().decode(Dynamics.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)

        let empty = try JSONDecoder().decode(Dynamics.self, from: Data("{}".utf8))
        #expect(empty.curve == nil)
        #expect(empty.resolvedCurve == .db(range: 30, shape: 1))
        #expect(empty.resolvedLayers == 4)
        #expect(empty.resolvedRoundRobin == 2)

        let curve = try JSONDecoder().decode(VelocityCurve.self, from: Data("{}".utf8))
        #expect(curve == .db(range: 30, shape: 1))
        let linear = try roundTrip(VelocityCurve.linear)
        #expect(linear == .linear)
        let table = try roundTrip(VelocityCurve.table([0.9, 0.1, 0.2, 0.4, 0.3, 0.5, 0.8, 0.6]))
        if case .table(let points) = table {
            #expect(points == points.sorted())
        } else {
            Issue.record("table case missing")
        }

        let mic = try JSONDecoder().decode(MicMix.self, from: Data("{}".utf8))
        #expect(mic.close == nil)
        #expect(mic.resolvedClose == 1)
        #expect(mic.resolvedOverhead == 0.35)
        #expect(mic.resolvedRoom == 0.2)
        #expect(mic.resolvedRoomSize == .medium)
        let micFull = MicMix(close: 0.8, overhead: 0.4, room: 0.5, roomTone: 0.2, roomSize: .hall)
        #expect(try roundTrip(micFull) == micFull)

        let spec = ArticulationSpec(name: "Rim", tag: "r", recipe: .snareRimshot, f0: 180, wires: 0.2)
        #expect(try roundTrip(spec) == spec)
        let unknown = Data(#"{"recipe":"not-a-recipe","name":"X"}"#.utf8)
        let loose = try JSONDecoder().decode(ArticulationSpec.self, from: unknown)
        #expect(loose.recipe == nil)
        #expect(loose.name == "X")
    }

    @Test func legacyFixturesKeepNewFieldsNil() throws {
        let session = try JSONDecoder().decode(SessionState.self, from: fixture("legacy_session_v0"))
        #expect(session.padVelocityMode == .fixed)
        #expect(session.fullLevel == false)
        #expect(session.velocitySensitivity == .medium)
        #expect(session.humanizeVelocity == 0)
        #expect(session.accentAmount == 0.2)
        #expect(session.midiMap.binding(note: 36)?.track == 0)

        let presets = try JSONDecoder().decode([SoundPreset].self, from: fixture("legacy_sound_preset_v0"))
        #expect(presets.allSatisfy { $0.dynamics == nil && $0.articulations == nil && $0.mic == nil })

        let track = try JSONDecoder().decode(SequencerTrack.self, from: fixture("legacy_track_v0"))
        #expect(track.steps.allSatisfy { $0.accent == nil && $0.articulation == nil })

        struct Pair: Decodable { var kit: DrumKit }
        let pair = try JSONDecoder().decode(Pair.self, from: fixture("legacy_pattern_kit_v0"))
        #expect(pair.kit.mic == nil)
        #expect(pair.kit.dynamicsDefault == nil)
        #expect(pair.kit.character == nil)
        #expect(pair.kit.accentAmount == nil)
        #expect(pair.kit.resolvedAccentAmount == 0.2)
    }

    @Test func stepWithoutAccentDecodesAsBeforeAndRoundTrips() throws {
        let bare = Data(#"{"isActive":true,"velocity":0.4,"probability":0.5}"#.utf8)
        let step = try JSONDecoder().decode(SequencerStep.self, from: bare)
        #expect(step.isActive == true)
        #expect(step.velocity == 0.4)
        #expect(step.probability == 0.5)
        #expect(step.accent == nil)
        #expect(step.articulation == nil)

        var marked = step
        marked.accent = true
        marked.articulation = 2
        let again = try JSONDecoder().decode(SequencerStep.self, from: JSONEncoder().encode(marked))
        #expect(again.accent == true)
        #expect(again.articulation == 2)
        #expect(again.velocity == 0.4)
    }

    @Test func enumCountsStayInsideTheCompatibleSet() {
        #expect(SoundPreset.VoiceKind.allCases.count == 10)
        #expect(SoundPreset.SoundCategory.allCases.count == 6)
        #expect(FactoryStyle.allCases.count == 7)
        #expect(FactoryStyle.allCases.contains(.percussion))
        let unknown = Data(#"{"id":"00000000-0000-0000-0000-000000000001","name":"X","filename":"x","category":"kick","style":"not-a-style"}"#.utf8)
        let preset = try? JSONDecoder().decode(SoundPreset.self, from: unknown)
        #expect(preset?.style == nil)
    }
}

struct VelocityCurveTests {
    @Test func linearIsIdentityAndDbHitsTheSpec() {
        #expect(abs(VelocityCurve.linear.gain(at: 0.4) - 0.4) < 1e-9)
        let curve = VelocityCurve.db(range: 30, shape: 1)
        #expect(abs(curve.gain(at: 1) - 1) < 1e-9)
        let quiet = curve.gain(at: 0.25)
        let db = 20 * log10(quiet)
        #expect(abs(db - (-22.5)) < 0.5, "\(db)")
        let table = curve.curveTable()
        #expect(table.count == 128)
        #expect(zip(table, table.dropFirst()).allSatisfy { $0 <= $1 + 0.000_001 })
    }

    @Test func unsortedTableBecomesMonotonic() {
        let curve = VelocityCurve.table([0.9, 0.05, 0.4, 0.2, 1.4, -0.2, 0.7, 0.5])
        let table = curve.curveTable()
        #expect(table.allSatisfy { $0.isFinite })
        #expect(zip(table, table.dropFirst()).allSatisfy { $0 <= $1 + 0.000_001 })
        #expect(table.last == 1)
    }

    @Test func accentThenGrooveAndHumanizeStayDeterministic() {
        let accented = VelocityMath.resolve(
            velocity: 0.5, accent: true, accentAmount: 0.2,
            grooveMultiplier: nil, humanizeSpread: 0, unitSigned: 0
        )
        #expect(abs(accented - 0.7) < 1e-6)
        let clamped = VelocityMath.resolve(
            velocity: 0.9, accent: true, accentAmount: 0.2,
            grooveMultiplier: nil, humanizeSpread: 0, unitSigned: 0
        )
        #expect(clamped == 1)
        let ordered = VelocityMath.resolve(
            velocity: 0.5, accent: true, accentAmount: 0.2,
            grooveMultiplier: 0.5, humanizeSpread: 0, unitSigned: 0.2
        )
        #expect(abs(ordered - 0.35) < 1e-6)
        let plain = VelocityMath.resolve(
            velocity: 0.4, accent: false, accentAmount: 0.2,
            grooveMultiplier: nil, humanizeSpread: 0, unitSigned: 99
        )
        #expect(plain == 0.4)
        #expect(VelocityMath.spread(sessionPercent: 0, dynamicsHumanize: 0) == 0)
        #expect(abs(VelocityMath.spread(sessionPercent: 100, dynamicsHumanize: 0) - 0.15) < 1e-6)
        let a = VelocityMath.resolve(
            velocity: 0.8, accent: false, accentAmount: 0.2,
            grooveMultiplier: nil, humanizeSpread: 0.15, unitSigned: -1
        )
        let b = VelocityMath.resolve(
            velocity: 0.8, accent: false, accentAmount: 0.2,
            grooveMultiplier: nil, humanizeSpread: 0.15, unitSigned: -1
        )
        #expect(a == b)
        #expect(a < 0.8)
    }
}

struct PadAndKeyboardTests {
    @Test func padMappingFollowsPositionPressureAndModifiers() {
        let top = PadVelocity.interpret(
            mode: .position, y: 0, height: 100, pressure: nil,
            option: false, shift: false, fullLevel: false, sensitivity: .medium
        )
        let bottom = PadVelocity.interpret(
            mode: .position, y: 100, height: 100, pressure: nil,
            option: false, shift: false, fullLevel: false, sensitivity: .medium
        )
        #expect(abs(top.velocity - 1) < 1e-5)
        #expect(abs(bottom.velocity - 0.25) < 1e-5)

        let ghost = PadVelocity.interpret(
            mode: .position, y: 0, height: 100, pressure: 1,
            option: true, shift: true, fullLevel: false, sensitivity: .hard
        )
        #expect(ghost.velocity == 0.35)
        #expect(ghost.accent == false)

        let accent = PadVelocity.interpret(
            mode: .position, y: 80, height: 100, pressure: nil,
            option: false, shift: true, fullLevel: false, sensitivity: .soft
        )
        #expect(accent.velocity == 1)
        #expect(accent.accent == true)

        let full = PadVelocity.interpret(
            mode: .position, y: 90, height: 100, pressure: nil,
            option: true, shift: true, fullLevel: true, sensitivity: .hard
        )
        #expect(full.velocity == 1)
        #expect(full.accent == false)

        let fixed = PadVelocity.interpret(
            mode: .fixed, y: 90, height: 100, pressure: 0.2,
            option: false, shift: false, fullLevel: false, sensitivity: .hard
        )
        #expect(fixed.velocity == 1)

        let fallback = PadVelocity.interpret(
            mode: .pressure, y: 100, height: 100, pressure: nil,
            option: false, shift: false, fullLevel: false, sensitivity: .medium
        )
        #expect(abs(fallback.velocity - 0.25) < 1e-5)

        let pressed = PadVelocity.interpret(
            mode: .pressure, y: 0, height: 100, pressure: 0.5,
            option: false, shift: false, fullLevel: false, sensitivity: .medium
        )
        #expect(abs(pressed.velocity - 0.5) < 1e-5)

        let peak = PadVelocity.peakPressure(samples: [
            (time: 0, pressure: 0.2),
            (time: 0.006, pressure: 0.8),
            (time: 0.020, pressure: 1)
        ])
        #expect(peak == 0.8)
        let noForce = PadVelocity.peakPressure(samples: [(time: 0, pressure: 0), (time: 0.004, pressure: 0)])
        #expect(noForce == nil)

        #expect(VelocitySensitivity.soft.shape == 0.6)
        #expect(VelocitySensitivity.medium.shape == 1)
        #expect(VelocitySensitivity.hard.shape == 1.6)
    }

    @Test func keysOneThroughEightPlayPadsWithoutTakingSpaceOrFill() {
        let ready = KeyContext()
        #expect(ready.decide("1") == .pad(track: 0, ghost: false, accent: false))
        #expect(ready.decide("8") == .pad(track: 7, ghost: false, accent: false))
        #expect(ready.decide("1", shift: true) == .pad(track: 0, ghost: false, accent: true))
        #expect(ready.decide("1", option: true, shift: true) == .pad(track: 0, ghost: true, accent: false))
        #expect(ready.decide(" ", keyCode: 49) == .playToggle)
        #expect(ready.decide("f") == .fillOnce)
        #expect(ready.decide("F") == .fillOnce)
        #expect(ready.decide(" ", keyCode: 49, option: true) == .pass)
        #expect(ready.decide("f", option: true) == .pass)
        #expect(ready.decide("1", command: true) == .pass)
        #expect(ready.decide("1", control: true) == .pass)
        #expect(ready.decide("1", isRepeat: true) == .consume)
        #expect(ready.decide("1", isKeyWindow: false) == .pass)
        #expect(ready.decide("1", isPanel: true) == .pass)
        #expect(ready.decide("1", hasSheet: true) == .pass)
        #expect(ready.decide("1", firstResponderIsText: true) == .pass)
        #expect(ready.decide(" ", keyCode: 49, audioReady: false) == .pass)
        #expect(ready.decide("f", audioReady: false) == .pass)
    }
}

struct MIDIParserTests {
    @Test func noteOnOffAndCC4FollowTheGMMap() {
        let on = MIDIPacketParser.events(bytes: [0x90, 36, 127])
        #expect(on == [.noteOn(channel: 0, note: 36, velocity: 127)])
        let zero = MIDIPacketParser.events(bytes: [0x90, 36, 0])
        #expect(zero == [.noteOn(channel: 0, note: 36, velocity: 0)])
        #expect(MIDIResolver.hit(event: zero[0], cc4: nil, map: .gm, sensitivity: .medium) == nil)
        let off = MIDIPacketParser.events(bytes: [0x80, 38, 0])
        #expect(MIDIResolver.hit(event: off[0], cc4: nil, map: .gm, sensitivity: .medium) == nil)

        let kick = MIDIResolver.hit(event: on[0], cc4: nil, map: .gm, sensitivity: .medium)
        #expect(kick == MIDIHit(track: 0, velocity: 1, articulation: 0))
        let rim = MIDIResolver.hit(
            event: .noteOn(channel: 0, note: 40, velocity: 127),
            cc4: nil, map: .gm, sensitivity: .medium
        )
        #expect(rim?.track == 1)
        #expect(rim?.articulation == 1)
        let stick = MIDIResolver.hit(
            event: .noteOn(channel: 0, note: 37, velocity: 64),
            cc4: nil, map: .gm, sensitivity: .medium
        )
        #expect(stick?.articulation == 2)
        #expect(abs((stick?.velocity ?? 0) - Float(64) / 127) < 1e-5)

        let ccPedal = MIDIPacketParser.events(bytes: [0xB0, 4, 100, 0x90, 42, 100])
        #expect(ccPedal[0] == .controlChange(channel: 0, controller: 4, value: 100))
        let pedal = MIDIResolver.hit(event: ccPedal[1], cc4: 100, map: .gm, sensitivity: .medium)
        #expect(pedal?.track == 2)
        #expect(pedal?.articulation == 2)
        let half = MIDIResolver.hit(event: ccPedal[1], cc4: 50, map: .gm, sensitivity: .medium)
        #expect(half?.articulation == 3)
        let noteDecides = MIDIResolver.hit(event: ccPedal[1], cc4: 10, map: .gm, sensitivity: .medium)
        #expect(noteDecides?.articulation == 0)

        let hard = MIDIResolver.hit(
            event: .noteOn(channel: 0, note: 38, velocity: 64),
            cc4: nil, map: .gm, sensitivity: .hard
        )
        let plain = MIDIResolver.hit(
            event: .noteOn(channel: 0, note: 38, velocity: 64),
            cc4: nil, map: .gm, sensitivity: .medium
        )
        #expect((hard?.velocity ?? 1) < (plain?.velocity ?? 0))
    }

    @Test func midiLaneIgnoresGenerationAndStillTriggers() throws {
        let engine = VoiceEngine(sampleRate: 48_000)
        var click = [Float](repeating: 0, count: 32)
        click[0] = 1
        engine.swapSample(track: 0, samples: click)
        engine.setAcceptedGeneration(5)
        engine.trigger(
            track: 0, velocity: 0.5, chokeGroup: -1, atSample: 0,
            generation: 99, lane: .midi
        )
        let played = try renderOffline(frames: 64, chunkFrames: 64) { _ in engine.sourceNode }
        #expect((played.map { abs($0) }.max() ?? 0) > 0.01)

        let blocked = VoiceEngine(sampleRate: 48_000)
        blocked.swapSample(track: 0, samples: click)
        blocked.setAcceptedGeneration(5)
        blocked.trigger(
            track: 0, velocity: 0.5, chokeGroup: -1, atSample: 0,
            generation: 99, lane: .control
        )
        let silent = try renderOffline(frames: 64, chunkFrames: 64) { _ in blocked.sourceNode }
        #expect((silent.map { abs($0) }.max() ?? 0) == 0)
    }
}

struct SchedulerVelocityTests {
    @Test func zeroHumanizeKeepsTheWrittenVelocity() throws {
        let full = try hitPeak(velocity: 1)
        let written = try hitPeak(velocity: 0.4)
        #expect(full > 0.01)
        #expect(abs(written / full - 0.4) < 0.001)
    }

    @Test func accentIsAppliedBeforeTheGrooveMultiplier() throws {
        let full = try hitPeak(velocity: 1)
        let accented = try hitPeak(velocity: 0.5, accent: true, grooveMul: 0.5)
        #expect(abs(accented / full - 0.35) < 0.02, "ratio \(accented / full)")
    }

    @Test func velocityHumanizeRepeatsForTheSameSeedAndMovesTheHit() throws {
        let plain = try hitPeak(velocity: 0.8)
        let once = try hitPeak(velocity: 0.8, humanizeVelocity: 100)
        let twice = try hitPeak(velocity: 0.8, humanizeVelocity: 100)
        #expect(once == twice)
        #expect(abs(once - plain) > 0.000_1)
    }
}

@MainActor
struct SeededRandomizeTests {
    @Test func twoEnginesDrawTheSamePattern() {
        let first = SequencerEngine()
        let second = SequencerEngine()
        first.randomizePattern(density: 0.55)
        second.randomizePattern(density: 0.55)
        for (leftTrack, rightTrack) in zip(first.tracks, second.tracks) {
            #expect(leftTrack.steps.count == rightTrack.steps.count)
            for (left, right) in zip(leftTrack.steps, rightTrack.steps) {
                #expect(left.isActive == right.isActive)
                #expect(left.velocity == right.velocity)
            }
        }
        let before = first.tracks[0].steps.map(\.velocity)
        first.randomizePattern(density: 0.55)
        #expect(first.tracks[0].steps.map(\.velocity) != before)
    }

    @Test func recordedAccentIsStoredOnTheStep() {
        let engine = SequencerEngine()
        engine.recordMode = .overdub
        engine.play()
        defer { engine.stop() }
        engine.recordPadHit(trackIndex: 1, velocity: 1, atStep: 4, accent: true)
        #expect(engine.tracks[1].steps[4].isActive == true)
        #expect(engine.tracks[1].steps[4].velocity == 1)
        #expect(engine.tracks[1].steps[4].accent == true)
        engine.recordPadHit(trackIndex: 1, velocity: 0.35, atStep: 5, accent: false)
        #expect(engine.tracks[1].steps[5].velocity == 0.35)
        #expect(engine.tracks[1].steps[5].accent == nil)
    }
}

private struct KeyContext {
    func decide(
        _ characters: String,
        keyCode: UInt16 = 0,
        command: Bool = false,
        option: Bool = false,
        control: Bool = false,
        shift: Bool = false,
        isRepeat: Bool = false,
        audioReady: Bool = true,
        isKeyWindow: Bool = true,
        isPanel: Bool = false,
        hasSheet: Bool = false,
        firstResponderIsText: Bool = false
    ) -> KeyDecision {
        KeyboardRouter.decide(
            characters: characters,
            keyCode: keyCode,
            command: command,
            option: option,
            control: control,
            shift: shift,
            isRepeat: isRepeat,
            audioReady: audioReady,
            isKeyWindow: isKeyWindow,
            isPanel: isPanel,
            hasSheet: hasSheet,
            firstResponderIsText: firstResponderIsText
        )
    }
}

private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
    try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
}

private func hitPeak(
    velocity: Float,
    accent: Bool = false,
    humanizeVelocity: Double = 0,
    grooveMul: Float? = nil
) throws -> Float {
    let engine = VoiceEngine(sampleRate: 48_000)
    var click = [Float](repeating: 0, count: 64)
    click[0] = 1
    engine.swapSample(track: 0, samples: click)
    var snap = kickPattern(bpm: 120)
    for index in snap.tracks[0].steps.indices {
        snap.tracks[0].steps[index].isActive = index == 0
        snap.tracks[0].steps[index].velocity = velocity
        snap.tracks[0].steps[index].accent = accent
    }
    snap.humanizeVelocity = humanizeVelocity
    snap.accentAmount = 0.2
    if let grooveMul {
        snap.groove = GrooveSnapshot(
            timing: Array(repeating: 0, count: 16),
            velocity: Array(repeating: Double(grooveMul), count: 16),
            randomDepth: 0,
            trackOn: Array(repeating: true, count: 8),
            isActive: true
        )
    }
    let scheduler = SequencerScheduler(voiceEngine: engine, sampleRate: 48_000)
    scheduler.replace(snap)
    scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)
    let rendered = try drive(engine: engine, scheduler: scheduler, frames: 8_000)
    return rendered.map { abs($0) }.max() ?? 0
}
