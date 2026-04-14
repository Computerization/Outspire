import Foundation

class DisclaimerManager {
    static let shared = DisclaimerManager()

    private init() {}

    // Keys for UserDefaults
    private let reflectionSuggestionDisclaimerKey = "hasShownReflectionSuggestionDisclaimer"
    private let recordSuggestionDisclaimerKey = "hasShownRecordSuggestionDisclaimer"

    /// Check if the suggestion disclaimer has been shown for reflections
    var hasShownReflectionSuggestionDisclaimer: Bool {
        UserDefaults.standard.bool(forKey: reflectionSuggestionDisclaimerKey)
    }

    /// Check if the suggestion disclaimer has been shown for activity records
    var hasShownRecordSuggestionDisclaimer: Bool {
        UserDefaults.standard.bool(forKey: recordSuggestionDisclaimerKey)
    }

    /// Mark the reflection suggestion disclaimer as shown
    func markReflectionSuggestionDisclaimerAsShown() {
        UserDefaults.standard.set(true, forKey: reflectionSuggestionDisclaimerKey)
    }

    /// Mark the record suggestion disclaimer as shown
    func markRecordSuggestionDisclaimerAsShown() {
        UserDefaults.standard.set(true, forKey: recordSuggestionDisclaimerKey)
    }

    /// Reset all disclaimer flags (for testing or account changes)
    func resetDisclaimers() {
        UserDefaults.standard.set(false, forKey: reflectionSuggestionDisclaimerKey)
        UserDefaults.standard.set(false, forKey: recordSuggestionDisclaimerKey)
    }
}

// MARK: - Disclaimer Text

extension DisclaimerManager {
    /// Get the full disclaimer text
    static var fullDisclaimerText: String {
        "IMPORTANT: Artificial Intelligence features are provided solely for entertainment purposes. The generated content should NOT be used for any form of academic work. The developer of this app takes no responsibility for any consequences, academic or otherwise, resulting from the use of generated content. Always review and verify all content before submission."
    }

    /// Get the short disclaimer text for post-suggestion reminders
    static var shortDisclaimerText: String {
        "AI-generated content is for recreational purposes only, not for academic work. Do not submit generated content."
    }
}
