import Foundation
import SwiftUI

// Removed ColorfulX usage in favor of system materials

struct TodayView: View {
    // MARK: - Environment & State

    @EnvironmentObject var classtableViewModel: ClasstableViewModel
    @ObservedObject private var authV2 = AuthServiceV2.shared
    @EnvironmentObject var urlSchemeHandler: URLSchemeHandler
    @EnvironmentObject var gradientManager: GradientManager

    @State private var isLoading = false
    @State private var animateCards = false
    @State private var isSettingsSheetPresented: Bool = false
    @State private var forceUpdate: Bool = false

    @AppStorage("hasShownScheduleTip") private var hasShownScheduleTip: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Convenience accessors for VM-owned settings

    private var selectedDayOverride: Int? {
        classtableViewModel.selectedDayOverride
    }

    private var setAsToday: Bool {
        classtableViewModel.setAsToday
    }

    private var isHolidayMode: Bool {
        classtableViewModel.isHolidayMode
    }

    private var holidayHasEndDate: Bool {
        classtableViewModel.holidayHasEndDate
    }

    private var holidayEndDate: Date {
        classtableViewModel.holidayEndDate
    }

    private var currentTime: Date {
        classtableViewModel.currentTime
    }

    private var effectiveDayIndex: Int {
        classtableViewModel.effectiveDayIndex
    }

    private var upcomingClassInfo:
        (period: ClassPeriod, classData: String, dayIndex: Int, isForToday: Bool)?
    {
        classtableViewModel.upcomingClassInfo
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            contentView
        }
        // Use inline title and a custom principal area to show a subtitle date
        .navigationBarTitleDisplayMode(.inline)
        .applyScrollEdgeEffect()
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(greeting)
                        .font(AppText.body.weight(.bold))
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let statusText = toolbarStatusText {
                        Text(statusText)
                            .font(AppText.caption.weight(.medium))
                            .foregroundStyle(toolbarStatusColor)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                scheduleButton
            }
        }
        .sheet(
            isPresented: $isSettingsSheetPresented,
            onDismiss: {
                updateGradientColors()
            }
        ) {
            scheduleSettingsSheet
        }
        .onAppear {
            setupOnAppear()
            updateGradientColors()

            if urlSchemeHandler.navigateToToday {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    urlSchemeHandler.navigateToToday = false
                }
            }
        }
        .onDisappear {
            saveSettings()
            classtableViewModel.stopTimer()
        }
        .onChange(of: classtableViewModel.years) { _, years in
            handleYearsChange(years)
        }
        .onChange(of: classtableViewModel.isLoadingYears) { _, _ in
            syncLoadingState()
        }
        .onChange(of: classtableViewModel.isLoadingTimetable) { _, isLoading in
            self.isLoading = classtableViewModel.isLoadingYears || isLoading
        }
        .onChange(of: classtableViewModel.timetable) { _, timetable in
            classtableViewModel.startLiveActivityIfNeeded(timetable: timetable)
            ClassActivityManager.shared.setHolidayActive(classtableViewModel.isHolidayActive())
            // Keep the activity manager's timetable in sync for Worker registration
            ClassActivityManager.shared.setTimetable(timetable)
        }
        .onChange(of: authV2.isAuthenticated) { _, isAuthenticated in
            handleAuthChange(isAuthenticated)
            updateGradientColors()
        }
        .onChange(of: classtableViewModel.selectedDayOverride) { _, newValue in
            Configuration.selectedDayOverride = newValue
            updateGradientColors()
        }
        .onChange(of: classtableViewModel.setAsToday) { _, newValue in
            Configuration.setAsToday = newValue
        }
        .onChange(of: classtableViewModel.isHolidayMode) { _, newValue in
            Configuration.isHolidayMode = newValue
            ClassActivityManager.shared.setHolidayActive(classtableViewModel.isHolidayActive())
            updateGradientColors()
        }
        .onChange(of: classtableViewModel.holidayHasEndDate) { _, newValue in
            Configuration.holidayHasEndDate = newValue
            ClassActivityManager.shared.setHolidayActive(classtableViewModel.isHolidayActive())
        }
        .onChange(of: classtableViewModel.holidayEndDate) { _, newValue in
            Configuration.holidayEndDate = newValue
            ClassActivityManager.shared.setHolidayActive(classtableViewModel.isHolidayActive())
        }
        .onChange(of: colorScheme) { _, _ in
            updateGradientColors()
        }
        .environment(\.colorScheme, colorScheme)
    }

    // MARK: - Gradient Methods

    private func updateGradientColors() {
        if !isAuthenticated {
            gradientManager.updateGradientForContext(
                context: .notSignedIn, colorScheme: colorScheme
            )
            return
        }

        if classtableViewModel.isHolidayActive() {
            gradientManager.updateGradientForContext(context: .holiday, colorScheme: colorScheme)
            return
        }

        if isCurrentDateWeekend() {
            gradientManager.updateGradientForContext(context: .weekend, colorScheme: colorScheme)
            return
        }

        if let upcomingInfo = upcomingClassInfo {
            let isSelfStudy = upcomingInfo.classData.contains("Self-Study")
            let isActive = upcomingInfo.period.isCurrentlyActive()

            if isActive {
                if isSelfStudy {
                    gradientManager.updateGradientForContext(
                        context: .inSelfStudy, colorScheme: colorScheme
                    )
                } else {
                    gradientManager.updateGradientForContext(
                        context: .inClass(subject: upcomingInfo.classData),
                        colorScheme: colorScheme
                    )
                }
            } else {
                if isSelfStudy {
                    gradientManager.updateGradientForContext(
                        context: .upcomingSelfStudy, colorScheme: colorScheme
                    )
                } else {
                    gradientManager.updateGradientForContext(
                        context: .upcomingClass(subject: upcomingInfo.classData),
                        colorScheme: colorScheme
                    )
                }
            }
        } else {
            gradientManager.updateGradientForContext(
                context: .afterSchool, colorScheme: colorScheme
            )
        }
    }

    private func saveSettings() {
        Configuration.selectedDayOverride = selectedDayOverride
        Configuration.setAsToday = setAsToday
        Configuration.isHolidayMode = isHolidayMode
        Configuration.holidayHasEndDate = holidayHasEndDate
        Configuration.holidayEndDate = holidayEndDate
    }

    // MARK: - Components

    private var contentView: some View {
        VStack(spacing: 20) {
            mainContentView
            Spacer(minLength: 60)
        }
        .padding(.top, 10)
    }

    private var scheduleButton: some View {
        Button {
            HapticManager.shared.playButtonTap()
            isSettingsSheetPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .symbolRenderingMode(.hierarchical)
        }
        .disabled(!isAuthenticated)
        .opacity(isAuthenticated ? 1.0 : 0.5)
    }

    private var scheduleSettingsSheet: some View {
        ScheduleSettingsSheet(
            selectedDay: $classtableViewModel.selectedDayOverride,
            setAsToday: $classtableViewModel.setAsToday,
            isHolidayMode: $classtableViewModel.isHolidayMode,
            isPresented: $isSettingsSheetPresented,
            holidayEndDate: $classtableViewModel.holidayEndDate,
            holidayHasEndDate: $classtableViewModel.holidayHasEndDate
        )
        .presentationDetents([.medium, .large])
    }

    // MARK: - Subviews

    private var mainContentView: some View {
        TodayMainContentView(
            isAuthenticated: isAuthenticated,
            isHolidayActive: classtableViewModel.isHolidayActive(),
            isLoading: isLoading,
            upcomingClassInfo: upcomingClassInfo,
            assemblyTime: assemblyTime,
            arrivalTime: arrivalTime,
            isCurrentDateWeekend: isCurrentDateWeekend(),
            isHolidayMode: isHolidayMode,
            holidayHasEndDate: holidayHasEndDate,
            holidayEndDate: holidayEndDate,
            classtableViewModel: classtableViewModel,
            effectiveDayIndex: effectiveDayIndex,
            currentTime: currentTime,
            setAsToday: setAsToday,
            selectedDayOverride: selectedDayOverride,
            animateCards: animateCards,
            effectiveDate: classtableViewModel.effectiveDateForSelectedDay
        )
    }

    // MARK: - Computed Properties

    private var toolbarStatusText: String? {
        if let override = selectedDayOverride {
            return "Viewing \(TodayViewHelpers.weekdayName(for: override + 1))'s schedule"
        } else if classtableViewModel.isHolidayActive(), holidayHasEndDate {
            return "Holiday until \(holidayEndDateString)"
        } else if isHolidayMode {
            return "Holiday Mode"
        }
        return nil
    }

    private var toolbarStatusColor: Color {
        if selectedDayOverride != nil { return AppColor.brand }
        if classtableViewModel.isHolidayActive() || isHolidayMode { return .orange }
        return .secondary
    }

    private var formattedDate: String {
        TodayViewHelpers.formatDateString(currentTime)
    }

    var greeting: String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        switch hour {
        case 6 ..< 12: return "Good Morning"
        case 12 ..< 18: return "Good Afternoon"
        default: return "Good Evening"
        }
    }

    private var isAuthenticated: Bool {
        AuthServiceV2.shared.isAuthenticated
    }

    private var assemblyTime: String {
        let dayIndex = effectiveDayIndex
        if dayIndex == 0 {
            return "7:45 - 8:05"
        } // Monday
        else if dayIndex >= 1, dayIndex <= 4 {
            return "7:55 - 8:05"
        } // Tues - Fri
        else {
            return "No assembly"
        }
    }

    private var arrivalTime: String {
        let dayIndex = effectiveDayIndex
        if dayIndex == 0 {
            return "before 7:45"
        } // Monday
        else if dayIndex >= 1, dayIndex <= 4 {
            return "before 7:55"
        } // Tues - Fri
        else {
            return "No arrival requirement"
        }
    }

    private var holidayEndDateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: holidayEndDate)
    }

    // MARK: - Helper Methods

    private func setupOnAppear() {
        checkForDateChange()

        // Ensure that on first app launch we're not selecting any specific day
        if AnimationManager.shared.isFirstLaunch {
            classtableViewModel.selectedDayOverride = nil
            classtableViewModel.setAsToday = false
            Configuration.selectedDayOverride = nil
            Configuration.setAsToday = false
        }

        if AuthServiceV2.shared.isAuthenticated {
            // Optimistic auth or verified — load from cache or fetch
            let cacheStatus = classtableViewModel.getCacheStatus()
            if !cacheStatus.hasValidYearsCache || !cacheStatus.hasValidTimetableCache {
                isLoading = true
                classtableViewModel.fetchYears()
            } else {
                isLoading = false
            }

            // If timetable is already loaded from cache (no onChange will fire),
            // explicitly trigger Live Activity + Worker registration.
            if !classtableViewModel.timetable.isEmpty {
                ClassActivityManager.shared.setHolidayActive(classtableViewModel.isHolidayActive())
                classtableViewModel.startLiveActivityIfNeeded(timetable: classtableViewModel.timetable)
                ClassActivityManager.shared.setTimetable(classtableViewModel.timetable)
            }
        }

        syncLoadingState()

        classtableViewModel.startTimer()

        animateCards = true
        AnimationManager.shared.markAppLaunched()
    }

    /// Check if we need to reset the selected day override
    private func checkForDateChange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastLaunch = Configuration.lastAppLaunchDate {
            let lastLaunchDay = calendar.startOfDay(for: lastLaunch)

            // Reset settings if this is a new day
            if !calendar.isDate(today, inSameDayAs: lastLaunchDay) {
                classtableViewModel.selectedDayOverride = nil
                classtableViewModel.setAsToday = false
                Configuration.selectedDayOverride = nil
                Configuration.setAsToday = false
            }
        }

        // Update last app launch date
        Configuration.lastAppLaunchDate = Date()
    }

    private func handleYearsChange(_ years: [Year]) {
        if !years.isEmpty, !classtableViewModel.selectedYearId.isEmpty {
            // Check if we need to fetch or if we have valid cache
            let cacheStatus = classtableViewModel.getCacheStatus()
            if !cacheStatus.hasValidTimetableCache {
                classtableViewModel.fetchTimetable()
            }
        } else if !years.isEmpty {
            classtableViewModel.selectYear(years.first!.W_YearID)
        }
    }

    private func handleAuthChange(_ isAuthenticated: Bool) {
        if isAuthenticated {
            // Freshly authenticated (login or background reauth) — load timetable if needed.
            // Only fetch if timetable is empty AND years haven't started loading yet
            // (handleYearsChange will trigger fetchTimetable when years arrive).
            if classtableViewModel.timetable.isEmpty, classtableViewModel.years.isEmpty,
               !classtableViewModel.isLoadingYears
            {
                isLoading = true
                classtableViewModel.fetchYears()
            }
        } else {
            classtableViewModel.timetable = []

            // Reset all schedule settings when logged out
            classtableViewModel.selectedDayOverride = nil
            classtableViewModel.setAsToday = false
            classtableViewModel.isHolidayMode = false

            // Also reset in Configuration to ensure persistence
            Configuration.selectedDayOverride = nil
            Configuration.setAsToday = false
            Configuration.isHolidayMode = false

            // No animation when switching between views
            animateCards = true
        }

        syncLoadingState()
    }

    private func isCurrentDateWeekend() -> Bool {
        if let override = selectedDayOverride {
            return override < 0 || override >= 5
        } else {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: currentTime)
            return weekday == 1 || weekday == 7
        }
    }

    private func syncLoadingState() {
        isLoading = classtableViewModel.isLoadingYears || classtableViewModel.isLoadingTimetable
    }
}
