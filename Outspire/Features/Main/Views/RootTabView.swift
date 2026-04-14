import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var urlSchemeHandler: URLSchemeHandler
    @EnvironmentObject var gradientManager: GradientManager
    @AppStorage("lastVersionRun") private var lastVersionRun: String?

    @ObservedObject private var authV2 = AuthServiceV2.shared

    @State private var selectedTab: MainTab = .today
    @State private var showOnboardingSheet = false
    @State private var hasCheckedOnboarding = false

    enum MainTab: Hashable { case today, classtable, activities, search }
    enum DeepLinkRoute: Hashable { case clubInfo }

    @State private var explorePath = NavigationPath()

    var body: some View {
        Group {
            if authV2.isResolvingSession {
                ProgressView()
            } else if #available(iOS 26.0, *) {
                ios26TabView
            } else if #available(iOS 18.0, *) {
                ios18TabView
            } else {
                legacyTabView
            }
        }
        .sheet(isPresented: $showOnboardingSheet) {
            OnboardingView(isPresented: $showOnboardingSheet)
                .onDisappear { checkOnboardingStatus() }
        }
        .onChange(of: showOnboardingSheet) { _, newValue in
            ConnectivityManager.shared.setOnboardingActive(newValue)
        }
        .task {
            checkOnboardingStatus()
        }
        .onChange(of: urlSchemeHandler.navigateToToday) { _, newValue in
            if newValue { selectedTab = .today }
        }
        .onChange(of: urlSchemeHandler.navigateToClassTable) { _, newValue in
            if newValue { selectedTab = .classtable }
        }
        .onChange(of: urlSchemeHandler.navigateToClub) { _, clubId in
            if clubId != nil {
                selectedTab = .search
                explorePath = NavigationPath()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    explorePath.append(DeepLinkRoute.clubInfo)
                }
            }
        }
        .onChange(of: urlSchemeHandler.navigateToAddActivity) { _, clubId in
            if clubId != nil { selectedTab = .activities }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in
            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showOnboardingSheet = true
            }
        }
    }

    // MARK: - iOS 26+ (Liquid Glass tab bar)

    @available(iOS 26.0, *)
    private var ios26TabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "text.rectangle.page.fill", value: MainTab.today) {
                NavigationStack {
                    TodayView()
                }
            }

            Tab("Class", systemImage: "calendar.day.timeline.left", value: MainTab.classtable) {
                NavigationStack {
                    ModernClasstableView()
                }
            }

            Tab("Activities", systemImage: "checklist.checked", value: MainTab.activities) {
                NavigationStack {
                    ClubActivitiesView()
                }
            }

            Tab("Explore", systemImage: "square.grid.2x2", value: MainTab.search) {
                NavigationStack(path: $explorePath) {
                    ExtraView()
                        .navigationDestination(for: DeepLinkRoute.self) { route in
                            switch route {
                            case .clubInfo:
                                ClubInfoView()
                            }
                        }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - iOS 18+

    @available(iOS 18.0, *)
    private var ios18TabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Today", systemImage: "text.rectangle.page.fill", value: MainTab.today) {
                NavigationStack {
                    TodayView()
                }
            }

            Tab("Class", systemImage: "calendar.day.timeline.left", value: MainTab.classtable) {
                NavigationStack {
                    ModernClasstableView()
                }
            }

            Tab("Activities", systemImage: "checklist.checked", value: MainTab.activities) {
                NavigationStack {
                    ClubActivitiesView()
                }
            }

            Tab("Explore", systemImage: "square.grid.2x2", value: MainTab.search) {
                NavigationStack(path: $explorePath) {
                    ExtraView()
                        .navigationDestination(for: DeepLinkRoute.self) { route in
                            switch route {
                            case .clubInfo:
                                ClubInfoView()
                            }
                        }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Legacy

    private var legacyTabView: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "text.rectangle.page.fill") }
            .tag(MainTab.today)

            NavigationStack {
                ModernClasstableView()
            }
            .tabItem { Label("Class", systemImage: "calendar.day.timeline.left") }
            .tag(MainTab.classtable)

            NavigationStack {
                ClubActivitiesView()
            }
            .tabItem { Label("Activities", systemImage: "checklist.checked") }
            .tag(MainTab.activities)

            NavigationStack(path: $explorePath) {
                ExtraView()
                    .navigationDestination(for: DeepLinkRoute.self) { route in
                        switch route {
                        case .clubInfo:
                            ClubInfoView()
                        }
                    }
            }
            .tabItem { Label("Explore", systemImage: "square.grid.2x2") }
            .tag(MainTab.search)
        }
        .onChange(of: selectedTab) { _, _ in
            HapticManager.shared.playSelectionFeedback()
        }
    }

    private func checkOnboardingStatus() {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let thresholdVersion = "0.5.1"

        if shouldShowOnboardingForVersion(
            lastVersionRun: lastVersionRun,
            thresholdVersion: thresholdVersion
        ) {
            showOnboardingSheet = true
            lastVersionRun = currentVersion
        } else if !hasCheckedOnboarding {
            hasCheckedOnboarding = true

            if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
                showOnboardingSheet = true
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
}
