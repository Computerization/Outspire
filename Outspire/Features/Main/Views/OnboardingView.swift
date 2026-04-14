import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var nextPage = 0
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAppeared = false
    @Environment(\.dismiss) private var dismiss

    @State private var liveActivityEnabled = true

    /// Focus state for keyboard controls
    @FocusState private var buttonFocused: OnboardingButtonFocus?

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to Outspire",
            description: "Your ultimate companion for WFLA school life! Everything you need, all in one place.\n"
                + "Let's get started!",
            imageName: "sparkles.rectangle.stack",
            imageColor: .blue,
            pageType: .information
        ),
        OnboardingPage(
            title: "Smart Schedule",
            description:
            "Stay on top of your classes and deadlines with smart scheduling. Never miss what matters most.",
            imageName: "calendar",
            imageColor: .orange,
            pageType: .information
        ),
        OnboardingPage(
            title: "CAS Made Simple",
            description: "Track your clubs, activities, and achievements effortlessly. "
                + "Complete with artificial intelligent insights to help you succeed.",
            imageName: "person.2.circle",
            imageColor: .green,
            pageType: .information
        ),
        OnboardingPage(
            title: "Academic Performance",
            description:
            "Track your grades and progress with complete privacy. Your data stays secure and belongs to you.",
            imageName: "lock.document",
            imageColor: .purple,
            pageType: .information
        ),
        OnboardingPage(
            title: "Live Schedule",
            description:
            "Get real-time class countdowns on your Lock Screen. Automatically starts before your first class and disappears after school.",
            imageName: "clock.badge.checkmark",
            imageColor: .cyan,
            pageType: .liveActivityPermission
        ),
        OnboardingPage(
            title: "You're All Set!",
            description:
            "Welcome to your enhanced school experience! Everything is ready for you to explore and succeed.",
            imageName: "checkmark.circle.fill",
            imageColor: .green,
            pageType: .information
        )
    ]

    var body: some View {
        GeometryReader { geometry in
            VStack {
                // Close button
                HStack {
                    Spacer()
                    Button(action: {
                        HapticManager.shared.playButtonTap()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            markOnboardingComplete()
                            isPresented = false
                        }
                    }) {
                        #if targetEnvironment(macCatalyst)
                            Text("Close")
                                .font(.system(size: 14, weight: .medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(.tertiarySystemFill))
                                .cornerRadius(6)
                                .foregroundStyle(.primary)
                        #else
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                        #endif
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding()
                    .focused($buttonFocused, equals: .close)
                }

                // Custom page viewer with explicit animation control
                ZStack {
                    ForEach(0 ..< pages.count, id: \.self) { index in
                        pageView(for: pages[index])
                            .frame(width: geometry.size.width)
                            .offset(x: CGFloat(index - currentPage) * geometry.size.width)
                            .opacity(index == currentPage ? 1 : 0)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8),
                                value: currentPage
                            )
                    }
                }
                .frame(maxHeight: .infinity)

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0 ..< pages.count, id: \.self) { index in
                        Circle()
                            .frame(width: 8, height: 8)
                            .foregroundColor(
                                index == currentPage ? .accentColor : .gray.opacity(0.3)
                            )
                    }
                }
                .padding(.vertical, 20)

                // Navigation buttons
                HStack(spacing: 20) {
                    if currentPage > 0 {
                        Button(action: {
                            HapticManager.shared.playButtonTap()
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                currentPage -= 1
                            }
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Previous")
                            }
                            #if targetEnvironment(macCatalyst)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.quaternarySystemFill))
                            .cornerRadius(8)
                            #endif
                            .foregroundStyle(.secondary)
                        }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .focused($buttonFocused, equals: .previous)
                    }

                    Spacer()

                    Button(action: {
                        HapticManager.shared.playButtonTap()
                        handleNextAction()
                    }) {
                        HStack {
                            Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            Image(
                                systemName: currentPage < pages.count - 1
                                    ? "chevron.right" : "checkmark.circle"
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        #if targetEnvironment(macCatalyst)
                            .background(
                                Capsule().fill(Color.accentColor.opacity(0.8))
                            )
                        #else
                            .background(
                                    Capsule().fill(Color.accentColor)
                                )
                        #endif
                                .foregroundStyle(.white)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .keyboardShortcut(.return, modifiers: [])
                    .keyboardShortcut(.space, modifiers: [])
                    .focused($buttonFocused, equals: .next)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
            .background(
                colorScheme == .dark
                    ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground)
            )
        }
        .onAppear {
            hasAppeared = true

            // Mark onboarding as active to prevent alerts during onboarding
            ConnectivityManager.shared.setOnboardingActive(true)

            // Set initial focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                buttonFocused = .next
            }
        }
        .interactiveDismissDisabled(true)
        .onDisappear {
            // Mark onboarding as inactive when view disappears
            ConnectivityManager.shared.setOnboardingActive(false)
        }
        .onChange(of: isPresented) { _, newValue in
            if !newValue, !hasAppeared {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                        isPresented = true
                    }
                }
            }
        }
        .onKeyPress(.rightArrow) {
            if currentPage < pages.count - 1 {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    currentPage += 1
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.leftArrow) {
            if currentPage > 0 {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    currentPage -= 1
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            markOnboardingComplete()
            isPresented = false
            return .handled
        }
    }

    /// Handle next button action based on current page type
    private func handleNextAction() {
        let currentPageInfo = pages[currentPage]

        switch currentPageInfo.pageType {
        case .information:
            // For regular information pages
            if currentPage == pages.count - 1 {
                // This is the final page, complete onboarding
                let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
                impactFeedback.prepare()
                impactFeedback.impactOccurred()

                markOnboardingComplete()
                isPresented = false
            } else {
                // Move to next page
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.prepare()
                impactFeedback.impactOccurred()

                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    currentPage += 1
                }
            }

        case .liveActivityPermission:
            // Save user's choice and move on
            UserDefaults.standard.set(liveActivityEnabled, forKey: "liveActivityEnabled")
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.prepare()
            impactFeedback.impactOccurred()

            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentPage += 1
            }
        }
    }

    @ViewBuilder
    func pageView(for page: OnboardingPage) -> some View {
        switch page.pageType {
        case .information:
            standardPageView(for: page)
        case .liveActivityPermission:
            liveActivityPageView(for: page)
        }
    }

    func standardPageView(for page: OnboardingPage) -> some View {
        VStack(spacing: 30) {
            Image(systemName: page.imageName)
                .font(.system(size: 70))
                .foregroundStyle(page.imageColor)
                .padding()
                .background(
                    Circle()
                        .fill(page.imageColor.opacity(0.1))
                        .frame(width: 140, height: 140)
                )
                .scaleEffect(
                    currentPage == pages.firstIndex(where: { $0.title == page.title }) ? 1.0 : 0.8
                )

            Text(page.title)
                .font(.largeTitle)
                .fontDesign(.rounded)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(page.description)
                .font(.title3)
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .frame(maxWidth: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    func liveActivityPageView(for page: OnboardingPage) -> some View {
        VStack(spacing: 30) {
            ZStack {
                Image(systemName: page.imageName)
                    .font(.system(size: 70))
                    .foregroundStyle(page.imageColor)
                    .padding()
                    .background(
                        Circle()
                            .fill(page.imageColor.opacity(0.1))
                            .frame(width: 140, height: 140)
                    )

                if liveActivityEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.green)
                        .background(
                            Circle()
                                .fill(Color(UIColor.systemBackground))
                                .frame(width: 32, height: 32)
                        )
                        .offset(x: 50, y: 50)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: liveActivityEnabled)
            .onTapGesture {
                liveActivityEnabled.toggle()
                HapticManager.shared.playSelectionFeedback()
            }

            Text(page.title)
                .font(.largeTitle)
                .fontDesign(.rounded)
                .bold()
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(page.description)
                .font(.title3)
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
                .frame(maxWidth: 500)

            // Toggle
            Toggle(isOn: $liveActivityEnabled) {
                Text("Enable Live Activity")
                    .font(.body)
                    .fontDesign(.rounded)
                    .fontWeight(.medium)
            }
            .tint(page.imageColor)
            .padding(.horizontal, 40)
            .frame(maxWidth: 400)

            Text("You can always change this in Settings.")
                .font(.footnote)
                .fontDesign(.rounded)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func markOnboardingComplete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        // Make sure to mark onboarding as inactive
        ConnectivityManager.shared.setOnboardingActive(false)
    }
}

/// Updated OnboardingPage struct with page type
struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let imageColor: Color
    let pageType: OnboardingPageType

    /// Default to information type for backward compatibility
    init(
        title: String, description: String, imageName: String, imageColor: Color,
        pageType: OnboardingPageType = .information
    ) {
        self.title = title
        self.description = description
        self.imageName = imageName
        self.imageColor = imageColor
        self.pageType = pageType
    }
}

/// Page type to distinguish between information and permission pages
enum OnboardingPageType {
    case information
    case liveActivityPermission
}

/// Enum for focus management
enum OnboardingButtonFocus {
    case previous, next, close
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
