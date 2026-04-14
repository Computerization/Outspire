import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: ClassWidgetEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch entry.status {
        case .notAuthenticated:
            smallPlaceholder(label: "OUTSPIRE", message: "Sign In", gradient: grayGradient)
        case .holiday:
            smallPlaceholder(label: "HOLIDAY", message: "No Classes", gradient: warmGradient)
        case .noClasses, .completed:
            smallPlaceholder(label: "TODAY", message: "No Classes", gradient: grayGradient)
        case .ongoing, .ending:
            ongoingView
        case .upcoming:
            upcomingView
        case .break:
            breakView
        case .event:
            smallPlaceholder(label: "TODAY", message: entry.eventName ?? "Event", gradient: purpleGradient)
        }
    }

    private var ongoingView: some View {
        widgetCard {
            ongoingBackground
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("NOW")
                    .captionStyle()
                    .foregroundStyle(secondaryForegroundStyle)
                    .textCase(.uppercase)

                if let cls = entry.currentClass {
                    Text(cls.className)
                        .titleStyle(size: 20)
                        .foregroundStyle(primaryForegroundStyle)
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                Spacer()

                if let cls = entry.currentClass {
                    Text(
                        timerInterval: cls.startTime ... cls.endTime,
                        pauseTime: nil,
                        countsDown: true,
                        showsHours: false
                    )
                    .numberStyle(size: 34)
                    .foregroundStyle(primaryForegroundStyle)
                    .tracking(-1.5)

                    Text(widgetSubtitle(for: cls))
                        .captionStyle()
                        .foregroundStyle(tertiaryForegroundStyle)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var upcomingView: some View {
        widgetCard {
            ongoingBackground
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("NEXT")
                    .captionStyle()
                    .foregroundStyle(secondaryForegroundStyle)
                    .textCase(.uppercase)

                if let cls = entry.currentClass {
                    Text(cls.className)
                        .titleStyle(size: 20)
                        .foregroundStyle(primaryForegroundStyle)
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                Spacer()

                if let cls = entry.currentClass {
                    Text(
                        timerInterval: entry.date ... cls.startTime,
                        pauseTime: nil,
                        countsDown: true,
                        showsHours: false
                    )
                    .numberStyle(size: 34)
                    .foregroundStyle(primaryForegroundStyle)
                    .tracking(-1.5)

                    Text(widgetSubtitle(for: cls))
                        .captionStyle()
                        .foregroundStyle(tertiaryForegroundStyle)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var breakView: some View {
        widgetCard {
            breakBackground
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.currentClass?.className ?? "Break")
                    .captionStyle()
                    .foregroundStyle(secondaryForegroundStyle)
                    .textCase(.uppercase)

                if let next = entry.upcomingClasses.first {
                    Text(next.className)
                        .titleStyle(size: 20)
                        .foregroundStyle(primaryForegroundStyle)
                        .lineLimit(1)
                        .padding(.top, 2)
                }

                Spacer()

                if let cls = entry.currentClass {
                    Text(
                        timerInterval: entry.date ... cls.endTime,
                        pauseTime: nil,
                        countsDown: true,
                        showsHours: false
                    )
                    .numberStyle(size: 34)
                    .foregroundStyle(primaryForegroundStyle)
                    .tracking(-1.5)
                }

                if let next = entry.upcomingClasses.first, !next.roomNumber.isEmpty {
                    Text(next.roomNumber)
                        .captionStyle()
                        .foregroundStyle(tertiaryForegroundStyle)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func smallPlaceholder(label: String, message: String, gradient: LinearGradient) -> some View {
        widgetCard {
            gradient
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .captionStyle()
                    .foregroundStyle(secondaryForegroundStyle)
                    .textCase(.uppercase)

                Spacer()

                Text(message)
                    .titleStyle(size: 20)
                    .foregroundStyle(primaryForegroundStyle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func widgetCard(
        @ViewBuilder background: () -> some View,
        @ViewBuilder content: () -> some View
    ) -> some View {
        content()
            .containerBackground(for: .widget) {
                if renderingMode == .fullColor {
                    background()
                } else {
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var ongoingBackground: some View {
        if let cls = entry.currentClass {
            SubjectColors.gradient(for: cls.className)
        } else {
            grayGradient
        }
    }

    @ViewBuilder
    private var breakBackground: some View {
        if let cls = entry.currentClass, cls.className.contains("Lunch") {
            LinearGradient(
                colors: [Color.purple.opacity(0.6), Color.purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else if let next = entry.upcomingClasses.first {
            SubjectColors.gradient(for: next.className)
        } else {
            grayGradient
        }
    }

    private var grayGradient: LinearGradient {
        LinearGradient(
            colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var warmGradient: LinearGradient {
        LinearGradient(
            colors: [Color.orange.opacity(0.6), Color.orange.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var purpleGradient: LinearGradient {
        LinearGradient(
            colors: [Color.purple.opacity(0.6), Color.purple.opacity(0.4)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func widgetSubtitle(for scheduledClass: ScheduledClass) -> String {
        if scheduledClass.isSelfStudy {
            return scheduledClass.roomNumber.isEmpty ? "Class-Free Period" : scheduledClass.roomNumber
        }
        return scheduledClass.roomNumber.isEmpty ? " " : scheduledClass.roomNumber
    }

    private var primaryForegroundStyle: AnyShapeStyle {
        AnyShapeStyle(renderingMode == .fullColor ? Color.white : Color.primary)
    }

    private var secondaryForegroundStyle: AnyShapeStyle {
        AnyShapeStyle(renderingMode == .fullColor ? Color.white.opacity(0.7) : Color.primary.opacity(0.75))
    }

    private var tertiaryForegroundStyle: AnyShapeStyle {
        AnyShapeStyle(renderingMode == .fullColor ? Color.white.opacity(0.55) : Color.secondary)
    }
}
