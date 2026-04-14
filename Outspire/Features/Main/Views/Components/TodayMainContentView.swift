import SwiftUI

struct TodayMainContentView: View {
    let isAuthenticated: Bool
    let isHolidayActive: Bool
    let isLoading: Bool
    let upcomingClassInfo:
        (period: ClassPeriod, classData: String, dayIndex: Int, isForToday: Bool)?
    let assemblyTime: String
    let arrivalTime: String
    let isCurrentDateWeekend: Bool
    let isHolidayMode: Bool
    let holidayHasEndDate: Bool
    let holidayEndDate: Date
    let classtableViewModel: ClasstableViewModel
    let effectiveDayIndex: Int
    let currentTime: Date
    let setAsToday: Bool
    let selectedDayOverride: Int?
    let animateCards: Bool
    let effectiveDate: Date?

    var body: some View {
        if isAuthenticated {
            authenticatedContent
        } else {
            notAuthenticatedContent
        }
    }

    private func animatedCard(
        delay: Double, @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        content()
            .padding(.horizontal)
    }

    private var hasValidWeekdaySchedule: Bool {
        effectiveDayIndex >= 0 && effectiveDayIndex < 5 && !classtableViewModel.timetable.isEmpty
    }

    private var contentStateID: String {
        if isHolidayActive { return "holiday" }
        if isLoading { return "loading" }
        if isCurrentDateWeekend { return "weekend" }
        if effectiveDayIndex < 0 || effectiveDayIndex >= 5 { return "noclass" }
        return "schedule-\(effectiveDayIndex)"
    }

    private var authenticatedContent: some View {
        VStack(spacing: AppSpace.lg) {
            // Main content area with smooth transitions
            Group {
                if isHolidayActive {
                    HolidayModeCard(hasEndDate: holidayHasEndDate, endDate: holidayEndDate)
                        .padding(.horizontal)
                        .staggeredEntry(index: 0, animate: animateCards)
                } else if isLoading {
                    UpcomingClassSkeletonView()
                        .padding(.horizontal)
                } else if isCurrentDateWeekend {
                    WeekendCard()
                        .padding(.horizontal)
                        .staggeredEntry(index: 0, animate: animateCards)
                } else if effectiveDayIndex < 0 || effectiveDayIndex >= 5 {
                    NoClassCard()
                        .padding(.horizontal)
                        .staggeredEntry(index: 0, animate: animateCards)
                } else {
                    VStack(spacing: AppSpace.lg) {
                        // Status banner when classes are over
                        if areClassesOverForToday() {
                            NoClassCard(isDimmed: true)
                                .padding(.horizontal)
                                .staggeredEntry(index: 0, animate: animateCards)
                        }

                        // Schedule card — always visible on weekdays
                        UnifiedScheduleCard(
                            viewModel: classtableViewModel,
                            dayIndex: effectiveDayIndex,
                            isForToday: selectedDayOverride == nil,
                            setAsToday: setAsToday,
                            effectiveDate: effectiveDate
                        )
                        .padding(.horizontal)
                        .staggeredEntry(index: 1, animate: animateCards)
                    }
                }
            }
            .id(contentStateID)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.easeInOut(duration: 0.3), value: contentStateID)

            // Quick links
            QuickLinksCard()
                .padding(.horizontal)
                .staggeredEntry(index: 2, animate: animateCards)
        }
    }

    private var notAuthenticatedContent: some View {
        SignInPromptCard()
            .padding(.horizontal)
    }

    /// Method to check if all classes for today are over
    private func areClassesOverForToday() -> Bool {
        // Only check this for weekdays
        guard !isCurrentDateWeekend, !isHolidayActive, effectiveDayIndex >= 0,
              effectiveDayIndex <= 4
        else {
            return false
        }

        let now = Date()

        // Get the last period of the day
        if let lastClassPeriod = ClassPeriodsManager.shared.classPeriods.last?.number,
           let timetable = classtableViewModel.timetable.isEmpty
           ? nil : classtableViewModel.timetable,
           !timetable.isEmpty
        {
            // Check if there's any class data for this day
            if effectiveDayIndex + 1 < timetable[min(lastClassPeriod, timetable.count - 1)].count {
                // Check if we have any scheduled classes
                let classes = getScheduledClassesForDay(effectiveDayIndex)
                if !classes.isEmpty, let lastPeriodNumber = classes.map(\.0).max(),
                   let lastPeriod = ClassPeriodsManager.shared.classPeriods.first(where: {
                       $0.number == lastPeriodNumber
                   })
                {
                    // If current time is after the end time of the last class, all classes are over
                    return now > lastPeriod.endTime
                }
            }
        }

        return false
    }

    /// Helper to get scheduled classes for a day
    private func getScheduledClassesForDay(_ dayIndex: Int) -> [(Int, String)] {
        var classes: [(Int, String)] = []
        guard !classtableViewModel.timetable.isEmpty, dayIndex >= 0, dayIndex < 5 else {
            return classes
        }

        for row in 1 ..< classtableViewModel.timetable.count {
            if row < classtableViewModel.timetable.count,
               dayIndex + 1 < classtableViewModel.timetable[row].count
            {
                let classData = classtableViewModel.timetable[row][dayIndex + 1]
                if !classData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    classes.append((row, classData))
                }
            }
        }
        return classes
    }
}
