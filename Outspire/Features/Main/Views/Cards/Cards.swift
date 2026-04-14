import SwiftUI

// MARK: - Breathe/Pulse Compatibility

private struct BreatheOrPulseModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.symbolEffect(.breathe, isActive: true)
        } else {
            content.symbolEffect(.pulse, isActive: true)
        }
    }
}

private extension View {
    func breatheOrPulse() -> some View {
        modifier(BreatheOrPulseModifier())
    }
}

// MARK: - Status Cards (Rich colored fills with depth)

struct NoClassCard: View {
    let isDimmed: Bool
    @State private var appeared = false

    init(isDimmed: Bool = false) {
        self.isDimmed = isDimmed
    }

    private var gradientColors: [Color] {
        isDimmed
            ? [Color.indigo.opacity(0.8), Color.indigo.opacity(0.6)]
            : [Color.green.opacity(0.75), Color.mint.opacity(0.65)]
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: AppSpace.sm) {
                Image(systemName: isDimmed ? "moon.stars.fill" : "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
                    .symbolEffect(.bounce, value: appeared)
                    .onAppear { appeared = true }

                Spacer().frame(height: AppSpace.xs)

                Text(isDimmed ? "All Done for Today" : "No Classes")
                    .font(AppText.title)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)

                Text(isDimmed ? "Great work! Time to relax." : "Enjoy your free time!")
                    .font(AppText.label)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Decorative background icon
            Image(systemName: isDimmed ? "sparkles" : "leaf.fill")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(.white.opacity(0.12))
                .rotationEffect(.degrees(isDimmed ? 0 : -15))
                .offset(x: 10, y: -6)
        }
        .padding(AppSpace.cardPadding)
        .coloredRichCard(colors: gradientColors)
    }
}

struct WeekendCard: View {
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: AppSpace.sm) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
                    .breatheOrPulse()

                Spacer().frame(height: AppSpace.xs)

                Text("It's the Weekend!")
                    .font(AppText.title)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)

                Text("Relax and recharge.")
                    .font(AppText.label)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Decorative background icon
            Image(systemName: "star.fill")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 6, y: -4)
        }
        .padding(AppSpace.cardPadding)
        .coloredRichCard(colors: [Color.yellow.opacity(0.85), Color.orange.opacity(0.75)])
    }
}

struct HolidayModeCard: View {
    let hasEndDate: Bool
    let endDate: Date

    private var formattedEndDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: endDate)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: AppSpace.sm) {
                Image(systemName: "beach.umbrella.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)
                    .breatheOrPulse()

                Spacer().frame(height: AppSpace.xs)

                Text("Holiday Mode")
                    .font(AppText.title)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)

                Text(hasEndDate ? "Until \(formattedEndDate)" : "Enjoy your time off!")
                    .font(AppText.label)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Decorative background icon
            Image(systemName: "airplane")
                .font(.system(size: 64, weight: .thin))
                .foregroundStyle(.white.opacity(0.12))
                .rotationEffect(.degrees(-20))
                .offset(x: 6, y: -4)
        }
        .padding(AppSpace.cardPadding)
        .coloredRichCard(colors: [Color.orange.opacity(0.85), Color.red.opacity(0.7)])
    }
}

// MARK: - School Day Summary (compact info row)

struct SchoolDaySummaryCard: View {
    let assemblyTime: String
    let arrivalTime: String

    var body: some View {
        HStack(spacing: 0) {
            SummaryItem(icon: "bell.fill", label: "Assembly", value: assemblyTime)
            SummaryDivider()
            SummaryItem(icon: "door.left.hand.open", label: "Arrive by", value: arrivalTime)
            SummaryDivider()
            SummaryItem(icon: "fork.knife", label: "Lunch", value: "11:30")
        }
        .padding(.vertical, AppSpace.md)
        .coloredRichCard(
            colors: [AppColor.brand.opacity(0.7), Color.indigo.opacity(0.6)],
            shadowRadius: 10
        )
    }
}

private struct SummaryDivider: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 28)
    }
}

private struct SummaryItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: AppSpace.xxs + 1) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.15), in: Circle())
            Text(label)
                .font(AppText.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(AppText.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Daily schedule summary card
struct DailyScheduleCard: View {
    @ObservedObject var viewModel: ClasstableViewModel
    let dayIndex: Int
    let maxClassesToShow: Int = 3
    @State private var isExpandedSchedule = false
    @State private var isClassesOver: Bool = false

    /// Convert dayIndex (0-4) to weekday (2-6, Monday-Friday)
    private var dayWeekday: Int {
        dayIndex + 2
    }

    /// Class period model that conforms to Equatable and Identifiable
    struct ClassPeriodItem: Equatable, Identifiable {
        let id: String // Using composite id for uniqueness
        let period: Int
        let data: String
        let isSelfStudy: Bool

        init(period: Int, data: String, isSelfStudy: Bool) {
            self.id = "\(period)-\(isSelfStudy ? "self" : "class")"
            self.period = period
            self.data = data
            self.isSelfStudy = isSelfStudy
        }

        static func == (lhs: ClassPeriodItem, rhs: ClassPeriodItem) -> Bool {
            lhs.period == rhs.period &&
                lhs.data == rhs.data &&
                lhs.isSelfStudy == rhs.isSelfStudy
        }
    }

    /// Get max periods for this day of the week
    private var maxPeriodsForDay: Int {
        ClassPeriodsManager.shared.getMaxPeriodsByWeekday(dayWeekday)
    }

    /// Check if there are any classes or self-study periods for the day
    private var hasClasses: Bool {
        guard !viewModel.timetable.isEmpty, viewModel.timetable.count > 1 else { return false }
        return (1 ..< min(viewModel.timetable.count, maxPeriodsForDay + 1)).contains { row in
            row < viewModel.timetable.count && dayIndex + 1 < viewModel.timetable[row].count
        }
    }

    /// Get a list of classes/self-study periods for the day using our new struct
    private var scheduledClassesForToday: [ClassPeriodItem] {
        guard !viewModel.timetable.isEmpty else { return [] }

        let maxRow = min(viewModel.timetable.count, maxPeriodsForDay + 1)
        return (1 ..< maxRow).compactMap { row in
            guard row < viewModel.timetable.count, dayIndex + 1 < viewModel.timetable[row].count else {
                return nil
            }

            let classData = viewModel.timetable[row][dayIndex + 1]
            let isSelfStudy = classData.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            return ClassPeriodItem(
                period: row,
                data: isSelfStudy ? "Class-Free\n\nSelf-Study" : classData,
                isSelfStudy: isSelfStudy
            )
        }
    }

    /// Add method to check if all classes for today are over
    private func checkIfClassesOver() {
        let now = Date()
        if dayIndex >= 0, dayIndex <= 4 {
            let classes = scheduledClassesForToday
            if !classes.isEmpty {
                if let lastClassPeriod = classes.map(\.period).max(),
                   let lastPeriod = ClassPeriodsManager.shared.classPeriods
                   .first(where: { $0.number == lastClassPeriod })
                {
                    isClassesOver = now > lastPeriod.endTime
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpace.cardSpacing) {
            // Card header with class count
            HStack {
                Label("Schedule", systemImage: "calendar.day.timeline.left")
                    .font(AppText.sectionTitle)
                    .fontDesign(.rounded)
                    .foregroundStyle(.primary)
                Spacer()
                if hasClasses {
                    let regularClassCount = scheduledClassesForToday.filter { !$0.isSelfStudy }.count
                    let selfStudyCount = scheduledClassesForToday.filter(\.isSelfStudy).count

                    Text("\(regularClassCount) Classes, \(selfStudyCount) Self-Study")
                        .font(AppText.meta)
                        .foregroundStyle(.secondary)
                }
            }
            SubtleDivider()

            // Class listing
            if hasClasses {
                VStack(spacing: AppSpace.sm) {
                    let visibleClasses = isExpandedSchedule ?
                        scheduledClassesForToday :
                        Array(scheduledClassesForToday.prefix(maxClassesToShow))

                    ForEach(visibleClasses) { item in
                        if let period = ClassPeriodsManager.shared.classPeriods
                            .first(where: { $0.number == item.period })
                        {
                            let info = ClassInfoParser.parse(item.data)
                            ScheduleRow(
                                period: item.period,
                                time: period.timeRangeFormatted,
                                subject: info.subject ?? "Class",
                                room: info.room ?? "",
                                isSelfStudy: item.isSelfStudy
                            )
                        }
                    }

                    if scheduledClassesForToday.count > maxClassesToShow {
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                isExpandedSchedule.toggle()
                            }
                        } label: {
                            HStack {
                                Text(isExpandedSchedule ? "See Less" : "See Full Schedule")
                                    .font(AppText.label)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .rotationEffect(.degrees(isExpandedSchedule ? 180 : 0))
                                    .symbolEffect(.bounce, value: isExpandedSchedule)
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(AppColor.brand)
                        }
                        .padding(.top, AppSpace.xxs + 2)
                    }
                }
            } else {
                Text("No classes scheduled for today")
                    .font(AppText.label)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppSpace.lg)
            }
        }
        .padding(AppSpace.cardSpacing)
        .richCard()
        .onAppear {
            checkIfClassesOver()
        }
        .onChange(of: dayIndex) { _, _ in
            checkIfClassesOver()
        }
    }
}

/// Sign in prompt card
struct SignInPromptCard: View {
    @ViewBuilder
    private var sparklesIcon: some View {
        let base = Image(systemName: "sparkles")
            .font(.system(size: 52, weight: .medium))
            .foregroundStyle(AppColor.brand.gradient)
            .shadow(color: AppColor.brand.opacity(0.3), radius: 8, y: 4)

        if #available(iOS 18.0, *) {
            base.symbolEffect(.breathe, isActive: true)
        } else {
            base.symbolEffect(.pulse, isActive: true)
        }
    }

    var body: some View {
        VStack(spacing: AppSpace.lg) {
            Spacer()

            sparklesIcon
                .padding(.bottom, AppSpace.xxs)

            Text("Welcome to Outspire!")
                .font(.title.weight(.bold))
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)

            Text("Make your campus life easier")
                .font(AppText.subtitle)
                .foregroundStyle(.secondary)
                .fontDesign(.rounded)
                .multilineTextAlignment(.center)

            NavigationLink(destination: SettingsView(showSettingsSheet: .constant(false), isModal: false)) {
                Label("Sign In with TSIMS", systemImage: "person.fill.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, AppSpace.xs)

            Spacer()
        }
        .padding(AppSpace.xl)
    }
}

// MARK: - Quick Links

struct QuickLinksCard: View {
    var body: some View {
        VStack(spacing: AppSpace.sm) {
            HStack(spacing: AppSpace.sm) {
                QuickLinkCard(
                    destination: ClubInfoView(),
                    title: "Clubs",
                    systemImage: "person.2.fill",
                    colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)]
                )
                QuickLinkCard(
                    destination: LunchMenuView(),
                    title: "Dining",
                    systemImage: "fork.knife",
                    colors: [Color.orange.opacity(0.8), Color.orange.opacity(0.6)]
                )
            }
            HStack(spacing: AppSpace.sm) {
                QuickLinkCard(
                    destination: ClubActivitiesView(),
                    title: "Activities",
                    systemImage: "checklist",
                    colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)]
                )
                QuickLinkCard(
                    destination: ReflectionsView(),
                    title: "Reflect",
                    systemImage: "square.and.pencil",
                    colors: [Color.purple.opacity(0.8), Color.purple.opacity(0.6)]
                )
            }
        }
    }
}

private struct QuickLinkCard<Dest: View>: View {
    let destination: Dest
    let title: String
    let systemImage: String
    let colors: [Color]

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)

                Spacer().frame(height: AppSpace.xxs)

                Text(title)
                    .font(AppText.sectionTitle)
                    .fontDesign(.rounded)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpace.md)
            .coloredRichCard(colors: colors, shadowRadius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }
}

/// Add the button style that was in TodayView
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Self Study Period Card
struct SelfStudyPeriodCard: View {
    let currentPeriod: Int
    let nextClassPeriod: Int?
    let nextClassName: String?
    let dayOfWeek: Int? // 1-7, where 1 is Sunday

    private var isLastPeriodOfDay: Bool {
        guard let dayOfWeek else { return false }
        return currentPeriod >= ClassPeriodsManager.shared.getMaxPeriodsByWeekday(dayOfWeek)
    }

    var body: some View {
        VStack(spacing: AppSpace.cardSpacing) {
            Image(systemName: "book.fill")
                .font(.system(size: 44))
                .foregroundStyle(.purple)
                .symbolRenderingMode(.hierarchical)
                .breatheOrPulse()

            VStack(spacing: AppSpace.xxs) {
                Text("Self-Study Period")
                    .font(AppText.title)
                    .fontDesign(.rounded)

                Text("Period \(currentPeriod)\(isLastPeriodOfDay ? " (Last Period)" : "")")
                    .font(AppText.meta)
                    .foregroundStyle(.secondary)

                if let nextClassPeriod, let nextClassName {
                    Text("Next: Period \(nextClassPeriod) — \(nextClassName)")
                        .font(AppText.meta)
                        .foregroundStyle(.purple)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .richCard()
    }
}

/// Lunch Break Card
struct LunchBreakCard: View {
    let nextClassPeriod: Int?
    let nextClassName: String?
    let currentTime: Date
    let lunchEndTime: Date

    private var timeRemaining: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated

        let timeInterval = lunchEndTime.timeIntervalSince(currentTime)
        return formatter.string(from: max(0, timeInterval)) ?? ""
    }

    var body: some View {
        VStack(spacing: AppSpace.cardSpacing) {
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)
                .breatheOrPulse()

            VStack(spacing: AppSpace.xxs) {
                Text("Lunch Break")
                    .font(AppText.title)
                    .fontDesign(.rounded)

                Text("Time remaining: \(timeRemaining)")
                    .font(AppText.meta)
                    .foregroundStyle(.secondary)

                if let nextClassPeriod, let nextClassName {
                    let components = nextClassName.components(separatedBy: "\n").filter { !$0.isEmpty }
                    let subjectName = components.count > 1 ? components[1] : nextClassName

                    Text("Next: Period \(nextClassPeriod) — \(subjectName)")
                        .font(AppText.meta)
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .richCard()
    }
}

// MARK: - Interactive Card Button Style

/// Press-to-depress button style with haptic feedback and shadow reduction.
struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyle.Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .rotation3DEffect(
                .degrees(configuration.isPressed ? 1 : 0),
                axis: (x: 1, y: 0, z: 0)
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    HapticManager.shared.playLightFeedback()
                }
            }
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle {
        PressableCardStyle()
    }
}
