import Foundation

enum Configuration {
    // For LLM Service
    // Go to Configuration.local.swift

    static var hideAcademicScore: Bool {
        get {
            UserDefaults.standard.bool(forKey: "hideAcademicScore")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "hideAcademicScore")
        }
    }

    static var showMondayClass: Bool {
        get {
            UserDefaults.standard.object(forKey: "showMondayClass") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showMondayClass")
        }
    }

    static var showSecondsInLongCountdown: Bool {
        get {
            UserDefaults.standard.object(forKey: "showSecondsInLongCountdown") as? Bool
                ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showSecondsInLongCountdown")
        }
    }

    static var showCountdownForFutureClasses: Bool {
        get {
            UserDefaults.standard.object(forKey: "showCountdownForFutureClasses") as? Bool
                ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "showCountdownForFutureClasses")
        }
    }

    static var selectedDayOverride: Int? {
        get {
            let value = UserDefaults.standard.integer(forKey: "selectedDayOverride")
            return value == -1 ? nil : value
        }
        set {
            UserDefaults.standard.set(newValue ?? -1, forKey: "selectedDayOverride")
        }
    }

    static var setAsToday: Bool {
        get {
            UserDefaults.standard.bool(forKey: "setAsToday")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "setAsToday")
        }
    }

    static var lastAppLaunchDate: Date? {
        get {
            UserDefaults.standard.object(forKey: "lastAppLaunchDate") as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastAppLaunchDate")
        }
    }

    /// Base URL for TSIMS v2 server
    static var tsimsV2BaseURL: String {
        "http://101.227.232.33:8001"
    }

    static var headers: [String: String] = [
        "Content-Type": "application/x-www-form-urlencoded"
    ]

    // MARK: - LLM configuration

    static var llmModel: String {
        "grok/grok-3-latest"
    }

    static var isHolidayMode: Bool {
        get {
            UserDefaults.standard.bool(forKey: "isHolidayMode")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "isHolidayMode")
            NotificationCenter.default.post(name: .holidayModeDidChange, object: nil)
            WidgetDataManager.updateHolidayMode(
                enabled: newValue,
                hasEndDate: Configuration.holidayHasEndDate,
                endDate: Configuration.holidayEndDate
            )
        }
    }

    static var holidayHasEndDate: Bool {
        get {
            UserDefaults.standard.bool(forKey: "holidayHasEndDate")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "holidayHasEndDate")
            NotificationCenter.default.post(name: .holidayModeDidChange, object: nil)
        }
    }

    static var holidayEndDate: Date {
        get {
            UserDefaults.standard.object(forKey: "holidayEndDate") as? Date
                ?? Date().addingTimeInterval(86400)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "holidayEndDate")
            NotificationCenter.default.post(name: .holidayModeDidChange, object: nil)
        }
    }

    // Debug: verbose network logging for TSIMS v2
    static var debugNetworkLogging: Bool {
        get {
            if UserDefaults.standard.object(forKey: "debugNetworkLogging") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "debugNetworkLogging")
        }
        set { UserDefaults.standard.set(newValue, forKey: "debugNetworkLogging") }
    }

    //// Add setting for AI suggestion disclaimer flags
    // static func resetAIDisclaimers() {
    //    DisclaimerManager.shared.resetDisclaimers()
    // }
}
