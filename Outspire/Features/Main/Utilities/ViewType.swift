import Foundation

/// Enum defining the different view types in the app for navigation
enum ViewType: String, CaseIterable, Codable, Hashable {
    case today
    case classtable
    case score
    case clubInfo
    case clubActivities
    case clubReflections
    case schoolArrangements
    case lunchMenu
    case map
    case notSignedIn
    case weekend
    case holiday
    case help

    var displayName: String {
        switch self {
        case .today: "Today View"
        case .classtable: "Class Table"
        case .score: "Academic Grades"
        case .clubInfo: "Club Information"
        case .clubActivities: "Club Activities"
        case .clubReflections: "Club Reflections"
        case .schoolArrangements: "School Arrangements"
        case .lunchMenu: "Lunch Menu"
        case .map: "Campus Map"
        case .notSignedIn: "Not Signed In"
        case .weekend: "Weekend"
        case .holiday: "Holiday Mode"
        case .help: "Help"
        }
    }

    /// Helper to create a ViewType from navigation link
    static func fromLink(_ link: String) -> ViewType? {
        switch link {
        case "today": .today
        case "classtable": .classtable
        case "score": .score
        case "club-info": .clubInfo
        case "club-activity": .clubActivities
        case "club-reflection": .clubReflections
        case "school-arrangement": .schoolArrangements
        case "lunch-menu": .lunchMenu
        case "map": .map
        case "help": .help
        default: nil
        }
    }
}

/// Add an initializer to create from navigation link
extension ViewType {
    init?(fromLink link: String) {
        switch link {
        case "today": self = .today
        case "classtable": self = .classtable
        case "score": self = .score
        case "club-info": self = .clubInfo
        case "club-activity": self = .clubActivities
        case "club-reflection": self = .clubReflections
        case "school-arrangement": self = .schoolArrangements
        case "lunch-menu": self = .lunchMenu
        case "map": self = .map
        case "help": self = .help
        default: return nil
        }
    }
}
