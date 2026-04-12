import ActivityKit
import Foundation

// NOTE: This file must be kept in sync with OutspireWidget/Shared/ClassActivityAttributes.swift
// Both targets need the same ActivityAttributes definition.

struct ClassActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// All classes for the day, sorted by start time ascending.
        /// The LA UI derives current state from this array + current time.
        var classes: [ClassInfo]

        struct ClassInfo: Codable, Hashable {
            var name: String
            var room: String
            var start: Date
            var end: Date
        }
    }

    var startDate: Date
}
