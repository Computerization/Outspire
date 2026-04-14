import SwiftUI

/// ClasstableViewModel with Enhanced Caching System
///
/// This view model provides comprehensive caching for academic timetable data to improve
/// app performance and reduce loading times, especially on the first screen (TodayView).
///
/// Key Features:
/// - 1-day cache duration for both years and timetable data
/// - Automatic cache validation with timestamp checking
/// - Background cache loading for instant UI updates
/// - Smart cache invalidation and refresh mechanisms
///
/// Cache Strategy:
/// - Years data is cached for 24 hours (86400 seconds)
/// - Timetable data is cached per year ID for 24 hours
/// - Cache is automatically loaded on initialization
/// - Cache validation prevents unnecessary network requests
/// - Manual refresh capability with force refresh option
///
/// Performance Benefits:
/// - Reduces first screen loading time significantly
/// - Minimizes network requests for frequently accessed data
/// - Provides offline-like experience with cached data
/// - Smooth user experience with background updates
@MainActor
class ClasstableViewModel: ObservableObject {
    private let timetableCacheVersion = 3
    @Published var years: [Year] = []
    @Published var selectedYearId: String = ""
    @Published var timetable: [[String]] = []

    @Published var errorMessage: String?
    @Published var isLoadingYears: Bool = false
    @Published var isLoadingTimetable: Bool = false
    @Published var lastUpdateTime: Date = .init()
    @Published var formattedLastUpdateTime: String = ""
    @Published var isUsingCachedData: Bool = false

    private let cacheDuration: TimeInterval = 86400 // 1 day in seconds

    init() {
        // Clean up outdated cache entries on initialization
        CacheManager.cleanupOutdatedCache()
        loadCachedData()
        updateFormattedTimestamp()
    }

    private func updateFormattedTimestamp() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        self.formattedLastUpdateTime = "Last updated: \(formatter.string(from: lastUpdateTime))"
    }

    private func loadCachedData(ignoreTTL: Bool = false) {
        // Load cached years
        if let cachedYearsData = UserDefaults.standard.data(forKey: "cachedYears"),
           let decodedYears = try? JSONDecoder().decode([Year].self, from: cachedYearsData),
           ignoreTTL || isCacheValid(for: "yearsCacheTimestamp")
        {
            self.years = decodedYears

            // Load the selected year ID
            if let savedYearId = UserDefaults.standard.string(forKey: "selectedYearId"),
               decodedYears.contains(where: { $0.W_YearID == savedYearId })
            {
                self.selectedYearId = savedYearId
            } else if let firstYear = decodedYears.first {
                self.selectedYearId = firstYear.W_YearID
            }

            // Load cached timetable for the selected year
            loadCachedTimetable(for: selectedYearId)
        }
    }

    /// Load cached timetable from UserDefaults.
    /// - Parameter ignoreTTL: When true, loads even if cache has expired (used as
    ///   fallback when network fails — stale data is better than no data).
    private func loadCachedTimetable(for yearId: String, ignoreTTL: Bool = false) {
        guard !yearId.isEmpty else { return }

        let cacheKey = "cachedTimetable-\(yearId)"
        let timestampKey = "timetableCacheTimestamp-\(yearId)"
        let versionKey = "timetableCacheVersion-\(yearId)"

        if let cachedTimetableData = UserDefaults.standard.data(forKey: cacheKey),
           let decodedTimetable = try? JSONDecoder().decode(
               [[String]].self, from: cachedTimetableData
           ),
           ignoreTTL || isCacheValid(for: timestampKey),
           UserDefaults.standard.integer(forKey: versionKey) == timetableCacheVersion
        {
            self.timetable = decodedTimetable

            // Load cached timestamp
            if let cachedTimestamp = UserDefaults.standard.object(forKey: timestampKey)
                as? TimeInterval
            {
                self.lastUpdateTime = Date(timeIntervalSince1970: cachedTimestamp)
            }

            updateFormattedTimestamp()
        }
    }

    private func cacheYears(_ years: [Year]) {
        if let encodedData = try? JSONEncoder().encode(years) {
            UserDefaults.standard.set(encodedData, forKey: "cachedYears")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "yearsCacheTimestamp")
        }
    }

    private func cacheTimetable(_ timetable: [[String]], for yearId: String) {
        let cacheKey = "cachedTimetable-\(yearId)"
        let timestampKey = "timetableCacheTimestamp-\(yearId)"
        let versionKey = "timetableCacheVersion-\(yearId)"

        if let encodedData = try? JSONEncoder().encode(timetable) {
            UserDefaults.standard.set(encodedData, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
            UserDefaults.standard.set(timetableCacheVersion, forKey: versionKey)
            self.lastUpdateTime = Date()
            updateFormattedTimestamp()

            // Share with widget
            WidgetDataManager.updateTimetable(timetable)

            // Schedule class reminders
            NotificationManager.shared.scheduleClassReminders(from: timetable)
        }
    }

    private func isCacheValid(for key: String) -> Bool {
        let lastUpdate = UserDefaults.standard.double(forKey: key)
        let currentTime = Date().timeIntervalSince1970
        return (currentTime - lastUpdate) < cacheDuration
    }

    func fetchYears(forceRefresh: Bool = false) {
        if !forceRefresh, !years.isEmpty, isCacheValid(for: "yearsCacheTimestamp") {
            if timetable.isEmpty, !selectedYearId.isEmpty { fetchTimetable(forceRefresh: forceRefresh) }
            return
        }

        isLoadingYears = true
        errorMessage = nil

        TimetableServiceV2.shared.fetchYearOptions { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoadingYears = false
                switch result {
                case let .success(options):
                    let mapped: [Year] = options.map { Year(W_YearID: $0.id, W_Year: $0.name) }
                    self.years = mapped
                    self.cacheYears(mapped)
                    if let first = mapped.first {
                        self.selectedYearId = first.W_YearID
                        UserDefaults.standard.set(first.W_YearID, forKey: "selectedYearId")
                        self.fetchTimetable(forceRefresh: forceRefresh)
                    }
                case .failure:
                    // Fall back to cached data silently — ignore TTL since
                    // stale data is better than an empty screen when offline.
                    if self.years.isEmpty {
                        self.loadCachedData(ignoreTTL: true)
                        self.isUsingCachedData = !self.years.isEmpty
                    }
                }
            }
        }
    }

    func fetchTimetable(forceRefresh: Bool = false) {
        guard !selectedYearId.isEmpty else {
            errorMessage = "Please select a year."
            return
        }

        let timestampKey = "timetableCacheTimestamp-\(selectedYearId)"
        if !forceRefresh, !timetable.isEmpty, isCacheValid(for: timestampKey) { return }

        isLoadingTimetable = true
        errorMessage = nil

        // studentId is optional on server; prefer session user id if available
        var sid = AuthServiceV2.shared.user?.userId.map(String.init)
        if sid == nil {
            // Try to resolve user id from profile before fetching
            AuthServiceV2.shared.ensureProfile { _ in
                sid = AuthServiceV2.shared.user?.userId.map(String.init)
                TimetableServiceV2.shared
                    .fetchTimetable(yearId: self.selectedYearId, studentId: sid) { [weak self] result in
                        guard let self = self else { return }
                        DispatchQueue.main.async {
                            self.isLoadingTimetable = false
                            self.isUsingCachedData = false
                            switch result {
                            case let .success(items):
                                let grid = Self.buildGrid(from: items)
                                self.timetable = grid
                                self.cacheTimetable(grid, for: self.selectedYearId)
                            case .failure:
                                self.loadCachedTimetable(for: self.selectedYearId, ignoreTTL: true)
                                self.isUsingCachedData = !self.timetable.isEmpty
                            }
                        }
                    }
            }
            return
        }
        TimetableServiceV2.shared.fetchTimetable(yearId: selectedYearId, studentId: sid) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoadingTimetable = false
                self.isUsingCachedData = false
                switch result {
                case let .success(items):
                    let grid = Self.buildGrid(from: items)
                    self.timetable = grid
                    self.cacheTimetable(grid, for: self.selectedYearId)
                case .failure:
                    self.loadCachedTimetable(for: self.selectedYearId, ignoreTTL: true)
                    self.isUsingCachedData = !self.timetable.isEmpty
                }
            }
        }
    }

    // Build legacy 2D grid from v2 timetable items
    // IMPORTANT: Row index must match period number so TodayView can index timetable[period.number]
    private static func buildGrid(from items: [V2TimetableItem]) -> [[String]] {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        let header = [""] + ["Mon", "Tue", "Wed", "Thu", "Fri"]
        var dayIndex: [String: Int] = [:]
        for (i, d) in days.enumerated() {
            dayIndex[d] = i + 1
        }

        // Determine maximum period count from configured periods (fallback to items)
        let configuredMax = ClassPeriodsManager.shared.classPeriods.map { $0.number }.max() ?? 9
        let itemsMax = items.map { $0.period }.max() ?? configuredMax
        let maxPeriod = max(configuredMax, itemsMax)

        var grid: [[String]] = []
        grid.append(header)

        // Create a row for every period index so missing classes stay empty (self-study)
        for p in 1 ... maxPeriod {
            var row = Array(repeating: "", count: header.count)
            row[0] = String(p)
            for it in items where it.period == p {
                guard let col = dayIndex[it.day] else { continue }
                let subject = it.course ?? ""
                let room = it.room ?? ""
                let teacher = it.teacher ?? ""
                // UI expects order: Teacher (top), Subject (pill), Room (bottom)
                let display = [teacher, subject, room].filter { !$0.isEmpty }.joined(separator: "\n")
                row[col] = display
            }
            grid.append(row)
        }
        return grid
    }

    func refreshData() {
        // Clear error message
        errorMessage = nil

        // Update timestamp immediately for visual feedback
        lastUpdateTime = Date()
        updateFormattedTimestamp()

        // Force refresh both years and timetable
        fetchYears(forceRefresh: true)
    }

    func selectYear(_ yearId: String) {
        guard yearId != selectedYearId else { return }

        selectedYearId = yearId
        UserDefaults.standard.set(yearId, forKey: "selectedYearId")

        // Load cached timetable for the new year if available
        loadCachedTimetable(for: yearId)

        // If no cached data or cache is invalid, fetch new data
        let timestampKey = "timetableCacheTimestamp-\(yearId)"
        if timetable.isEmpty || !isCacheValid(for: timestampKey) {
            fetchTimetable()
        }
    }

    // MARK: - Cache Management

    func clearCache() {
        // Clear years cache
        UserDefaults.standard.removeObject(forKey: "cachedYears")
        UserDefaults.standard.removeObject(forKey: "yearsCacheTimestamp")

        // Clear all timetable caches
        for year in years {
            let cacheKey = "cachedTimetable-\(year.W_YearID)"
            let timestampKey = "timetableCacheTimestamp-\(year.W_YearID)"
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: timestampKey)
        }

        // Clear selected year
        UserDefaults.standard.removeObject(forKey: "selectedYearId")

        // Reset view model state
        years = []
        timetable = []
        selectedYearId = ""
        errorMessage = nil
    }

    func getCacheStatus() -> (hasValidYearsCache: Bool, hasValidTimetableCache: Bool) {
        let hasValidYearsCache = !years.isEmpty && isCacheValid(for: "yearsCacheTimestamp")
        let hasValidTimetableCache =
            !timetable.isEmpty && !selectedYearId.isEmpty
                && isCacheValid(for: "timetableCacheTimestamp-\(selectedYearId)")

        return (hasValidYearsCache, hasValidTimetableCache)
    }

    // MARK: - Timer & Current Time

    @Published var currentTime = Date()
    private var timer: Timer?

    /// Settings that the view binds to; the VM uses them to compute upcoming class info.
    @Published var selectedDayOverride: Int? = Configuration.selectedDayOverride
    @Published var setAsToday: Bool = Configuration.setAsToday
    @Published var isHolidayMode: Bool = Configuration.isHolidayMode
    @Published var holidayHasEndDate: Bool = Configuration.holidayHasEndDate
    @Published var holidayEndDate: Date = Configuration.holidayEndDate

    func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = Date()

                let second = Calendar.current.component(.second, from: self.currentTime)
                if second % 10 == 0 {
                    if self.checkForClassTransition() {
                        self.forceContentRefresh()
                    }
                }
                // Check if all classes are done and end the Live Activity
                if second == 0 {
                    self.endLiveActivityIfDone()
                }
            }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Effective Day Index

    var effectiveDayIndex: Int {
        if isHolidayActive() {
            return -1
        }
        if let override = selectedDayOverride {
            return override
        } else {
            let calendar = Calendar.current
            let weekday = calendar.component(.weekday, from: currentTime)
            return (weekday == 1 || weekday == 7) ? -1 : weekday - 2
        }
    }

    // MARK: - Upcoming Class Info

    var upcomingClassInfo:
        (period: ClassPeriod, classData: String, dayIndex: Int, isForToday: Bool)?
    {
        guard !timetable.isEmpty else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let isForToday = selectedDayOverride == nil
        let isWeekendToday = (currentWeekday == 1 || currentWeekday == 7)
        let dayIndex = effectiveDayIndex

        if isHolidayActive() { return nil }
        if isForToday && isWeekendToday && Configuration.showMondayClass {
            return getNextClassForDay(0, isForToday: false)
        }
        if dayIndex < 0 || dayIndex >= 5 { return nil }

        return getNextClassForDay(dayIndex, isForToday: isForToday)
    }

    // MARK: - Class Resolution Helpers

    func getNextClassForDay(_ dayIndex: Int, isForToday: Bool) -> (
        period: ClassPeriod, classData: String, dayIndex: Int, isForToday: Bool
    )? {
        if setAsToday, selectedDayOverride != nil {
            let periodInfo = ClassPeriodsManager.shared.getCurrentOrNextPeriod(
                useEffectiveDate: true,
                effectiveDate: effectiveDateForSelectedDay
            )
            return getClassForPeriod(periodInfo, dayIndex: dayIndex, isForToday: true)
        } else if isForToday {
            let periodInfo = ClassPeriodsManager.shared.getCurrentOrNextPeriod()
            return getClassForPeriod(periodInfo, dayIndex: dayIndex, isForToday: true)
        } else {
            for row in 1 ..< timetable.count {
                if row < timetable.count,
                   dayIndex + 1 < timetable[row].count
                {
                    let classData = timetable[row][dayIndex + 1]
                    let isSelfStudy = classData.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty

                    if let period = ClassPeriodsManager.shared.classPeriods.first(where: {
                        $0.number == row
                    }) {
                        if isSelfStudy {
                            return (
                                period: period, classData: "You\nSelf-Study", dayIndex: dayIndex,
                                isForToday: false
                            )
                        } else {
                            return (
                                period: period, classData: classData, dayIndex: dayIndex,
                                isForToday: false
                            )
                        }
                    }
                }
            }
            return nil
        }
    }

    func getClassForPeriod(
        _ periodInfo: (period: ClassPeriod?, isCurrentlyActive: Bool),
        dayIndex: Int, isForToday: Bool
    ) -> (period: ClassPeriod, classData: String, dayIndex: Int, isForToday: Bool)? {
        guard let startPeriod = periodInfo.period else { return nil }

        func dataFor(periodNumber: Int) -> String? {
            guard periodNumber < timetable.count,
                  dayIndex + 1 < timetable[periodNumber].count else { return nil }
            return timetable[periodNumber][dayIndex + 1]
        }

        if isForToday {
            if periodInfo.isCurrentlyActive {
                if let raw = dataFor(periodNumber: startPeriod.number) {
                    let isEmpty = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    let classData = isEmpty ? "You\nSelf-Study" : raw
                    return (period: startPeriod, classData: classData, dayIndex: dayIndex, isForToday: isForToday)
                } else {
                    return (
                        period: startPeriod,
                        classData: "You\nSelf-Study",
                        dayIndex: dayIndex,
                        isForToday: isForToday
                    )
                }
            } else {
                let allPeriods = ClassPeriodsManager.shared.classPeriods.map { $0.number }
                for p in allPeriods where p >= startPeriod.number {
                    if let raw = dataFor(periodNumber: p) {
                        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            if let periodObj = ClassPeriodsManager.shared.classPeriods
                                .first(where: { $0.number == p })
                            {
                                return (period: periodObj, classData: raw, dayIndex: dayIndex, isForToday: isForToday)
                            }
                        }
                    }
                }
                return nil
            }
        }

        guard let raw = dataFor(periodNumber: startPeriod.number) else { return nil }
        let isSelfStudy = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let classData = isSelfStudy ? "You\nSelf-Study" : raw
        return (period: startPeriod, classData: classData, dayIndex: dayIndex, isForToday: isForToday)
    }

    // MARK: - Holiday & Date Helpers

    func isHolidayActive() -> Bool {
        if !isHolidayMode {
            return false
        }
        if !holidayHasEndDate {
            return true
        }
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: currentTime)
        let endDay = calendar.startOfDay(for: holidayEndDate)
        return currentDay <= endDay
    }

    var effectiveDateForSelectedDay: Date? {
        guard setAsToday, let override = selectedDayOverride else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let targetWeekday = override + 2

        if targetWeekday == currentWeekday {
            return now
        }

        var daysToAdd = targetWeekday - currentWeekday
        if daysToAdd > 3 {
            daysToAdd -= 7
        } else if daysToAdd < -3 {
            daysToAdd += 7
        }

        return calendar.date(byAdding: .day, value: daysToAdd, to: now)
    }

    // MARK: - Class Transition Detection

    func checkForClassTransition() -> Bool {
        if let upcoming = upcomingClassInfo,
           upcoming.isForToday && upcoming.period.isCurrentlyActive()
        {
            let secondsRemaining = upcoming.period.endTime.timeIntervalSince(Date())
            if secondsRemaining <= 5 && secondsRemaining > 0 {
                return true
            }
        }
        return false
    }

    func forceContentRefresh() {
        if AuthServiceV2.shared.isAuthenticated {
            fetchTimetable()
        }
        currentTime = Date()
    }

    // MARK: - Live Activity

    /// The real weekday index (0=Mon..4=Fri, -1=weekend).
    /// Used exclusively for Live Activity lifecycle — ignores selectedDayOverride/setAsToday.
    private var realTodayDayIndex: Int {
        NormalizedScheduleBuilder.weekdayIndex(for: Date())
    }

    func startLiveActivityIfNeeded(timetable: [[String]]) {
        let todayIndex = realTodayDayIndex
        guard !timetable.isEmpty,
              !isHolidayActive(),
              !ClassActivityManager.shared.isActivityRunning,
              todayIndex >= 0, todayIndex < 5
        else { return }

        let schedule = NormalizedScheduleBuilder.buildDaySchedule(
            from: timetable,
            dayIndex: todayIndex
        )
        let now = Date()

        guard schedule.contains(where: { $0.endTime > now }) else { return }

        // Don't start LA before the first class starts (allow 30 min before)
        if let firstStart = schedule.map(\.startTime).min() {
            guard now >= firstStart.addingTimeInterval(-1800) else { return }
        }

        ClassActivityManager.shared.startActivity(schedule: schedule, timetable: timetable)
    }

    /// End the Live Activity if all classes for today are done.
    /// Uses realTodayDayIndex to avoid ending based on previewed day.
    private func endLiveActivityIfDone() {
        let todayIndex = realTodayDayIndex
        guard ClassActivityManager.shared.isActivityRunning,
              !timetable.isEmpty,
              todayIndex >= 0, todayIndex < 5
        else { return }

        let now = Date()
        let schedule = NormalizedScheduleBuilder.buildDaySchedule(
            from: timetable,
            dayIndex: todayIndex
        )

        if !schedule.contains(where: { $0.endTime > now }) {
            ClassActivityManager.shared.endActivity()
        }
    }
}
