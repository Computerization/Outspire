import Combine
import Foundation
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    /// Request notification permissions
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, error in
            DispatchQueue.main.async {
                if let error {
                    print("Notification authorization request error: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                completion(granted)
            }
        }
    }

    /// Check notification permission status
    func checkAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    /// Register notification categories with actions
    func registerNotificationCategories() {
        notificationCenter.setNotificationCategories([])
    }

    /// Cancel all notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    /// Remove all pending notifications
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Centralized Notification Management

    /// Handles notification settings changes
    func handleNotificationSettingsChange() {
        // Re-schedule class reminders when settings change
        scheduleClassRemindersIfNeeded()
    }

    /// Handles app becoming active - ensures notifications are properly scheduled
    func handleAppBecameActive() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasCompletedOnboarding {
            scheduleClassRemindersIfNeeded()
        }
    }

    // MARK: - Class Reminders

    private static let classReminderCategory = "CLASS_REMINDER"
    private static let reminderLeadTime: TimeInterval = 300 // 5 minutes before class

    /// Schedule local notifications for upcoming classes today.
    /// Called when timetable data is available and app becomes active.
    func scheduleClassReminders(from timetable: [[String]]) {
        // Remove old class reminders first
        notificationCenter.removePendingNotificationRequests(withIdentifiers: pendingClassReminderIds())

        guard UserDefaults.standard.bool(forKey: "classRemindersEnabled") else { return }

        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let dayColumn = weekday - 1 // Mon=1..Fri=5
        guard dayColumn >= 1, dayColumn <= 5 else { return }

        let periods = ClassPeriodsManager.shared.classPeriods

        var ids: [String] = []

        for row in 1 ..< timetable.count {
            guard dayColumn < timetable[row].count else { continue }
            let cellData = timetable[row][dayColumn]
            let trimmed = cellData.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let period = periods.first(where: { $0.number == row }) else { continue }

            // Only schedule for future classes
            let reminderTime = period.startTime.addingTimeInterval(-Self.reminderLeadTime)
            guard reminderTime > now else { continue }

            let components = cellData.components(separatedBy: "\n")
            let subject = (components.count > 1 ? components[1] : components[0])
                .replacingOccurrences(of: "\\(\\d+\\)$", with: "", options: .regularExpression)
            let room = components.count > 2 ? components[2] : ""

            let content = UNMutableNotificationContent()
            content.title = subject
            content.body = room.isEmpty ? "Class starts in 5 minutes" : "Room \(room) — starts in 5 minutes"
            content.sound = .default
            content.categoryIdentifier = Self.classReminderCategory

            let triggerDate = calendar.dateComponents([.hour, .minute, .second], from: reminderTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

            let id = "class-reminder-\(row)"
            ids.append(id)

            let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            notificationCenter.add(request) { error in
                if let error {
                    Log.app.error("Failed to schedule class reminder: \(error.localizedDescription)")
                }
            }
        }

        // Save IDs for later cleanup
        UserDefaults.standard.set(ids, forKey: "pendingClassReminderIds")
    }

    private func pendingClassReminderIds() -> [String] {
        UserDefaults.standard.stringArray(forKey: "pendingClassReminderIds") ?? []
    }

    private func scheduleClassRemindersIfNeeded() {
        guard AuthServiceV2.shared.isAuthenticated else { return }
        let timetable = WidgetDataManager.readTimetable()
        guard !timetable.isEmpty else { return }
        scheduleClassReminders(from: timetable)
    }
}
