import Foundation

/// Helper functions that can be shared between components
enum TodayViewHelpers {
    static func weekdayName(for index: Int) -> String {
        let days = ["Mon", "Tue", "Wed", "Thu", "Fri"]
        guard index >= 1, index <= 5 else { return "" }
        return days[index - 1]
    }

    static func isCurrentDateWeekend() -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    static func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter.string(from: date)
    }
}
