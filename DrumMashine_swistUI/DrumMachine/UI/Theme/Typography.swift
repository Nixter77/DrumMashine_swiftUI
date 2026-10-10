import SwiftUI

struct Typography {
    static let header = Font.system(.title2, design: .rounded).weight(.bold)
    static let subheader = Font.system(.headline, design: .rounded).weight(.semibold)
    static let body = Font.system(.body, design: .default)
    static let data = Font.system(.caption, design: .monospaced)
    static let value = Font.system(.callout, design: .monospaced).weight(.medium)
}
