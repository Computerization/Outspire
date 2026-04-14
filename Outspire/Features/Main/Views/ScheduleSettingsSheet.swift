import SwiftUI

struct ScheduleSettingsSheet: View {
    @ObservedObject private var authV2 = AuthServiceV2.shared
    @Binding var selectedDay: Int?
    @Binding var setAsToday: Bool
    @Binding var isHolidayMode: Bool
    @Binding var isPresented: Bool
    @Binding var holidayEndDate: Date
    @Binding var holidayHasEndDate: Bool
    @State private var showCountdownForFutureClasses = Configuration.showCountdownForFutureClasses

    @Environment(\.dismiss) private var dismiss

    private var currentWeekday: Int {
        let weekday = Calendar.current.component(.weekday, from: Date())
        // Convert to 0-based index (0 = Monday)
        return weekday == 1 ? 6 : weekday - 2
    }

    private var isCurrentDayWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weekday == 7
    }

    var body: some View {
        NavigationStack {
            if !authV2.isAuthenticated {
                VStack(spacing: 20) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)

                    Text("Authentication Required")
                        .font(AppText.title)

                    Text("Please sign in to access schedule settings")
                        .foregroundStyle(.secondary)

                    Button("Close") {
                        HapticManager.shared.playButtonTap()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .padding()
                .navigationTitle("Schedule Settings")
            } else {
                List {
                    // Day selection section
                    Section(header: Text("Day Selection")) {
                        Button {
                            HapticManager.shared.playSelectionFeedback()
                            selectedDay = nil
                            isHolidayMode = false
                            setAsToday = false

                        } label: {
                            HStack {
                                if !isCurrentDayWeekend, currentWeekday >= 0, currentWeekday < 5 {
                                    Text("Today (\(dayName(for: currentWeekday)))")
                                } else {
                                    Text("Today")
                                }

                                Spacer()
                                if selectedDay == nil, !isHolidayMode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .foregroundStyle(.primary)

                        ForEach(0 ..< 5, id: \.self) { index in
                            if index == currentWeekday, !isCurrentDayWeekend {
                                EmptyView()
                            } else {
                                Button {
                                    HapticManager.shared.playSelectionFeedback()
                                    selectedDay = index
                                    isHolidayMode = false

                                } label: {
                                    HStack {
                                        Text(dayName(for: index))

                                        Spacer()
                                        if selectedDay == index, !isHolidayMode {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }

                    if let day = selectedDay, day != currentWeekday || isCurrentDayWeekend {
                        Section(header: Text("View Mode")) {
                            Toggle("Set as Current Day", isOn: $setAsToday)
                                .foregroundStyle(.primary)
                                .onChange(of: setAsToday) { _, newValue in
                                    HapticManager.shared.playToggle()
                                    Configuration.setAsToday = newValue
                                }
                        }
                    }

                    // Holiday mode section
                    Section(header: Text("Holiday Mode")) {
                        Toggle(isOn: $isHolidayMode) {
                            Label("Enable Holiday Mode", systemImage: "sun.max.fill")
                                .foregroundStyle(isHolidayMode ? .orange : .primary)
                        }
                        .onChange(of: isHolidayMode) { _, enabled in
                            HapticManager.shared.playToggle()
                            if enabled {
                                selectedDay = nil
                                setAsToday = false
                            }
                        }

                        if isHolidayMode {
                            Toggle("Set End Date", isOn: $holidayHasEndDate)
                                .onChange(of: holidayHasEndDate) { _, _ in
                                    HapticManager.shared.playToggle()
                                }
                            if holidayHasEndDate {
                                DatePicker(
                                    "Holiday Ends",
                                    selection: $holidayEndDate,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                            }
                        }
                    }

                    // Display options
                    Section(header: Text("Display Options")) {
                        Toggle(
                            "Show Countdown for Future Classes",
                            isOn: $showCountdownForFutureClasses
                        )
                        .onChange(of: showCountdownForFutureClasses) { _, newValue in
                            HapticManager.shared.playToggle()
                            Configuration.showCountdownForFutureClasses = newValue
                        }
                    }
                }
                .toggleStyle(.switch)
                .navigationTitle("Schedule Settings")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            HapticManager.shared.playButtonTap()
                            isPresented = false
                        }
                    }
                }
            }
        }
    }

    private func dayName(for index: Int) -> String {
        let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        return days[index]
    }
}
