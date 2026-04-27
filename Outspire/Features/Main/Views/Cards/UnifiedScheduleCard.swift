import SwiftUI

struct UnifiedScheduleCard: View {
    @ObservedObject var viewModel: ClasstableViewModel
    let dayIndex: Int
    let isForToday: Bool
    let setAsToday: Bool
    let effectiveDate: Date?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = false

    private var dayWeekday: Int { dayIndex + 2 }

    private var maxPeriodsForDay: Int {
        ClassPeriodsManager.shared.getMaxPeriodsByWeekday(dayWeekday)
    }

    private var dayName: String {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        guard dayIndex >= 0, dayIndex < 5 else { return "" }
        return days[dayIndex]
    }

    private var scheduledPeriods: [SchedulePeriodItem] {
        guard !viewModel.timetable.isEmpty else { return [] }
        let maxRow = min(viewModel.timetable.count, maxPeriodsForDay + 1)

        return (1 ..< maxRow).compactMap { row in
            guard row < viewModel.timetable.count,
                  dayIndex + 1 < viewModel.timetable[row].count
            else { return nil }

            let classData = viewModel.timetable[row][dayIndex + 1]
            let info = ClassInfoParser.parse(classData)
            guard let period = ClassPeriodsManager.shared.classPeriods.first(where: { $0.number == row })
            else { return nil }

            return SchedulePeriodItem(periodNumber: row, period: period, info: info)
        }
    }

    private var classCount: Int {
        scheduledPeriods.filter { !$0.info.isSelfStudy }.count
    }

    private var accentColor: Color {
        if let firstClass = scheduledPeriods.first(where: { !$0.info.isSelfStudy }),
           let subject = firstClass.info.subject
        {
            return ModernScheduleRow.subjectColor(for: subject)
        }
        return .blue
    }

    private var hasLunchDivider: Bool {
        scheduledPeriods.contains { $0.periodNumber == 4 } && scheduledPeriods.contains { $0.periodNumber == 5 }
    }

    private func isLunchDivider(after periodNumber: Int) -> Bool {
        periodNumber == 4 && hasLunchDivider
    }

    private var displayedPeriods: [SchedulePeriodItem] {
        if isExpanded || scheduledPeriods.count <= 5 {
            return scheduledPeriods
        }
        return Array(scheduledPeriods.prefix(5))
    }

    private var collapsedHeight: CGFloat {
        CGFloat(5 * 56)
    }

    var body: some View {
        if scheduledPeriods.isEmpty {
            NoClassCard()
        } else {
            scheduleContent
        }
    }

    private var scheduleContent: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            // Colored header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dayName)'s Schedule")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("\(classCount) classes")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .overlay(alignment: .trailing) {
                Text("\(scheduledPeriods.count)")
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.18))
                    .offset(x: 12, y: 8)
            }
            .clipped()
            .background(
                LinearGradient(
                    colors: [accentColor, accentColor.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.white.opacity(0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                }
            )

            // Period rows - show all or fade based on state
            if scheduledPeriods.count > 5 && !isExpanded {
                // Collapsed: show 3 items with fade hint
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        ForEach(displayedPeriods) { item in
                            let isActive = (isForToday || setAsToday)
                                && isItemActive(item, at: context.date)
                            let isPast = (isForToday || setAsToday)
                                && isItemPast(item, at: context.date) && !isActive

                            UnifiedScheduleRow(
                                item: item,
                                isActive: isActive,
                                isPast: isPast,
                                currentDate: context.date,
                                accentColor: accentColor
                            )

if isLunchDivider(after: item.periodNumber) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(width: 114, height: 2)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: collapsedHeight)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        .frame(height: collapsedHeight - 40)
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)
                    }
                )

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Label("Show more", systemImage: "chevron.down")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            } else {
                // Expanded or <=3 items: show all
                TimelineView(.periodic(from: .now, by: 1)) { context in
                   VStack(spacing: 0) {
                        ForEach(scheduledPeriods) { item in
                            let isActive = (isForToday || setAsToday)
                                && isItemActive(item, at: context.date)
                            let isPast = (isForToday || setAsToday)
                                && isItemPast(item, at: context.date) && !isActive

                            UnifiedScheduleRow(
                                item: item,
                                isActive: isActive,
                                isPast: isPast,
                                currentDate: context.date,
                                accentColor: accentColor
                            )

if isLunchDivider(after: item.periodNumber) {
                                Capsule()
                                    .fill(Color.accentColor.opacity(0.15))
                                    .frame(height: 2)
                                    .frame(width: 114, alignment: .leading)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                if scheduledPeriods.count > 5 {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Label("Show less", systemImage: "chevron.up")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(
            shape.fill(colorScheme == .dark ? AppColor.richDarkCard : .white)
        )
        .clipShape(shape)
        // Tight edge shadow
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.06), radius: 2, x: 0, y: 1)
        // Wide color-matched glow
        .shadow(
            color: accentColor.opacity(colorScheme == .dark ? 0.25 : 0.18),
            radius: 18, x: 0, y: 10
        )
    }

    // MARK: - Time Helpers

    private func isItemActive(_ item: SchedulePeriodItem, at date: Date) -> Bool {
        if setAsToday, let effectiveDate {
            return isPeriodActiveForEffectiveDate(item.period, effectiveDate: effectiveDate, now: date)
        }
        return isForToday && date >= item.period.startTime && date <= item.period.endTime
    }

    private func isItemPast(_ item: SchedulePeriodItem, at date: Date) -> Bool {
        if setAsToday, let effectiveDate {
            return isPeriodPastForEffectiveDate(item.period, effectiveDate: effectiveDate, now: date)
        }
        return isForToday && date > item.period.endTime
    }

    private func isPeriodActiveForEffectiveDate(_ period: ClassPeriod, effectiveDate: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        var components = calendar.dateComponents([.year, .month, .day], from: effectiveDate)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        guard let effectiveNow = calendar.date(from: components) else { return false }
        let adjustedStart = createAdjustedTime(from: period.startTime, onDate: effectiveDate)
        let adjustedEnd = createAdjustedTime(from: period.endTime, onDate: effectiveDate)
        return effectiveNow >= adjustedStart && effectiveNow <= adjustedEnd
    }

    private func isPeriodPastForEffectiveDate(_ period: ClassPeriod, effectiveDate: Date, now: Date) -> Bool {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: now)
        var components = calendar.dateComponents([.year, .month, .day], from: effectiveDate)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        guard let effectiveNow = calendar.date(from: components) else { return false }
        let adjustedEnd = createAdjustedTime(from: period.endTime, onDate: effectiveDate)
        return effectiveNow > adjustedEnd
    }

    private func createAdjustedTime(from time: Date, onDate date: Date) -> Date {
        let calendar = Calendar.current
        let tc = calendar.dateComponents([.hour, .minute, .second], from: time)
        var dc = calendar.dateComponents([.year, .month, .day], from: date)
        dc.hour = tc.hour; dc.minute = tc.minute; dc.second = tc.second
        return calendar.date(from: dc) ?? date
    }
}

// MARK: - Schedule Period Item

struct SchedulePeriodItem: Identifiable {
    let id: String
    let periodNumber: Int
    let period: ClassPeriod
    let info: ClassInfo

    init(periodNumber: Int, period: ClassPeriod, info: ClassInfo) {
        self.id = "\(periodNumber)"
        self.periodNumber = periodNumber
        self.period = period
        self.info = info
    }
}

// MARK: - Unified Schedule Row

private struct UnifiedScheduleRow: View {
    let item: SchedulePeriodItem
    let isActive: Bool
    let isPast: Bool
    let currentDate: Date
    let accentColor: Color

    @Environment(\.colorScheme) private var colorScheme

    private var subjectColor: Color {
        if item.info.isSelfStudy { return .purple }
        if let subject = item.info.subject {
            return ModernScheduleRow.subjectColor(for: subject)
        }
        return .blue
    }

    private var progress: Double {
        let total = item.period.endTime.timeIntervalSince(item.period.startTime)
        let elapsed = currentDate.timeIntervalSince(item.period.startTime)
        return max(0, min(1, elapsed / total))
    }

    private var formattedCountdown: String {
        let remaining = max(0, item.period.endTime.timeIntervalSince(currentDate))
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return "\(f.string(from: item.period.startTime)) – \(f.string(from: item.period.endTime))"
    }

    /// Inline metadata line: "8:15 – 8:55 · Teacher · Room"
    private var metadataLine: String {
        var parts = [timeRange]
        if let teacher = item.info.teacher, !teacher.isEmpty, !item.info.isSelfStudy {
            parts.append(teacher)
        }
        if let room = item.info.room, !room.isEmpty {
            parts.append(room)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            // Dot: show for non-self-study, invisible placeholder for self-study
            Circle()
                .fill(item.info.isSelfStudy ? Color.clear : subjectColor)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: isActive ? 6 : 3) {
                // Subject name
                Text(item.info.subject ?? (item.info.isSelfStudy ? "Self-Study" : "Class"))
                    .font(isActive ? .body.weight(.bold) : .subheadline.weight(.semibold))
                    .foregroundColor(isPast ? .secondary : .primary)

                // Metadata line
                Text(item.info.isSelfStudy && !isActive ? timeRange : metadataLine)
                    .font(.caption)
                    .foregroundColor(isPast ? .secondary.opacity(0.4) : .secondary)
                    .lineLimit(1)

                // Active: progress bar
                if isActive {
                    HStack(spacing: 10) {
                        ProgressView(value: progress)
                            .tint(subjectColor)
                            .scaleEffect(y: 1.5)

                        Text("ends in \(formattedCountdown)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(subjectColor)
                            .monospacedDigit()
                            .fixedSize()
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, isActive ? 12 : 9)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(subjectColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .padding(.horizontal, 6)
            }
        }
        .opacity(isPast ? 0.45 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }
}
