import SwiftUI

enum CASType: String {
    case creativity = "C"
    case activity = "A"
    case service = "S"

    var color: Color {
        switch self {
        case .creativity: .red
        case .activity: .mint
        case .service: .indigo
        }
    }
}

struct CASBadge: View {
    let type: CASType
    let value: String

    var body: some View {
        Text("\(type.rawValue): \(value)")
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(value == "0.0" ? Color.gray : type.color)
            .clipShape(Capsule())
    }
}
