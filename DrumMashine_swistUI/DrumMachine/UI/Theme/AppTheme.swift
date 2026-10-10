import SwiftUI

// MARK: - Premium App Theme
// Every token returns the original dark value unless Studio Light is chosen.
struct AppTheme {
    /// Tokens are built once per theme. Before, every access parsed a hex string, and step, pad
    /// and knob bodies read several tokens on each redraw.
    enum Dark {
        static let backgroundDeep = Color(hex: "060609")
        static let background = Color(hex: "0E0E14")
        static let surface = Color(hex: "1A1A22")
        static let surfaceElevated = Color(hex: "242430")
        static let surfacePanel = Color(hex: "2C2C38")
        static let inactiveStep = Color(hex: "22222C")
        static let accent = Color(hex: "FF6B35")
        static let accentSuccess = Color(hex: "30D158")
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.4)
        static let hairline = Color.white
        static let onAccent = Color.black
        static let shadowColor = Color.black.opacity(0.4)
    }

    enum Light {
        static let backgroundDeep = Color(hex: "EDE6DC")
        static let background = Color(hex: "F4EFE8")
        static let surface = Color(hex: "FBF9F6")
        static let surfaceElevated = Color(hex: "FFFFFF")
        static let surfacePanel = Color(hex: "F1ECE5")
        static let inactiveStep = Color(hex: "ECE7E0")
        static let accent = Color(hex: "FF7A2F")
        static let accentSuccess = Color(hex: "2DBE4E")
        static let textPrimary = Color(hex: "2B2B30")
        static let textSecondary = Color(hex: "2B2B30").opacity(0.72)
        static let textTertiary = Color(hex: "2B2B30").opacity(0.45)
        static let hairline = Color(hex: "2B2B30")
        static let onAccent = Color.white
        static let shadowColor = Color.black.opacity(0.10)
    }

    // MARK: - Backgrounds (multi-layered for depth)
    static var backgroundDeep: Color { ThemeStore.isLight ? Light.backgroundDeep : Dark.backgroundDeep }
    static var background: Color { ThemeStore.isLight ? Light.background : Dark.background }
    static var surface: Color { ThemeStore.isLight ? Light.surface : Dark.surface }
    static var surfaceElevated: Color { ThemeStore.isLight ? Light.surfaceElevated : Dark.surfaceElevated }
    static var surfacePanel: Color { ThemeStore.isLight ? Light.surfacePanel : Dark.surfacePanel }

    // MARK: - Legacy compat
    static var inactiveStep: Color { ThemeStore.isLight ? Light.inactiveStep : Dark.inactiveStep }

    // MARK: - Accent Colors (rich palette)
    static var accent: Color { ThemeStore.isLight ? Light.accent : Dark.accent }
    static let accentSecondary = Color(hex: "0A84FF")
    static let accentBlue = Color(hex: "0A84FF")
    static let accentTertiary = Color(hex: "FF2D55")
    static var accentSuccess: Color { ThemeStore.isLight ? Light.accentSuccess : Dark.accentSuccess }
    static let accentWarning = Color(hex: "FFD60A")
    static let accentMute = Color(hex: "FF453A")

    // MARK: - Text Colors
    static var textPrimary: Color { ThemeStore.isLight ? Light.textPrimary : Dark.textPrimary }
    static var textSecondary: Color { ThemeStore.isLight ? Light.textSecondary : Dark.textSecondary }
    static var textTertiary: Color { ThemeStore.isLight ? Light.textTertiary : Dark.textTertiary }

    /// Base colour for faint fills, strokes and dividers (white on dark, graphite on light).
    static var hairline: Color { ThemeStore.isLight ? Light.hairline : Dark.hairline }
    /// Text drawn on top of an accent-filled capsule.
    static var onAccent: Color { ThemeStore.isLight ? Light.onAccent : Dark.onAccent }

    // MARK: - Corner Radii
    static var cornerRadiusSection: CGFloat { ThemeStore.isLight ? 18 : 16 }
    static let cornerRadiusButton: CGFloat = 8
    static let cornerRadiusSmall: CGFloat = 6

    // MARK: - Shadows
    static var shadowColor: Color { ThemeStore.isLight ? Light.shadowColor : Dark.shadowColor }
    static var shadowRadius: CGFloat { ThemeStore.isLight ? 14 : 8 }
    static var shadowY: CGFloat { ThemeStore.isLight ? 6 : 4 }

    // MARK: - Gradients
    private static let accentGradientEnd = Color(hex: "FF8F5E")
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentGradientEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let blueGradient = LinearGradient(
        colors: [Color(hex: "0A84FF"), Color(hex: "5AC8FA")], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static var surfaceGradient: LinearGradient {
        LinearGradient(colors: [surface, surfaceElevated], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Pad Colors (each pad gets a unique gradient)
    static var padColors: [Color] { ThemeStore.isLight ? lightPadColors : darkPadColors }

    static let darkPadColors: [Color] = [
        Color(hex: "FF453A"),  // Kick - Red
        Color(hex: "FFD60A"),  // Snare - Yellow
        Color(hex: "30D158"),  // HiHat - Green
        Color(hex: "5AC8FA"),  // Clap - Cyan
        Color(hex: "0A84FF"),  // Tom - Blue
        Color(hex: "BF5AF2"),  // Ride - Purple
        Color(hex: "FF6B35"),  // Crash - Orange
        Color(hex: "FF375F"),  // Perc - Pink
    ]

    /// Candy colours from the Studio Light reference.
    static let lightPadColors: [Color] = [
        Color(hex: "F2362B"), Color(hex: "FFC81A"), Color(hex: "34C24A"), Color(hex: "3EA8F5"),
        Color(hex: "1F7BF2"), Color(hex: "9B4DEB"), Color(hex: "F27A1A"), Color(hex: "EF2D4B"),
    ]
}

// MARK: - Glassmorphism View Modifier
struct GlassmorphismModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.cornerRadiusSection
    var borderOpacity: Double = 0.15

    func body(content: Content) -> some View {
        content
            .background(Self.fill(cornerRadius: cornerRadius))
            .overlay(Self.border(cornerRadius: cornerRadius, borderOpacity: borderOpacity))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    static func fill(cornerRadius: CGFloat) -> some View {
        ZStack {
            // Subtle gradient overlay
            LinearGradient(
                colors: ThemeStore.isLight
                    ? [Color.white.opacity(0.95), Color.white.opacity(0.70)]
                    : [Color.white.opacity(0.08), Color.white.opacity(0.03)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Frosted glass effect
            AppTheme.surface.opacity(ThemeStore.isLight ? 0.75 : 0.85)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    static func border(cornerRadius: CGFloat, borderOpacity: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                LinearGradient(
                    colors: ThemeStore.isLight
                        ? [Color.white, Color.black.opacity(0.06)]
                        : [Color.white.opacity(borderOpacity), Color.white.opacity(0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Multi-Level Shadow Modifier
struct ElevatedShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(ThemeStore.isLight ? 0.06 : 0.3), radius: 8, y: 4)
            .shadow(color: .black.opacity(ThemeStore.isLight ? 0.08 : 0.15), radius: 24, y: 12)
    }
}

/// `glassPanel()` + `elevatedShadow()` with the shadows cast by the glass fill alone.
/// A shadow on the whole panel made SwiftUI re-rasterise the panel and run two blurs every time
/// anything inside changed; on the sequencer that is every playhead step. The glass fill never
/// changes, so its shadow is drawn once. The fill is the same shape and alpha that cast the shadow
/// before, so the shadow looks the same, including the part seen through the translucent fill.
struct ElevatedGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = AppTheme.cornerRadiusSection

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        content
            .clipShape(shape)
            .background(
                GlassmorphismModifier.fill(cornerRadius: cornerRadius)
                    .compositingGroup()
                    .modifier(ElevatedShadowModifier())
            )
            .overlay(GlassmorphismModifier.border(cornerRadius: cornerRadius, borderOpacity: 0.15))
    }
}

// MARK: - View Extensions
extension View {
    func glassPanel(cornerRadius: CGFloat = AppTheme.cornerRadiusSection) -> some View {
        self.modifier(GlassmorphismModifier(cornerRadius: cornerRadius))
    }
    
    /// Glass panel with the elevated shadow, cheap to redraw when the contents change.
    func elevatedGlassPanel(cornerRadius: CGFloat = AppTheme.cornerRadiusSection) -> some View {
        self.modifier(ElevatedGlassModifier(cornerRadius: cornerRadius))
    }

    func elevatedShadow() -> some View {
        self.modifier(ElevatedShadowModifier())
    }
    
    func appShadow() -> some View {
        self.shadow(color: AppTheme.shadowColor, radius: AppTheme.shadowRadius, y: AppTheme.shadowY)
    }
}
