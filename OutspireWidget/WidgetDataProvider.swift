import Foundation
import WidgetKit

struct ClassWidgetEntry: TimelineEntry {
    let date: Date
    let status: WidgetClassStatus
    let currentClass: ScheduledClass?
    let upcomingClasses: [ScheduledClass]
    let eventName: String?
}

struct ClassWidgetProvider: TimelineProvider {
    typealias Entry = ClassWidgetEntry

    func placeholder(in context: Context) -> ClassWidgetEntry {
        ClassWidgetEntry(
            date: Date(),
            status: .ongoing,
            currentClass: ScheduledClass(
                periodNumber: 3, className: "Mathematics", roomNumber: "A108",
                teacherName: "Yu Song", startTime: Date(), endTime: Date().addingTimeInterval(2400),
                isSelfStudy: false
            ),
            upcomingClasses: [],
            eventName: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ClassWidgetEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassWidgetEntry>) -> Void) {
        guard WidgetDataReader.readAuthState() else {
            let entry = ClassWidgetEntry(
                date: Date(),
                status: .notAuthenticated,
                currentClass: nil,
                upcomingClasses: [],
                eventName: nil
            )
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }

        let holiday = WidgetDataReader.readHolidayMode()
        if holiday.enabled {
            let entry = ClassWidgetEntry(
                date: Date(),
                status: .holiday,
                currentClass: nil,
                upcomingClasses: [],
                eventName: nil
            )
            completion(Timeline(entries: [entry], policy: .atEnd))
            return
        }

        let timetable = WidgetDataReader.readTimetable()
        let schedule = buildTodaySchedule(from: timetable)

        if schedule.isEmpty {
            let entry = ClassWidgetEntry(
                date: Date(),
                status: .noClasses,
                currentClass: nil,
                upcomingClasses: [],
                eventName: nil
            )
            completion(Timeline(entries: [entry], policy: .after(nextMorning())))
            return
        }

        var entries: [ClassWidgetEntry] = []

        // Before first class
        if let first = schedule.first {
            entries.append(ClassWidgetEntry(
                date: first.startTime.addingTimeInterval(-1800),
                status: .upcoming,
                currentClass: first,
                upcomingClasses: Array(schedule.dropFirst()),
                eventName: nil
            ))
        }

        for (i, cls) in schedule.enumerated() {
            let upcoming = Array(schedule.dropFirst(i + 1))

            entries.append(ClassWidgetEntry(
                date: cls.startTime,
                status: .ongoing,
                currentClass: cls,
                upcomingClasses: upcoming,
                eventName: nil
            ))

            entries.append(ClassWidgetEntry(
                date: cls.endTime.addingTimeInterval(-300),
                status: .ending,
                currentClass: cls,
                upcomingClasses: upcoming,
                eventName: nil
            ))

            if let next = upcoming.first {
                let breakKind = NormalizedScheduleBuilder.breakKind(
                    between: cls,
                    and: next
                )

                let breakClass = ScheduledClass(
                    periodNumber: 0,
                    className: breakKind == .lunch ? "Lunch Break" : "Break",
                    roomNumber: "",
                    teacherName: "",
                    startTime: cls.endTime,
                    endTime: next.startTime,
                    isSelfStudy: false
                )

                entries.append(ClassWidgetEntry(
                    date: cls.endTime,
                    status: .break,
                    currentClass: breakClass,
                    upcomingClasses: [next] + Array(upcoming.dropFirst()),
                    eventName: nil
                ))
            }
        }

        if let last = schedule.last {
            entries.append(ClassWidgetEntry(
                date: last.endTime,
                status: .completed,
                currentClass: nil,
                upcomingClasses: [],
                eventName: nil
            ))
        }

        let now = Date()
        let sortedEntries = entries.sorted { $0.date < $1.date }
        let currentEntry = sortedEntries.last { $0.date <= now }
        let futureEntries = sortedEntries.filter { $0.date > now }
        let filtered = (currentEntry.map { [$0] } ?? []) + futureEntries

        // Use .atEnd for active schedule (entries have exact transition times),
        // .after(nextMorning) for completed state so widget refreshes next day
        let hasActiveEntries = filtered.contains { $0.status != .completed }
        completion(Timeline(entries: filtered, policy: hasActiveEntries ? .atEnd : .after(nextMorning())))
    }

    private func nextMorning() -> Date {
        Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 7, minute: 30),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(86400)
    }

    private func buildTodaySchedule(from timetable: [[String]]) -> [ScheduledClass] {
        guard !timetable.isEmpty else { return [] }

        let dayIndex = NormalizedScheduleBuilder.weekdayIndex(for: Date())
        guard dayIndex >= 0, dayIndex < 5 else { return [] }

        return NormalizedScheduleBuilder.buildDaySchedule(
            from: timetable,
            dayIndex: dayIndex,
            periods: WidgetClassPeriods.today
        )
    }
}
