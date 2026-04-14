import Foundation

// MARK: - ResultType decoding that supports both string and integer forms

enum ResultTypeValue: Decodable {
    case string(String)
    case int(Int)

    var isSuccess: Bool {
        switch self {
        case let .string(s):
            s == "0"
        case let .int(i):
            i == 0
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else {
            let s = try container.decode(String.self)
            self = .string(s)
        }
    }
}

// MARK: - Generic API envelope used by the new TSIMS server

struct ApiResponse<T: Decodable>: Decodable {
    let resultType: ResultTypeValue
    let message: String?
    let data: T?

    enum CodingKeys: String, CodingKey {
        case resultType = "ResultType"
        case message = "Message"
        case data = "Data"
    }

    var isSuccess: Bool {
        resultType.isSuccess
    }
}

// MARK: - Paged wrapper used by many list endpoints

struct Paged<T: Decodable>: Decodable {
    let totalCount: Int
    let list: [T]

    enum CodingKeys: String, CodingKey {
        case totalCount = "TotalCount"
        case list = "List"
    }
}
