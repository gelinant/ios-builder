import SwiftUI

/// Agency colors are already validated by the Transitous parser. Invalid or absent values use the
/// app accent, and a missing text color is selected by fill luminance for a legible line pill.
enum TransitActivityPalette {
    static let accent = Color(red: 0x14 / 255.0, green: 0x93 / 255.0, blue: 0x87 / 255.0)

    static func fill(_ hex: String?) -> Color {
        rgb(hex).map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? accent
    }

    static func text(fill fillHex: String?, explicit textHex: String?) -> Color {
        if let text = rgb(textHex) {
            return Color(red: text.r, green: text.g, blue: text.b)
        }
        guard let fill = rgb(fillHex) else { return .white }
        let luminance = 0.2126 * fill.r + 0.7152 * fill.g + 0.0722 * fill.b
        return luminance > 0.62 ? .black : .white
    }

    private static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7,
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
