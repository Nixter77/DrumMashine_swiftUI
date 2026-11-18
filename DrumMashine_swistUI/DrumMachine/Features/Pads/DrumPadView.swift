import AppKit
import SwiftUI
// MARK: - Premium Drum Pad with Ripple Animation + Long Press for ADSR
struct DrumPadView: View {
    var pad: DrumPad
    var padIndex: Int
    var onTap: (PadHit) -> Void
    /// Position, pressure, option, and shift. The default is fixed velocity 1.
    var resolveHit: (Double, Double, Double?, Bool, Bool) -> PadHit = { _, _, _, _, _ in
        PadHit(velocity: 1, accent: false)
    }
    var pressureEnabled: Bool = false
    var onLongPress: (() -> Void)? = nil
    /// Sound menu shown from the ≡ icon and the right-click menu.
    var soundMenu: (() -> AnyView)? = nil
    /// CUT_12: "C1"…"C4" from the track preset's choke group; nil hides the badge.
    var chokeBadge: String? = nil
    /// Live track preset name shown below the pad label.
    var presetName: String? = nil
    
    @State private var isPressed: Bool = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var isLongPressing: Bool = false
    @State private var longPressProgress: Double = 0
    @State private var velocityRing: Double = 0
    @State private var padHeight: CGFloat = 1
    
    private var padColor: Color {
        guard padIndex < AppTheme.padColors.count else { return pad.color }
        return AppTheme.padColors[padIndex]
    }
    
    var body: some View {
        ZStack {
            if ThemeStore.isLight {
                CandyFill(color: padColor, cornerRadius: 16, pressed: isPressed)
            } else {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    RadialGradient(
                        colors: [
                            padColor.opacity(isPressed ? 0.5 : 0.25),
                            padColor.opacity(isPressed ? 0.2 : 0.08)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    padColor.opacity(0.6),
                                    padColor.opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
            
            }

            RoundedRectangle(cornerRadius: 14)
                .fill(padColor.opacity(glowOpacity))
            
            // Long-press progress ring
            if isLongPressing {
                Circle()
                    .trim(from: 0, to: longPressProgress)
                    .stroke(padColor.opacity(0.8), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
                    .transition(.opacity)
            }
            
            // Ripple effect on tap
            Circle()
                .stroke(padColor.opacity(0.6), lineWidth: 2)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
            
            // Content
            VStack(spacing: 2) {
                Image(systemName: pad.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(
                        LinearGradient(
                            colors: ThemeStore.isLight
                                ? [Color.white, Color.white.opacity(0.85)]
                                : [padColor, padColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text(pad.name)
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let presetName, !presetName.isEmpty {
                    Text(presetName)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeStore.isLight ? Color.white.opacity(0.9) : AppTheme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                }
                
                // ADSR indicator (small dot if customized)
                if let soundMenu {
                    Menu {
                        soundMenu()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9))
                            .foregroundColor(ThemeStore.isLight ? Color.white.opacity(0.85) : padColor.opacity(0.75))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Выбрать звук")
                    .accessibilityIdentifier("pad.soundMenu.\(padIndex)")
                } else if onLongPress != nil {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 7))
                        .foregroundColor(ThemeStore.isLight ? Color.white.opacity(0.7) : padColor.opacity(0.5))
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let chokeBadge {
                Text(chokeBadge)
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .foregroundColor(ThemeStore.isLight ? Color.white : padColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(ThemeStore.isLight ? padColor.opacity(0.85) : AppTheme.surfaceElevated.opacity(0.85))
                    )
                    .overlay(Capsule().stroke(padColor.opacity(ThemeStore.isLight ? 0 : 0.5), lineWidth: 1))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("pad.chokeBadge.\(padIndex)")
            }
        }
        .scaleEffect(isPressed ? (ThemeStore.isLight ? 0.95 : 0.92) : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: isPressed)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke((ThemeStore.isLight ? Color.white : padColor).opacity(isPressed ? 0.9 : 0), lineWidth: 2)
        )
        .overlay {
            Circle()
                .stroke(padColor.opacity(velocityRing), lineWidth: 3)
                .padding(8)
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { padHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in padHeight = height }
            }
        }
        .overlay {
            if pressureEnabled {
                PressureCatcher { peak, y in
                    fire(y: y, height: Double(padHeight), pressure: peak)
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isPressed && !pressureEnabled {
                        isPressed = true
                        fire(y: Double(value.location.y), height: Double(padHeight), pressure: nil)
                        
                        // Trigger ripple animation
                        rippleScale = 0.3
                        rippleOpacity = 1
                        glowOpacity = 0.3
                        
                        withAnimation(.easeOut(duration: 0.5)) {
                            rippleScale = 1.4
                            rippleOpacity = 0
                        }
                        
                        withAnimation(.easeOut(duration: 0.1)) {
                            glowOpacity = 0.3
                        }
                        
                    }
                }
                .onEnded { _ in
                    isPressed = false
                    withAnimation(.easeOut(duration: 0.3)) {
                        glowOpacity = 0
                    }
                }
        )
        .contextMenu { soundMenu?() }
        // Long press for ADSR editor
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.6)
                .onChanged { _ in
                    withAnimation(.linear(duration: 0.6)) {
                        isLongPressing = true
                        longPressProgress = 1.0
                    }
                }
                .onEnded { _ in
                    isLongPressing = false
                    longPressProgress = 0
                    onLongPress?()
                }
        )
        .onChange(of: isLongPressing) { _, newVal in
            if !newVal { longPressProgress = 0 }
        }
    }
}

extension DrumPadView {
    private func fire(y: Double, height: Double, pressure: Double?) {
        isPressed = true
        let flags = NSEvent.modifierFlags
        let hit = resolveHit(
            y,
            height,
            pressure,
            flags.contains(.option),
            flags.contains(.shift)
        )
        velocityRing = Double(hit.velocity)
        withAnimation(.easeOut(duration: 0.15)) { velocityRing = 0 }
        onTap(hit)
    }

    func withHitResolver(_ resolver: @escaping (Double, Double, Double?, Bool, Bool) -> PadHit) -> DrumPadView {
        var copy = self
        copy.resolveHit = resolver
        return copy
    }

    func withPressure(_ enabled: Bool) -> DrumPadView {
        var copy = self
        copy.pressureEnabled = enabled
        return copy
    }

    /// Sets `chokeBadge` after the trailing-closure init.
    func withChokeBadge(_ badge: String?) -> DrumPadView {
        var copy = self
        copy.chokeBadge = badge
        return copy
    }

    /// Sets `presetName` after the trailing-closure init.
    func withPresetName(_ name: String?) -> DrumPadView {
        var copy = self
        copy.presetName = name
        return copy
    }
}

/// Collects Force Touch for 12 ms, then reports the peak. A mouse with no pressure reports nil.
private struct PressureCatcher: NSViewRepresentable {
    var onHit: (Double?, Double) -> Void

    func makeNSView(context: Context) -> PressureView {
        let view = PressureView()
        view.onHit = onHit
        return view
    }

    func updateNSView(_ nsView: PressureView, context: Context) {
        nsView.onHit = onHit
    }
}

private final class PressureView: NSView {
    var onHit: ((Double?, Double) -> Void)?
    private var samples: [(time: Double, pressure: Double)] = []
    private var armed = false

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let y = Double(bounds.height - local.y)
        samples = [(event.timestamp, Double(event.pressure))]
        armed = true
        let start = event.timestamp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            guard let self, self.armed else { return }
            self.armed = false
            let peak = PadVelocity.peakPressure(
                samples: self.samples.filter { $0.time <= start + 0.012 || $0.time >= start },
                window: 0.012
            )
            self.onHit?(peak, y)
        }
    }

    override func pressureChange(with event: NSEvent) {
        samples.append((event.timestamp, Double(event.pressure)))
    }
}
