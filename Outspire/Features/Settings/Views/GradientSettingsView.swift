import SwiftUI
#if !targetEnvironment(macCatalyst)
    import ColorfulX
#endif

struct GradientSettingsView: View {
    @EnvironmentObject var gradientManager: GradientManager
    @Environment(\.colorScheme) private var colorScheme

    // Since we're removing view-specific settings, we'll focus on global settings only
    @State private var animationSpeed: Double = 0.5
    @State private var noiseAmount: Double = 20.0
    @State private var transitionSpeed: Double = 1.0
    #if !targetEnvironment(macCatalyst)
        @State private var selectedPreset: GradientPreset = .aurora
    #else
        @State private var selectedPreset: GradientPreset = .forest
    #endif

    /// Track if user has customized settings
    @State private var hasCustomized: Bool = false

    /// Define the available gradient presets
    enum GradientPreset: String, CaseIterable, Identifiable {
        #if !targetEnvironment(macCatalyst)
            // Added all ColorfulPreset options
            case sunrise, sunset, love, ocean, barbie, starry, jelly
            case lavandula, watermelon, dandelion, lemon
            case spring, summer, autumn, winter, neon, aurora
            /// Custom color schemes
            case forest, lavender, cherry
        #else
            case forest, lavender, cherry
        #endif

        var id: String {
            self.rawValue
        }

        var colors: [Color] {
            switch self {
            #if !targetEnvironment(macCatalyst)
                // Map to ColorfulPreset values where available
                case .sunrise: return ColorfulPreset.sunrise.swiftUIColors
                case .sunset: return ColorfulPreset.sunset.swiftUIColors
                case .love: return ColorfulPreset.love.swiftUIColors
                case .ocean: return ColorfulPreset.ocean.swiftUIColors
                case .barbie: return ColorfulPreset.barbie.swiftUIColors
                case .starry: return ColorfulPreset.starry.swiftUIColors
                case .jelly: return ColorfulPreset.jelly.swiftUIColors
                case .lavandula: return ColorfulPreset.lavandula.swiftUIColors
                case .watermelon: return ColorfulPreset.watermelon.swiftUIColors
                case .dandelion: return ColorfulPreset.dandelion.swiftUIColors
                case .lemon: return ColorfulPreset.lemon.swiftUIColors
                case .spring: return ColorfulPreset.spring.swiftUIColors
                case .summer: return ColorfulPreset.summer.swiftUIColors
                case .autumn: return ColorfulPreset.autumn.swiftUIColors
                case .winter: return ColorfulPreset.winter.swiftUIColors
                case .neon: return ColorfulPreset.neon.swiftUIColors
                case .aurora: return ColorfulPreset.aurora.swiftUIColors
            #endif
            // Custom gradient combinations
            case .forest: return [Color.green, Color.mint, Color.teal, Color.blue]
            case .lavender: return [Color.purple, Color.indigo, Color.blue, Color.purple.opacity(0.7)]
            case .cherry: return [Color.red, Color.pink, Color.purple, Color.red.opacity(0.7)]
            }
        }
    }

    var body: some View {
        List {
            #if DEBUG
                Section(header: Text("Gradient Preset")) {
                    Picker("Preset", selection: $selectedPreset) {
                        ForEach(
                            GradientPreset.allCases.sorted(by: { $0.rawValue < $1.rawValue }),
                            id: \.self
                        ) { preset in
                            HStack {
                                LinearGradient(
                                    colors: preset.colors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 30, height: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                                Text(preset.rawValue.capitalized)
                                    .padding(.leading, 8)
                            }
                            .tag(preset)
                        }
                    }
                    .onChange(of: selectedPreset) { _, newValue in
                        updateGradient(preset: newValue)
                        hasCustomized = true
                    }
                    .pickerStyle(.navigationLink)

                    // Preview of current gradient
                    gradientPreview
                }
            #endif

            Section(header: Text("Animation Settings")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Animation Speed")
                        Spacer()
                        Text(String(format: "%.1f", animationSpeed))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $animationSpeed, in: 0.1 ... 1.5) { editing in
                        if !editing {
                            updateGradientAnimation()
                            hasCustomized = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Noise Amount")
                        Spacer()
                        Text(String(format: "%.1f", noiseAmount))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $noiseAmount, in: 0 ... 50) { editing in
                        if !editing {
                            updateGradientAnimation()
                            hasCustomized = true
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Transition Speed")
                        Spacer()
                        Text(String(format: "%.1f", transitionSpeed))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $transitionSpeed, in: 0.1 ... 2.0) { editing in
                        if !editing {
                            updateGradientAnimation()
                            hasCustomized = true
                        }
                    }
                }
            }

            Section {
                Button("Reset to Default") {
                    resetAllSettings()
                }
                .foregroundColor(.red)
                .disabled(!hasCustomized)
            }

            Section(header: Text("About Gradients")) {
                Text(
                    "The app will automatically adjust gradients based on context, such as when you're in class or when it's a weekend."
                )
                //                    .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Display")
        .onAppear {
            loadCurrentSettings()
        }
    }

    /// Preview of the current gradient
    private var gradientPreview: some View {
        ZStack {
            #if !targetEnvironment(macCatalyst)
                ColorfulView(
                    color: .constant(selectedPreset.colors),
                    speed: .constant(animationSpeed),
                    noise: .constant(noiseAmount),
                    transitionSpeed: .constant(transitionSpeed)
                )
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            #else
                LinearGradient(
                    colors: selectedPreset.colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            #endif

            Text("Preview")
                .font(.headline)
                .foregroundStyle(colorScheme == .dark ? .white : .black)
                .shadow(color: Color.black.opacity(0.3), radius: 1, x: 0, y: 1)
        }
        .padding(.vertical, 8)
    }

    /// Load current settings from the gradient manager
    private func loadCurrentSettings() {
        // Load customization status
        hasCustomized = UserDefaults.standard.bool(forKey: "hasCustomizedGradients")

        // Load global settings
        let settings = gradientManager.getBaseSettings()

        // Update UI state with these settings
        animationSpeed = settings.speed
        noiseAmount = settings.noise
        transitionSpeed = settings.transitionSpeed

        // Try to determine which preset matches the colors
        #if !targetEnvironment(macCatalyst)
            selectedPreset = findMatchingPreset(for: settings.colors) ?? .aurora
        #else
            selectedPreset = findMatchingPreset(for: settings.colors) ?? .forest
        #endif
    }

    /// Find which preset matches a set of colors
    private func findMatchingPreset(for colors: [Color]) -> GradientPreset? {
        // Simple implementation - just check if the arrays have the same count
        // and if each color is approximately the same
        for preset in GradientPreset.allCases {
            if preset.colors.count == colors.count {
                // This is a simplistic approach - a more sophisticated approach would
                // compare the actual colors in detail
                return preset
            }
        }
        return nil
    }

    /// Update the gradient based on selected preset
    private func updateGradient(preset: GradientPreset) {
        // Update global settings
        gradientManager.updateGlobalGradient(
            colors: preset.colors,
            speed: animationSpeed,
            noise: noiseAmount,
            transitionSpeed: transitionSpeed
        )
        saveCustomSettings()
    }

    /// Update just the animation settings
    private func updateGradientAnimation() {
        // Update global settings
        gradientManager.updateGlobalGradient(
            speed: animationSpeed,
            noise: noiseAmount,
            transitionSpeed: transitionSpeed
        )
        saveCustomSettings()
    }

    /// Reset all settings
    private func resetAllSettings() {
        // Reset all settings
        gradientManager.resetAllSettings()

        // Update UI with default settings
        loadCurrentSettings()

        // Clear customization flags
        hasCustomized = false
        saveCustomSettings()
    }

    /// Save custom settings to UserDefaults
    private func saveCustomSettings() {
        UserDefaults.standard.set(true, forKey: "hasCustomizedGradients")
    }
}
