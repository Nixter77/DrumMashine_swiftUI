import Foundation
import Observation

/// What the meters and the visualizer draw. One value, so one assignment wakes SwiftUI once.
struct MeterDisplay: Equatable {
    var bands: [Float]
    var waveform: [Float]
    var rmsL: Float
    var rmsR: Float
    var levelL: Float
    var levelR: Float

    static let silent = MeterDisplay(
        bands: Array(repeating: 0, count: SpectrumAnalyzer.bandCount),
        waveform: Array(repeating: 0, count: SpectrumAnalyzer.waveformPoints),
        rmsL: 0,
        rmsR: 0,
        levelL: 0,
        levelR: 0
    )
}

/// Polls `SpectrumAnalyzer` 30 times a second and publishes a single frame, only on change.
/// After a second without change (stopped or silent) it backs off to `idleNanoseconds`.
/// Views that do not read `display` stay out of this update.
@MainActor
@Observable
final class MeterModel {
    static let shared = MeterModel()

    private(set) var display = MeterDisplay.silent
    /// Stays lit for one second after the pre-limiter peak reaches full scale.
    private(set) var isClipping = false

    private var clients = 0
    private var task: Task<Void, Never>?
    private var clipClearAt = ContinuousClock.now
    /// Consecutive polls that changed nothing.
    private(set) var unchangedPolls = 0
    var isIdle: Bool { unchangedPolls >= Self.idleAfterPolls }

    /// 30 Hz. The canvases redraw from `display` itself (no separate timeline clock), so there is
    /// no second clock adding lag.
    static let pollNanoseconds: UInt64 = 33_333_333
    /// Poll interval once nothing has changed for `idleAfterPolls` polls.
    static let idleNanoseconds: UInt64 = 100_000_000
    static let idleAfterPolls = 30
    /// Per-poll VU fall at 30 Hz (same fall per second as 0.9592 at 60 Hz).
    static let levelDecay: Float = 0.92
    /// Levels below this snap to zero so a silent meter stops changing.
    static let levelFloor: Float = 1e-4

    private init() {}

    func start() {
        clients += 1
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                self.pull()
                try? await Task.sleep(nanoseconds: self.isIdle ? Self.idleNanoseconds : Self.pollNanoseconds)
            }
        }
    }

    func stop() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        task?.cancel()
        task = nil
    }

    func pull() {
        let measured = AudioEngineManager.shared.spectrumAnalyzer.copyFrame()
        let next = MeterDisplay(
            bands: measured.bands,
            waveform: measured.waveform,
            rmsL: measured.rmsL,
            rmsR: measured.rmsR,
            levelL: Self.decayed(measured.rmsL, from: display.levelL),
            levelR: Self.decayed(measured.rmsR, from: display.levelR)
        )
        if next != display {
            display = next
            unchangedPolls = 0
        } else if unchangedPolls < Self.idleAfterPolls {
            unchangedPolls += 1
        }
        updateClip(peak: AudioEngineManager.shared.consumePreLimiterPeak())
    }

    static func decayed(_ rms: Float, from level: Float) -> Float {
        let next = max(rms * 2.5, level * levelDecay)
        return next < levelFloor ? 0 : next
    }

    private func updateClip(peak: Float) {
        let now = ContinuousClock.now
        if peak >= 0.99 {
            clipClearAt = now.advanced(by: .seconds(1))
            if !isClipping { isClipping = true }
        } else if isClipping, now >= clipClearAt {
            isClipping = false
        }
    }
}
