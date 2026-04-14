import SwiftUI

#if !targetEnvironment(macCatalyst)
    import ColorfulX

    /// A central place to define app-wide gradient presets for consistency
    enum AppGradients {
        // Context-specific gradients (these take priority)
        static let inClass = ColorfulPreset.ocean.swiftUIColors
        static let upcomingClass = ColorfulPreset.aurora.swiftUIColors
        static let selfStudy = ColorfulPreset.lavandula.swiftUIColors
        static let upcomingSelfStudy = ColorfulPreset.lavandula.swiftUIColors.map { $0.opacity(0.8) }
        static let afterSchool = ColorfulPreset.sunset.swiftUIColors

        // State gradients
        static let notSignedIn = ColorfulPreset.winter.swiftUIColors
        static let weekend = ColorfulPreset.sunrise.swiftUIColors
        static let holiday = ColorfulPreset.autumn.swiftUIColors

        /// Default fallback gradient
        static let defaultGradient = ColorfulPreset.aurora.swiftUIColors
    }
#else
    /// Fallback gradients for Mac Catalyst (simple color arrays)
    enum AppGradients {
        static let inClass = [Color.blue, Color.green]
        static let upcomingClass = [Color.purple, Color.blue]
        static let selfStudy = [Color.purple, Color.gray]
        static let upcomingSelfStudy = [Color.purple.opacity(0.8), Color.gray.opacity(0.8)]
        static let afterSchool = [Color.orange, Color.red]
        static let notSignedIn = [Color.gray, Color.white]
        static let weekend = [Color.yellow, Color.orange]
        static let holiday = [Color.red, Color.orange]
        static let defaultGradient = [Color.blue, Color.purple]
    }
#endif
