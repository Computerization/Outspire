import Foundation
import SwiftUI

/// Handles URL scheme navigation and universal links for deep linking in Outspire
@MainActor
class URLSchemeHandler: ObservableObject {
    static let shared = URLSchemeHandler()

    // Published properties to trigger navigation
    @Published var navigateToToday = false
    @Published var navigateToClassTable = false
    @Published var navigateToClub: String?
    @Published var navigateToAddActivity: String?

    /// Add a property to signal that sheets should be closed
    @Published var closeAllSheets = false

    // Error alert control
    @Published var showErrorAlert = false
    @Published var errorMessage = ""

    // Flag to track if app is ready for navigation
    private var isAppReady = false
    private var pendingNavigation: (() -> Void)?

    private init() {}

    /// Set the app ready state and process any pending navigation
    func setAppReady() {
        isAppReady = true
        if let pendingAction = pendingNavigation {
            DispatchQueue.main.async {
                pendingAction()
                self.pendingNavigation = nil
            }
        }
    }

    /// Handle universal links (applinks) from the web
    /// - Parameter url: The universal link URL to process
    /// - Returns: True if the URL was successfully handled
    func handleUniversalLink(_ url: URL) -> Bool {
        if Configuration.debugNetworkLogging {
            print("Processing Universal Link: \(url.absoluteString)")
        }

        // Verify it's our domain
        guard url.host == "outspire.wrye.dev" else { return false }

        // Extract the path after /app/
        guard url.path.starts(with: "/app/") else { return false }

        // Convert universal link path to URL scheme format
        let appPath = url.path.replacingOccurrences(of: "/app/", with: "")

        // Create equivalent scheme URL and handle with existing logic
        if let schemeURL = URL(string: "outspire://\(appPath)") {
            print("Converted to scheme URL: \(schemeURL.absoluteString)")
            return handleURL(schemeURL)
        }

        return false
    }

    /// Process an incoming URL to determine navigation path
    /// - Parameter url: The URL to process
    /// - Returns: True if the URL was successfully handled
    func handleURL(_ url: URL) -> Bool {
        if Configuration.debugNetworkLogging {
            print("Processing URL: \(url.absoluteString)")
        }

        // First check for HTTPS URLs and redirect them to handleUniversalLink
        if url.scheme == "https" {
            return handleUniversalLink(url)
        }

        guard url.scheme == "outspire" else { return false }

        // Create a navigation action to execute immediately or queue
        let navigationAction = { [weak self] in
            guard let self else { return }

            // Signal that sheets should be closed when handling a URL
            self.closeAllSheets = true

            // Reset any previous navigation states except the current URL we're processing
            self.resetNavigationStatesExceptCurrent()

            // Get the path components after the host
            let host = url.host ?? ""
            let pathComponents = url.pathComponents.filter { $0 != "/" }

            if Configuration.debugNetworkLogging {
                print("Navigating to host: \(host), path components: \(pathComponents)")
            }

            // Reset closeAllSheets after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.closeAllSheets = false
            }

            switch host {
            case "today":
                self.navigateToToday = true

            case "classtable":
                self.navigateToClassTable = true

            case "club":
                if pathComponents.count >= 1 {
                    let clubId = pathComponents[0]
                    if Configuration.debugNetworkLogging {
                        print("URL Handler found club ID: \(clubId)")
                    }

                    // If we're already navigating to the same club, don't reset
                    if self.navigateToClub != clubId {
                        // Remove any previous club ID first to ensure the change is detected
                        self.navigateToClub = nil

                        // Use a slight delay to ensure the nil change is processed first
                        DispatchQueue.main.async {
                            self.navigateToClub = clubId
                        }
                    }
                } else {
                    self.showError("Invalid club URL: missing club ID")
                }

            case "addactivity":
                if pathComponents.count >= 1 {
                    let clubId = pathComponents[0]
                    self.navigateToAddActivity = clubId
                } else {
                    self.showError("Invalid activity URL: missing club ID")
                }

            default:
                self.showError("Unsupported URL path: \(host)")
                return
            }
        }

        // Either execute the navigation now or queue it for later
        if isAppReady {
            navigationAction()
        } else {
            pendingNavigation = navigationAction
            // Initialize app ready state for immediate navigation
            // This ensures navigation works even if setAppReady() hasn't been called yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.isAppReady = true
                if let pendingAction = self.pendingNavigation {
                    pendingAction()
                    self.pendingNavigation = nil
                }
            }
        }

        return true
    }

    /// Handle user activity from universal links
    /// - Parameter userActivity: The user activity to process
    /// - Returns: True if the activity was handled successfully
    func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL
        else {
            return false
        }

        print("Handling user activity with URL: \(url.absoluteString)")
        return handleUniversalLink(url)
    }

    /// Reset all navigation state triggers
    private func resetNavigationStates() {
        navigateToToday = false
        navigateToClassTable = false
        navigateToClub = nil
        navigateToAddActivity = nil
    }

    /// Reset navigation states except for the current URL being processed
    private func resetNavigationStatesExceptCurrent() {
        navigateToToday = false
        navigateToClassTable = false
        // We don't reset navigateToClub here because it will be set correctly in the case statements
        navigateToAddActivity = nil
    }

    /// Show an error alert with the given message
    /// - Parameter message: Error message to display
    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }
}

/// Extension to handle URL validation
extension URLSchemeHandler {
    /// Creates a valid deep link URL for the app
    /// - Parameters:
    ///   - path: The path component (e.g., "today", "club/123")
    ///   - queryItems: Optional query parameters
    /// - Returns: A formatted URL or nil if invalid
    static func createDeepLink(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "outspire"

        // Split path into host and path components
        let pathParts = path.split(separator: "/", maxSplits: 1)
        if pathParts.isEmpty { return nil }

        components.host = String(pathParts[0])

        if pathParts.count > 1 {
            components.path = "/\(pathParts[1])"
        }

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url
    }

    /// Creates a valid universal link URL for sharing
    /// - Parameters:
    ///   - path: The path component (e.g., "today", "club/123")
    ///   - queryItems: Optional query parameters
    /// - Returns: A formatted URL or nil if invalid
    static func createUniversalLink(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "outspire.wrye.dev"
        components.path = "/app/\(path)"

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        return components.url
    }
}
