import Foundation

struct ScheduledClass: Codable, Hashable, Identifiable {
    var id: Int {
        periodNumber
    }

    let periodNumber: Int
    let className: String
    let roomNumber: String
    let teacherName: String
    let startTime: Date
    let endTime: Date
    let isSelfStudy: Bool
}

enum ScheduleBreakKind: String, Codable, Hashable {
    case regular
    case lunch
}

enum NormalizedScheduleBuilder {
    static let schoolTimeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current

    static func buildDaySchedule(
        from timetable: [[String]],
        dayIndex: Int,
        periods: [ClassPeriod] = ClassPeriodsManager.shared.classPeriods
    ) -> [ScheduledClass] {
        guard !timetable.isEmpty, dayIndex >= 0, dayIndex < 5 else { return [] }

        let dayColumn = dayIndex + 1
        let availablePeriods = periods.sorted { $0.number < $1.number }

        var lastNonEmptyPeriodNumber: Int?
        for period in availablePeriods {
            guard period.number < timetable.count,
                  dayColumn < timetable[period.number].count
            else { continue }

            let raw = timetable[period.number][dayColumn]
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastNonEmptyPeriodNumber = period.number
            }
        }

        guard let lastNonEmptyPeriodNumber else { return [] }

        var result: [ScheduledClass] = []
        for period in availablePeriods where period.number <= lastNonEmptyPeriodNumber {
            guard period.number < timetable.count,
                  dayColumn < timetable[period.number].count
            else { continue }

            let raw = timetable[period.number][dayColumn]
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let info = ClassInfoParser.parse(raw)

            result.append(ScheduledClass(
                periodNumber: period.number,
                className: info.subject ?? "Self-Study",
                roomNumber: info.room ?? "",
                teacherName: info.teacher ?? "",
                startTime: period.startTime,
                endTime: period.endTime,
                isSelfStudy: trimmed.isEmpty || info.isSelfStudy
            ))
        }

        return result
    }

    static func breakKind(
        between current: ScheduledClass,
        and next: ScheduledClass
    ) -> ScheduleBreakKind {
        // Lunch is defined by the school's midday bell boundary, not gap duration.
        if current.periodNumber == 4, next.periodNumber == 5 {
            return .lunch
        }
        return .regular
    }

    static func dayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = schoolTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func weekdayIndex(for date: Date = Date()) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schoolTimeZone
        let weekday = calendar.component(.weekday, from: date)
        return (weekday == 1 || weekday == 7) ? -1 : weekday - 2
    }
}

enum WidgetClassStatus: String, Codable {
    case ongoing
    case ending // <5 min remaining
    case upcoming // before first class
    case `break`
    case event
    case completed
    case noClasses
    case notAuthenticated
    case holiday
}
