import Foundation

/// CUT_10: which rows flash when the playhead lands on a column.
/// Same audibility rule as SequencerScheduler: muted rows never sound; if any row is solo, only solo rows do.
nonisolated enum StepFlash {
    static func flashedRows(tracks: [SequencerTrack], step: Int) -> [Int] {
        guard step >= 0 else { return [] }
        let hasSolo = tracks.contains { $0.isSolo }
        return tracks.indices.filter { i in
            let t = tracks[i]
            guard step < t.steps.count, t.steps[step].isActive else { return false }
            if t.isMuted { return false }
            if hasSolo && !t.isSolo { return false }
            return true
        }
    }
}
