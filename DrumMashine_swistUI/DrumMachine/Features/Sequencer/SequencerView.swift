import SwiftUI
struct SequencerView: View {
    @Bindable var sequencer: SequencerEngine
    
    init(sequencer: SequencerEngine) {
        self.sequencer = sequencer
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Clock and step count read the playhead. The step grid below does not.
            SequencerTopBar(sequencer: sequencer)
            
            Divider()
                .overlay(AppTheme.accent.opacity(0.12))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            
            // ── Step Number Header ──
            HStack(spacing: 4) {
                Color.clear.frame(width: AppLayout.sequencerTrackWidth)
                
                let activeSteps = sequencer.stepCount.rawValue
                let beatCount = activeSteps / 4
                
                ForEach(0..<beatCount, id: \.self) { beat in
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { sub in
                            let stepNum = beat * 4 + sub
                            Text("\(stepNum + 1)")
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                                .foregroundColor(sub == 0 ? AppTheme.textSecondary : AppTheme.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 2)
                    .overlay(
                        Rectangle()
                            .fill(AppTheme.accent.opacity(0.12))
                            .frame(width: 1)
                            .padding(.vertical, 2),
                        alignment: .leading
                    )
                }
                
                Color.clear.frame(width: AppLayout.sequencerMuteWidth)
                Color.clear.frame(width: AppLayout.sequencerVolumeWidth)
                Color.clear.frame(width: AppLayout.sequencerPanWidth)
            }
            .frame(height: 16)
            .padding(.horizontal, 8)
            
            Divider()
                .overlay(AppTheme.accent.opacity(0.08))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            
            // Rows shrink to the space under the header. The playhead stays inside the scroll.
            trackArea
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .elevatedGlassPanel()
    }

    /// Eight rows at 26…44 pt. Shorter than that, the same grid scrolls and the playhead scrolls with it.
    private var trackArea: some View {
        GeometryReader { proxy in
            let count = CGFloat(max(sequencer.tracks.count, 1))
            let gaps = CGFloat(max(sequencer.tracks.count - 1, 0)) * AppLayout.sequencerTrackSpacing
            let available = max(0, proxy.size.height - gaps)
            let fitted = min(AppLayout.sequencerRowMax, max(AppLayout.sequencerRowMin, floor(available / count)))
            ViewThatFits(in: .vertical) {
                trackGrid(rowHeight: fitted)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.vertical) {
                    trackGrid(rowHeight: AppLayout.sequencerRowMin)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private func trackGrid(rowHeight: CGFloat) -> some View {
        SequencerTracksView(sequencer: sequencer, rowHeight: rowHeight)
            .overlayPreferenceValue(StepColumnKey.self) { anchors in
                PlayheadOverlay(sequencer: sequencer, anchors: anchors)
            }
    }
}

// MARK: - Top bar (playhead clock). Kept out of the step grid.
struct SequencerTopBar: View {
    @Bindable var sequencer: SequencerEngine

    var body: some View {
        BeatClockView(
            currentStep: sequencer.currentStep,
            isPlaying: sequencer.isPlaying,
            stepCount: sequencer.stepCount
        )
        .overlay(
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    ForEach(StepCount.allCases, id: \.self) { sc in
                        Button(action: {
                            withAnimation(.spring(response: 0.2)) {
                                sequencer.stepCount = sc
                            }
                        }) {
                            Text(sc.label)
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundColor(sequencer.stepCount == sc ? AppTheme.accent : AppTheme.textTertiary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(sequencer.stepCount == sc ? AppTheme.accent.opacity(0.15) : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(sequencer.stepCount == sc ? AppTheme.accent.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 12)
            }
        )
    }
}

// MARK: - Track rows. This view does not read currentStep.
struct SequencerTracksView: View {
    @Bindable var sequencer: SequencerEngine
    var rowHeight: CGFloat

    var body: some View {
        VStack(spacing: AppLayout.sequencerTrackSpacing) {
            ForEach(sequencer.tracks.indices, id: \.self) { index in
                SequencerRowView(
                    track: $sequencer.tracks[index],
                    trackIndex: index,
                    stepCount: sequencer.stepCount.rawValue,
                    rowHeight: rowHeight
                )
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Reads the playhead so the grid that publishes the anchors does not.
struct PlayheadOverlay: View {
    var sequencer: SequencerEngine
    var anchors: [Int: [Anchor<CGRect>]]

    var body: some View {
        PlayheadCursor(
            anchors: anchors,
            step: sequencer.currentStep,
            isPlaying: sequencer.isPlaying
        )
    }
}

/// One column over the current step. Buttons publish their frames and do not read the playhead.
struct PlayheadCursor: View {
    var anchors: [Int: [Anchor<CGRect>]]
    var step: Int
    var isPlaying: Bool

    var body: some View {
        GeometryReader { proxy in
            if isPlaying, let column = anchors[step], !column.isEmpty {
                let rects = column.map { proxy[$0] }
                let minX = rects.map(\.minX).min() ?? 0
                let maxX = rects.map(\.maxX).max() ?? 0
                let minY = rects.map(\.minY).min() ?? 0
                let maxY = rects.map(\.maxY).max() ?? 0
                RoundedRectangle(cornerRadius: 4)
                    .stroke(AppTheme.hairline.opacity(0.9), lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(AppTheme.hairline.opacity(0.14)))
                    .frame(width: max(0, maxX - minX), height: max(0, maxY - minY))
                    .position(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

struct StepColumnKey: PreferenceKey {
    static var defaultValue: [Int: [Anchor<CGRect>]] = [:]

    static func reduce(
        value: inout [Int: [Anchor<CGRect>]],
        nextValue: () -> [Int: [Anchor<CGRect>]]
    ) {
        for (column, anchors) in nextValue() {
            value[column, default: []].append(contentsOf: anchors)
        }
    }
}

// MARK: - Sequencer Row
struct SequencerRowView: View {
    @Binding var track: SequencerTrack
    let trackIndex: Int
    let stepCount: Int
    var rowHeight: CGFloat = AppLayout.sequencerRowMax
    
    var body: some View {
        HStack(spacing: 4) {
            // ── Track Name ──
            HStack(spacing: 5) {
                Circle()
                    .fill(padColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: padColor.opacity(0.6), radius: 2)
                
                Button {
                    SoundEditorRouter.shared.trackIndex = trackIndex
                } label: {
                    Text(track.soundPreset.name)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundColor(track.isMuted ? AppTheme.textTertiary : AppTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("\(track.soundPreset.name) — edit sound")
                .accessibilityIdentifier("sequencer.editSound.\(trackIndex)")
            }
            .frame(width: AppLayout.sequencerTrackWidth, alignment: .leading)
            
            // ── Steps (grouped by beats) ──
            let beatCount = stepCount / 4
            
            ForEach(0..<beatCount, id: \.self) { beat in
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { sub in
                        let stepIndex = beat * 4 + sub
                        if stepIndex < track.steps.count {
                            StepButtonView(
                                step: $track.steps[stepIndex],
                                column: stepIndex,
                                trackIndex: trackIndex,
                                trackColor: padColor,
                                buttonHeight: rowHeight
                            )
                            .opacity(track.isMuted ? 0.35 : 1.0)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppTheme.hairline.opacity(0.02))
                )
            }
            
            // ── Mute / Solo ──
            HStack(spacing: 4) {
                Button(action: {
                    withAnimation(.spring(response: 0.2)) { track.isMuted.toggle() }
                }) {
                    Text("M")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(track.isMuted ? .white : AppTheme.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(track.isMuted ? AppTheme.accentMute : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(track.isMuted ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1))
                        .shadow(color: track.isMuted ? AppTheme.accentMute.opacity(0.5) : .clear, radius: 5)
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    withAnimation(.spring(response: 0.2)) { track.isSolo.toggle() }
                }) {
                    Text("S")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundColor(track.isSolo ? AppTheme.onAccent : AppTheme.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(track.isSolo ? AppTheme.accentWarning : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(track.isSolo ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1))
                        .shadow(color: track.isSolo ? AppTheme.accentWarning.opacity(0.5) : .clear, radius: 5)
                }
                .buttonStyle(.plain)
            }
            .frame(width: AppLayout.sequencerMuteWidth)
            
            // ── Volume Slider ──
            HStack(spacing: 4) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 9))
                    .foregroundColor(padColor.opacity(0.7))
                Slider(value: $track.volume, in: 0...1)
                    .tint(padColor.opacity(0.8))
                    .onChange(of: track.volume) { _, newVal in
                        AudioEngineManager.shared.setTrackVolume(newVal, trackIndex: trackIndex)
                    }
            }
            .frame(width: AppLayout.sequencerVolumeWidth)
            .opacity(track.isMuted ? 0.3 : 1.0)
            
            // ── Pan Slider ──
            HStack(spacing: 4) {
                Text("L")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                Slider(value: $track.pan, in: -1...1)
                    .tint(padColor.opacity(0.6))
                    .onChange(of: track.pan) { _, newVal in
                        AudioEngineManager.shared.setTrackPan(newVal, trackIndex: trackIndex)
                    }
                Text("R")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
            }
            .frame(width: AppLayout.sequencerPanWidth)
            .opacity(track.isMuted ? 0.3 : 1.0)
        }
        .frame(height: rowHeight)
        .fixedSize(horizontal: false, vertical: true)  // Prevents vertical drift
    }
    
    private var padColor: Color {
        guard trackIndex < AppTheme.padColors.count else { return AppTheme.accent }
        return AppTheme.padColors[trackIndex]
    }
}
