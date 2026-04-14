import SwiftUI

extension Color {
    /// Adjusts the brightness of a color by the given amount
    /// - Parameters:
    ///   - color: The color to adjust
    ///   - amount: The amount to adjust by (positive = brighter, negative = darker)
    /// - Returns: A new color with adjusted brightness
    static func adjustBrightness(_ color: Color, by amount: CGFloat) -> Color {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return color
        }

        let newBrightness = max(min(b + amount, 1.0), 0.0)
        return Color(UIColor(hue: h, saturation: s, brightness: newBrightness, alpha: a))
    }
}
