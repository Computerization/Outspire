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

    private func loadCachedData() {
        // Load cached years
        if let cachedYearsData = UserDefaults.standard.data(forKey: "cachedYears"),
           let decodedYears = try? JSONDecoder().decode([Year].self, from: cachedYearsData),
           isCacheValid(for: "yearsCacheTimestamp")
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

    private func loadCachedTimetable(for yearId: String) {
        guard !yearId.isEmpty else { return }

        let cacheKey = "cachedTimetable-\(yearId)"
        let timestampKey = "timetableCacheTimestamp-\(yearId)"
        let versionKey = "timetableCacheVersion-\(yearId)"

        if let cachedTimetableData = UserDefaults.standard.data(forKey: cacheKey),
           let decodedTimetable = try? JSONDecoder().decode(
               [[String]].self, from: cachedTimetableData
           ),
           isCacheValid(for: timestampKey),
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
                case let .failure(error):
                    self.errorMessage = "Failed to load years: \(error.localizedDescription)"
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
                            switch result {
                            case let .success(items):
                                let grid = Self.buildGrid(from: items)
                                self.timetable = grid
                                self.cacheTimetable(grid, for: self.selectedYearId)
                            case let .failure(error):
                                self.errorMessage = "Failed to load timetable: \(error.localizedDescription)"
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
                switch result {
                case let .success(items):
                    let grid = Self.buildGrid(from: items)
                    self.timetable = grid
                    self.cacheTimetable(grid, for: self.selectedYearId)
                case let .failure(error):
                    self.errorMessage = "Failed to load timetable: \(error.localizedDescription)"
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
}
