import ActivityKit
import Foundation
import OSLog

private enum LiveActivityOwner: String {
    case app
    case worker
}

private enum LiveActivityStateBuilder {
    static func state(
        for schedule: [ScheduledClass],
        at now: Date
    ) -> ClassActivityAttributes.ContentState? {
        let sorted = schedule.sorted { $0.startTime < $1.startTime }
        guard let first = sorted.first, let last = sorted.last else { return nil }

        let dayKey = NormalizedScheduleBuilder.dayKey(for: now)

        if now < first.startTime {
            let countdownStart = max(now, first.startTime.addingTimeInterval(-1800))
            return ClassActivityAttributes.ContentState(
                dayKey: dayKey,
                phase: .upcoming,
                title: first.className,
                subtitle: subtitle(for: first),
                rangeStart: countdownStart,
                rangeEnd: first.startTime,
                nextTitle: sorted.dropFirst().first?.className,
                sequence: 0
            )
        }

        for (index, current) in sorted.enumerated() {
            if current.startTime <= now, current.endTime > now {
                let remaining = current.endTime.timeIntervalSince(now)
                return ClassActivityAttributes.ContentState(
                    dayKey: dayKey,
                    phase: remaining <= 300 ? .ending : .ongoing,
                    title: current.className,
                    subtitle: subtitle(for: current),
                    rangeStart: current.startTime,
                    rangeEnd: current.endTime,
                    nextTitle: sorted.dropFirst(index + 1).first?.className,
                    sequence: index * 3 + (remaining <= 300 ? 2 : 1)
                )
            }

            if current.endTime <= now, let next = sorted.dropFirst(index + 1).first, next.startTime > now {
                let breakKind = NormalizedScheduleBuilder.breakKind(between: current, and: next)
                return ClassActivityAttributes.ContentState(
                    dayKey: dayKey,
                    phase: .breakTime,
                    title: breakKind == .lunch ? "Lunch Break" : "Break",
                    subtitle: "Next: \(next.className)",
                    rangeStart: current.endTime,
                    rangeEnd: next.startTime,
                    nextTitle: next.className,
                    sequence: index * 3 + 3
                )
            }
        }

        return ClassActivityAttributes.ContentState(
            dayKey: dayKey,
            phase: .done,
            title: "Schedule Complete",
            subtitle: "",
            rangeStart: last.endTime,
            rangeEnd: last.endTime.addingTimeInterval(900),
            nextTitle: nil,
            sequence: sorted.count * 3 + 1
        )
    }

    static func staleDate(for schedule: [ScheduledClass]) -> Date? {
        schedule.map(\.endTime).max()?.addingTimeInterval(900)
    }

    private static func subtitle(for scheduledClass: ScheduledClass) -> String {
        if scheduledClass.isSelfStudy {
            return scheduledClass.roomNumber.isEmpty ? "Class-Free Period" : scheduledClass.roomNumber
        }
        return scheduledClass.roomNumber
    }
}

@MainActor
final class ClassActivityManager: ObservableObject {
    static let shared = ClassActivityManager()

    @Published private(set) var isActivityRunning = false

    private var currentActivity: Activity<ClassActivityAttributes>?
    private var currentSchedule: [ScheduledClass] = []
    private var currentTimetable: [[String]] = []
    private var holidayActive = false
    private var lastPushStartToken: String?
    private var lastUploadedUpdateTokenByActivity: [String: String] = [:]
    private var tokenObservationTasks: [String: Task<Void, Never>] = [:]
    private var currentOwner: LiveActivityOwner = .worker

    private var hasRegistered = false
    private var registerGeneration = 0
    private var retryCount = 0
    private var isRegistering = false
    private static let maxRetries = 2

    private init() {
        if #available(iOS 17.2, *) {
            Task { @MainActor in
                for await token in Activity<ClassActivityAttributes>.pushToStartTokenUpdates {
                    let tokenString = token.map { String(format: "%02x", $0) }.joined()
                    Log.app.debug("LA pushToStart token: \(tokenString.prefix(20))...")
                    if self.lastPushStartToken != tokenString {
                        self.lastPushStartToken = tokenString
                        self.hasRegistered = false
                        self.registerIfReady()
                    }
                }
            }
        }

        reconcileExistingActivities()
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func reconcileExistingActivities() {
        let activities = Activity<ClassActivityAttributes>.activities.sorted {
            $0.attributes.startDate > $1.attributes.startDate
        }

        guard !activities.isEmpty else {
            currentActivity = nil
            isActivityRunning = false
            return
        }

        let existingCurrentID = currentActivity?.id
        currentActivity = nil
        isActivityRunning = false

        var adoptedActivityID: String?
        for activity in activities {
            let state = activity.content.state
            guard !state.dayKey.isEmpty, !state.title.isEmpty else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                continue
            }

            if adoptedActivityID == nil {
                let owner: LiveActivityOwner = activity.id == existingCurrentID ? currentOwner : .worker
                adopt(activity, owner: owner)
                adoptedActivityID = activity.id
            } else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    func startActivity(
        schedule: [ScheduledClass],
        timetable: [[String]] = [],
        skipEnabledCheck: Bool = false
    ) {
        guard skipEnabledCheck || isEnabled, isSupported else { return }

        let normalizedSchedule = schedule.sorted { $0.startTime < $1.startTime }
        guard !normalizedSchedule.isEmpty else { return }

        if !timetable.isEmpty {
            currentTimetable = timetable
        }
        currentSchedule = normalizedSchedule

        reconcileExistingActivities()
        if currentActivity != nil {
            refreshActivityStateIfNeeded(schedule: normalizedSchedule)
            return
        }

        let now = Date()
        guard let initialState = LiveActivityStateBuilder.state(for: normalizedSchedule, at: now),
              initialState.phase != .done
        else { return }

        let attributes = ClassActivityAttributes(startDate: now)
        let content = ActivityContent(
            state: initialState,
            staleDate: LiveActivityStateBuilder.staleDate(for: normalizedSchedule)
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            currentOwner = .app
            adopt(activity, owner: .app)
            refreshActivityStateIfNeeded(schedule: normalizedSchedule)
            Log.app.info("Live Activity started with sequence \(initialState.sequence)")
        } catch {
            Log.app.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    func refreshActivityStateIfNeeded(schedule: [ScheduledClass]? = nil) {
        if let schedule {
            currentSchedule = schedule.sorted { $0.startTime < $1.startTime }
        }

        guard let activity = currentActivity, !currentSchedule.isEmpty else { return }
        guard let desiredState = LiveActivityStateBuilder.state(for: currentSchedule, at: Date()) else { return }

        if desiredState.phase == .done {
            endActivity()
            return
        }

        guard activity.content.state.sequence != desiredState.sequence else { return }

        let staleDate = LiveActivityStateBuilder.staleDate(for: currentSchedule)
        Task {
            await activity.update(ActivityContent(state: desiredState, staleDate: staleDate))
            Log.app.debug("Live Activity updated to sequence \(desiredState.sequence)")
        }
    }

    func endActivity() {
        guard let activity = currentActivity else { return }
        let dayKey = activity.content.state.dayKey

        Task {
            let finalState = LiveActivityStateBuilder.state(for: currentSchedule, at: Date())
            let finalContent = finalState.map {
                ActivityContent(
                    state: $0,
                    staleDate: LiveActivityStateBuilder.staleDate(for: currentSchedule)
                )
            }
            await activity.end(
                finalContent,
                dismissalPolicy: .after(Date().addingTimeInterval(900))
            )
            Log.app.info("Live Activity ended")
        }

        PushRegistrationService.notifyActivityEnded(
            activityId: activity.id,
            dayKey: dayKey
        )

        clearCurrentActivity(activityID: activity.id)
    }

    func endAllActivities() {
        Task {
            for activity in Activity<ClassActivityAttributes>.activities {
                PushRegistrationService.notifyActivityEnded(
                    activityId: activity.id,
                    dayKey: activity.content.state.dayKey
                )
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        for (_, task) in tokenObservationTasks {
            task.cancel()
        }
        tokenObservationTasks.removeAll()
        lastUploadedUpdateTokenByActivity.removeAll()
        currentActivity = nil
        isActivityRunning = false
        currentSchedule = []
        currentTimetable = []
        hasRegistered = false
    }

    func endActivityIfClassesDone(schedule: [ScheduledClass]) {
        currentSchedule = schedule.sorted { $0.startTime < $1.startTime }
        if !currentSchedule.contains(where: { $0.endTime > Date() }) {
            endActivity()
        }
    }

    func retryRegistrationIfNeeded() {
        reconcileExistingActivities()
        if let schedule = buildTodayScheduleFromTimetable() {
            currentSchedule = schedule
            refreshActivityStateIfNeeded(schedule: schedule)
            if !holidayActive, currentActivity == nil, shouldStartActivity(for: schedule, at: Date()) {
                startActivity(schedule: schedule, timetable: currentTimetable)
            }
        }

        guard !hasRegistered else { return }
        retryCount = 0
        registerIfReady()
    }

    func setTimetable(_ timetable: [[String]]) {
        guard !timetable.isEmpty else { return }
        currentTimetable = timetable
        if let schedule = buildTodayScheduleFromTimetable() {
            currentSchedule = schedule
            refreshActivityStateIfNeeded(schedule: schedule)
            if !holidayActive, currentActivity == nil, shouldStartActivity(for: schedule, at: Date()) {
                startActivity(schedule: schedule, timetable: timetable)
            }
        }
        hasRegistered = false
        registerIfReady()
    }

    func setHolidayActive(_ active: Bool) {
        holidayActive = active
        if active, currentActivity != nil {
            endActivity()
        }
    }

    private func adopt(
        _ activity: Activity<ClassActivityAttributes>,
        owner: LiveActivityOwner
    ) {
        currentActivity = activity
        currentOwner = owner
        isActivityRunning = true
        observePushTokenUpdates(for: activity, owner: owner)
        if let token = activity.pushToken {
            handlePushUpdateToken(
                token.map { String(format: "%02x", $0) }.joined(),
                for: activity,
                owner: owner
            )
        }
        Log.app.info("Adopted Live Activity \(activity.id, privacy: .public)")
    }

    private func observePushTokenUpdates(
        for activity: Activity<ClassActivityAttributes>,
        owner: LiveActivityOwner
    ) {
        guard tokenObservationTasks[activity.id] == nil else { return }

        tokenObservationTasks[activity.id] = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                let tokenString = token.map { String(format: "%02x", $0) }.joined()
                await MainActor.run {
                    self?.handlePushUpdateToken(tokenString, for: activity, owner: owner)
                }
            }
        }
    }

    private func handlePushUpdateToken(
        _ token: String,
        for activity: Activity<ClassActivityAttributes>,
        owner: LiveActivityOwner
    ) {
        guard !token.isEmpty else { return }
        if lastUploadedUpdateTokenByActivity[activity.id] == token { return }

        lastUploadedUpdateTokenByActivity[activity.id] = token
        PushRegistrationService.updateActivityToken(
            activityId: activity.id,
            dayKey: activity.content.state.dayKey,
            pushUpdateToken: token,
            owner: owner.rawValue
        ) { success in
            if success {
                Log.app.info("Uploaded LA update token for activity \(activity.id, privacy: .public)")
            } else {
                Log.app.error("Failed to upload LA update token for activity \(activity.id, privacy: .public)")
            }
        }
    }

    private func clearCurrentActivity(activityID: String) {
        tokenObservationTasks[activityID]?.cancel()
        tokenObservationTasks.removeValue(forKey: activityID)
        lastUploadedUpdateTokenByActivity.removeValue(forKey: activityID)
        currentActivity = nil
        isActivityRunning = false
        currentOwner = .worker
    }

    private func buildTodayScheduleFromTimetable() -> [ScheduledClass]? {
        guard !currentTimetable.isEmpty else { return nil }

        let dayIndex = NormalizedScheduleBuilder.weekdayIndex(for: Date())
        guard dayIndex >= 0, dayIndex < 5 else { return nil }

        let schedule = NormalizedScheduleBuilder.buildDaySchedule(
            from: currentTimetable,
            dayIndex: dayIndex
        )
        return schedule.isEmpty ? nil : schedule
    }

    private func shouldStartActivity(for schedule: [ScheduledClass], at now: Date) -> Bool {
        guard !schedule.isEmpty else { return false }
        guard schedule.contains(where: { $0.endTime > now }) else { return false }

        if let firstStart = schedule.map(\.startTime).min() {
            return now >= firstStart.addingTimeInterval(-1800)
        }

        return false
    }

    private func registerIfReady() {
        guard !hasRegistered, !isRegistering,
              let startToken = lastPushStartToken,
              !currentTimetable.isEmpty,
              let userCode = AuthServiceV2.shared.user?.userCode,
              let studentInfo = StudentInfo(userCode: userCode)
        else { return }

        isRegistering = true
        registerGeneration += 1
        let generation = registerGeneration
        let timetable = currentTimetable

        PushRegistrationService.register(
            pushStartToken: startToken,
            studentCode: userCode,
            studentInfo: studentInfo,
            timetable: timetable
        ) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRegistering = false

                if generation != self.registerGeneration {
                    self.registerIfReady()
                    return
                }

                if success {
                    self.hasRegistered = true
                    self.retryCount = 0
                    Log.app
                        .info(
                            "Registered with push worker (deviceId: \(PushRegistrationService.deviceId.prefix(8))...)"
                        )
                } else if self.retryCount < Self.maxRetries {
                    self.retryCount += 1
                    Log.app
                        .warning("Push worker registration failed, retrying (\(self.retryCount)/\(Self.maxRetries))...")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        self.registerIfReady()
                    }
                } else {
                    Log.app.error("Push worker registration failed after \(Self.maxRetries) retries")
                }
            }
        }
    }
}
