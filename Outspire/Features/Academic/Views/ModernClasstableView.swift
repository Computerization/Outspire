import SwiftUI

struct ModernClasstableView: View {
    @EnvironmentObject var viewModel: ClasstableViewModel
    @State private var selectedDay: Int = ModernClasstableView.currentWeekdayIndex()

    static func currentWeekdayIndex() -> Int {
        let w = Calendar.current.component(.weekday, from: Date())
        return (w == 1 || w == 7) ? 0 : max(0, min(4, w - 2))
    }

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri"]
    private let fullDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

    private var currentWeekDates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let mondayOffset = -(weekday - 2)
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset + (weekday == 1 ? -6 : 0), to: today)
        else { return [] }
        return (0 ..< 5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    var body: some View {
        VStack(spacing: 0) {
            dayPicker
                .padding(.vertical, 10)

            Divider()

            TimelineView(.periodic(from: .now, by: 60)) { context in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(ClassPeriodsManager.shared.classPeriods, id: \.number) { period in
                            let info = classInfo(for: period, dayIndex: selectedDay)
                            let isActive = period.isCurrentlyActive() && selectedDay == Self.currentWeekdayIndex()
                            let isPast = selectedDay == Self.currentWeekdayIndex() && context.date > period.endTime

                            if let info, !info.isSelfStudy {
                                Button {
                                    selectedDetail = ClassDetail(period: period, info: info)
                                } label: {
                                    ClassPeriodCard(
                                        period: period,
                                        info: info,
                                        isActive: isActive,
                                        isPast: isPast,
                                        currentDate: context.date
                                    )
                                }
                                .buttonStyle(.pressableCard)
                            } else {
                                ClassPeriodCard(
                                    period: period,
                                    info: info,
                                    isActive: isActive,
                                    isPast: isPast,
                                    currentDate: context.date
                                )
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 80)
                    .animation(.easeInOut(duration: 0.25), value: selectedDay)
                }
            }
        }
        .appBackground()
        .navigationTitle("Class")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today") {
                    HapticManager.shared.playSelectionFeedback()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedDay = Self.currentWeekdayIndex()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.shared.playRefresh()
                    viewModel.refreshData()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !viewModel.years.isEmpty {
                    Menu {
                        ForEach(viewModel.years) { year in
                            Button(year.W_Year) {
                                HapticManager.shared.playSelectionFeedback()
                                viewModel.selectYear(year.W_YearID)
                            }
                        }
                    } label: {
                        Image(systemName: "calendar")
                    }
                }
            }
        }
        .task {
            if viewModel.years.isEmpty { viewModel.fetchYears() }
            if viewModel.timetable.isEmpty { viewModel.fetchTimetable() }
        }
        .sheet(item: $selectedDetail) { detail in
            NavigationStack {
                ClassDetailSheet(period: detail.period, info: detail.info)
                    .navigationTitle(detail.info.subject ?? (detail.info.isSelfStudy ? "Self-Study" : "Class"))
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Day Picker

    @ViewBuilder
    private var dayPicker: some View {
        let dates = currentWeekDates
        let todayIndex = Self.currentWeekdayIndex()
        let fmt: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "d"; return f
        }()

        HStack(spacing: 0) {
            ForEach(0 ..< 5) { index in
                Button {
                    HapticManager.shared.playSelectionFeedback()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selectedDay = index
                    }
                } label: {
                    let isSelected = selectedDay == index
                    let isToday = index == todayIndex

                    VStack(spacing: 4) {
                        Text(isSelected ? fullDayNames[index] : dayNames[index])
                            .font(.caption2.weight(isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                        if index < dates.count {
                            Text(fmt.string(from: dates[index]))
                                .font(.system(.body, design: .rounded).weight(isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? .white : (isToday ? Color.primary : .primary))
                                .frame(width: 36, height: 36)
                                .background {
                                    if isSelected {
                                        Circle()
                                            .fill(Color.primary)
                                    } else if isToday {
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1.5)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Helpers

    private func classInfo(for period: ClassPeriod, dayIndex: Int) -> ClassInfo? {
        guard !viewModel.timetable.isEmpty,
              period.number < viewModel.timetable.count,
              dayIndex + 1 < viewModel.timetable[period.number].count else { return nil }
        let data = viewModel.timetable[period.number][dayIndex + 1]
        let info = ClassInfoParser.parse(data)
        return info.isSelfStudy && (info.subject == nil) ? nil : info
    }

    struct ClassDetail: Identifiable { let id = UUID(); let period: ClassPeriod; let info: ClassInfo }
    @State private var selectedDetail: ClassDetail?
}

// MARK: - Class Period Card (colored gradient hero style, like the detail sheet)

private struct ClassPeriodCard: View {
    let period: ClassPeriod
    let info: ClassInfo?
    let isActive: Bool
    let isPast: Bool
    let currentDate: Date

    @Environment(\.colorScheme) private var colorScheme

    private var displayInfo: ClassInfo {
        info ?? ClassInfo(teacher: nil, subject: nil, room: nil, isSelfStudy: true)
    }

    private var subjectColor: Color {
        if let subject = displayInfo.subject { return ModernScheduleRow.subjectColor(for: subject) }
        return displayInfo.isSelfStudy ? .purple.opacity(0.6) : .gray
    }

    private var progress: Double {
        guard isActive else { return 0 }
        let total = period.endTime.timeIntervalSince(period.startTime)
        let elapsed = currentDate.timeIntervalSince(period.startTime)
        return max(0, min(1, elapsed / total))
    }

    private var formattedCountdown: String {
        let remaining = max(0, period.endTime.timeIntervalSince(currentDate))
        let m = Int(remaining) / 60
        let s = Int(remaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Subject, period, time
            VStack(alignment: .leading, spacing: 4) {
                Text(displayInfo.subject ?? (displayInfo.isSelfStudy ? "Self-Study" : "Class"))
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white)

                HStack(spacing: 6) {
                    Text("Period \(period.number)")
                    Text("·")
                    Text(period.timeRangeFormatted)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Teacher + Room row (always shown for uniform card height)
            HStack(spacing: 16) {
                if displayInfo.isSelfStudy {
                    Label("Free Period", systemImage: "book.fill")
                } else {
                    if let teacher = displayInfo.teacher, !teacher.isEmpty {
                        Label(teacher, systemImage: "person.fill")
                    }
                    if let room = displayInfo.room, !room.isEmpty {
                        Label(room, systemImage: "door.left.hand.open")
                    }
                }
                Spacer()

                if !displayInfo.isSelfStudy {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Active progress
            if isActive {
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.white)
                        .scaleEffect(y: 1.3)

                    Text(formattedCountdown)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(
            LinearGradient(
                colors: [subjectColor, subjectColor.opacity(0.75)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(alignment: .top) {
                LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .shadow(
            color: isPast ? .clear : subjectColor.opacity(colorScheme == .dark ? 0.2 : 0.15),
            radius: isActive ? 10 : 5,
            y: isActive ? 5 : 3
        )
        .opacity(isPast ? 0.4 : 1.0)
        .contentShape(Rectangle())
    }
}

// MARK: - Schedule Row (public, referenced by other files)

struct ModernScheduleRow: View {
    let period: ClassPeriod
    let info: ClassInfo?
    var isActive: Bool = false

    static func subjectColor(for subject: String) -> Color {
        let subjectLower = subject.lowercased()

        let colors: [(Color, [String])] = [
            (.blue.opacity(0.8), ["math", "mathematics", "maths"]),
            (.green.opacity(0.8), ["english", "language", "literature", "general paper", "esl"]),
            (.orange.opacity(0.8), ["physics", "science"]),
            (.pink.opacity(0.8), ["chemistry", "chem"]),
            (.teal.opacity(0.8), ["biology", "bio"]),
            (.mint.opacity(0.8), ["further math", "maths further"]),
            (.yellow.opacity(0.8), ["体育", "pe", "sports", "p.e"]),
            (.brown.opacity(0.8), ["economics", "econ"]),
            (.cyan.opacity(0.8), ["arts", "art", "tok"]),
            (.indigo.opacity(0.8), ["chinese", "mandarin", "语文"]),
            (.gray.opacity(0.8), ["history", "历史", "geography", "geo", "政治"])
        ]

        for (color, keywords) in colors {
            if keywords.contains(where: { subjectLower.contains($0) }) { return color }
        }

        // Deterministic hash — String.hashValue is randomized per process
        var djb2: UInt64 = 5381
        for byte in subjectLower.utf8 {
            djb2 = djb2 &* 33 &+ UInt64(byte)
        }
        let hue = Double(djb2 % 12) / 12.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }

    var body: some View {
        EmptyView()
    }
}

// MARK: - Class Detail Sheet

private struct ClassDetailSheet: View {
    let period: ClassPeriod
    let info: ClassInfo

    private var subjectColor: Color {
        if let subject = info.subject {
            return ModernScheduleRow.subjectColor(for: subject)
        }
        return .blue
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(info.subject ?? (info.isSelfStudy ? "Self-Study" : "Class"))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Period \(period.number) · \(period.timeRangeFormatted)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .listRowBackground(
                    LinearGradient(
                        colors: [subjectColor, subjectColor.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Section {
                if let teacher = info.teacher, !teacher.isEmpty {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Teacher").font(.caption).foregroundStyle(.secondary)
                            Text(teacher).font(.body.weight(.medium))
                        }
                    } icon: {
                        Image(systemName: "person.fill").foregroundStyle(subjectColor)
                    }
                }

                if let room = info.room, !room.isEmpty {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Room").font(.caption).foregroundStyle(.secondary)
                            Text(room).font(.body.weight(.medium))
                        }
                    } icon: {
                        Image(systemName: "door.left.hand.open").foregroundStyle(subjectColor)
                    }
                }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Duration").font(.caption).foregroundStyle(.secondary)
                        Text("40 minutes").font(.body.weight(.medium))
                    }
                } icon: {
                    Image(systemName: "clock.fill").foregroundStyle(subjectColor)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
