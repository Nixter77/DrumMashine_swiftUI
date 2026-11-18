import AppKit
import SwiftUI

struct LaneBarFrames: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Bars under the selected track. Height is velocity, accent is brighter, a dot marks a ghost.
struct VelocityLaneStrip: View {
    @Binding var track: SequencerTrack
    let trackIndex: Int
    let stepCount: Int
    var trackColor: Color
    var sequencer: SequencerEngine
    @Environment(\.undoManager) private var undoManager
    @State private var frames: [Int: CGRect] = [:]
    @State private var dragBefore: [SequencerTrack]?

    var body: some View {
        let beatCount = stepCount / 4
        HStack(spacing: 4) {
            Text("VEL")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: AppLayout.sequencerTrackWidth, alignment: .leading)

            ForEach(0..<beatCount, id: \.self) { beat in
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { sub in
                        let stepIndex = beat * 4 + sub
                        if stepIndex < track.steps.count {
                            bar(stepIndex)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Color.clear.frame(width: AppLayout.sequencerMuteWidth)
            Color.clear.frame(width: AppLayout.sequencerVolumeWidth)
            Color.clear.frame(width: AppLayout.sequencerPanWidth)
        }
        .frame(height: 28)
        .simultaneousGesture(drag)
        .coordinateSpace(name: "velocityLane")
        .onPreferenceChange(LaneBarFrames.self) { frames = $0 }
    }

    private func bar(_ index: Int) -> some View {
        let step = track.steps[index]
        let accent = step.accent == true
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(AppTheme.inactiveStep)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(trackColor.opacity(accent ? 1 : (step.isActive ? 0.72 : 0.4)))
                .frame(height: max(2, 24 * CGFloat(min(1, max(0, step.velocity)))))
            if VelocityLane.isGhostMark(step.velocity) {
                Circle()
                    .fill(AppTheme.surface)
                    .frame(width: 5, height: 5)
                    .overlay(Circle().fill(AppTheme.textPrimary).frame(width: 3, height: 3))
                    .padding(.bottom, 1)
            }
        }
        .overlay(alignment: .top) {
            if accent {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.top, 1)
            }
        }
        .overlay {
            if accent {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(AppTheme.textPrimary.opacity(0.85), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: LaneBarFrames.self,
                    value: [index: geo.frame(in: .named("velocityLane"))]
                )
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("seq.velocityLane.\(trackIndex).\(index)")
        .accessibilityLabel("Velocity \(trackIndex + 1) \(index + 1)")
        .accessibilityValue(String(format: "%.2f", step.velocity))
        .onTapGesture(count: 2) {
            sequencer.applyVelocityLane(track: trackIndex, name: "Velocity", undoManager: undoManager) { steps, _ in
                steps = VelocityLane.setDefault(steps, index: index)
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("velocityLane"))
            .onChanged { value in
                guard sequencer.tracks.indices.contains(trackIndex),
                      let index = index(at: value.location) else { return }
                if dragBefore == nil { dragBefore = sequencer.tracks }
                let option = NSEvent.modifierFlags.contains(.option)
                let next = VelocityLane.paint(
                    sequencer.tracks[trackIndex].steps,
                    index: index,
                    velocity: velocity(at: value.location, index: index),
                    activeOnly: option
                )
                guard next != sequencer.tracks[trackIndex].steps else { return }
                sequencer.tracks[trackIndex].steps = next
            }
            .onEnded { _ in
                if let before = dragBefore {
                    sequencer.registerTrackSwap(undoManager: undoManager, tracks: before, name: "Velocity")
                }
                dragBefore = nil
            }
    }

    private func index(at point: CGPoint) -> Int? {
        if let hit = frames.first(where: { $0.value.minX <= point.x && point.x <= $0.value.maxX }) {
            return hit.key
        }
        return frames.min(by: { abs($0.value.midX - point.x) < abs($1.value.midX - point.x) })?.key
    }

    private func velocity(at point: CGPoint, index: Int) -> Float {
        guard let rect = frames[index], rect.height > 1 else { return VelocityLane.resetVelocity }
        let y = min(max(0, point.y - rect.minY), rect.height)
        return Float(1 - y / rect.height)
    }
}
