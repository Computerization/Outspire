import Foundation

class CacheManager {
    static func clearAllCache() {
        let userDefaults = UserDefaults.standard

        // Preserve app settings
        let hideAcademicScore = Configuration.hideAcademicScore

        // Clear club activities cache
        userDefaults.removeObject(forKey: "cachedClubGroups")
        userDefaults.removeObject(forKey: "clubActivitiesCacheTimestamp")
        userDefaults.removeObject(forKey: "selectedClubGroupId")

        // Clear academic scores cache
        userDefaults.removeObject(forKey: "cachedTerms")
        userDefaults.removeObject(forKey: "termsCacheTimestamp")
        userDefaults.removeObject(forKey: "selectedTermId")

        // Clear classtable cache
        clearClasstableCache()

        // Clear school arrangements cache
        userDefaults.removeObject(forKey: "cachedSchoolArrangements")
        userDefaults.removeObject(forKey: "cachedSchoolArrangements-timestamp")

        // Clear pattern-based keys
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("cachedActivities-") || key.hasPrefix("cachedScores-")
                || key.hasPrefix("scoresCacheTimestamp-") || key.hasPrefix("cachedTimetable-")
                || key.hasPrefix("timetableCacheTimestamp-")
                || key.hasPrefix("cachedSchoolArrangementDetail-")
            {
                userDefaults.removeObject(forKey: key)
                userDefaults.removeObject(forKey: "\(key)-timestamp")
            }
        }

        // Clear terms with data tracking
        userDefaults.removeObject(forKey: "termsWithData")

        // Restore preserved settings
        Configuration.hideAcademicScore = hideAcademicScore

        // Remove reference to AddRecordViewModel.cachedFormData - we'll handle this differently
        // instead of directly accessing a private property
        NotificationCenter.default.post(name: Notification.Name("ClearCachedFormData"), object: nil)
    }

    // Clear only club activities related cache
    static func clearClubActivitiesCache() {
        let userDefaults = UserDefaults.standard

        userDefaults.removeObject(forKey: "cachedClubGroups")
        userDefaults.removeObject(forKey: "clubActivitiesCacheTimestamp")
        userDefaults.removeObject(forKey: "selectedClubGroupId")

        // Clear all cached activities but preserve the groups list
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("cachedActivities-") {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    // Clear only academic scores related cache
    static func clearAcademicScoresCache() {
        let userDefaults = UserDefaults.standard

        userDefaults.removeObject(forKey: "cachedTerms")
        userDefaults.removeObject(forKey: "termsCacheTimestamp")
        userDefaults.removeObject(forKey: "selectedTermId")
        userDefaults.removeObject(forKey: "termsWithData")

        // Clear all cached scores
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("cachedScores-") || key.hasPrefix("scoresCacheTimestamp-") {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    // Clear only classtable related cache
    static func clearClasstableCache() {
        let userDefaults = UserDefaults.standard

        // Clear years cache
        userDefaults.removeObject(forKey: "cachedYears")
        userDefaults.removeObject(forKey: "yearsCacheTimestamp")
        userDefaults.removeObject(forKey: "selectedYearId")

        // Clear all timetable caches
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("cachedTimetable-") || key.hasPrefix("timetableCacheTimestamp-") {
                userDefaults.removeObject(forKey: key)
            }
        }
    }

    // Clear school arrangements cache
    static func clearSchoolArrangementsCache() {
        let userDefaults = UserDefaults.standard

        userDefaults.removeObject(forKey: "cachedSchoolArrangements")
        userDefaults.removeObject(forKey: "cachedSchoolArrangements-timestamp")

        // Clear all school arrangement details
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("cachedSchoolArrangementDetail-") {
                userDefaults.removeObject(forKey: key)
                userDefaults.removeObject(forKey: "\(key)-timestamp")
            }
        }
    }

    // MARK: - Cache Status and Management

    /// Get cache status for all major components
    static func getCacheStatus() -> CacheStatus {
        let userDefaults = UserDefaults.standard
        let currentTime = Date().timeIntervalSince1970

        // Check years cache (1 day)
        let yearsTimestamp = userDefaults.double(forKey: "yearsCacheTimestamp")
        let hasValidYearsCache =
            (currentTime - yearsTimestamp) < 86400
                && userDefaults.data(forKey: "cachedYears") != nil

        // Check terms cache (5 minutes)
        let termsTimestamp = userDefaults.double(forKey: "termsCacheTimestamp")
        let hasValidTermsCache =
            (currentTime - termsTimestamp) < 300 && userDefaults.data(forKey: "cachedTerms") != nil

        // Check club groups cache (5 minutes)
        let clubsTimestamp = userDefaults.double(forKey: "clubActivitiesCacheTimestamp")
        let hasValidClubsCache =
            (currentTime - clubsTimestamp) < 300
                && userDefaults.data(forKey: "cachedClubGroups") != nil

        // Check school arrangements cache (24 hours)
        let arrangementsTimestamp = userDefaults.double(
            forKey: "cachedSchoolArrangements-timestamp")
        let hasValidArrangementsCache =
            (currentTime - arrangementsTimestamp) < 86400
                && userDefaults.data(forKey: "cachedSchoolArrangements") != nil

        // Count timetable caches
        let timetableCacheCount = userDefaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix("cachedTimetable-")
        }.count

        return CacheStatus(
            hasValidYearsCache: hasValidYearsCache,
            hasValidTermsCache: hasValidTermsCache,
            hasValidClubsCache: hasValidClubsCache,
            hasValidArrangementsCache: hasValidArrangementsCache,
            timetableCacheCount: timetableCacheCount,
            lastYearsCacheUpdate: yearsTimestamp > 0
                ? Date(timeIntervalSince1970: yearsTimestamp) : nil,
            lastTermsCacheUpdate: termsTimestamp > 0
                ? Date(timeIntervalSince1970: termsTimestamp) : nil,
            lastClubsCacheUpdate: clubsTimestamp > 0
                ? Date(timeIntervalSince1970: clubsTimestamp) : nil,
            lastArrangementsCacheUpdate: arrangementsTimestamp > 0
                ? Date(timeIntervalSince1970: arrangementsTimestamp) : nil
        )
    }

    /// Get total cache size estimate (rough calculation)
    static func getEstimatedCacheSize() -> String {
        let userDefaults = UserDefaults.standard
        var totalSize = 0

        // Calculate size of cached data
        let cacheKeys = [
            "cachedYears", "cachedTerms", "cachedClubGroups", "cachedSchoolArrangements"
        ]

        for key in cacheKeys {
            if let data = userDefaults.data(forKey: key) {
                totalSize += data.count
            }
        }

        // Add pattern-based cache sizes
        for key in userDefaults.dictionaryRepresentation().keys {
            if key.hasPrefix("cachedTimetable-") || key.hasPrefix("cachedScores-")
                || key.hasPrefix("cachedActivities-")
                || key.hasPrefix("cachedSchoolArrangementDetail-")
            {
                if let data = userDefaults.data(forKey: key) {
                    totalSize += data.count
                }
            }
        }

        // Convert to human readable format
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(totalSize))
    }

    /// Force refresh specific cache type
    static func refreshCache(type: CacheType) {
        switch type {
        case .classtable:
            // Post notification to refresh classtable
            NotificationCenter.default.post(name: .refreshClasstableCache, object: nil)
        case .academicScores:
            // Post notification to refresh academic scores
            NotificationCenter.default.post(name: .refreshAcademicScoresCache, object: nil)
        case .clubActivities:
            // Post notification to refresh club activities
            NotificationCenter.default.post(name: .refreshClubActivitiesCache, object: nil)
        case .schoolArrangements:
            // Post notification to refresh school arrangements
            NotificationCenter.default.post(name: .refreshSchoolArrangementsCache, object: nil)
        }
    }

    // MARK: - Automatic Cache Cleanup

    /// Clean up outdated cache entries automatically
    /// This should be called periodically or on app launch
    static func cleanupOutdatedCache() {
        let userDefaults = UserDefaults.standard
        let currentTime = Date().timeIntervalSince1970

        // Define cache durations for different types (in seconds)
        let cacheDurations: [String: TimeInterval] = [
            "yearsCacheTimestamp": 86400, // 1 day
            "termsCacheTimestamp": 300, // 5 minutes
            "clubActivitiesCacheTimestamp": 300, // 5 minutes
            "cachedSchoolArrangements-timestamp": 86400 // 1 day
        ]

        // Clean up known cache types
        for (timestampKey, duration) in cacheDurations {
            let lastUpdate = userDefaults.double(forKey: timestampKey)
            if (currentTime - lastUpdate) >= duration {
                // Cache is outdated, remove it
                switch timestampKey {
                case "yearsCacheTimestamp":
                    userDefaults.removeObject(forKey: "cachedYears")
                    userDefaults.removeObject(forKey: timestampKey)
                case "termsCacheTimestamp":
                    userDefaults.removeObject(forKey: "cachedTerms")
                    userDefaults.removeObject(forKey: timestampKey)
                    userDefaults.removeObject(forKey: "termsWithData")
                case "clubActivitiesCacheTimestamp":
                    userDefaults.removeObject(forKey: "cachedClubGroups")
                    userDefaults.removeObject(forKey: timestampKey)
                case "cachedSchoolArrangements-timestamp":
                    userDefaults.removeObject(forKey: "cachedSchoolArrangements")
                    userDefaults.removeObject(forKey: timestampKey)
                default:
                    break
                }
            }
        }

        // Clean up pattern-based caches (timetables, scores, activities)
        cleanupPatternBasedCaches()

        // Clean up orphaned cache entries
        cleanupOrphanedCacheEntries()
    }

    /// Clean up pattern-based cache entries that are outdated
    private static func cleanupPatternBasedCaches() {
        let userDefaults = UserDefaults.standard
        let currentTime = Date().timeIntervalSince1970

        // Get all keys from UserDefaults
        let allKeys = userDefaults.dictionaryRepresentation().keys

        // Clean up timetable caches (1 day duration)
        for key in allKeys {
            if key.hasPrefix("timetableCacheTimestamp-") {
                let lastUpdate = userDefaults.double(forKey: key)
                if (currentTime - lastUpdate) >= 86400 { // 1 day
                    let cacheKey = key.replacingOccurrences(
                        of: "timetableCacheTimestamp-", with: "cachedTimetable-"
                    )
                    userDefaults.removeObject(forKey: cacheKey)
                    userDefaults.removeObject(forKey: key)
                }
            }

            // Clean up score caches (5 minutes duration)
            if key.hasPrefix("scoresCacheTimestamp-") {
                let lastUpdate = userDefaults.double(forKey: key)
                if (currentTime - lastUpdate) >= 300 { // 5 minutes
                    let cacheKey = key.replacingOccurrences(
                        of: "scoresCacheTimestamp-", with: "cachedScores-"
                    )
                    userDefaults.removeObject(forKey: cacheKey)
                    userDefaults.removeObject(forKey: key)
                }
            }

            // Clean up activity caches (5 minutes duration)
            if key.hasPrefix("cachedActivities-") {
                let timestampKey = "\(key)-timestamp"
                let lastUpdate = userDefaults.double(forKey: timestampKey)
                if (currentTime - lastUpdate) >= 300 { // 5 minutes
                    userDefaults.removeObject(forKey: key)
                    userDefaults.removeObject(forKey: timestampKey)
                }
            }
        }
    }

    /// Clean up cache entries that no longer have corresponding timestamp entries
    private static func cleanupOrphanedCacheEntries() {
        let userDefaults = UserDefaults.standard
        let allKeys = userDefaults.dictionaryRepresentation().keys

        // Find cache entries without timestamps
        let cacheKeys = allKeys.filter { key in
            key.hasPrefix("cached") && !key.contains("timestamp") && !key.contains("-timestamp")
        }

        for cacheKey in cacheKeys {
            var hasTimestamp = false

            // Check for corresponding timestamp key
            if cacheKey == "cachedYears" {
                hasTimestamp = allKeys.contains("yearsCacheTimestamp")
            } else if cacheKey == "cachedTerms" {
                hasTimestamp = allKeys.contains("termsCacheTimestamp")
            } else if cacheKey == "cachedClubGroups" {
                hasTimestamp = allKeys.contains("clubActivitiesCacheTimestamp")
            } else if cacheKey == "cachedSchoolArrangements" {
                hasTimestamp = allKeys.contains("cachedSchoolArrangements-timestamp")
            } else if cacheKey.hasPrefix("cachedTimetable-") {
                let yearId = cacheKey.replacingOccurrences(of: "cachedTimetable-", with: "")
                hasTimestamp = allKeys.contains("timetableCacheTimestamp-\(yearId)")
            } else if cacheKey.hasPrefix("cachedScores-") {
                let termId = cacheKey.replacingOccurrences(of: "cachedScores-", with: "")
                hasTimestamp = allKeys.contains("scoresCacheTimestamp-\(termId)")
            }

            // Remove orphaned cache entry
            if !hasTimestamp {
                userDefaults.removeObject(forKey: cacheKey)
            }
        }
    }

    /// Get total count of outdated cache entries
    static func getOutdatedCacheCount() -> Int {
        let userDefaults = UserDefaults.standard
        let currentTime = Date().timeIntervalSince1970
        var outdatedCount = 0

        // Check known cache types
        let cacheDurations: [String: TimeInterval] = [
            "yearsCacheTimestamp": 86400,
            "termsCacheTimestamp": 300,
            "clubActivitiesCacheTimestamp": 300,
            "cachedSchoolArrangements-timestamp": 86400
        ]

        for (timestampKey, duration) in cacheDurations {
            let lastUpdate = userDefaults.double(forKey: timestampKey)
            if lastUpdate > 0 && (currentTime - lastUpdate) >= duration {
                outdatedCount += 1
            }
        }

        // Check pattern-based caches
        let allKeys = userDefaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix("timetableCacheTimestamp-") {
                let lastUpdate = userDefaults.double(forKey: key)
                if lastUpdate > 0 && (currentTime - lastUpdate) >= 86400 {
                    outdatedCount += 1
                }
            } else if key.hasPrefix("scoresCacheTimestamp-") {
                let lastUpdate = userDefaults.double(forKey: key)
                if lastUpdate > 0 && (currentTime - lastUpdate) >= 300 {
                    outdatedCount += 1
                }
            }
        }

        return outdatedCount
    }

    /// Schedule automatic cleanup to run periodically
    static func scheduleAutomaticCleanup() {
        // Clean up immediately
        cleanupOutdatedCache()

        // Schedule cleanup to run daily
        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            cleanupOutdatedCache()
        }
    }
}

// MARK: - Supporting Types

struct CacheStatus {
    let hasValidYearsCache: Bool
    let hasValidTermsCache: Bool
    let hasValidClubsCache: Bool
    let hasValidArrangementsCache: Bool
    let timetableCacheCount: Int
    let lastYearsCacheUpdate: Date?
    let lastTermsCacheUpdate: Date?
    let lastClubsCacheUpdate: Date?
    let lastArrangementsCacheUpdate: Date?

    var overallCacheHealth: CacheHealth {
        let validCaches = [
            hasValidYearsCache, hasValidTermsCache, hasValidClubsCache, hasValidArrangementsCache
        ]
        let validCount = validCaches.filter { $0 }.count

        switch validCount {
        case 4: return .excellent
        case 3: return .good
        case 2: return .fair
        case 1: return .poor
        default: return .none
        }
    }
}

enum CacheHealth {
    case excellent, good, fair, poor, none

    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .none: return "No Cache"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        case .none: return "gray"
        }
    }
}

enum CacheType {
    case classtable
    case academicScores
    case clubActivities
    case schoolArrangements
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshClasstableCache = Notification.Name("refreshClasstableCache")
    static let refreshAcademicScoresCache = Notification.Name("refreshAcademicScoresCache")
    static let refreshClubActivitiesCache = Notification.Name("refreshClubActivitiesCache")
    static let refreshSchoolArrangementsCache = Notification.Name("refreshSchoolArrangementsCache")
}
