import SwiftUI
import WidgetKit

struct SmallClassWidget: Widget {
    let kind = "SmallClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClassWidgetProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Class")
        .description("Current or upcoming class countdown")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#if DEBUG
    private enum SmallWidgetPreviewData {
        static let now = Date()

        static let math = ScheduledClass(
            periodNumber: 3,
            className: "Mathematics",
            roomNumber: "A108",
            teacherName: "Yu Song",
            startTime: now.addingTimeInterval(-900),
            endTime: now.addingTimeInterval(1500),
            isSelfStudy: false
        )

        static let selfStudy = ScheduledClass(
            periodNumber: 4,
            className: "Self-Study",
            roomNumber: "",
            teacherName: "",
            startTime: now.addingTimeInterval(600),
            endTime: now.addingTimeInterval(3000),
            isSelfStudy: true
        )

        static let english = ScheduledClass(
            periodNumber: 5,
            className: "English Literature",
            roomNumber: "B205",
            teacherName: "Ms. Zhang",
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(6000),
            isSelfStudy: false
        )

        static let lunchBreak = ScheduledClass(
            periodNumber: 0,
            className: "Lunch Break",
            roomNumber: "",
            teacherName: "",
            startTime: now,
            endTime: now.addingTimeInterval(1800),
            isSelfStudy: false
        )
    }

    #Preview("Widget Ongoing", as: .systemSmall) {
        SmallClassWidget()
    } timeline: {
        ClassWidgetEntry(
            date: SmallWidgetPreviewData.now,
            status: .ongoing,
            currentClass: SmallWidgetPreviewData.math,
            upcomingClasses: [SmallWidgetPreviewData.english],
            eventName: nil
        )
    }

    #Preview("Widget Self-Study", as: .systemSmall) {
        SmallClassWidget()
    } timeline: {
        ClassWidgetEntry(
            date: SmallWidgetPreviewData.now,
            status: .upcoming,
            currentClass: SmallWidgetPreviewData.selfStudy,
            upcomingClasses: [SmallWidgetPreviewData.english],
            eventName: nil
        )
    }

    #Preview("Widget Lunch Break", as: .systemSmall) {
        SmallClassWidget()
    } timeline: {
        ClassWidgetEntry(
            date: SmallWidgetPreviewData.now,
            status: .break,
            currentClass: SmallWidgetPreviewData.lunchBreak,
            upcomingClasses: [SmallWidgetPreviewData.english],
            eventName: nil
        )
    }
#endif
