import SwiftUI

struct ErrorView: View {
    let errorMessage: String
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.red.opacity(0.8))
                .padding(.bottom, 8)

            Text("Oops, Something Went Wrong")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let retryAction {
                Button(action: {
                    HapticManager.shared.playButtonTap()
                    retryAction()
                }) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ErrorView(errorMessage: "Something went wrong", retryAction: {})
}
