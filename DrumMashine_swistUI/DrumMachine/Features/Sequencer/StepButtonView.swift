import SwiftUI
// MARK: - Step Button with Velocity Editing & Per-Track Color
// NOTE: GeometryReader was removed — it caused layout drift in HStack rows.
// Fixed height (36pt) + overlay-based velocity bar is stable and predictable.
struct StepButtonView: View {
    @Binding var step: SequencerStep
    /// Column index. Used only to publish this button's frame for the playhead cursor.
    var column: Int
    var trackIndex: Int = 0
    var trackColor: Color = AppTheme.accent
    /// Matches the row. Short windows shrink the step instead of clipping it.
    var buttonHeight: CGFloat = 36
    var articulations: [ArticulationSpec] = []

    @State private var isDraggingVelocity = false
    @State private var startVelocity: Float = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if ThemeStore.isLight {
                // Studio Light: empty cell, or a glossy "jelly" block in the row colour.
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 2, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall + 2, style: .continuous)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                if step.isActive {
                    CandyFill(color: trackColor, cornerRadius: AppTheme.cornerRadiusSmall + 2, glow: 0)
                        .opacity(0.45 + 0.55 * Double(step.velocity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step.velocity)
                }
            } else {
            // ── Background ──
            RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                .fill(
                    step.isActive
                        ? trackColor.opacity(0.15)
                        : AppTheme.inactiveStep
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                        .stroke(
                            step.isActive ? trackColor.opacity(0.4) : Color.clear,
                            lineWidth: 1
                        )
                )

            // ── Velocity Fill Bar ──
            // Uses proportional height via frame — no GeometryReader needed
            if step.isActive {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadiusSmall)
                    .fill(
                        LinearGradient(
                            colors: [
                                trackColor.opacity(0.95),
                                trackColor.opacity(0.5)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: buttonHeight * CGFloat(step.velocity))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: step.velocity)
            }
            }

            // ── Velocity Tooltip (shown during drag) ──
            if isDraggingVelocity {
                Text("\(Int(step.velocity * 127))")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    // Fixed offset above the button — no GeometryReader needed
                    .offset(y: -(buttonHeight / 2 + 16))
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(10)
            }
        }
        // Fixed frame — the single source of truth for this button's size
        .frame(height: buttonHeight)
        .overlay(alignment: .topTrailing) {
            if step.isActive && step.probability < 0.999 {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 4, height: 4)
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            if step.accent == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.accentWarning)
                    .padding(2)
                    .background(Circle().fill(AppTheme.surface.opacity(0.9)))
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            let mark = VelocityLane.letter(articulation: step.articulation, specs: articulations)
            if !mark.isEmpty {
                Text(mark)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .padding(.horizontal, 2)
                    .background(Capsule().fill(AppTheme.surface.opacity(0.9)))
                    .padding(.bottom, 2)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(step.isActive ? 1.0 : 0.88)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: step.isActive)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("seq.step.\(trackIndex).\(column)")
        .accessibilityValue(step.isActive ? "on" : "off")
        .accessibilityLabel("Step \(trackIndex + 1) \(column + 1)")
        .accessibilityAddTraits(.isButton)
        .anchorPreference(key: StepColumnKey.self, value: .bounds) { [column: [trackIndex: $0]] }
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                step.isActive.toggle()
                if step.isActive && step.velocity < 0.1 {
                    step.velocity = 0.8
                }
            }
        }
        // Long press + drag for velocity editing
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    switch value {
                    case .second(true, let drag):
                        if !isDraggingVelocity {
                            isDraggingVelocity = true
                            startVelocity = step.velocity
                        }
                        if let drag = drag {
                            // Vertical drag: up = louder, down = softer
                            let delta = Float(-drag.translation.height) / 120.0
                            step.velocity = max(0.05, min(1.0, startVelocity + delta))
                        }
                    default:
                        break
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        isDraggingVelocity = false
                    }
                }
        )
        .contextMenu {
            stepContextMenu
        }
    }

    private var articulationChoices: [String] {
        if articulations.isEmpty { return ["Default"] }
        return articulations.enumerated().map { index, spec in
            if let name = spec.name, !name.isEmpty { return name }
            return index == 0 ? "Default" : "\(index)"
        }
    }

    @ViewBuilder
    private var stepContextMenu: some View {
        Menu("Velocity") {
            ForEach([100, 80, 50, 25], id: \.self) { percent in
                let value = Float(percent) / 100.0
                Button {
                    step.isActive = true
                    step.velocity = value
                } label: {
                    if step.isActive && abs(step.velocity - value) < 0.02 {
                        Label("\(percent)%", systemImage: "checkmark")
                    } else {
                        Text("\(percent)%")
                    }
                }
            }
        }
        Menu("Probability") {
            ForEach([100, 75, 50, 25, 10], id: \.self) { percent in
                let value = Float(percent) / 100.0
                Button {
                    step.probability = value
                } label: {
                    if abs(step.probability - value) < 0.02 {
                        Label("\(percent)%", systemImage: "checkmark")
                    } else {
                        Text("\(percent)%")
                    }
                }
            }
        }
        Button(step.accent == true ? "Accent On" : "Accent") {
            step = VelocityLane.setAccent([step], index: 0, on: step.accent != true)[0]
        }
        Menu("Articulation") {
            ForEach(Array(articulationChoices.enumerated()), id: \.offset) { index, name in
                Button {
                    step = VelocityLane.setArticulation([step], index: 0, articulation: index)[0]
                } label: {
                    let current = step.articulation ?? 0
                    if current == index {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        }
        Button("Ghost 0.35") {
            step = VelocityLane.ghost([step], index: 0)[0]
        }
        Divider()
        Button("Clear Step") {
            step.isActive = false
        }
        .disabled(!step.isActive)
    }
}
