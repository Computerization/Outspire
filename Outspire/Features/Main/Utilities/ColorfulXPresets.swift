import SwiftUI

#if !targetEnvironment(macCatalyst)
    import ColorfulX

    /// Extension to convert ColorfulPreset to SwiftUI Color array
    extension ColorfulPreset {
        var swiftUIColors: [Color] {
            colors.map { Color(uiColor: $0) }
        }
    }
#endif

/// Extension to add these presets to ColorfulX
extension Color {
    /// Safely adjust color brightness
    func adjustBrightness(by amount: CGFloat) -> Color {
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0

        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // Adjust brightness but keep within valid range
        let newBrightness = max(0, min(1, b + amount))

        return Color(UIColor(hue: h, saturation: s, brightness: newBrightness, alpha: a))
    }

    /// Blend two colors for better readability
    func blended(with color: Color, ratio: CGFloat = 0.5) -> Color {
        let uiColor1 = UIColor(self)
        let uiColor2 = UIColor(color)

        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        uiColor1.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiColor2.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        // Blend components with the provided ratio
        let r = r1 * (1 - ratio) + r2 * ratio
        let g = g1 * (1 - ratio) + g2 * ratio
        let b = b1 * (1 - ratio) + b2 * ratio
        let a = a1 * (1 - ratio) + a2 * ratio

        return Color(UIColor(red: r, green: g, blue: b, alpha: a))
    }
}

/// Helper extension to ensure gradient colors are properly applied
extension [Color] {
    func withOpacity(_ opacity: Double) -> [Color] {
        map { $0.opacity(opacity) }
    }
}
