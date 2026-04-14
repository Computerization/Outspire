import Foundation
import SwiftUI

class AnimationManager {
    static let shared = AnimationManager()

    private init() {}

    /// Tracking app launch state
    private(set) var isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")

    /// Dictionary to track animation states for different views
    private var animatedViews = Set<String>()

    func markAppLaunched() {
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            isFirstLaunch = false
        }
    }

    func resetAnimationFlags() {
        // Reset for testing or when signing out
        isFirstLaunch = true
        animatedViews.removeAll()
        UserDefaults.standard.set(false, forKey: "hasLaunchedBefore")
    }

    /// Track if a specific view has been animated
    func hasAnimated(viewId: String) -> Bool {
        animatedViews.contains(viewId)
    }

    /// Mark a specific view as animated
    func markAnimated(viewId: String) {
        animatedViews.insert(viewId)
    }

    /// Force a view to animate again
    func resetAnimation(viewId: String) {
        animatedViews.remove(viewId)
    }
}

/// Extension to help determine device characteristics
extension UIDevice {
    static var isSmallScreen: Bool {
        let screenSize = UIScreen.main.bounds.size
        let smallerDimension = min(screenSize.width, screenSize.height)
        return smallerDimension <= 375 // iPhone SE, iPhone 8 and similar
    }

    static var isIpad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
}
