import SwiftUI

enum SubjectColors {
    static func color(for subject: String) -> Color {
        let subjectLower = subject.lowercased()

        let colors: [(Color, [String])] = [
            (.blue.opacity(0.8), ["math", "mathematics", "maths"]),
            (.green.opacity(0.8), ["english", "language", "literature", "general paper", "esl"]),
            (.orange.opacity(0.8), ["physics", "science"]),
            (.pink.opacity(0.8), ["chemistry", "chem"]),
            (.teal.opacity(0.8), ["biology", "bio"]),
            (.mint.opacity(0.8), ["further math", "maths further"]),
            (.yellow.opacity(0.8), ["体育", "pe", "sports", "p.e"]),
            (.brown.opacity(0.8), ["economics", "econ"]),
            (.cyan.opacity(0.8), ["arts", "art", "tok"]),
            (.indigo.opacity(0.8), ["chinese", "mandarin", "语文"]),
            (.gray.opacity(0.8), ["history", "历史", "geography", "geo", "政治"])
        ]

        for (color, keywords) in colors {
            if keywords.contains(where: { subjectLower.contains($0) }) { return color }
        }

        // Deterministic hash fallback
        var djb2: UInt64 = 5381
        for byte in subjectLower.utf8 {
            djb2 = djb2 &* 33 &+ UInt64(byte)
        }
        let hue = Double(djb2 % 12) / 12.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }

    /// Darker variant for gradient end
    static func darkerColor(for subject: String) -> Color {
        color(for: subject).opacity(0.6)
    }

    /// Gradient for small widget backgrounds
    static func gradient(for subject: String) -> LinearGradient {
        LinearGradient(
            colors: [color(for: subject), darkerColor(for: subject)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
