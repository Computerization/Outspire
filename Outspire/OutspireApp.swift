import OSLog
import SwiftUI
import Toasts
import UIKit
import UserNotifications

// Create an environment object to manage settings state globally
@MainActor
class SettingsManager: ObservableObject {
    @Published var showSettingsSheet = false
}

@main
struct OutspireApp: App {
    @StateObject private var regionChecker = RegionChecker.shared
    @StateObject private var notificationManager = NotificationManager.shared

    // Add settings manager
    @StateObject private var settingsManager = SettingsManager()

    // Add gradient manager
    @StateObject private var gradientManager = GradientManager()

    // Shared classtable view model
    @StateObject private var classtableViewModel = ClasstableViewModel()

    // Add connectivity manager
    @StateObject private var connectivityManager = ConnectivityManager.shared

    @UIApplicationDelegateAdaptor(OutspireAppDelegate.self) var appDelegate

    // Add URL scheme handler
    @StateObject private var urlSchemeHandler = URLSchemeHandler.shared

    // Add scene phase detection
    @Environment(\.scenePhase) private var scenePhase

    // Add NSUserActivity property to handle universal links
    @State private var userActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)

    init() {}

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .tint(AppColor.brand)
                .environmentObject(regionChecker)
                .environmentObject(notificationManager)
                .environmentObject(settingsManager) // Add settings manager
                .environmentObject(urlSchemeHandler) // Add URL scheme handler
                .environmentObject(gradientManager) // Add gradient manager to environment
                .environmentObject(classtableViewModel) // Shared classtable view model
                .environmentObject(connectivityManager) // Add connectivity manager
                .installToast(position: .top)
                .withConnectivityAlerts() // Add the connectivity alerts
                .onAppear {
                    // Setup URL Scheme Handler
                    URLSchemeHandler.shared.setAppReady()
                    // Start connectivity monitoring
                    connectivityManager.startMonitoring()
                    // Retry any failed push unregister from a previous session
                    PushRegistrationService.retryPendingUnregisterIfNeeded()
                    // Schedule automatic cache cleanup
                    CacheManager.scheduleAutomaticCleanup()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        // Check connectivity when app becomes active
                        connectivityManager.checkConnectivity()

                        // Handle notification scheduling when app becomes active
                        NotificationManager.shared.handleAppBecameActive()

                        // Proactively refresh TSIMS v2 session and restart keep-alive
                        AuthServiceV2.shared.onAppForegrounded()

                        // Sync auth state to widget
                        WidgetDataManager.updateAuthState(AuthServiceV2.shared.isAuthenticated)

                        // Retry push registration if it hasn't succeeded yet
                        ClassActivityManager.shared.retryRegistrationIfNeeded()
                    }
                }
                // Handle URLs when app is already running
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                // Handle universal links with userActivity
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    if let url = userActivity.webpageURL {
                        _ = urlSchemeHandler.handleUniversalLink(url)
                    }
                }
                // Error alert for URL handling failures
                .alert(
                    "Invalid URL",
                    isPresented: $urlSchemeHandler.showErrorAlert,
                    actions: {
                        Button("OK", role: .cancel) {}
                    },
                    message: {
                        Text(urlSchemeHandler.errorMessage)
                    }
                )
        }
        #if targetEnvironment(macCatalyst)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings") {
                    settingsManager.showSettingsSheet = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }

    // Handle incoming URL schemes
    private func handleIncomingURL(_ url: URL) {
        // Signal that sheets should be closed
        urlSchemeHandler.closeAllSheets = true

        // Always allow Today deep link without auth
        if url.host == "today" {
            _ = urlSchemeHandler.handleURL(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.urlSchemeHandler.closeAllSheets = false }
            return
        }

        // If already authenticated in either system, proceed immediately
        if AuthServiceV2.shared.isAuthenticated {
            _ = urlSchemeHandler.handleURL(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.urlSchemeHandler.closeAllSheets = false }
            return
        }

        // Otherwise, verify/reauth TSIMS v2 before deciding
        AuthServiceV2.shared.refreshSessionDetailed { result in
            switch result {
            case .valid, .reauthed:
                _ = self.urlSchemeHandler.handleURL(url)
            case .credentialsMissing:
                self.urlSchemeHandler.errorMessage = "You need to be signed in to access this feature"
                self.urlSchemeHandler.showErrorAlert = true
            case let .wrongCredentials(reason):
                self.urlSchemeHandler.errorMessage = reason
                self.urlSchemeHandler.showErrorAlert = true
            case let .serverUnavailable(reason):
                self.urlSchemeHandler.errorMessage = "Server unavailable: \(reason)"
                self.urlSchemeHandler.showErrorAlert = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.urlSchemeHandler.closeAllSheets = false }
        }
    }

    // Update the method to share club to include universal links
    private func shareClub(groupInfo: GroupInfo) {
        // Create both URLs for better sharing compatibility
        _ = "outspire://club/\(groupInfo.C_GroupsID)"
        let universalLinkString = "https://outspire.wrye.dev/app/club/\(groupInfo.C_GroupsID)"

        // Use the universal link for sharing, as it works for non-app users too
        guard let url = URL(string: universalLinkString) else { return }

        let activityViewController = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        // Present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController
        {
            // On iPad, set the popover presentation controller's source
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityViewController.popoverPresentationController?.sourceView =
                    rootViewController.view
                activityViewController.popoverPresentationController?.sourceRect = CGRect(
                    x: UIScreen.main.bounds.width / 2, y: UIScreen.main.bounds.height / 2, width: 0,
                    height: 0
                )
                activityViewController.popoverPresentationController?.permittedArrowDirections = []
            }
            rootViewController.present(activityViewController, animated: true)
        }
    }
}

class OutspireAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register notification categories for interactive notifications
        NotificationManager.shared.registerNotificationCategories()

        // Use centralized notification management if onboarding is completed
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if hasCompletedOnboarding {
            NotificationManager.shared.handleAppBecameActive()
        }

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {}

    // Handle URL scheme when app is launched from a URL
    func application(
        _ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return URLSchemeHandler.shared.handleURL(url)
    }
}

extension Notification.Name {
    static let authStateDidChange = Notification.Name("authStateDidChange")
    static let holidayModeDidChange = Notification.Name("holidayModeDidChange")
    static let authenticationStatusChanged = Notification.Name("authenticationStatusChanged")
    static let tsimsV2Unauthorized = Notification.Name("tsimsV2Unauthorized")
    static let tsimsV2ReauthFailed = Notification.Name("tsimsV2ReauthFailed")
}
