import SwiftUI

// MARK: - Beat Clock View (animated beat indicator above sequencer)
struct BeatClockView: View {
    var currentStep: Int
    var isPlaying: Bool
    var stepCount: StepCount
    
    // 4 beats, each beat = 4 steps
    private var currentBeat: Int { currentStep / 4 }
    private var totalBeats: Int { stepCount.rawValue / 4 }
    
    var body: some View {
        HStack(spacing: 0) {
            // Beat indicators
            HStack(spacing: 6) {
                ForEach(0..<totalBeats, id: \.self) { beat in
                    BeatDot(
                        beat: beat,
                        currentBeat: currentBeat,
                        isPlaying: isPlaying,
                        totalBeats: totalBeats
                    )
                }
            }
            
            Spacer()
            
            // Step count selector
            HStack(spacing: 4) {
                Text("STEPS")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(AppTheme.textTertiary)
                
                ForEach(StepCount.allCases, id: \.self) { sc in
                    Text(sc.label)
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundColor(stepCount == sc ? AppTheme.accent : AppTheme.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(stepCount == sc ? AppTheme.accent.opacity(0.15) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(stepCount == sc ? AppTheme.accent.opacity(0.4) : Color.gray.opacity(0.2), lineWidth: 1)
                                )
                        )
                        // NOTE: stepCount is passed in as read-only for display;
                        // actual changes are driven by the parent via onStepCountChange
                }
            }
        }
        .frame(height: 32)  // Fixed height — pulse ring animation must not shift layout
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Individual Beat Dot
struct BeatDot: View {
    let beat: Int
    let currentBeat: Int
    let isPlaying: Bool
    let totalBeats: Int
    
    private var isActive: Bool { isPlaying && beat == currentBeat }
    
    // Colour cycles through 4 beat colours
    private var beatColor: Color {
        let colors: [Color] = [
            AppTheme.accent,
            AppTheme.accentSecondary,
            Color(hex: "30D158"),
            Color(hex: "BF5AF2")
        ]
        return colors[beat % colors.count]
    }
    
    var body: some View {
        ZStack {
            // The old pulse ring was always opacity 0 (never visible) but ran a repeatForever
            // animation on every beat. Keep its 22 pt footprint so the layout is unchanged.
            if isActive {
                Color.clear
                    .frame(width: 22, height: 22)
                    .scaleEffect(1.4)
            }
            
            Circle()
                .fill(isActive ? beatColor : AppTheme.hairline.opacity(0.08))
                .frame(width: 14, height: 14)
                .shadow(color: isActive ? beatColor.opacity(0.7) : .clear, radius: 6)
                .overlay(
                    Circle()
                        .stroke(isActive ? beatColor.opacity(0.5) : AppTheme.hairline.opacity(0.1), lineWidth: 1)
                )
            
            // Beat number
            Text("\(beat + 1)")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundColor(isActive ? .white : AppTheme.textTertiary)
        }
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isActive)
    }
}
