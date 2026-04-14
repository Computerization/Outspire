import SwiftUI

struct ScheduleRow: View {
    let period: Int
    let time: String
    let subject: String
    let room: String
    let isSelfStudy: Bool

    init(period: Int, time: String, subject: String, room: String, isSelfStudy: Bool = false) {
        self.period = period
        self.time = time
        self.subject = subject
        self.room = room
        self.isSelfStudy = isSelfStudy
    }

    /// Get dynamic color based on subject or self-study status
    private var periodColor: Color {
        if isSelfStudy {
            .purple
        } else if !subject.isEmpty {
            ModernScheduleRow.subjectColor(for: subject)
        } else {
            .blue
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: AppSpace.sm) {
            // Colored dot + Period number
            HStack(spacing: 6) {
                Circle()
                    .fill(periodColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: periodColor.opacity(0.4), radius: 3)

                Text("\(period)")
                    .font(.system(.callout, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(periodColor)
                    .frame(width: 20, alignment: .center)
            }

            // Class details
            VStack(alignment: .leading, spacing: 2) {
                Text(subject)
                    .font(AppText.label)
                    .foregroundStyle(isSelfStudy ? Color.purple : Color.primary)

                HStack(spacing: AppSpace.xxs) {
                    if !room.isEmpty {
                        Text(room)
                            .font(AppText.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(AppText.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Text(time)
                        .font(AppText.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isSelfStudy {
                Text("Self-Study")
                    .font(AppText.caption)
                    .foregroundStyle(.purple.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.purple.opacity(0.1), in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }
}
