import Foundation
import Testing
@testable import DrumMashine_swistUI

@MainActor
struct GrooveTests {
    @Test func factoryGroovesAreValid() {
        #expect(FactoryGrooves.all.count == 15)
        #expect(Set(FactoryGrooves.all.map(\.id)).count == 15)
        for g in FactoryGrooves.all {
            #expect(g.timing.count == 16 && g.velocity.count == 16)
            #expect(g.timing.allSatisfy { GrooveTemplate.timingRange.contains($0) })
            #expect(g.velocity.allSatisfy { GrooveTemplate.velocityRange.contains($0) })
            #expect(g.normalized() == g)
        }
        #expect(FactoryGrooves.template(id: FactoryGrooves.cleanID)?.isClean == true)
    }

    @Test func cleanAndZeroAmountAreInactive() {
        var s = GrooveSettings()
        #expect(GrooveSnapshot(template: FactoryGrooves.template(id: "clean"), settings: s).isActive == false)
        s.grooveID = "mpc66"; s.amount = 0
        #expect(GrooveSnapshot(template: FactoryGrooves.template(id: "mpc66"), settings: s).isActive == false)
        #expect(GrooveSnapshot(template: nil, settings: s) == .clean)
    }

    @Test func mpc66PushesOddSixteenths() {
        var s = GrooveSettings(); s.grooveID = "mpc66"
        let snap = GrooveSnapshot(template: FactoryGrooves.template(id: "mpc66"), settings: s)
        #expect(snap.isActive)
        #expect(abs(snap.timingOffset(step: 1) - 0.32) < 1e-9)
        #expect(snap.timingOffset(step: 0) == 0)
        #expect(abs(snap.timingOffset(step: 17) - 0.32) < 1e-9)   // 32-step patterns wrap
        s.amount = 50
        let half = GrooveSnapshot(template: FactoryGrooves.template(id: "mpc66"), settings: s)
        #expect(abs(half.timingOffset(step: 1) - 0.16) < 1e-9)
        s.amount = 100; s.timing = 0
        let noTiming = GrooveSnapshot(template: FactoryGrooves.template(id: "mpc66"), settings: s)
        #expect(noTiming.timingOffset(step: 1) == 0)
        #expect(noTiming.velocityMul(step: 1) < 1)
    }

    @Test func perTrackMask() {
        var s = GrooveSettings(); s.grooveID = "dilla"; s.perTrack[2] = false
        let snap = GrooveSnapshot(template: FactoryGrooves.template(id: "dilla"), settings: s)
        #expect(snap.isOn(track: 2) == false)
        #expect(snap.isOn(track: 0))
    }

    @Test func oldSessionJSONDecodesWithCleanGroove() throws {
        let json = #"{"bpm":100,"swing":10,"humanize":0}"#.data(using: .utf8)!
        let state = try JSONDecoder().decode(SessionState.self, from: json)
        #expect(state.groove == GrooveSettings())
        var s = GrooveSettings(); s.grooveID = "bossa"; s.random = 30
        let round = try JSONDecoder().decode(GrooveSettings.self, from: JSONEncoder().encode(s))
        #expect(round == s)
    }

    @Test func extractUsesAccentsAndSwing() {
        var t = SequencerTrack(soundPreset: SoundLibraryManager.shared.defaultPreset(forTrackIndex: 0))
        while t.steps.count < 16 { t.steps.append(SequencerStep()) }
        t.steps[0].isActive = true; t.steps[0].velocity = 1.0
        t.steps[4].isActive = true; t.steps[4].velocity = 0.6
        let g = SequencerEngine.extractGroove(tracks: [t], stepCount: 16, name: "x")
        #expect(g.velocity[0] == 1.0)
        #expect(abs(g.velocity[4] - 0.6) < 1e-6)
        #expect(g.velocity[2] == 1.0)
        #expect(g.timing.allSatisfy { $0 == 0 })   // swing is applied on top, not copied

    }

    @Test func eightStepPatternsReuseTheFirstEightSlots() {
        var s = GrooveSettings(); s.grooveID = "mpc66"
        let snap = GrooveSnapshot(template: FactoryGrooves.template(id: "mpc66"), settings: s)
        // The scheduler indexes by pattern step; slot 9 of a 16-step groove equals slot 1.
        #expect(snap.timingOffset(step: 9 % 8) == snap.timingOffset(step: 1))
    }

    @Test func userGrooveNamesAreUnique() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = UserGrooveStore(directory: dir)
        let base = GrooveTemplate(id: "u1", name: "MPC 54%", timing: [], velocity: [])
        let a = store.add(base)
        #expect(a.name == "MPC 54% 2")
        #expect(a.timing.count == 16)
        let reloaded = UserGrooveStore(directory: dir)
        #expect(reloaded.grooves.map(\.name) == ["MPC 54% 2"])
    }
}

/// P2-2: a large negative groove pull on step k+1 must not land behind step k.
struct GrooveCrossStepTests {
    @Test func negativePullNeverMergesWithThePreviousStep() throws {
        let engine = VoiceEngine(sampleRate: 48_000)
        var click = [Float](repeating: 0, count: 64)
        click[0] = 1
        engine.swapSample(track: 0, samples: click)
        var snap = kickPattern(bpm: 120)
        let timing = (0..<16).map { $0 % 2 == 0 ? 0.4 : -0.9 }
        snap.groove = GrooveSnapshot(timing: timing, velocity: Array(repeating: 1, count: 16),
                                     randomDepth: 0, trackOn: Array(repeating: true, count: 8), isActive: true)
        let scheduler = SequencerScheduler(voiceEngine: engine, sampleRate: 48_000)
        scheduler.replace(snap)
        scheduler.begin(at: 0, ioBufferFrames: 512, timer: false)
        let rendered = try drive(engine: engine, scheduler: scheduler, frames: 192_000)
        let hits = onsets(rendered, threshold: 0.2)
        #expect(hits.count == 32, "\(hits.count) onsets")
        #expect(zip(hits, hits.dropFirst()).allSatisfy { $0 < $1 })
    }
}
