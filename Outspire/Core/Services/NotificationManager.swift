import Combine
import Foundation
import UserNotifications

@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    // Request notification permissions
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) {
            granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Notification authorization request error: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                completion(granted)
            }
        }
    }

    // Check notification permission status
    func checkAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus)
            }
        }
    }

    // Register notification categories with actions
    func registerNotificationCategories() {
        notificationCenter.setNotificationCategories([])
    }

    // Cancel all notifications
    func cancelAllNotifications() {
        notificationCenter.removeAllPendingNotificationRequests()
    }

    // Remove all pending notifications
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Centralized Notification Management

    /// Handles notification settings changes
    func handleNotificationSettingsChange() {
        // No-op for now — can be extended for future notification types
    }

    /// Handles app becoming active - ensures notifications are properly scheduled
    func handleAppBecameActive() {
        // Only update if onboarding is completed
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasCompletedOnboarding {
            // No-op for now — can be extended for future notification types
        }
    }
}
