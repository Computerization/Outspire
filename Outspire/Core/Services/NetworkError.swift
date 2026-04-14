import Foundation

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError(Error)
    case requestFailed(Error)
    case serverError(Int)
    case unauthorized

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            "Invalid URL"
        case .noData:
            "No data received"
        case let .decodingError(error):
            "Failed to decode response: \(error.localizedDescription)"
        case let .requestFailed(error):
            "Request failed: \(error.localizedDescription)"
        case let .serverError(code):
            "Server error with code: \(code)"
        case .unauthorized:
            "Unauthorized access"
        }
    }
}
