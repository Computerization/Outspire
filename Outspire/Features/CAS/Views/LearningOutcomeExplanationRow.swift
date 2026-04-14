import SwiftUI

struct LearningOutcomeExplanationRow: View {
    let icon: String
    let title: String
    let explanation: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(explanation)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Preview
struct LearningOutcomeExplanationRow_Previews: PreviewProvider {
    static var previews: some View {
        LearningOutcomeExplanationRow(
            icon: "brain.head.profile",
            title: "Awareness",
            explanation: "Increase your awareness of your strengths and areas for growth"
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
