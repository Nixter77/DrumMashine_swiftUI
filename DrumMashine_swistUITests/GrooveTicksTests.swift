import Foundation
import Testing
@testable import DrumMashine_swistUI

/// CUT_11 IN-4: header ticks mirror the scheduler's GrooveSnapshot timing.
struct GrooveTicksTests {
    private func t(_ id: String) -> GrooveTemplate { FactoryGrooves.template(id: id)! }

    @Test func cleanHasNoTicks() {
        var s = GrooveSettings(); s.grooveID = FactoryGrooves.cleanID
        #expect(GrooveTicks.offsets(template: t(FactoryGrooves.cleanID), settings: s, stepCount: 16).isEmpty)
        #expect(GrooveTicks.offsets(template: nil, settings: s, stepCount: 32).isEmpty)
    }

    @Test(arguments: ["mpc58", "shuffle8"])
    func matchesSnapshotTiming(_ id: String) {
        let s = GrooveSettings()
        let snap = GrooveSnapshot(template: t(id), settings: s)
        let o = GrooveTicks.offsets(template: t(id), settings: s, stepCount: 16)
        #expect(o.count == 16)
        for i in 0..<16 { #expect(o[i] == snap.timing[i]) }
        if id == "mpc58" {
            for i in stride(from: 1, to: 16, by: 2) { #expect(abs(o[i] - 0.16) < 1e-9) }
            for i in stride(from: 0, to: 16, by: 2) { #expect(o[i] == 0) }
        } else {
            #expect(abs(o[2] - 0.33) < 1e-9 && o[1] == 0)
        }
    }

    @Test func amount50Halves() {
        var half = GrooveSettings(); half.amount = 50
        let full = GrooveTicks.offsets(template: t("mpc58"), settings: GrooveSettings(), stepCount: 16)
        let h = GrooveTicks.offsets(template: t("mpc58"), settings: half, stepCount: 16)
        #expect(h == GrooveSnapshot(template: t("mpc58"), settings: half).timing)
        for i in 0..<16 { #expect(abs(h[i] - full[i] / 2) < 1e-12) }
        #expect(h[1] > 0)
    }

    @Test func timingZeroOrStrengthZeroHidesTicks() {
        var s = GrooveSettings(); s.timing = 0
        #expect(GrooveTicks.offsets(template: t("mpc66"), settings: s, stepCount: 16).isEmpty)
        var a = GrooveSettings(); a.amount = 0
        #expect(GrooveTicks.offsets(template: t("mpc66"), settings: a, stepCount: 16).isEmpty)
    }

    @Test func thirtyTwoRepeatsTemplate() {
        let snap = GrooveSnapshot(template: t("dilla"), settings: GrooveSettings())
        let o = GrooveTicks.offsets(template: t("dilla"), settings: GrooveSettings(), stepCount: 32)
        #expect(o.count == 32)
        for i in 0..<32 {
            #expect(o[i] == snap.timing[i % GrooveTemplate.length])
            #expect(o[i] == snap.timingOffset(step: i))
        }
        #expect(Array(o[0..<16]) == Array(o[16..<32]))
    }

    @Test func allFactoryGroovesInRange() {
        #expect(FactoryGrooves.all.count >= 10)
        for g in FactoryGrooves.all {
            for n in [16, 32] {
                let o = GrooveTicks.offsets(template: g, settings: GrooveSettings(), stepCount: n)
                if g.isClean { #expect(o.isEmpty); continue }
                #expect(o.count == n, "\(g.id)")
                #expect(o.allSatisfy { GrooveTemplate.timingRange.contains($0) }, "\(g.id)")
            }
        }
    }

    /// AC-4: header struct reads groove state, not the playhead.
    @Test func headerDoesNotReadPlayhead() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DrumMashine_swistUI/DrumMachine/Features/Sequencer/SequencerView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        let start = try #require(src.range(of: "struct SequencerStepHeader"))
        let rest = src[start.upperBound...]
        let body = rest.range(of: "\nstruct ").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        #expect(body.contains("grooveSettings") && body.contains("activeGroove"))
        #expect(!body.contains("currentStep"))
        #expect(!body.contains("isPlaying"))
    }
}
