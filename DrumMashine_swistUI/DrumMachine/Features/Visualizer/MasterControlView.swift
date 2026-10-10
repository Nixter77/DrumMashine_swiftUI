import SwiftUI
// MARK: - Master Control View (master volume + limiter + output meter)
struct MasterControlView: View {
    private let meters = MeterModel.shared

    private var masterVolume: Binding<Double> {
        Binding(
            get: { Double(AudioEngineManager.shared.masterVolume) },
            set: { AudioEngineManager.shared.masterVolume = Float($0) }
        )
    }

    private var limiterEnabled: Bool {
        AudioEngineManager.shared.limiterEnabled
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Master Volume Knob
            VStack(spacing: 4) {
                KnobView(
                    value: masterVolume,
                    range: 0...1,
                    title: "MASTER",
                    color: AppTheme.accentSuccess,
                    size: 52,
                    valueFormatter: { "\(Int($0 * 100))%" }
                )
            }
            
            // Output meters + limiter
            VStack(alignment: .leading, spacing: 6) {
                // Limiter toggle
                HStack(spacing: 6) {
                    Button(action: {
                        AudioEngineManager.shared.limiterEnabled.toggle()
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(limiterEnabled ? AppTheme.accentSuccess : Color.gray.opacity(0.3))
                                .frame(width: 7, height: 7)
                            Text("LIMITER")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundColor(limiterEnabled ? AppTheme.accentSuccess : AppTheme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Clip indicator
                    Text("CLIP")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(meters.isClipping ? AppTheme.accentMute : AppTheme.textTertiary.opacity(0.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(meters.isClipping ? AppTheme.accentMute.opacity(0.2) : Color.clear)
                        )
                }
                
                // Stereo output meters
                OutputMetersCanvas()
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .glassPanel(cornerRadius: AppTheme.cornerRadiusButton)
        .onAppear {
            meters.start()
        }
        .onDisappear { meters.stop() }
    }
}

/// Stereo LED meters. One canvas, redrawn with the meter clock.
private struct OutputMetersCanvas: View {
    var body: some View {
        let display = MeterModel.shared.display
        Canvas { context, size in
                let row = (size.height - 3) / 2
                drawOutputMeter(label: "L", level: display.rmsL, rect: CGRect(x: 0, y: 0, width: size.width, height: row), context: &context)
                drawOutputMeter(label: "R", level: display.rmsR, rect: CGRect(x: 0, y: row + 3, width: size.width, height: row), context: &context)
            }
    }
}

private func drawOutputMeter(label: String, level: Float, rect: CGRect, context: inout GraphicsContext) {
    context.draw(
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(AppTheme.textTertiary),
        at: CGPoint(x: rect.minX + 5, y: rect.midY)
    )
    let segments = 20
    let originX = rect.minX + 14
    let width = max(1, rect.width - 14)
    let gap: CGFloat = 1.5
    let segmentWidth = (width - gap * CGFloat(segments - 1)) / CGFloat(segments)
    for index in 0..<segments {
        let threshold = Float(index) / Float(segments)
        let lit = level > threshold
        let color: Color
        if !lit {
            color = AppTheme.hairline.opacity(0.06)
        } else if index >= Int(Float(segments) * 0.85) {
            color = AppTheme.accentMute
        } else if index >= Int(Float(segments) * 0.65) {
            color = AppTheme.accentWarning
        } else {
            color = AppTheme.accentSuccess
        }
        let x = originX + CGFloat(index) * (segmentWidth + gap)
        let segment = CGRect(x: x, y: rect.minY, width: max(1, segmentWidth), height: rect.height)
        context.fill(Path(roundedRect: segment, cornerRadius: 1), with: .color(color))
    }
}

// MARK: - Output Meter Bar (segmented LED style)
struct OutputMeterBar: View {
    var level: Float
    let label: String
    
    private let segments = 20
    
    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(AppTheme.textTertiary)
                .frame(width: 10)
            
            HStack(spacing: 1.5) {
                ForEach(0..<segments, id: \.self) { i in
                    let threshold = Float(i) / Float(segments)
                    let isLit = level > threshold
                    let isRed = i >= Int(Float(segments) * 0.85)
                    let isYellow = i >= Int(Float(segments) * 0.65)
                    
                    RoundedRectangle(cornerRadius: 1)
                        .fill(
                            isLit
                                ? (isRed ? AppTheme.accentMute : (isYellow ? AppTheme.accentWarning : AppTheme.accentSuccess))
                                : AppTheme.hairline.opacity(0.06)
                        )
                        .frame(height: 6)
                }
            }
        }
    }
}
