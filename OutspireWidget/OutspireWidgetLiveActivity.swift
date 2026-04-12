import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Color Helpers

private func stateColor(for state: ClassActivityAttributes.ContentState) -> Color {
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

private func countdownColor(for state: ClassActivityAttributes.ContentState) -> Color {
    switch state.status {
    case .ongoing:
        return .white
    case .ending:
        return .orange
    case .upcoming, .break, .event:
        return .white.opacity(0.4)
    }
}

private func countdownLabel(for status: ClassActivityAttributes.ContentState.Status) -> String {
    switch status {
    case .ongoing, .ending:
        return "ENDS IN"
    case .upcoming, .break:
        return "STARTS IN"
    case .event:
        return "TODAY"
    }
}

private func progress(for state: ClassActivityAttributes.ContentState, at date: Date) -> Double {
    let total = state.periodEnd.timeIntervalSince(state.periodStart)
    guard total > 0 else { return 0 }
    let elapsed = date.timeIntervalSince(state.periodStart)
    return min(max(elapsed / total, 0), 1)
}

// MARK: - Progress Bar (shared between Lock Screen and DI Expanded)

private struct ProgressBar: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.08))
                    .frame(height: 3)

                TimelineView(.periodic(from: .now, by: 10)) { timeline in
                    let prog = progress(for: state, at: timeline.date)
                    if prog > 0 {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [stateColor(for: state), stateColor(for: state).opacity(0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * prog, 3), height: 3)
                    }
                }
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Lock Screen View
// Matches v3 mockup: la-card with padding 16px 20px 14px
// la-row: flex center, left (title + caption), right (label + number)
// progress bar at bottom with margin-top 12px

private struct LockScreenView: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 0) {
            // Main row — vertically centered
            HStack {
                // Left: class name + room
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

                Spacer(minLength: 16)

                // Right: label + countdown
                VStack(alignment: .trailing, spacing: 2) {
                    Text(countdownLabel(for: state.status))
                        .font(WidgetFont.caption())
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.4))

                    Text(timerInterval: state.periodStart ... state.periodEnd, countsDown: true)
                        .font(WidgetFont.number())
                        .tracking(-1)
                        .foregroundStyle(countdownColor(for: state))
                        .monospacedDigit()
                }
            }

            // Progress bar — 12pt gap from row
            ProgressBar(state: state)
                .padding(.top, 12)
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
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

// MARK: - Dynamic Island Compact

private struct CompactLeadingView: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            ProgressRing(
                progress: progress(for: state, at: timeline.date),
                color: stateColor(for: state),
                lineWidth: 2,
                size: 14
            )
        }
    }
}

private struct CompactTrailingView: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        // Only countdown, no class name
        Text(timerInterval: state.periodStart ... state.periodEnd, countsDown: true)
            .font(WidgetFont.number(size: 14))
            .tracking(-0.5)
            .foregroundStyle(stateColor(for: state))
            .monospacedDigit()
    }
}

// MARK: - Dynamic Island Minimal

private struct MinimalView: View {
    let state: ClassActivityAttributes.ContentState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 10)) { timeline in
            ProgressRing(
                progress: progress(for: state, at: timeline.date),
                color: stateColor(for: state),
                lineWidth: 2,
                size: 14
            )
        }
    }
}

// MARK: - Widget Configuration

struct OutspireWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClassActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(red: 0.11, green: 0.11, blue: 0.12))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded — same layout as lock screen but scaled down
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.className)
                            .font(WidgetFont.title(size: 15))
                            .tracking(-0.2)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if !context.state.roomNumber.isEmpty {
                            Text(context.state.roomNumber)
                                .font(WidgetFont.caption(size: 10))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(countdownLabel(for: context.state.status))
                            .font(WidgetFont.caption(size: 10))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.4))

                        Text(timerInterval: context.state.periodStart ... context.state.periodEnd, countsDown: true)
                            .font(WidgetFont.number(size: 24))
                            .tracking(-1)
                            .foregroundStyle(stateColor(for: context.state))
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressBar(state: context.state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                CompactLeadingView(state: context.state)
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .widgetURL(URL(string: "outspire://today"))
        }
    }
}
