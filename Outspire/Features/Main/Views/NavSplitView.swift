import SwiftUI

// Removed ColorfulX usage in favor of system materials

struct NavSplitView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var urlSchemeHandler: URLSchemeHandler
    @EnvironmentObject var gradientManager: GradientManager // Add gradient manager
    @State private var selectedView: ViewType? = .today
    @State private var refreshID = UUID()
    @State private var showOnboardingSheet = false
    @State private var hasCheckedOnboarding = false
    @AppStorage("lastVersionRun") private var lastVersionRun: String?
    @State private var onboardingCompleted = false
    @Environment(\.colorScheme) private var colorScheme // Add colorScheme
    @State private var splitSearch: String = ""

    var body: some View {
        NavigationSplitView {
            // Sidebar list content; use system background/materials
            List(selection: $selectedView) {
                NavigationLink(value: ViewType.today) {
                    Label("Today", systemImage: "text.rectangle.page")
                }

                NavigationLink(value: ViewType.classtable) {
                    Label("Class Schedule", systemImage: "clock.badge.questionmark")
                }

                if !Configuration.hideAcademicScore {
                    NavigationLink(value: ViewType.score) {
                        Label("Academic Grades", systemImage: "pencil.and.list.clipboard")
                    }
                }

                Section {
                    NavigationLink(value: ViewType.clubInfo) {
                        Label("Hall of Clubs", systemImage: "person.2.circle")
                    }
                    NavigationLink(value: ViewType.clubActivities) {
                        Label("Activity Records", systemImage: "checklist")
                    }
                    NavigationLink(value: ViewType.clubReflections) {
                        Label("Reflections", systemImage: "pencil.and.list.clipboard")
                    }
                } header: {
                    Text("Activities")
                }

                Section {
                    NavigationLink(value: ViewType.map) {
                        Label("Campus Map", systemImage: "map")
                    }
                    NavigationLink(value: ViewType.schoolArrangements) {
                        Label("School Arrangements", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink(value: ViewType.lunchMenu) {
                        Label("Dining Menus", systemImage: "fork.knife")
                    }
                    #if DEBUG
                        NavigationLink(value: ViewType.help) {
                            Label("Help", systemImage: "questionmark.circle.dashed")
                        }
                    #endif
                } header: {
                    Text("Miscellaneous")
                }
            }
            // Keep default list background to align with Liquid Glass behavior
            .modifier(NavigationColumnWidthModifier()) // Apply column width correctly
            .navigationTitle("Outspire")
            .contentMargins(.vertical, 10)
            // Settings is now available under Search; remove sidebar sheet presentation
            .sheet(isPresented: $showOnboardingSheet) {
                OnboardingView(isPresented: $showOnboardingSheet)
                    .onDisappear { checkOnboardingStatus() }
            }
            .onChange(of: showOnboardingSheet) { _, newValue in
                ConnectivityManager.shared.setOnboardingActive(newValue)
            }
        } detail: {
            detailView
        }
        .searchable(text: $splitSearch, prompt: "Search")
        .onChange(of: Configuration.hideAcademicScore) { _, newValue in
            if newValue, selectedView == .score { selectedView = .today }
            refreshID = UUID()
        }
        // Add URL scheme handling changes
        .onChange(of: urlSchemeHandler.navigateToToday) { _, newValue in if newValue { selectedView = .today } }
        .onChange(of: urlSchemeHandler.navigateToClassTable) { _, newValue in
            if newValue { selectedView = .classtable }
        }
        .onChange(of: urlSchemeHandler.navigateToClub) { _, clubId in if clubId != nil { selectedView = .clubInfo } }
        .onChange(of: urlSchemeHandler.navigateToAddActivity) { _, clubId in
            if clubId != nil { selectedView = .clubActivities }
        }
        .id(refreshID)
        .task {
            checkOnboardingStatus()
        }
        .onChange(of: selectedView) { _, newView in
            // Update gradient when the selected view changes
            updateGradient(for: newView)
        }
        .onAppear {
            // Initialize gradient based on current view
            updateGradient(for: selectedView)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            // Ensure onboarding sheet reappears if not completed
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showOnboardingSheet = true
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        // Use a NavigationStack wrapper for each view type
        switch selectedView {
        case .today:
            NavigationStack {
                TodayView() // Removed explicit id to enable default transition animations
            }
        case .classtable:
            NavigationStack {
                ModernClasstableView()
                    .id("classtable-nav-content")
            }
        case .score:
            NavigationStack {
                ScoreView()
                    .id("score-nav-content")
            }
        case .clubInfo:
            NavigationStack {
                ClubInfoView()
                    .id("club-info-nav-content")
            }
        case .clubActivities:
            NavigationStack {
                ClubActivitiesView()
                    .id("club-activity-nav-content")
            }
        case .clubReflections:
            NavigationStack {
                ReflectionsView()
                    .id("club-reflection-nav-content")
            }
        case .schoolArrangements:
            NavigationStack {
                SchoolArrangementView()
                    .id("school-arrangement-nav-content")
            }
        case .lunchMenu:
            NavigationStack {
                LunchMenuView()
                    .id("lunch-menu-nav-content")
            }
        case .help:
            NavigationStack {
                HelpView()
                    .id("help-nav-content")
            }
        case .map:
            NavigationStack {
                MapView()
                    .id("map-nav-content")
            }
        default:
            NavigationStack {
                TodayView()
                    .id("default-nav-content")
            }
        }
    }

    private func checkOnboardingStatus() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let thresholdVersion = "0.5.1"

        if shouldShowOnboardingForVersion(
            lastVersionRun: lastVersionRun, thresholdVersion: thresholdVersion
        ) {
            showOnboardingSheet = true
            lastVersionRun = currentVersion
            Log.app.info("Showing onboarding due to version check.")
        } else if !hasCheckedOnboarding {
            hasCheckedOnboarding = true

            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showOnboardingSheet = true
                Log.app.info("Showing onboarding because 'hasCompletedOnboarding' is false.")
            } else {
                Log.app.info("'hasCompletedOnboarding' is already true. Onboarding will not be shown.")
            }
        }
    }

    private func shouldShowOnboardingForVersion(lastVersionRun: String?, thresholdVersion: String)
        -> Bool
    {
        guard let lastVersion = lastVersionRun else {
            return true
        }
        return lastVersion.compare(thresholdVersion, options: .numeric) == .orderedAscending
    }

    /// Update the method to update gradient based on selected view
    private func updateGradient(for view: ViewType?) {
        guard let view else {
            // Default to today view gradient
            gradientManager.updateGradientForView(.today, colorScheme: colorScheme)
            return
        }

        // For Today view, we need to check the actual context
        if view == .today {
            // Today view handles context-specific gradients in its own view
            let isWeekend = TodayViewHelpers.isCurrentDateWeekend()
            let isHoliday = Configuration.isHolidayMode

            if !AuthServiceV2.shared.isAuthenticated {
                gradientManager.updateGradientForContext(
                    context: .notSignedIn, colorScheme: colorScheme
                )
            } else if isHoliday {
                gradientManager.updateGradientForContext(
                    context: .holiday, colorScheme: colorScheme
                )
            } else if isWeekend {
                gradientManager.updateGradientForContext(
                    context: .weekend, colorScheme: colorScheme
                )
            } else {
                // Let the Today view handle this in its own onAppear
                gradientManager.updateGradientForContext(context: .normal, colorScheme: colorScheme)
            }
        } else {
            // For other views, check if we have an active context
            if gradientManager.currentContext.isSpecialContext {
                // Keep the current context colors but update animation settings
                gradientManager.updateGradientForView(view, colorScheme: colorScheme)
            } else {
                // No special context, use regular view settings
                gradientManager.updateGradientForView(view, colorScheme: colorScheme)
            }
        }
    }
}

// MARK: - Navigation Column Width Modifier

struct NavigationColumnWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
            // Use NavigationSplitViewVisibility instead of width for more consistent behavior
            content
                .navigationSplitViewColumnWidth(min: 180, ideal: 180, max: 300)
                .onAppear {
                    // Apply AppKit-specific customizations for Mac Catalyst
                    if let windowScene = UIApplication.shared.connectedScenes.first
                        as? UIWindowScene
                    {
                        windowScene.titlebar?.titleVisibility = .visible
                        windowScene.titlebar?.toolbar?.isVisible = true

                        // Let system handle navigation bar appearance (Liquid Glass on iOS 26+)
                        UITableView.appearance().backgroundColor = .clear
                    }
                }
        #else
            // On iOS/iPadOS, use regular settings
            content
                .if(horizontalSizeClass == .regular) { view in
                    // Only on iPad, set default width
                    view.navigationSplitViewColumnWidth(250)
                }
        #endif
    }
}
