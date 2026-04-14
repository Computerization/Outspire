import Foundation
import WidgetKit

enum WidgetDataManager {
    private static let suiteName = "group.dev.wrye.Outspire"

    private static var shared: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    // MARK: - Write (main app)

    static func updateTimetable(_ timetable: [[String]]) {
        guard let data = try? JSONEncoder().encode(timetable) else { return }
        shared?.set(data, forKey: "widgetTimetable")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func updateAuthState(_ isAuthenticated: Bool) {
        shared?.set(isAuthenticated, forKey: "widgetAuthState")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func updateHolidayMode(enabled: Bool, hasEndDate: Bool, endDate: Date) {
        shared?.set(enabled, forKey: "widgetHolidayMode")
        shared?.set(hasEndDate, forKey: "widgetHolidayHasEndDate")
        shared?.set(endDate, forKey: "widgetHolidayEndDate")
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func updateStudentInfo(track: String, entryYear: String) {
        shared?.set(track, forKey: "widgetTrack")
        shared?.set(entryYear, forKey: "widgetEntryYear")
    }

    static func clearAll() {
        let keys = [
            "widgetTimetable",
            "widgetAuthState",
            "widgetHolidayMode",
            "widgetHolidayHasEndDate",
            "widgetHolidayEndDate",
            "widgetTrack",
            "widgetEntryYear"
        ]
        keys.forEach { shared?.removeObject(forKey: $0) }
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Read (widget extension)

    static func readTimetable() -> [[String]] {
        guard let data = shared?.data(forKey: "widgetTimetable"),
              let timetable = try? JSONDecoder().decode([[String]].self, from: data)
        else { return [] }
        return timetable
    }

    static func readAuthState() -> Bool {
        shared?.bool(forKey: "widgetAuthState") ?? false
    }

    static func readHolidayMode() -> (enabled: Bool, hasEndDate: Bool, endDate: Date) {
        let enabled = shared?.bool(forKey: "widgetHolidayMode") ?? false
        let hasEndDate = shared?.bool(forKey: "widgetHolidayHasEndDate") ?? false
        let endDate = shared?.object(forKey: "widgetHolidayEndDate") as? Date ?? Date()
        return (enabled, hasEndDate, endDate)
    }
}
