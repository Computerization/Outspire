import SwiftUI

struct ClassSummaryCard: View {
    let day: String
    let period: ClassPeriod
    let classData: String
    let isForToday: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var classInfo: ClassInfo {
        ClassInfoParser.parse(classData)
    }

    private var isCurrentClass: Bool {
        isForToday && period.isCurrentlyActive()
    }

    private var titleText: String {
        isCurrentClass ? "Current Class" : "Upcoming Class"
    }

    private var statusBackgroundColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.3) : Color.secondary.opacity(0.12)
    }

    private var subjectColor: Color {
        if classInfo.isSelfStudy { return .purple }
        if let subject = classInfo.subject { return ModernScheduleRow.subjectColor(for: subject) }
        return .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleText)
                        .font(.headline)
                    Text("\(day) • Period \(period.number)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(period.timeRangeFormatted)
                    .font(AppText.meta)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(statusBackgroundColor)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                if let subject = classInfo.subject {
                    Text(subject)
                        .font(.body.weight(.semibold))
                } else if classInfo.isSelfStudy {
                    Text("Self-Study")
                        .font(.body.weight(.semibold))
                }

                HStack(spacing: 20) {
                    if let teacher = classInfo.teacher, !teacher.isEmpty {
                        Label(teacher, systemImage: "person.fill")
                            .font(AppText.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let room = classInfo.room, !room.isEmpty {
                        Label(room, systemImage: "mappin.circle.fill")
                            .font(AppText.meta)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            if classInfo.isSelfStudy {
                Divider().padding(.horizontal, 16)
                HStack(spacing: 8) {
                    Image(systemName: "book")
                        .foregroundStyle(subjectColor)
                    Text(isCurrentClass ? "Focus time" : "Free period ahead")
                        .font(AppText.meta)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .glassmorphicCard()
    }
}
