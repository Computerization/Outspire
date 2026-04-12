import ActivityKit
import Foundation
import OSLog

@MainActor
final class ClassActivityManager: ObservableObject {
    static let shared = ClassActivityManager()

    @Published private(set) var isActivityRunning = false
    private var currentActivity: Activity<ClassActivityAttributes>?
    private var lastPushStartToken: String?

    /// The full timetable grid, kept so we can register with the Worker.
    private var currentTimetable: [[String]] = []

    /// Whether we already sent a register request for the current token.
    private var hasRegistered = false

    /// Guard against overlapping register requests.
    private var registerGeneration = 0

    private init() {
        // Observe pushToStartToken once — lives for the entire app lifetime.
        // This is the only token needed for the self-driven LA architecture.
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

        // Restore any existing activity from a previous app session
        restoreExistingActivity()
    }

    var isEnabled: Bool {
        // Default to true for existing users who never saw the onboarding LA toggle
        UserDefaults.standard.object(forKey: "liveActivityEnabled") as? Bool ?? true
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: - Restore

    /// Reattach to an activity that survived an app kill/relaunch.
    /// Ends any activities with incompatible content-state (from pre-upgrade).
    private func restoreExistingActivity() {
        let activities = Activity<ClassActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        for activity in activities {
            // Verify the content-state has the new classes array format
            if activity.content.state.classes.isEmpty {
                // Old-schema or empty activity — end it
                Task {
                    await activity.end(nil, dismissalPolicy: .immediate)
                    Log.app.info("Ended incompatible Live Activity from previous version")
                }
                continue
            }

            // Adopt the first valid activity
            if currentActivity == nil {
                currentActivity = activity
                isActivityRunning = true
                Log.app.info("Restored existing Live Activity from previous session")
            } else {
                // Extra activity — end it
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    // MARK: - Start

    func startActivity(schedule: [ScheduledClass], timetable: [[String]] = [], skipEnabledCheck: Bool = false) {
        guard skipEnabledCheck || isEnabled, isSupported, !schedule.isEmpty else { return }

        // Store timetable for Worker registration
        if !timetable.isEmpty {
            currentTimetable = timetable
        }

        guard currentActivity == nil else {
            Log.app.debug("Live Activity already running")
            return
        }

        let now = Date()
        guard schedule.contains(where: { $0.endTime > now }) else { return }

        // Build the full-day content state with all classes
        let classInfos = schedule.map { sc in
            ClassActivityAttributes.ContentState.ClassInfo(
                name: sc.className,
                room: sc.roomNumber,
                start: sc.startTime,
                end: sc.endTime
            )
        }

        let initialState = ClassActivityAttributes.ContentState(classes: classInfos)
        let attributes = ClassActivityAttributes(startDate: now)

        // Set staleDate to 15 min after last class
        let lastEnd = schedule.map(\.endTime).max() ?? now
        let staleDate = lastEnd.addingTimeInterval(900)
        let content = ActivityContent(state: initialState, staleDate: staleDate)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: .token
            )
            isActivityRunning = true
            Log.app.info("Live Activity started with \(classInfos.count) classes")
        } catch {
            Log.app.error("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - End

    /// End the current activity. Called when app is foregrounded and all classes are done.
    func endActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .after(Date().addingTimeInterval(900)))
            Log.app.info("Live Activity ended")
        }

        currentActivity = nil
        isActivityRunning = false
    }

    /// End all activities (cleanup on logout).
    func endAllActivities() {
        Task {
            for activity in Activity<ClassActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        currentActivity = nil
        isActivityRunning = false
        currentTimetable = []
        hasRegistered = false
    }

    // MARK: - Check if classes are done (for foreground end)

    func endActivityIfClassesDone(schedule: [ScheduledClass]) {
        guard currentActivity != nil else { return }
        let now = Date()
        if !schedule.contains(where: { $0.endTime > now }) {
            endActivity()
        }
    }

    // MARK: - Worker Registration

    /// Called on scenePhase .active to re-attempt registration.
    func retryRegistrationIfNeeded() {
        guard !hasRegistered else { return }
        retryCount = 0
        registerIfReady()
    }

    /// Called externally when the timetable data becomes available.
    func setTimetable(_ timetable: [[String]]) {
        guard !timetable.isEmpty else { return }
        currentTimetable = timetable
        hasRegistered = false
        registerIfReady()
    }

    private var retryCount = 0
    private var isRegistering = false
    private static let maxRetries = 2

    private func registerIfReady() {
        // Only need pushStartToken — no pushUpdateToken required
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
                    Log.app.info("Registered with push worker (deviceId: \(PushRegistrationService.deviceId.prefix(8))...)")
                } else if self.retryCount < Self.maxRetries {
                    self.retryCount += 1
                    Log.app.warning("Push worker registration failed, retrying (\(self.retryCount)/\(Self.maxRetries))...")
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
