import Foundation

struct LunchMenuItem: Identifiable, Equatable {
    let id: String
    let title: String
    let publishDate: String
    let url: String
    var isExpanded: Bool = false

    static func == (lhs: LunchMenuItem, rhs: LunchMenuItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct LunchMenuDetail: Identifiable, Equatable {
    let id: String
    let title: String
    let publishDate: String
    let imageUrls: [String]
    let content: String

    static func == (lhs: LunchMenuDetail, rhs: LunchMenuDetail) -> Bool {
        lhs.id == rhs.id
    }
}

struct LunchMenuGroup: Identifiable {
    let id: String
    let title: String
    var items: [LunchMenuItem]
    var isExpanded: Bool = true
}
