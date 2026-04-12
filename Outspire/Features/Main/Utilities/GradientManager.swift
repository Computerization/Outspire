import SwiftUI
#if !targetEnvironment(macCatalyst)
    import ColorfulX
#endif

// Structure to hold view-specific gradient settings
struct ViewGradientSettings: Codable {
    var colors: [String] // Store colors as strings for Codable support
    var speed: Double
    var noise: Double
    var transitionSpeed: Double

    init(colors: [Color], speed: Double, noise: Double, transitionSpeed: Double) {
        // Convert SwiftUI Colors to hex strings for storage
        self.colors = colors.map { color in
            let uiColor = UIColor(color)
            return uiColor.toHexString()
        }
        self.speed = speed
        self.noise = noise
        self.transitionSpeed = transitionSpeed
    }

    // Get actual SwiftUI colors
    var swiftUIColors: [Color] {
        colors.compactMap { hexString in
            Color(UIColor(hex: hexString) ?? .clear)
        }
    }
}

@MainActor
class GradientManager: ObservableObject {
    @Published var gradientColors: [Color] = AppGradients.defaultGradient
    @Published var gradientSpeed: Double = 0.5
    @Published var gradientNoise: Double = 20.0
    @Published var gradientTransitionSpeed: Double = 1.5

    @Published var useGlobalSettings: Bool = true

    private var viewSettings: [ViewType: ViewGradientSettings] = [:]

    private var globalSettings: ViewGradientSettings?

    @Published var currentContext: GradientContext = .normal
    @Published var overrideGradientEnabled: Bool = false

    init() {
        loadSavedSettings()
    }

    func updateGradient(
        colors: [Color]? = nil,
        speed: Double? = nil,
        noise: Double? = nil,
        transitionSpeed: Double? = nil
    ) {
        if let colors = colors {
            gradientColors = colors
        }
        if let speed = speed {
            gradientSpeed = speed
        }
        if let noise = noise {
            gradientNoise = noise
        }
        if let transitionSpeed = transitionSpeed {
            gradientTransitionSpeed = transitionSpeed
        }

        // Save the updated settings
        saveCurrentSettings()
    }

    func updateGlobalGradient(
        colors: [Color]? = nil,
        speed: Double? = nil,
        noise: Double? = nil,
        transitionSpeed: Double? = nil
    ) {
        // Update the active gradient
        updateGradient(colors: colors, speed: speed, noise: noise, transitionSpeed: transitionSpeed)

        // Create or update global settings
        if globalSettings == nil {
            globalSettings = ViewGradientSettings(
                colors: gradientColors,
                speed: gradientSpeed,
                noise: gradientNoise,
                transitionSpeed: gradientTransitionSpeed
            )
        } else {
            if let colors = colors {
                globalSettings = ViewGradientSettings(
                    colors: colors,
                    speed: speed ?? globalSettings!.speed,
                    noise: noise ?? globalSettings!.noise,
                    transitionSpeed: transitionSpeed ?? globalSettings!.transitionSpeed
                )
            } else {
                globalSettings = ViewGradientSettings(
                    colors: globalSettings!.swiftUIColors,
                    speed: speed ?? globalSettings!.speed,
                    noise: noise ?? globalSettings!.noise,
                    transitionSpeed: transitionSpeed ?? globalSettings!.transitionSpeed
                )
            }
        }

        // Save global settings
        saveViewSettings()

        // Apply to all views if using global settings
        if useGlobalSettings {
            applyGlobalSettings()
        }
    }

    func updateViewGradient(
        viewType: ViewType,
        colors: [Color]? = nil,
        speed: Double? = nil,
        noise: Double? = nil,
        transitionSpeed: Double? = nil
    ) {
        // If we already have settings for this view, update them
        if var settings = viewSettings[viewType] {
            if let colors = colors {
                settings = ViewGradientSettings(
                    colors: colors,
                    speed: speed ?? settings.speed,
                    noise: noise ?? settings.noise,
                    transitionSpeed: transitionSpeed ?? settings.transitionSpeed
                )
            } else {
                settings = ViewGradientSettings(
                    colors: settings.swiftUIColors,
                    speed: speed ?? settings.speed,
                    noise: noise ?? settings.noise,
                    transitionSpeed: transitionSpeed ?? settings.transitionSpeed
                )
            }
            viewSettings[viewType] = settings
        } else {
            // Create new settings for this view
            let defaultColors = getDefaultColorsForViewType(viewType)
            viewSettings[viewType] = ViewGradientSettings(
                colors: colors ?? defaultColors,
                speed: speed ?? 0.5,
                noise: noise ?? 20.0,
                transitionSpeed: transitionSpeed ?? 1.0
            )
        }

        // Update the current displayed gradient if we're viewing this view type
        updateGradient(
            colors: colors,
            speed: speed,
            noise: noise,
            transitionSpeed: transitionSpeed
        )

        // Save settings
        saveViewSettings()
    }

    func applyGlobalSettings() {
        guard let globalSettings = globalSettings else { return }

        // Update all view settings with global settings
        for viewType in ViewType.allCases {
            viewSettings[viewType] = globalSettings
        }

        // Update the active gradient
        updateGradient(
            colors: globalSettings.swiftUIColors,
            speed: globalSettings.speed,
            noise: globalSettings.noise,
            transitionSpeed: globalSettings.transitionSpeed
        )

        // Save settings
        saveViewSettings()
    }

    func getSettingsForView(_ viewType: ViewType)
        -> (colors: [Color], speed: Double, noise: Double, transitionSpeed: Double)
    {
        if useGlobalSettings, let globalSettings = globalSettings {
            return (
                globalSettings.swiftUIColors,
                globalSettings.speed,
                globalSettings.noise,
                globalSettings.transitionSpeed
            )
        }

        if let settings = viewSettings[viewType] {
            return (settings.swiftUIColors, settings.speed, settings.noise, settings.transitionSpeed)
        }

        // Default settings if none exist
        let defaultColors = getDefaultColorsForViewType(viewType)
        return (defaultColors, 0.5, 20.0, 1.0)
    }

    func resetViewSettings(viewType: ViewType) {
        let defaultColors = getDefaultColorsForViewType(viewType)
        viewSettings[viewType] = ViewGradientSettings(
            colors: defaultColors,
            speed: 0.5,
            noise: 20.0,
            transitionSpeed: 1.0
        )

        // Update the active gradient if we're on this view
        updateGradient(
            colors: defaultColors,
            speed: 0.5,
            noise: 20.0,
            transitionSpeed: 1.0
        )

        // Save settings
        saveViewSettings()
    }

    func resetAllSettings() {
        // Clear all view-specific settings
        viewSettings.removeAll()

        // Reset global settings
        globalSettings = ViewGradientSettings(
            colors: AppGradients.defaultGradient,
            speed: 0.5,
            noise: 20.0,
            transitionSpeed: 1.0
        )

        // Set back to using global settings
        useGlobalSettings = true

        // Update the active gradient
        updateGradient(
            colors: AppGradients.defaultGradient,
            speed: 0.5,
            noise: 20.0,
            transitionSpeed: 1.0
        )

        // Clear saved settings
        UserDefaults.standard.removeObject(forKey: "viewGradientSettings")
        UserDefaults.standard.removeObject(forKey: "globalGradientSettings")
        UserDefaults.standard.removeObject(forKey: "useGlobalGradientSettings")
        UserDefaults.standard.removeObject(forKey: "hasCustomizedGradients")
    }

    private func getDefaultColorsForViewType(_ viewType: ViewType) -> [Color] {
        switch viewType {
        case .today: return AppGradients.defaultGradient
        case .classtable: return AppGradients.inClass
        case .score: return AppGradients.afterSchool
        case .clubInfo: return AppGradients.holiday
        case .clubActivities: return AppGradients.weekend
        case .schoolArrangements: return AppGradients.holiday
        case .clubReflections: return AppGradients.afterSchool
        case .lunchMenu: return AppGradients.afterSchool
        case .map: return AppGradients.defaultGradient
        case .notSignedIn: return AppGradients.notSignedIn
        case .weekend: return AppGradients.weekend
        case .holiday: return AppGradients.holiday
        case .help: return AppGradients.defaultGradient
        }
    }

    private func loadSavedSettings() {
        // Load whether to use global settings
        useGlobalSettings = UserDefaults.standard.bool(forKey: "useGlobalGradientSettings")

        // Load global settings
        if let globalData = UserDefaults.standard.data(forKey: "globalGradientSettings"),
           let decodedSettings = try? JSONDecoder().decode(ViewGradientSettings.self, from: globalData)
        {
            globalSettings = decodedSettings
        } else {
            // Default global settings
            globalSettings = ViewGradientSettings(
                colors: AppGradients.defaultGradient,
                speed: 0.5,
                noise: 20.0,
                transitionSpeed: 1.0
            )
        }

        // Load view-specific settings
        if let viewData = UserDefaults.standard.data(forKey: "viewGradientSettings"),
           let viewDictionary = try? JSONDecoder().decode([String: ViewGradientSettings].self, from: viewData)
        {
            // Convert string keys back to ViewType
            for (key, value) in viewDictionary {
                if let viewType = ViewType(rawValue: key) {
                    viewSettings[viewType] = value
                }
            }
        }

        // Set initial displayed gradient
        if useGlobalSettings, let globalSettings = globalSettings {
            gradientColors = globalSettings.swiftUIColors
            gradientSpeed = globalSettings.speed
            gradientNoise = globalSettings.noise
            gradientTransitionSpeed = globalSettings.transitionSpeed
        } else {
            // Just use today view settings as default
            let todaySettings = getSettingsForView(.today)
            gradientColors = todaySettings.colors
            gradientSpeed = todaySettings.speed
            gradientNoise = todaySettings.noise
            gradientTransitionSpeed = todaySettings.transitionSpeed
        }
    }

    private func saveCurrentSettings() {
        // Save useGlobalSettings flag
        UserDefaults.standard.set(useGlobalSettings, forKey: "useGlobalGradientSettings")

        // Flag that settings have been customized
        UserDefaults.standard.set(true, forKey: "hasCustomizedGradients")
    }

    private func saveViewSettings() {
        // Save global settings
        if let globalSettings = globalSettings,
           let encodedGlobal = try? JSONEncoder().encode(globalSettings)
        {
            UserDefaults.standard.set(encodedGlobal, forKey: "globalGradientSettings")
        }

        // Save view-specific settings
        // Convert ViewType keys to strings for JSON encoding
        var stringDictionary: [String: ViewGradientSettings] = [:]
        for (key, value) in viewSettings {
            stringDictionary[key.rawValue] = value
        }

        if let encodedViews = try? JSONEncoder().encode(stringDictionary) {
            UserDefaults.standard.set(encodedViews, forKey: "viewGradientSettings")
        }

        // Save useGlobalSettings flag
        UserDefaults.standard.set(useGlobalSettings, forKey: "useGlobalGradientSettings")

        // Flag that settings have been customized
        UserDefaults.standard.set(true, forKey: "hasCustomizedGradients")
    }

    func updateGradientForContext(context: GradientContext, colorScheme: ColorScheme) {
        // Store current context for consistency
        self.currentContext = context

        // Get base animation settings
        let baseSettings = getBaseSettings()

        // Apply the context-specific colors with base settings
        let contextColors = getColorsForContext(context)

        // Adjust speed for active contexts (like being in class)
        let contextSpeed = context.isActive ? 0.7 : baseSettings.speed

        updateGradient(
            colors: contextColors,
            speed: contextSpeed,
            noise: baseSettings.noise,
            transitionSpeed: baseSettings.transitionSpeed
        )
    }

    private func getColorsForContext(_ context: GradientContext) -> [Color] {
        switch context {
        case .normal:
            return AppGradients.defaultGradient

        case .notSignedIn:
            return AppGradients.notSignedIn

        case .weekend:
            return AppGradients.weekend

        case .holiday:
            return AppGradients.holiday

        case .afterSchool:
            return AppGradients.afterSchool

        case let .inClass(subject):
            // If we have a subject, create a subject-specific gradient
            if !subject.isEmpty {
                let components = subject.replacingOccurrences(of: "<br>", with: "\n")
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }

                if components.count > 1 {
                    let subjectColor = ModernScheduleRow.subjectColor(for: components[1])
                    // Use explicit path to the extension method
                    let darkerVariant = Color.adjustBrightness(subjectColor, by: -0.2)
                    let lighterVariant = Color.adjustBrightness(subjectColor, by: 0.2)

                    return [
                        Color.white,
                        lighterVariant,
                        subjectColor,
                        darkerVariant
                    ]
                }
            }
            return AppGradients.inClass

        case let .upcomingClass(subject):
            // If we have a subject, create a subject-specific gradient
            if !subject.isEmpty {
                let components = subject.replacingOccurrences(of: "<br>", with: "\n")
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }

                if components.count > 1 {
                    // Use a lighter version of the subject color
                    let subjectColor = ModernScheduleRow.subjectColor(for: components[1])
                    // Use explicit path to the extension method
                    let lighterVariant1 = Color.adjustBrightness(subjectColor, by: 0.2)
                    let lighterVariant2 = Color.adjustBrightness(subjectColor, by: 0.3)

                    return [
                        Color.white,
                        lighterVariant2,
                        lighterVariant1,
                        subjectColor.opacity(0.8)
                    ]
                }
            }
            return AppGradients.upcomingClass

        case .inSelfStudy:
            return AppGradients.selfStudy

        case .upcomingSelfStudy:
            return AppGradients.upcomingSelfStudy
        }
    }

    func getBaseSettings() -> (colors: [Color], speed: Double, noise: Double, transitionSpeed: Double) {
        if useGlobalSettings, let globalSettings = globalSettings {
            return (
                globalSettings.swiftUIColors,
                globalSettings.speed,
                globalSettings.noise,
                globalSettings.transitionSpeed
            )
        } else {
            // Use default animation settings
            return (AppGradients.defaultGradient, 0.5, 20.0, 1.0)
        }
    }
}

extension GradientManager {
    func updateGradientForView(_ viewType: ViewType, colorScheme: ColorScheme) {
        // Simply update with default settings since we're removing view-specific gradients
        let settings = getBaseSettings()

        // Apply default settings
        updateGradient(
            colors: settings.colors,
            speed: settings.speed,
            noise: settings.noise,
            transitionSpeed: settings.transitionSpeed
        )
    }

    func updateGradientForContext(
        isAuthenticated: Bool,
        isHolidayMode: Bool,
        isWeekend: Bool,
        upcomingClass: (classData: String, isActive: Bool)? = nil,
        colorScheme: ColorScheme
    ) {
        // Determine which view type to use based on context
        let viewType: ViewType

        if isHolidayMode {
            viewType = .holiday
        } else if isWeekend {
            viewType = .weekend
        } else if !isAuthenticated {
            viewType = .notSignedIn
        } else {
            viewType = .today
        }

        // Get settings for this view type
        let settings = getSettingsForView(viewType)

        // If we have class data, modify the gradient based on class subject
        if let (classData, isActive) = upcomingClass {
            let components = classData.replacingOccurrences(of: "<br>", with: "\n")
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }

            if components.count > 1 {
                let subjectColor = ModernScheduleRow.subjectColor(for: components[1])
                let darkerVariant = subjectColor.adjustBrightness(by: -0.2)
                let lighterVariant = subjectColor.adjustBrightness(by: 0.2)

                let colors = [
                    Color.white,
                    lighterVariant,
                    subjectColor,
                    darkerVariant
                ]

                updateGradient(
                    colors: colors,
                    speed: isActive ? 0.7 : settings.speed,
                    noise: settings.noise,
                    transitionSpeed: settings.transitionSpeed
                )
            } else {
                // Apply standard settings for this view type
                updateGradient(
                    colors: settings.colors,
                    speed: settings.speed,
                    noise: settings.noise,
                    transitionSpeed: settings.transitionSpeed
                )
            }
        } else {
            // Apply standard settings for this view type
            updateGradient(
                colors: settings.colors,
                speed: settings.speed,
                noise: settings.noise,
                transitionSpeed: settings.transitionSpeed
            )
        }
    }
}

// Enum to track various gradient contexts for consistency
enum GradientContext: Equatable {
    case normal
    case notSignedIn
    case weekend
    case holiday
    case afterSchool
    case inClass(subject: String)
    case upcomingClass(subject: String)
    case inSelfStudy
    case upcomingSelfStudy

    // Check if this is a special context that should override regular view settings
    var isSpecialContext: Bool {
        switch self {
        case .normal:
            return false
        case .notSignedIn, .weekend, .holiday, .afterSchool,
             .inClass, .upcomingClass, .inSelfStudy, .upcomingSelfStudy:
            return true
        }
    }

    // Check if this is an active context (like being in class)
    var isActive: Bool {
        switch self {
        case .inClass, .inSelfStudy:
            return true
        default:
            return false
        }
    }
}

// Add extension method to UIColor for hex string conversion
extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    func toHexString() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        getRed(&r, green: &g, blue: &b, alpha: &a)

        let rgb = Int(r * 255) << 16 | Int(g * 255) << 8 | Int(b * 255) << 0

        return String(format: "#%06x", rgb)
    }
}
