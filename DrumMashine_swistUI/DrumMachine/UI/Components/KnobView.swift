import SwiftUI
// MARK: - Premium Knob View (with value tooltip, color, double-tap reset)
struct KnobView: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var title: String = ""
    var color: Color = AppTheme.accent
    var size: CGFloat = 48
    var valueFormatter: ((Double) -> String)? = nil
    
    @State private var lastValue: Double = 0
    @State private var isDragging: Bool = false
    
    private var normalizedValue: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    
    private var angleForValue: Double {
        135.0 + normalizedValue * 270.0
    }
    
    private var displayString: String {
        if let fmt = valueFormatter { return fmt(value) }
        if range.upperBound <= 1.01 {
            return "\(Int(normalizedValue * 100))%"
        }
        return String(format: "%.2f", value)
    }
    
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                GeometryReader { geo in
                    let sz = min(geo.size.width, geo.size.height)
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                    let radius = sz / 2
                    let angle = angleForValue
                    
                    ZStack {
                        // Outer ring glow when dragging
                        if isDragging {
                            Circle()
                                .stroke(color.opacity(0.25), lineWidth: 3)
                                .frame(width: sz + 6, height: sz + 6)
                                .blur(radius: 4)
                                .position(center)
                        }
                        
                        // Background circle with gradient
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [AppTheme.surfaceElevated, AppTheme.surface],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: sz / 2
                                )
                            )
                            .frame(width: sz, height: sz)
                            .position(center)
                            .shadow(color: .black.opacity(ThemeStore.isLight ? 0.12 : 0.4), radius: 4, y: 3)
                        
                        // Background arc track
                        Path { path in
                            path.addArc(
                                center: center,
                                radius: radius - 5,
                                startAngle: .degrees(135),
                                endAngle: .degrees(405),
                                clockwise: false
                            )
                        }
                        .stroke(AppTheme.hairline.opacity(0.07), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        
                        // Value arc (colored gradient)
                        Path { path in
                            path.addArc(
                                center: center,
                                radius: radius - 5,
                                startAngle: .degrees(135),
                                endAngle: .degrees(angle),
                                clockwise: false
                            )
                        }
                        .stroke(
                            AngularGradient(
                                colors: [color.opacity(0.6), color],
                                center: .center,
                                startAngle: .degrees(135),
                                endAngle: .degrees(405)
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .shadow(color: color.opacity(0.4), radius: 3)
                        
                        // Inner circle (knob face): brushed silver in Studio Light
                        Circle()
                            .fill(ThemeStore.isLight
                                  ? AnyShapeStyle(AngularGradient(
                                        colors: [Color(hex: "F4F4F6"), Color(hex: "B9BBC2"), Color(hex: "EDEDF0"),
                                                 Color(hex: "A9ABB3"), Color(hex: "F4F4F6")],
                                        center: .center))
                                  : AnyShapeStyle(AppTheme.surfacePanel))
                            .overlay(Circle().stroke(Color.white.opacity(ThemeStore.isLight ? 0.9 : 0), lineWidth: 1))
                            .shadow(color: .black.opacity(ThemeStore.isLight ? 0.18 : 0), radius: 2, y: 1)
                            .frame(width: sz * 0.58, height: sz * 0.58)
                            .position(center)
                        
                        // Indicator line
                        Path { path in
                            let innerR = radius * 0.28
                            let outerR = radius * 0.46
                            let rad = Angle.degrees(angle).radians
                            path.move(to: CGPoint(
                                x: center.x + cos(rad) * innerR,
                                y: center.y + sin(rad) * innerR
                            ))
                            path.addLine(to: CGPoint(
                                x: center.x + cos(rad) * outerR,
                                y: center.y + sin(rad) * outerR
                            ))
                        }
                        .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .shadow(color: color.opacity(0.6), radius: 2)
                        
                        // Value overlay when dragging
                        if isDragging {
                            Text(displayString)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(AppTheme.textPrimary)
                                .position(center)
                                .transition(.opacity)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                if !isDragging {
                                    isDragging = true
                                    lastValue = value
                                }
                                let sensitivity = 0.004
                                let delta = -Double(gesture.translation.height) * sensitivity
                                value = min(
                                    max(lastValue + delta * (range.upperBound - range.lowerBound),
                                        range.lowerBound),
                                    range.upperBound
                                )
                            }
                            .onEnded { _ in
                                lastValue = value
                                withAnimation(.easeOut(duration: 0.15)) { isDragging = false }
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Double-tap resets to midpoint
                        withAnimation(.spring(response: 0.3)) {
                            value = range.lowerBound + (range.upperBound - range.lowerBound) / 2.0
                            lastValue = value
                        }
                    }
                    .onAppear { lastValue = value }
                }
                .frame(width: size, height: size)
            }
            
            if !title.isEmpty {
                Text(title)
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .foregroundColor(isDragging ? color : AppTheme.textTertiary)
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        KnobView(value: .constant(0.3), title: "MIX", color: Color(hex: "BF5AF2"))
        KnobView(value: .constant(0.7), title: "TIME", color: AppTheme.accentSecondary)
        KnobView(value: .constant(0.5), title: "DRIVE", color: AppTheme.accent)
    }
    .padding(30)
    .background(AppTheme.background)
}
