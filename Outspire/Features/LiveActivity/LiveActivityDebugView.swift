import ActivityKit
import SwiftUI

#if DEBUG

    struct LiveActivityDebugView: View {
        @ObservedObject private var manager = ClassActivityManager.shared
        @State private var isEnabled =
            UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true

        var body: some View {
            List {
                Section("Live Activity Status") {
                    HStack {
                        Text("Running")
                        Spacer()
                        Text(manager.isActivityRunning ? "Yes" : "No")
                            .foregroundStyle(manager.isActivityRunning ? .green : .secondary)
                    }
                    HStack {
                        Text("Supported")
                        Spacer()
                        Text(manager.isSupported ? "Yes" : "No")
                            .foregroundStyle(manager.isSupported ? .green : .red)
                    }
                    Toggle("Enabled", isOn: $isEnabled)
                }

                Section("Test Scenarios") {
                    Button("In Class — Mathematics (25 min left)") {
                        startTest(.ongoingMath)
                    }
                    Button("Ending Soon — Physics (3 min left)") {
                        startTest(.endingPhysics)
                    }
                    Button("Break — Next: English (8 min)") {
                        startTest(.breakBeforeEnglish)
                    }
                    Button("Lunch Break (25 min)") {
                        startTest(.lunchBreak)
                    }
                    Button("Last Class — Chemistry (12 min left)") {
                        startTest(.lastClass)
                    }
                    Button("Upcoming — First class in 15 min") {
                        startTest(.upcomingFirst)
                    }
                }

                Section {
                    Button("Stop Live Activity", role: .destructive) {
                        manager.endAllActivities()
                    }
                }
            }
            .navigationTitle("Live Activity Debug")
            .onAppear {
                isEnabled = UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
            }
            .onChange(of: isEnabled) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: "liveActivityEnabled")
            }
        }

        private func startTest(_ scenario: TestScenario) {
            manager.endAllActivities()

            // Small delay to let the old one dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let schedule = scenario.buildSchedule()
                manager.startActivity(schedule: schedule, skipEnabledCheck: true)
            }
        }
    }

    private enum TestScenario {
        case ongoingMath
        case endingPhysics
        case breakBeforeEnglish
        case lunchBreak
        case lastClass
        case upcomingFirst

        func buildSchedule() -> [ScheduledClass] {
            let now = Date()

            switch self {
            case .ongoingMath:
                // Currently in Math, 25 min left, English next
                return [
                    ScheduledClass(
                        periodNumber: 3, className: "Mathematics", roomNumber: "A108",
                        teacherName: "", startTime: now.addingTimeInterval(-900),
                        endTime: now.addingTimeInterval(1500), isSelfStudy: false
                    ),
                    ScheduledClass(
                        periodNumber: 4, className: "English Literature", roomNumber: "B205",
                        teacherName: "", startTime: now.addingTimeInterval(2100),
                        endTime: now.addingTimeInterval(4500), isSelfStudy: false
                    ),
                    ScheduledClass(
                        periodNumber: 5, className: "Physics", roomNumber: "C301",
                        teacherName: "", startTime: now.addingTimeInterval(5100),
                        endTime: now.addingTimeInterval(7500), isSelfStudy: false
                    )
                ]

            case .endingPhysics:
                // Physics ending in 3 min
                return [
                    ScheduledClass(
                        periodNumber: 5, className: "Physics", roomNumber: "C301",
                        teacherName: "", startTime: now.addingTimeInterval(-2220),
                        endTime: now.addingTimeInterval(180), isSelfStudy: false
                    ),
                    ScheduledClass(
                        periodNumber: 6, className: "Chemistry", roomNumber: "C302",
                        teacherName: "", startTime: now.addingTimeInterval(780),
                        endTime: now.addingTimeInterval(3180), isSelfStudy: false
                    )
                ]

            case .breakBeforeEnglish:
                // Break, English starts in 8 min
                return [
                    ScheduledClass(
                        periodNumber: 4, className: "English Literature", roomNumber: "B205",
                        teacherName: "", startTime: now.addingTimeInterval(480),
                        endTime: now.addingTimeInterval(2880), isSelfStudy: false
                    ),
                    ScheduledClass(
                        periodNumber: 5, className: "Physics", roomNumber: "C301",
                        teacherName: "", startTime: now.addingTimeInterval(3480),
                        endTime: now.addingTimeInterval(5880), isSelfStudy: false
                    )
                ]

            case .lunchBreak:
                // Lunch, next class in 25 min
                return [
                    ScheduledClass(
                        periodNumber: 6, className: "Chemistry", roomNumber: "C302",
                        teacherName: "", startTime: now.addingTimeInterval(1500),
                        endTime: now.addingTimeInterval(3900), isSelfStudy: false
                    )
                ]

            case .lastClass:
                // Last class, 12 min left
                return [
                    ScheduledClass(
                        periodNumber: 8, className: "Chemistry", roomNumber: "C302",
                        teacherName: "", startTime: now.addingTimeInterval(-1680),
                        endTime: now.addingTimeInterval(720), isSelfStudy: false
                    )
                ]

            case .upcomingFirst:
                // First class in 15 min
                return [
                    ScheduledClass(
                        periodNumber: 1, className: "Mathematics", roomNumber: "A108",
                        teacherName: "", startTime: now.addingTimeInterval(900),
                        endTime: now.addingTimeInterval(3300), isSelfStudy: false
                    ),
                    ScheduledClass(
                        periodNumber: 2, className: "English Literature", roomNumber: "B205",
                        teacherName: "", startTime: now.addingTimeInterval(3900),
                        endTime: now.addingTimeInterval(6300), isSelfStudy: false
                    )
                ]
            }
        }
    }

#endif
