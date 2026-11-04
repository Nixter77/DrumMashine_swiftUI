import Foundation

/// CUT_14: choke group a live pad tap passes to `AudioEngineManager.trigger`.
/// Same semantics as the sequencer: nil = Off (engine maps to -1).
nonisolated enum PadTriggerChoke {
    static func group(for preset: SoundPreset) -> Int? {
        preset.chokeGroup
    }
}
