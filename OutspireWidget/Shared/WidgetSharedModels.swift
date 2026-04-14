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
        periods: [WidgetClassPeriods.Period] = WidgetClassPeriods.today
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
            let parts = raw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let teacher = parts.indices.contains(0) ? parts[0] : ""
            let rawSubject = parts.indices.contains(1) ? parts[1] : parts.first ?? ""
            let room = parts.indices.contains(2) ? parts[2] : ""
            let subject = rawSubject.replacingOccurrences(
                of: "\\(\\d+\\)$",
                with: "",
                options: .regularExpression
            )
            let isSelfStudy = trimmed.isEmpty
                || subject.localizedCaseInsensitiveContains("self-study")
                || subject.localizedCaseInsensitiveContains("self study")

            result.append(ScheduledClass(
                periodNumber: period.number,
                className: isSelfStudy ? "Self-Study" : subject,
                roomNumber: room,
                teacherName: teacher,
                startTime: period.startTime,
                endTime: period.endTime,
                isSelfStudy: isSelfStudy
            ))
        }

        return result
    }

    static func breakKind(
        between current: ScheduledClass,
        and next: ScheduledClass
    ) -> ScheduleBreakKind {
        if current.periodNumber == 4, next.periodNumber == 5 {
            return .lunch
        }
        return .regular
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
    case ending
    case upcoming
    case `break`
    case event
    case completed
    case noClasses
    case notAuthenticated
    case holiday
}
