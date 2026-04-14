import ActivityKit
import SwiftUI
import WidgetKit

private struct DisplayState {
    let title: String
    let subtitle: String
    let phase: ClassActivityAttributes.ContentState.Phase
    let rangeStart: Date
    let rangeEnd: Date
    let nextTitle: String?

    init(_ state: ClassActivityAttributes.ContentState) {
        title = state.title
        subtitle = state.subtitle
        phase = state.phase
        rangeStart = state.rangeStart
        rangeEnd = state.rangeEnd
        nextTitle = state.nextTitle
    }
}

private func stateColor(for state: DisplayState) -> Color {
    switch state.phase {
    case .ongoing:
        SubjectColors.color(for: state.title)
    case .ending:
        .orange
    case .upcoming:
        .green
    case .breakTime:
        SubjectColors.color(for: state.nextTitle ?? state.title)
    case .event:
        .purple
    case .done:
        .white.opacity(0.4)
    }
}

private func countdownLabel(for phase: ClassActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .ongoing, .ending:
        "ENDS IN"
    case .upcoming, .breakTime:
        "STARTS IN"
    case .event:
        "TODAY"
    case .done:
        "DONE"
    }
}

private func countdownColor(for state: DisplayState) -> Color {
    switch state.phase {
    case .ongoing:
        .white
    case .ending:
        .orange
    case .upcoming, .breakTime, .event:
        .white.opacity(0.4)
    case .done:
        .white.opacity(0.45)
    }
}

private func progress(for state: DisplayState, at date: Date) -> Double {
    let total = state.rangeEnd.timeIntervalSince(state.rangeStart)
    guard total > 0 else { return 0 }
    let elapsed = date.timeIntervalSince(state.rangeStart)
    return min(max(elapsed / total, 0), 1)
}

private struct TimeProgressBar: View {
    let state: DisplayState

    var body: some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.08))
                .frame(height: 3)

            // Use ActivityKit's time-driven ProgressView for the linear bar so it
            // advances with the current range without relying on TimelineView to
            // re-layout the lock screen presentation.
            ProgressView(timerInterval: state.rangeStart ... state.rangeEnd, countsDown: false)
                .progressViewStyle(.linear)
                .tint(stateColor(for: state))
                .labelsHidden()
                .frame(height: 3)
                .clipShape(Capsule())
        }
        .frame(height: 3)
    }
}

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

private struct LockScreenView: View {
    let state: DisplayState

    var body: some View {
        if state.phase == .done {
            StaleView()
        } else {
            VStack(spacing: 2) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.title)
                            .font(WidgetFont.title())
                            .tracking(-0.2)
                            .foregroundStyle(stateColor(for: state))
                            .lineLimit(1)

                        Text(state.subtitle)
                            .font(WidgetFont.caption())
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(countdownLabel(for: state.phase))
                            .font(WidgetFont.caption())
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)

                        Text(
                            timerInterval: state.rangeStart ... state.rangeEnd,
                            pauseTime: nil,
                            countsDown: true,
                            showsHours: false
                        )
                        .font(WidgetFont.number())
                        .tracking(-1)
                        .foregroundStyle(countdownColor(for: state))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90, alignment: .trailing)
                    }
                }

                Spacer(minLength: 0)

                // Keep the original layout metrics and only swap the fill logic
                // to the system's time-based progress rendering.
                TimeProgressBar(state: state)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }
}

private struct CompactLeadingView: View {
    let state: DisplayState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
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

private struct CompactTrailingView: View {
    let state: DisplayState

    var body: some View {
        Text(
            timerInterval: state.rangeStart ... state.rangeEnd,
            pauseTime: nil,
            countsDown: true,
            showsHours: false
        )
        .font(WidgetFont.number(size: 14))
        .foregroundStyle(stateColor(for: state))
        .monospacedDigit()
        .frame(width: 44)
    }
}

private struct MinimalView: View {
    let state: DisplayState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            ProgressRing(
                progress: progress(for: state, at: timeline.date),
                color: stateColor(for: state),
                lineWidth: 2,
                size: 18
            )
        }
    }
}

struct OutspireWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            LockScreenView(state: DisplayState(context.state))
                .activityBackgroundTint(.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = DisplayState(context.state)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.title)
                            .font(WidgetFont.title(size: 15))
                            .tracking(-0.2)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if !dynamicIslandSubtitle(for: state).isEmpty {
                            Text(dynamicIslandSubtitle(for: state))
                                .font(WidgetFont.caption(size: 10))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.4))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(countdownLabel(for: state.phase))
                            .font(WidgetFont.caption(size: 10))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))
                            .textCase(.uppercase)

                        Text(
                            timerInterval: state.rangeStart ... state.rangeEnd,
                            pauseTime: nil,
                            countsDown: true,
                            showsHours: false
                        )
                        .font(WidgetFont.number(size: 22))
                        .tracking(-1)
                        .foregroundStyle(stateColor(for: state))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(.trailing, 4)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Match the lock screen bar behavior without changing spacing
                    // or sizing in the expanded island.
                    TimeProgressBar(state: state)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                }
            } compactLeading: {
                CompactLeadingView(state: state)
            } compactTrailing: {
                CompactTrailingView(state: state)
            } minimal: {
                MinimalView(state: state)
            }
            .widgetURL(URL(string: "outspire://today"))
        }
    }
}

private func dynamicIslandSubtitle(for state: DisplayState) -> String {
    switch state.phase {
    case .breakTime, .done:
        ""
    default:
        state.subtitle
    }
}

#if DEBUG
    private enum LiveActivityPreviewData {
        static let now = Date()
        static let attributes = ClassActivityAttributes(startDate: now)

        static let ongoing = ClassActivityAttributes.ContentState(
            dayKey: "2026-04-13",
            phase: .ongoing,
            title: "Mathematics",
            subtitle: "A108",
            rangeStart: now.addingTimeInterval(-900),
            rangeEnd: now.addingTimeInterval(1500),
            nextTitle: "English Literature",
            sequence: 4
        )

        static let breakTime = ClassActivityAttributes.ContentState(
            dayKey: "2026-04-13",
            phase: .breakTime,
            title: "Break",
            subtitle: "Next: Self-Study",
            rangeStart: now,
            rangeEnd: now.addingTimeInterval(600),
            nextTitle: "Self-Study",
            sequence: 6
        )

        static let lunch = ClassActivityAttributes.ContentState(
            dayKey: "2026-04-13",
            phase: .breakTime,
            title: "Lunch Break",
            subtitle: "Next: Chemistry",
            rangeStart: now,
            rangeEnd: now.addingTimeInterval(1800),
            nextTitle: "Chemistry",
            sequence: 9
        )

        static let done = ClassActivityAttributes.ContentState(
            dayKey: "2026-04-13",
            phase: .done,
            title: "Schedule Complete",
            subtitle: "",
            rangeStart: now,
            rangeEnd: now.addingTimeInterval(900),
            nextTitle: nil,
            sequence: 20
        )
    }

    #Preview("LA Ongoing", as: .content, using: LiveActivityPreviewData.attributes) {
        OutspireWidgetLiveActivity()
    } contentStates: {
        LiveActivityPreviewData.ongoing
    }

    #Preview("LA Break", as: .content, using: LiveActivityPreviewData.attributes) {
        OutspireWidgetLiveActivity()
    } contentStates: {
        LiveActivityPreviewData.breakTime
    }

    #Preview("LA Lunch", as: .content, using: LiveActivityPreviewData.attributes) {
        OutspireWidgetLiveActivity()
    } contentStates: {
        LiveActivityPreviewData.lunch
    }

    #Preview("LA Done", as: .content, using: LiveActivityPreviewData.attributes) {
        OutspireWidgetLiveActivity()
    } contentStates: {
        LiveActivityPreviewData.done
    }

    #Preview("DI Expanded", as: .dynamicIsland(.expanded), using: LiveActivityPreviewData.attributes) {
        OutspireWidgetLiveActivity()
    } contentStates: {
        LiveActivityPreviewData.ongoing
    }
#endif
