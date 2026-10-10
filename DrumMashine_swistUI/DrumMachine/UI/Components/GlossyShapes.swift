import SwiftUI

/// Studio Light "candy" surface: saturated body, top gloss, inner rim and a coloured glow underneath.
struct CandyFill: View {
    var color: Color
    var cornerRadius: CGFloat = 14
    var pressed: Bool = false
    var glow: Double = 0.45

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [color.mix(with: .white, by: 0.22), color, color.mix(with: .black, by: pressed ? 0.30 : 0.18)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // top gloss
            shape
                .fill(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.0)],
                                     startPoint: .top, endPoint: .center))
                .padding(.horizontal, 3).padding(.top, 2)
                .mask(shape)
            shape.strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.65), color.mix(with: .black, by: 0.25).opacity(0.6)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1.2
            )
        }
        // Flattened into one layer so playback redraws stay cheap; glow 0 = no blur shadow at all.
        .compositingGroup()
        .shadow(color: color.opacity(glow > 0 ? (pressed ? glow * 0.6 : glow) : 0),
                radius: glow > 0 ? (pressed ? 4 : 7) : 0, y: glow > 0 ? (pressed ? 2 : 4) : 0)
    }
}
