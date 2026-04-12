import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - State Computation

/// Display state derived from the schedule array + current time.
/// This is a pure function — no side effects, no state mutation.
private struct DisplayState {
    var className: String
    var roomNumber: String
    var status: Status
    var periodStart: Date
    var periodEnd: Date
    var nextClassName: String?

    enum Status {
        case ongoing, ending, upcoming, `break`, event
    }
}

/// Compute what to display from the full day schedule and current time.
private func currentDisplayState(
    from classes: [ClassActivityAttributes.ContentState.ClassInfo],
    at now: Date
) -> DisplayState? {
    let sorted = classes.sorted { $0.start < $1.start }
    guard !sorted.isEmpty else { return nil }

    // Currently in a class?
    if let current = sorted.first(where: { $0.start <= now && $0.end > now }) {
        let next = sorted.first(where: { $0.start >= current.end })
        let remaining = current.end.timeIntervalSince(now)
        return DisplayState(
            className: current.name,
            roomNumber: current.room,
            status: remaining <= 300 ? .ending : .ongoing,
            periodStart: current.start,
            periodEnd: current.end,
            nextClassName: next?.name
        )
    }

    // Between classes (break/lunch)?
    let previous = sorted.last(where: { $0.end <= now })
    if let next = sorted.first(where: { $0.start > now }) {
        if let prev = previous {
            let gap = next.start.timeIntervalSince(prev.end)
            return DisplayState(
                className: gap > 1800 ? "Lunch Break" : "Break",
                roomNumber: "",
                status: .break,
                periodStart: prev.end,
                periodEnd: next.start,
                nextClassName: next.name
            )
        }
        // Before first class
        return DisplayState(
            className: next.name,
            roomNumber: next.room,
            status: .upcoming,
            periodStart: next.start,
            periodEnd: next.end,
            nextClassName: sorted.first(where: { $0.start > next.start })?.name
        )
    }

    // All classes done — return nil to let staleDate dim the LA
    return nil
}

// MARK: - Color Helpers

private func stateColor(for state: DisplayState) -> Color {
    switch state.status {
    case .ongoing:
        return SubjectColors.color(for: state.className)
    case .ending:
        return .orange
    case .upcoming:
        return .green
    case .break:
        return SubjectColors.color(for: state.nextClassName ?? state.className)
    case .event:
        return .purple
    }
}

private func countdownColor(for state: DisplayState) -> Color {
    switch state.status {
    case .ongoing:
        return .white
    case .ending:
        return .orange
    case .upcoming, .break, .event:
        return .white.opacity(0.4)
    }
}

private func countdownLabel(for status: DisplayState.Status) -> String {
    switch status {
    case .ongoing, .ending:
        return "ENDS IN"
    case .upcoming, .break:
        return "STARTS IN"
    case .event:
        return "TODAY"
    }
}

private func progress(for state: DisplayState, at date: Date) -> Double {
    let total = state.periodEnd.timeIntervalSince(state.periodStart)
    guard total > 0 else { return 0 }
    let elapsed = date.timeIntervalSince(state.periodStart)
    return min(max(elapsed / total, 0), 1)
}

// MARK: - Stale View (shown when all classes are done)

private struct StaleView: View {
    var body: some View {
        HStack {
            Text("Schedule Complete")
                .font(WidgetFont.title())
                .foregroundStyle(.white.opacity(0.4))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let classes: [ClassActivityAttributes.ContentState.ClassInfo]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            if let state = currentDisplayState(from: classes, at: timeline.date) {
                LockScreenStateView(state: state)
            } else {
                StaleView()
            }
        }
    }
}

private struct LockScreenStateView: View {
    let state: DisplayState

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.className)
                        .font(WidgetFont.title())
                        .tracking(-0.2)
                        .foregroundStyle(stateColor(for: state))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(WidgetFont.caption())
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdownLabel(for: state.status))
                        .font(WidgetFont.caption())
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.4))
                        .textCase(.uppercase)

                    Text(timerInterval: state.periodStart ... state.periodEnd, countsDown: true)
                        .font(WidgetFont.number())
                        .tracking(-1)
                        .foregroundStyle(countdownColor(for: state))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90, alignment: .trailing)
                }
            }

            Spacer(minLength: 0)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.08))
                        .frame(height: 3)

                    TimelineView(.periodic(from: .now, by: 10)) { timeline in
                        Capsule()
                            .fill(stateColor(for: state))
                            .frame(width: geo.size.width * progress(for: state, at: timeline.date), height: 3)
                    }
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var subtitle: String {
        switch state.status {
        case .break:
            return state.nextClassName.map { "Next: \($0)" } ?? ""
        default:
            return state.roomNumber.isEmpty ? "" : state.roomNumber
        }
    }
}

// MARK: - Dynamic Island Views

private struct CompactLeadingView: View {
    let classes: [ClassActivityAttributes.ContentState.ClassInfo]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            if let state = currentDisplayState(from: classes, at: timeline.date) {
                ProgressRing(
                    progress: progress(for: state, at: timeline.date),
                    color: stateColor(for: state),
                    lineWidth: 2,
                    size: 14
                )
                .padding(1)
            }
        }
    }
}

private struct CompactTrailingView: View {
    let classes: [ClassActivityAttributes.ContentState.ClassInfo]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            if let state = currentDisplayState(from: classes, at: timeline.date) {
                Text(timerInterval: state.periodStart ... state.periodEnd, countsDown: true)
                    .font(WidgetFont.number(size: 14))
                    .foregroundStyle(stateColor(for: state))
                    .monospacedDigit()
                    .frame(width: 44)
            }
        }
    }
}

private struct MinimalView: View {
    let classes: [ClassActivityAttributes.ContentState.ClassInfo]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            if let state = currentDisplayState(from: classes, at: timeline.date) {
                ProgressRing(
                    progress: progress(for: state, at: timeline.date),
                    color: stateColor(for: state),
                    lineWidth: 2,
                    size: 18
                )
            }
        }
    }
}

// MARK: - Widget Configuration

struct OutspireWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            LockScreenView(classes: context.state.classes)
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        if let state = currentDisplayState(from: context.state.classes, at: timeline.date) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(state.className)
                                    .font(WidgetFont.title(size: 15))
                                    .tracking(-0.2)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)

                                if !state.roomNumber.isEmpty {
                                    Text(state.roomNumber)
                                        .font(WidgetFont.caption(size: 10))
                                        .tracking(0.5)
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                            }
                            .frame(maxHeight: .infinity, alignment: .leading)
                            .padding(.leading, 4)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        if let state = currentDisplayState(from: context.state.classes, at: timeline.date) {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(countdownLabel(for: state.status))
                                    .font(WidgetFont.caption(size: 10))
                                    .tracking(0.5)
                                    .foregroundStyle(.white.opacity(0.4))
                                    .textCase(.uppercase)

                                Text(timerInterval: state.periodStart ... state.periodEnd, countsDown: true)
                                    .font(WidgetFont.number(size: 22))
                                    .tracking(-1)
                                    .foregroundStyle(stateColor(for: state))
                                    .monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 4)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        if let state = currentDisplayState(from: context.state.classes, at: timeline.date) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(.white.opacity(0.08))
                                        .frame(height: 3)

                                    Capsule()
                                        .fill(stateColor(for: state))
                                        .frame(width: geo.size.width * progress(for: state, at: timeline.date), height: 3)
                                }
                            }
                            .frame(height: 3)
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                        }
                    }
                }
            } compactLeading: {
                CompactLeadingView(classes: context.state.classes)
            } compactTrailing: {
                CompactTrailingView(classes: context.state.classes)
            } minimal: {
                MinimalView(classes: context.state.classes)
            }
            .widgetURL(URL(string: "outspire://today"))
        }
    }
}
