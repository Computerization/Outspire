import SwiftUI

struct TodayHeaderView: View {
    let greeting: String
    let formattedDate: String
    // When true, renders the date within the header. Disable if using a nav subtitle.
    var showDateInHeader: Bool = true
    let nickname: String?
    let selectedDayOverride: Int?
    let isHolidayActive: Bool
    let holidayHasEndDate: Bool
    let holidayEndDateString: String
    let isHolidayMode: Bool
    let animateCards: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                // Optionally show the date here (when not shown as nav subtitle)
                if showDateInHeader {
                    Text(formattedDate)
                        .font(AppText.meta)
                        .foregroundStyle(.secondary)
                }
                additionalHeaderText
                    .padding(.top, 2)
            }
            Spacer()
            // Weather removed
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.leading, 3)
        // Remove fly-in animations for a calmer header
    }

    @ViewBuilder
    private var additionalHeaderText: some View {
        if let override = selectedDayOverride {
            HStack {
                Image(systemName: "calendar.badge.exclamationmark")
                    .foregroundStyle(.blue)
                Text("Viewing \(TodayViewHelpers.weekdayName(for: override + 1))'s schedule")
                    .font(AppText.meta)
                    .foregroundStyle(.blue)
            }
        } else if isHolidayActive, holidayHasEndDate {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("Holiday Mode Until \(holidayEndDateString)")
                    .font(AppText.meta)
                    .foregroundStyle(.orange)
            }
        } else if isHolidayMode {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.orange)
                Text("Holiday Mode Enabled")
                    .font(AppText.meta)
                    .foregroundStyle(.orange)
            }
        }
    }
}
