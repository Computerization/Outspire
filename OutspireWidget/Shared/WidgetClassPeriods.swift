import Foundation

/// Minimal class periods definition for the widget extension.
/// Mirrors ClassPeriodsManager from the main app.
enum WidgetClassPeriods {
    struct Period {
        let number: Int
        let startTime: Date
        let endTime: Date
    }

    static var today: [Period] {
        let calendar = Calendar.current
        let now = Date()

        let times: [(Int, Int, Int, Int, Int)] = [
            (1, 8, 15, 8, 55),
            (2, 9, 5, 9, 45),
            (3, 9, 55, 10, 35),
            (4, 10, 45, 11, 25),
            (5, 12, 30, 13, 10),
            (6, 13, 20, 14, 0),
            (7, 14, 10, 14, 50),
            (8, 15, 0, 15, 40),
            (9, 15, 50, 16, 30)
        ]

        return times.map { num, sh, sm, eh, em in
            let start = calendar.date(bySettingHour: sh, minute: sm, second: 0, of: now)!
            let end = calendar.date(bySettingHour: eh, minute: em, second: 0, of: now)!
            return Period(number: num, startTime: start, endTime: end)
        }
    }
}
