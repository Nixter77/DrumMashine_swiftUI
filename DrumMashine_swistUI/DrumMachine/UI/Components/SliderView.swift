import SwiftUI

struct SliderView: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var title: String = ""
    var vertical: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            
            ZStack(alignment: .bottomLeading) {
                // Track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                
                // Fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppTheme.accent)
                    .frame(
                        width: vertical ? width : width * CGFloat(normalizedValue),
                        height: vertical ? height * CGFloat(normalizedValue) : height
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if vertical {
                            let newValue = 1.0 - (gesture.location.y / height)
                            self.value = min(max(newValue * (range.upperBound - range.lowerBound) + range.lowerBound, range.lowerBound), range.upperBound)
                        } else {
                            let newValue = gesture.location.x / width
                            self.value = min(max(newValue * (range.upperBound - range.lowerBound) + range.lowerBound, range.lowerBound), range.upperBound)
                        }
                    }
            )
        }
        .frame(minWidth: vertical ? 20 : 100, minHeight: vertical ? 100 : 20)
    }
}

// MARK: - Preview
#Preview {
    SliderView(value: .constant(0.7))
        .padding()
        .background(Color.black)
}
