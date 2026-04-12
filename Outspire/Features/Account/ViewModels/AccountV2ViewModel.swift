import Combine
import SwiftUI

@MainActor
class AccountV2ViewModel: ObservableObject {
    @Published var code: String = ""
    @Published var password: String = ""
    @Published var isLoggingIn: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?

    @Published var isAuthenticated: Bool = false
    @Published var user: V2User?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Observe AuthServiceV2 state
        AuthServiceV2.shared.$isAuthenticated
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAuthenticated)

        AuthServiceV2.shared.$user
            .receive(on: DispatchQueue.main)
            .assign(to: &$user)

        // Prefill last used code
        if let saved = UserDefaults.standard.string(forKey: "v2LastCode"), !saved.isEmpty {
            self.code = saved
        }
    }

    func login() {
        guard !code.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter code and password"
            return
        }
        isLoggingIn = true
        errorMessage = nil
        successMessage = nil

        AuthServiceV2.shared.login(code: code, password: password) { [weak self] success, message in
            guard let self = self else { return }
            self.isLoggingIn = false
            if success {
                // Persist last used code for convenience
                UserDefaults.standard.set(self.code, forKey: "v2LastCode")
                self.code = ""
                self.password = ""
                self.successMessage = "Signed in successfully"
                NotificationCenter.default.post(
                    name: Notification.Name.authenticationStatusChanged,
                    object: nil,
                    userInfo: ["action": "signedin"]
                )
            } else {
                self.errorMessage = message ?? "Login failed"
            }
        }
    }

    func logout() {
        AuthServiceV2.shared.logout { _ in
            DispatchQueue.main.async {
                self.successMessage = "Signed out successfully"
                NotificationCenter.default.post(
                    name: Notification.Name.authenticationStatusChanged,
                    object: nil,
                    userInfo: ["action": "logout"]
                )
            }
        }
    }
}
