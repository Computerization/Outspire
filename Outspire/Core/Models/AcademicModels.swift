import Foundation

struct Year: Identifiable, Codable, Equatable {
    var id: String {
        W_YearID
    }

    let W_YearID: String
    let W_Year: String

    static func == (lhs: Year, rhs: Year) -> Bool {
        lhs.W_YearID == rhs.W_YearID
    }
}
