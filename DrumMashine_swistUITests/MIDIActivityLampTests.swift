import Foundation
import Testing
@testable import DrumMashine_swistUI

/// The transport's MIDI dot used a 20 Hz TimelineView that kept the window updating at display
/// rate while idle. The lamp is now event-driven: woken by the first note, dark and idle after.
@MainActor
struct MIDIActivityLampTests {
    @Test func markWakesOnlyOncePerLitPeriod() {
        let activity = MIDIActivity()
        #expect(activity.mark(at: 1_000) == true)
        #expect(activity.mark(at: 2_000) == false)
        #expect(activity.mark(at: 3_000) == false)
        activity.rearm()
        #expect(activity.mark(at: 4_000) == true)
    }

    @Test func litWindowIs150Milliseconds() {
        let activity = MIDIActivity()
        #expect(activity.isLit(at: 10) == false)
        activity.mark(at: 1_000_000_000)
        #expect(activity.isLit(at: 1_000_000_000))
        #expect(activity.remainingLit(at: 1_100_000_000) == 50_000_000)
        #expect(activity.isLit(at: 1_149_999_999))
        #expect(activity.isLit(at: 1_150_000_000) == false)
        #expect(activity.remainingLit(at: 2_000_000_000) == 0)
    }

    /// Waits on the real clock, with a generous ceiling: the full suite can starve the main actor.
    private func waitUntilIdle(_ lamp: MIDIActivityLamp) async {
        for _ in 0..<200 where lamp.isRunning {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    @Test func lampLightsThenGoesDarkAndStops() async {
        let activity = MIDIActivity()
        let lamp = MIDIActivityLamp(activity: activity)
        #expect(lamp.isLit == false)
        #expect(lamp.isRunning == false)

        #expect(activity.mark())
        lamp.wake()
        #expect(lamp.isLit)
        #expect(lamp.isRunning)

        await waitUntilIdle(lamp)
        #expect(lamp.isLit == false)
        #expect(lamp.isRunning == false)
        // Re-armed: the next note wakes it again.
        #expect(activity.mark())
    }

    @Test func noteWhileLitDoesNotHopAgainAndStillGoesDark() async {
        let activity = MIDIActivity()
        let lamp = MIDIActivityLamp(activity: activity)
        activity.mark()
        lamp.wake()
        #expect(activity.mark() == false)   // already woken: no second main-actor hop
        lamp.wake()                         // a duplicate wake is harmless
        #expect(lamp.isLit)
        await waitUntilIdle(lamp)
        #expect(lamp.isLit == false)
        #expect(activity.isLit() == false)
        #expect(activity.mark())            // re-armed after going dark
    }

    @Test func autoPlayFlagIsOptIn() {
        #expect(MainLayoutView.autoPlayRequested(["app"]) == false)
        #expect(MainLayoutView.autoPlayRequested(["app", "-DMAutoPlay"]))
    }

    @Test func transportDoesNotPollTheMIDIDot() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DrumMashine_swistUI/DrumMachine/Features/Transport/TransportBarView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("TimelineView(.periodic"))
        #expect(source.contains("MIDIActivityDot(lamp: MIDIHub.lamp)"))
    }
}

/// `outputLatencyFrames` is cached; the conversion itself must stay the same as before.
struct OutputLatencyFramesTests {
    @Test func secondsToFramesMatchesTheOldFormula() {
        #expect(AudioEngineManager.latencyFrames(0.01, sampleRate: 44_100) == 441)
        #expect(AudioEngineManager.latencyFrames(0.0123456, sampleRate: 48_000) == 593)
        #expect(AudioEngineManager.latencyFrames(0, sampleRate: 48_000) == 0)
        #expect(AudioEngineManager.latencyFrames(-1, sampleRate: 48_000) == 0)
        #expect(AudioEngineManager.latencyFrames(.nan, sampleRate: 48_000) == 0)
        #expect(AudioEngineManager.latencyFrames(.infinity, sampleRate: 48_000) == 0)
    }

    @MainActor @Test func cachedValueIsStable() {
        let audio = AudioEngineManager.shared
        let first = audio.outputLatencyFrames
        #expect(first >= 0)
        #expect(audio.outputLatencyFrames == first)
    }
}
