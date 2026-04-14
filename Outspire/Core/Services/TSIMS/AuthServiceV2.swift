import Foundation
import SwiftSoup

/// Authentication service for the new TSIMS server.
/// Provides cookie-backed login/logout and stores minimal user info in-memory.
@MainActor
final class AuthServiceV2: ObservableObject {
    static let shared = AuthServiceV2()
    private static let installMarkerKey = "app.installation.id"
    private static let keychainInstallMarkerKey = "app.installation.id.keychain"
    private static let usernameKey = "v2.username"
    private static let passwordKey = "v2.password"

    private init() {
        Self.resetKeychainIfFreshInstall()

        // Restore saved user and check session on launch
        let hasSavedUser: Bool
        if let data = UserDefaults.standard.data(forKey: "v2User"),
           let saved = try? JSONDecoder().decode(V2User.self, from: data)
        {
            self.user = saved
            hasSavedUser = true
        } else {
            hasSavedUser = false
        }

        // If we have a saved user + stored credentials, optimistically mark as
        // authenticated so the UI can show cached content immediately instead of
        // flashing the sign-in prompt while the network request completes.
        let hasCredentials = SecureStore.get(keyUsername) != nil
            && SecureStore.get(keyPassword) != nil
        if hasSavedUser, hasCredentials {
            self.isAuthenticated = true
            self.isResolvingSession = false
        }

        // Verify existing cookies/session in the background
        verifySession { ok in
            DispatchQueue.main.async {
                if ok {
                    self.isAuthenticated = true
                    self.startKeepAlive()
                } else {
                    // Session expired — try reauth before giving up
                    self.attemptReauthIfPossible()
                }
                self.isResolvingSession = false
            }
        }

        // Listen for server-side unauthorized events
        NotificationCenter.default
            .addObserver(forName: .tsimsV2Unauthorized, object: nil, queue: .main) { [weak self] _ in
                self?.attemptReauthIfPossible()
            }
    }

    @Published var user: V2User?
    @Published var isAuthenticated: Bool = false
    @Published private(set) var isResolvingSession: Bool = true

    private var keepAliveTimer: Timer?
    private var reauthInProgress = false

    // Keys for credential storage
    private let keyUsername = "v2.username"
    private let keyPassword = "v2.password"

    // Public: Called when app becomes active to proactively refresh session
    func onAppForegrounded(completion: ((Bool) -> Void)? = nil) {
        refreshSessionIfNeeded { ok in
            if ok { self.startKeepAlive() }
            completion?(ok)
        }
    }

    // Classification for detailed refresh outcomes
    enum RefreshResult {
        case valid
        case reauthed
        case credentialsMissing
        case wrongCredentials(reason: String)
        case serverUnavailable(reason: String)
    }

    func login(code: String, password: String, completion: @escaping (Bool, String?) -> Void) {
        // Step 1: Seed ASP.NET session by visiting the login page (sets .AspNetCore.Session)
        guard let loginURL = URL(string: Configuration.tsimsV2BaseURL + "/Home/Login?ReturnUrl=%2F") else {
            completion(false, "Invalid login URL")
            return
        }
        var seedReq = URLRequest(url: loginURL)
        seedReq.httpMethod = "GET"
        seedReq.httpShouldHandleCookies = true
        URLSession.shared.dataTask(with: seedReq) { _, _, _ in
            if Configuration.debugNetworkLogging {
                if let url = seedReq.url, let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                    print("[AuthV2] Seed cookies: \(cookies.map { $0.name }.joined(separator: ", "))")
                }
            }
            // Step 2: POST credentials
            let form = [
                "code": code,
                "password": password
            ]
            TSIMSClientV2.shared.postForm(path: "/Home/Login", form: form) { (result: Result<
                ApiResponse<V2User>,
                NetworkError
            >) in
                switch result {
                case let .success(envelope):
                    if Configuration
                        .debugNetworkLogging
                    {
                        print("[AuthV2] Login result isSuccess=\(envelope.isSuccess) msg=\(envelope.message ?? "")")
                    }
                    if envelope.isSuccess {
                        // Some deployments omit user data; try to fill from profile
                        if let user = envelope.data {
                            self.user = user
                        }
                        // Step 3: verify session via GetMenu (JSON requires auth)
                        self.verifySession { ok in
                            if Configuration.debugNetworkLogging { print("[AuthV2] verifySession=\(ok)") }
                            if ok {
                                self.isAuthenticated = true
                                // Persist credentials for auto re-login
                                SecureStore.set(code, for: self.keyUsername)
                                SecureStore.set(password, for: self.keyPassword)
                                self.fetchProfile { _ in completion(true, nil) }
                                self.startKeepAlive()
                            } else {
                                completion(false, "Login session not established")
                            }
                        }
                    } else {
                        completion(false, envelope.message ?? "Login failed")
                    }
                case let .failure(error):
                    if Configuration.debugNetworkLogging { print("[AuthV2] Login error=\(error.localizedDescription)") }
                    completion(false, error.localizedDescription)
                }
            }
        }.resume()
    }

    func logout(completion: @escaping (Bool) -> Void) {
        TSIMSClientV2.shared.postForm(path: "/Home/logout", form: [:]) { (result: Result<
            ApiResponse<String>,
            NetworkError
        >) in
            // Regardless of server response, clear local state when we can reach the server
            switch result {
            case .success:
                self.clearSession()
                completion(true)
            case .failure:
                // Still clear local cookies/session to avoid stale state
                self.clearSession()
                completion(false)
            }
        }
    }

    private func clearSession() {
        user = nil
        isAuthenticated = false
        stopKeepAlive()
        // Clear cookies to fully sign out
        if let cookies = HTTPCookieStorage.shared.cookies {
            for c in cookies {
                HTTPCookieStorage.shared.deleteCookie(c)
            }
        }
        URLSession.shared.reset {}
        URLCache.shared.removeAllCachedResponses()
        // Clear v2 persisted state and credentials to avoid auto re-auth with previous account
        UserDefaults.standard.removeObject(forKey: "v2User")
        SecureStore.remove(keyUsername)
        SecureStore.remove(keyPassword)

        // Clear all app caches to avoid data leaking between accounts
        CacheManager.clearAllCache()

        // Stop Live Activity and unregister from push worker
        ClassActivityManager.shared.endAllActivities()
        PushRegistrationService.unregister()
    }

    // Fetch profile HTML and parse basic info if missing from login response
    private func fetchProfile(completion: @escaping (Bool) -> Void) {
        // Try an HTML page that contains student info
        guard let url = URL(string: Configuration.tsimsV2BaseURL + "/Home/StudentInfo")
        else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.httpShouldHandleCookies = true
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard error == nil, let data = data,
                  let html = String(data: data, encoding: .utf8)
            else { DispatchQueue.main.async { completion(false) }; return }
            // Parse using SwiftSoup to be resilient
            var name: String? = nil
            var code: String? = nil
            do {
                let doc = try SwiftSoup.parse(html)
                // Try common label/value patterns in forms or tables
                // Look for inputs with name attributes
                if let input = try doc.select("input[name=UserCode]").first() {
                    code = try input.val()
                }
                // Try to extract numeric user id (id/UserId/StudentId)
                if let idVal = try doc.select("input[name=id], input[name=UserId], input[name=StudentId]").first()?
                    .val(), let uid = Int(idVal)
                {
                    if self.user == nil {
                        self.user = V2User(userId: uid, userCode: code, name: nil, role: nil)
                    } else {
                        self.user = V2User(
                            userId: uid,
                            userCode: self.user?.userCode ?? code,
                            name: self.user?.name,
                            role: self.user?.role
                        )
                    }
                }
                if code == nil, let tds = try? doc.select("td, th") {
                    for td in tds.array() {
                        let text = (try? td.text()) ?? ""
                        if text.contains("学号") || text.localizedCaseInsensitiveContains("UserCode") {
                            if let sibling = try? td.nextElementSibling()?.text(), !sibling.isEmpty { code = sibling }
                        }
                        if text.contains("姓名") || text.localizedCaseInsensitiveContains("Name") {
                            if let sibling = try? td.nextElementSibling()?.text(), !sibling.isEmpty { name = sibling }
                        }
                    }
                }
                // Try FirstName/LastName inputs
                if name == nil {
                    let first = try? doc.select("input[name=FirstName]").first()?.val()
                    let last = try? doc.select("input[name=LastName]").first()?.val()
                    let combined = [first ?? "", last ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if !combined.isEmpty { name = combined }
                }
            } catch {
                // fallback ignored
            }
            DispatchQueue.main.async {
                if Configuration
                    .debugNetworkLogging
                {
                    print("[AuthV2] Parsed profile name=\(name ?? "<nil>") code=\(code ?? "<nil>")")
                }
                if self.user == nil { self.user = V2User(userId: nil, userCode: code, name: name, role: nil) }
                else {
                    self.user = V2User(
                        userId: self.user?.userId,
                        userCode: self.user?.userCode ?? code,
                        name: self.user?.name ?? name,
                        role: self.user?.role
                    )
                }
                // Persist user for next launch
                if let u = self.user, let encoded = try? JSONEncoder().encode(u) {
                    UserDefaults.standard.set(encoded, forKey: "v2User")
                }
                completion(true)
            }
        }.resume()
    }

    private func verifySession(completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: Configuration.tsimsV2BaseURL + "/Home/GetMenu") else { completion(false); return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.httpShouldHandleCookies = true
        req.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200 && (data?.count ?? 0) > 0
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }

    // MARK: - Keep-alive to extend cookie lifetime (~30m reported)

    private func startKeepAlive() {
        stopKeepAlive()
        // Ping every 20 minutes to refresh session before 30-minute expiry
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 20 * 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.verifySession { ok in
                if !ok {
                    self.attemptReauthIfPossible()
                }
            }
        }
        if let t = keepAliveTimer { RunLoop.main.add(t, forMode: .common) }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }

    // MARK: - Auto Re-auth

    private func attemptReauthIfPossible() {
        guard !reauthInProgress else { return }
        guard let code = SecureStore.get(keyUsername), let pwd = SecureStore.get(keyPassword), !code.isEmpty,
              !pwd.isEmpty
        else {
            // No saved credentials; mark unauthenticated
            DispatchQueue.main.async { self.isAuthenticated = false }
            NotificationCenter.default.post(
                name: .tsimsV2ReauthFailed,
                object: nil,
                userInfo: ["reason": "Credentials missing"]
            )
            return
        }
        reauthInProgress = true
        login(code: code, password: pwd) { ok, message in
            DispatchQueue.main.async {
                self.reauthInProgress = false
                if ok {
                    self.isAuthenticated = true
                    self.startKeepAlive()
                } else {
                    self.isAuthenticated = false
                    let reason = message ?? "Re-login failed"
                    NotificationCenter.default.post(
                        name: .tsimsV2ReauthFailed,
                        object: nil,
                        userInfo: ["reason": reason]
                    )
                }
            }
        }
    }

    // Public: Ensure we have a valid session; will try reauth once if needed
    func refreshSessionIfNeeded(completion: @escaping (Bool) -> Void) {
        verifySession { ok in
            if ok {
                DispatchQueue.main.async {
                    self.isAuthenticated = true
                    completion(true)
                }
                return
            }
            // Attempt reauth using stored credentials
            guard let code = SecureStore.get(self.keyUsername), let pwd = SecureStore.get(self.keyPassword),
                  !code.isEmpty, !pwd.isEmpty
            else {
                DispatchQueue.main.async {
                    self.isAuthenticated = false
                    NotificationCenter.default.post(
                        name: .tsimsV2ReauthFailed,
                        object: nil,
                        userInfo: ["reason": "Credentials missing"]
                    )
                    completion(false)
                }
                return
            }
            self.login(code: code, password: pwd) { ok, _ in
                DispatchQueue.main.async {
                    self.isAuthenticated = ok
                    completion(ok)
                }
            }
        }
    }

    // Public: Ensure we have a valid session with reasoned outcome (for deep links/UI decisions)
    func refreshSessionDetailed(completion: @escaping (RefreshResult) -> Void) {
        verifySession { ok in
            if ok {
                DispatchQueue.main.async { completion(.valid) }
                return
            }
            guard let code = SecureStore.get(self.keyUsername), let pwd = SecureStore.get(self.keyPassword),
                  !code.isEmpty, !pwd.isEmpty
            else {
                DispatchQueue.main.async { completion(.credentialsMissing) }
                return
            }

            // Try login directly to capture wrong-credentials vs server errors
            TSIMSClientV2.shared.postForm(path: "/Home/Login", form: [
                "code": code,
                "password": pwd
            ]) { (result: Result<ApiResponse<V2User>, NetworkError>) in
                switch result {
                case let .success(envelope):
                    if envelope.isSuccess {
                        // Verify JSON endpoint after login to ensure cookies are set
                        self.verifySession { ok2 in
                            DispatchQueue.main.async {
                                if ok2 {
                                    self.isAuthenticated = true
                                    self.startKeepAlive()
                                    completion(.reauthed)
                                } else {
                                    self.isAuthenticated = false
                                    completion(.serverUnavailable(reason: "Session could not be verified after login"))
                                }
                            }
                        }
                    } else {
                        let reason = envelope.message ?? "Invalid username or password"
                        DispatchQueue.main.async {
                            self.isAuthenticated = false
                            completion(.wrongCredentials(reason: reason))
                        }
                    }
                case let .failure(error):
                    DispatchQueue.main.async {
                        self.isAuthenticated = false
                        completion(.serverUnavailable(reason: error.localizedDescription))
                    }
                }
            }
        }
    }

    // Public helper to refresh profile (to resolve userId after login)
    func ensureProfile(completion: @escaping (Bool) -> Void) {
        fetchProfile { ok in
            completion(ok)
        }
    }

    private static func resetKeychainIfFreshInstall() {
        let defaults = UserDefaults.standard
        let defaultsMarker = defaults.string(forKey: installMarkerKey)
        let keychainMarker = SecureStore.get(keychainInstallMarkerKey)

        switch (defaultsMarker, keychainMarker) {
        case let (.some(defaultsMarker), .some(keychainMarker)):
            if defaultsMarker != keychainMarker {
                SecureStore.set(defaultsMarker, for: keychainInstallMarkerKey)
            }

        case let (.some(defaultsMarker), .none):
            SecureStore.set(defaultsMarker, for: keychainInstallMarkerKey)

        case (.none, .some):
            SecureStore.remove(usernameKey)
            SecureStore.remove(passwordKey)
            let newMarker = UUID().uuidString
            defaults.set(newMarker, forKey: installMarkerKey)
            SecureStore.set(newMarker, for: keychainInstallMarkerKey)

        case (.none, .none):
            // Legacy upgrade or first-ever install: initialize markers without logging out.
            let newMarker = UUID().uuidString
            defaults.set(newMarker, forKey: installMarkerKey)
            SecureStore.set(newMarker, for: keychainInstallMarkerKey)
        }
    }
}
