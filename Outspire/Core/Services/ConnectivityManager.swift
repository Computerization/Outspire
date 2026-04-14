import Foundation
import Network
import OSLog
import SwiftUI

@MainActor
class ConnectivityManager: ObservableObject {
    static let shared = ConnectivityManager()

    // Published properties
    @Published var isInternetAvailable = true
    @Published var isCheckingConnectivity = false

    // Alert control
    @Published var showNoInternetAlert = false

    // Onboarding awareness
    private var isOnboardingActive = false

    // Private state
    private var networkMonitor: NWPathMonitor?
    private var serverMonitor: Timer?

    // Configuration
    private let serverProbeURL = Configuration.tsimsV2BaseURL
    private let checkInterval: TimeInterval = 300 // 5 minutes
    private let timeoutInterval: TimeInterval = 5.0

    // State tracking
    private var serverAccessible = true

    private init() {
        isOnboardingActive = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    deinit {
        networkMonitor?.cancel()
        networkMonitor = nil
        serverMonitor?.invalidate()
        serverMonitor = nil
    }

    // MARK: - Onboarding Management

    func setOnboardingActive(_ active: Bool) {
        isOnboardingActive = active

        if active {
            showNoInternetAlert = false
        } else {
            startMonitoring()
        }
    }

    func isInOnboarding() -> Bool {
        return isOnboardingActive
    }

    // MARK: - Public Methods

    func startMonitoring() {
        setupNetworkMonitoring()
        scheduleServerChecks()
        checkConnectivity(forceCheck: true)
    }

    func stopMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
        serverMonitor?.invalidate()
        serverMonitor = nil
    }

    func checkConnectivity(forceCheck: Bool = false) {
        if isCheckingConnectivity, !forceCheck { return }

        isCheckingConnectivity = true

        checkServerAccess(urlString: serverProbeURL) { [weak self] isAccessible in
            guard let self else { return }
            self.serverAccessible = isAccessible

            if !isAccessible, self.isInternetAvailable, !self.isOnboardingActive {
                Log.net.warning("Internet available but can't reach TSIMS server")
            }

            self.isCheckingConnectivity = false
        }
    }

    // MARK: - Private Methods

    private func setupNetworkMonitoring() {
        guard networkMonitor == nil else { return }

        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isInternetAvailable = path.status == .satisfied

                if path.status == .satisfied {
                    self?.checkConnectivity()
                } else {
                    if let self = self, !self.isOnboardingActive {
                        self.showNoInternetAlert = true
                    }
                }
            }
        }

        let queue = DispatchQueue(label: "NetworkMonitoring")
        networkMonitor?.start(queue: queue)
    }

    private func scheduleServerChecks() {
        serverMonitor?.invalidate()

        serverMonitor = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.checkConnectivity() }
        }
    }

    private func checkServerAccess(urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            Log.net.error("Invalid URL: \(urlString, privacy: .public)")
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutInterval
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    Log.net
                        .error(
                            "Server check failed: \(urlString, privacy: .public), error: \(error.localizedDescription, privacy: .public)"
                        )
                    completion(false)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    Log.net.error("Invalid response from: \(urlString, privacy: .public)")
                    completion(false)
                    return
                }

                Log.net.debug("Server \(urlString, privacy: .public) responded with code: \(httpResponse.statusCode)")
                completion(true)
            }
        }

        task.resume()
    }
}
