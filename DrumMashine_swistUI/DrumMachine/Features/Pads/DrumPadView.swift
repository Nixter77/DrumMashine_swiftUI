import SwiftUI
// MARK: - Premium Drum Pad with Ripple Animation + Long Press for ADSR
struct DrumPadView: View {
    var pad: DrumPad
    var padIndex: Int
    var onTap: (Float) -> Void
    var onLongPress: (() -> Void)? = nil
    /// Sound menu shown from the ≡ icon and the right-click menu.
    var soundMenu: (() -> AnyView)? = nil
    
    @State private var isPressed: Bool = false
    @State private var rippleScale: CGFloat = 0
    @State private var rippleOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var isLongPressing: Bool = false
    @State private var longPressProgress: Double = 0
    
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
            VStack(spacing: 6) {
                Image(systemName: pad.iconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 34)
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
                
                // ADSR indicator (small dot if customized)
                if let soundMenu {
                    Menu {
                        soundMenu()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9))
                            .foregroundColor(ThemeStore.isLight ? Color.white.opacity(0.85) : padColor.opacity(0.75))
                            .padding(3)
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
        .scaleEffect(isPressed ? (ThemeStore.isLight ? 0.95 : 0.92) : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.5), value: isPressed)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke((ThemeStore.isLight ? Color.white : padColor).opacity(isPressed ? 0.9 : 0), lineWidth: 2)
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                        onTap(1.0)
                        
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
