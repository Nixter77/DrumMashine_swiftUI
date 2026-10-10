import SwiftUI

// MARK: - Core/Models
struct DrumPad: Identifiable, Codable {
    var id: UUID
    var name: String
    var iconName: String
    var colorHex: String
    var soundPresetId: UUID
    
    var color: Color {
        Color(hex: colorHex)
    }
}
