import SwiftUI

// MARK: - Audio Visualizer (Real FFT spectrum + waveform from AVAudioEngine)
struct AudioVisualizerView: View {
    private let meters = MeterModel.shared
    @State private var displayMode: VisualizerMode = .spectrum

    enum VisualizerMode: String, CaseIterable {
        case spectrum = "SPECTRUM"
        case waveform = "WAVEFORM"
    }

    var body: some View {
        ZStack {
            // Mode switcher (top-right)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    ForEach(VisualizerMode.allCases, id: \.self) { mode in
                        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { displayMode = mode } }) {
                            Text(mode.rawValue)
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(displayMode == mode ? AppTheme.accent : AppTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(displayMode == mode ? AppTheme.accent.opacity(0.15) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)

                Spacer()
            }

            // Main visualization. The canvas reads the latest frame on its own clock.
            Group {
                if displayMode == .spectrum {
                    SpectrumCanvas()
                } else {
                    WaveformCanvas()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .padding(.bottom, 24)

            VStack {
                Spacer()
                VUMetersCanvas()
                    .frame(height: 8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .glassPanel()
        .onAppear { meters.start() }
        .onDisappear { meters.stop() }
    }
}

/// Draws the latest spectrum. MeterModel publishes, not a spring on each bar or a timeline.
private struct SpectrumCanvas: View {
    var body: some View {
        // Read in body: Observation redraws only when the model publishes a new frame.
        let bands = MeterModel.shared.display.bands
        Canvas { context, size in
                drawSpectrumGrid(context: &context, size: size)
                let count = bands.count
                guard count > 0, size.width > 1, size.height > 1 else { return }
                let slot = size.width / CGFloat(count)
                let barWidth = slot * 0.7
                for index in 0..<count {
                    let value = CGFloat(min(1, max(0, bands[index])))
                    let barHeight = max(2, value * size.height)
                    let x = slot * CGFloat(index) + (slot - barWidth) / 2
                    let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth, height: barHeight)
                    let hue = Double(index) / Double(count) * 0.5 + 0.55
                    let color = Color(hue: hue, saturation: 0.9, brightness: 0.95)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                }
            }
    }
}

private struct WaveformCanvas: View {
    var body: some View {
        let samples = MeterModel.shared.display.waveform
        Canvas { context, size in
                var axis = Path()
                axis.move(to: CGPoint(x: 0, y: size.height / 2))
                axis.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(axis, with: .color(AppTheme.hairline.opacity(0.1)), lineWidth: 1)

                guard samples.count > 1 else { return }
                var path = Path()
                let amplitude = size.height * 0.4
                let mid = size.height / 2
                let span = CGFloat(samples.count - 1)
                for (index, sample) in samples.enumerated() {
                    let x = size.width * CGFloat(index) / span
                    let y = mid - CGFloat(sample) * amplitude
                    let point = CGPoint(x: x, y: y)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(AppTheme.accent), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
    }
}

private struct VUMetersCanvas: View {
    var body: some View {
        let display = MeterModel.shared.display
        Canvas { context, size in
                let gap: CGFloat = 8
                let label: CGFloat = 14
                let meterWidth = max(1, (size.width - label * 2 - gap * 3) / 2)
                drawVULabel("L", at: CGPoint(x: label / 2, y: size.height / 2), context: &context)
                drawVU(
                    level: display.levelL,
                    rect: CGRect(x: label + gap, y: 0, width: meterWidth, height: size.height),
                    context: &context
                )
                let rightLabelX = label + gap + meterWidth + gap + label / 2
                drawVULabel("R", at: CGPoint(x: rightLabelX, y: size.height / 2), context: &context)
                drawVU(
                    level: display.levelR,
                    rect: CGRect(x: rightLabelX + label / 2 + gap, y: 0, width: meterWidth, height: size.height),
                    context: &context
                )
            }
    }
}

private func drawSpectrumGrid(context: inout GraphicsContext, size: CGSize) {
    var path = Path()
    for level in [0.25, 0.5, 0.75] as [CGFloat] {
        let y = size.height * (1 - level)
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
    }
    context.stroke(path, with: .color(AppTheme.hairline.opacity(0.05)), lineWidth: 0.5)
}

private func drawVULabel(_ text: String, at point: CGPoint, context: inout GraphicsContext) {
    context.draw(
        Text(text)
            .font(.system(.caption2, design: .monospaced))
            .foregroundColor(AppTheme.textTertiary),
        at: point
    )
}

private func drawVU(level: Float, rect: CGRect, context: inout GraphicsContext) {
    let clamped = CGFloat(min(1, max(0, level)))
    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(AppTheme.hairline.opacity(0.05)))
    guard clamped > 0 else { return }
    var clip = context
    let filled = CGRect(x: rect.minX, y: rect.minY, width: max(1, rect.width * clamped), height: rect.height)
    clip.clip(to: Path(roundedRect: filled, cornerRadius: 2))
    clip.fill(
        Path(roundedRect: rect, cornerRadius: 2),
        with: .linearGradient(
            Gradient(colors: [AppTheme.accentSuccess, Color(hex: "FFD60A"), AppTheme.accentMute]),
            startPoint: CGPoint(x: rect.minX, y: rect.midY),
            endPoint: CGPoint(x: rect.maxX, y: rect.midY)
        )
    )
}
