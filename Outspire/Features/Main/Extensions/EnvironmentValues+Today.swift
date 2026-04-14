import SwiftUI

/// Custom Environment Key for tracking setAsToday state
struct SetAsTodayKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var setAsToday: Binding<Bool> {
        get { self[SetAsTodayKey.self] }
        set { self[SetAsTodayKey.self] = newValue }
    }
}
