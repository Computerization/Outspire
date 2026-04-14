import Foundation
import OSLog

/// Lightweight client for the new TSIMS server (ASP.NET MVC)
/// Uses shared URLSession and HTTPCookieStorage for auth cookies.
final class TSIMSClientV2 {
    static let shared = TSIMSClientV2()
    private init() {}

    private let timeout: TimeInterval = 15.0
    private var session: URLSession = .shared

    #if DEBUG
        func setSession(_ session: URLSession) { self.session = session }
    #endif

    // Shared headers for form POSTs
    private var formHeaders: [String: String] {
        [
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": Configuration.tsimsV2BaseURL,
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Safari",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7"
        ]
    }

    // MARK: - Debug helpers

    private func log(_ message: String) {
        if Configuration.debugNetworkLogging { Log.net.debug("[TSIMS] \(message, privacy: .public)") }
    }

    private func cookieSummary(for url: URL) -> String {
        guard let cookies = HTTPCookieStorage.shared.cookies(for: url) else { return "<none>" }
        let names = cookies.map { $0.name }
        return names.joined(separator: ", ")
    }

    // MARK: - Public

    // Low-level POST returning raw data for custom decoding
    func postFormRaw(
        path: String,
        form: [String: String],
        completion: @escaping (Result<Data, NetworkError>) -> Void
    ) {
        guard let url = URL(string: Configuration.tsimsV2BaseURL + path) else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.allHTTPHeaderFields = formHeaders
        request.setValue(Configuration.tsimsV2BaseURL + "/", forHTTPHeaderField: "Referer")

        let body = form.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        #if DEBUG
            let bodyPreview = form.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            log(
                "POST \(path) keys=\(Array(form.keys).sorted()) body=\(bodyPreview) cookies=[\(cookieSummary(for: url))]"
            )
        #else
            log("POST \(path) keys=\(Array(form.keys).sorted()) cookies=[\(cookieSummary(for: url))]")
        #endif

        func makeRequest(retried: Bool) {
            session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(.requestFailed(error))); return }
                    guard let http = response as? HTTPURLResponse else { completion(.failure(.noData)); return }
                    let contentType = (http.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
                    if http.statusCode == 302 || http.statusCode == 401 || contentType.contains("text/html") {
                        if !retried {
                            AuthServiceV2.shared.refreshSessionIfNeeded { ok in
                                if ok { makeRequest(retried: true) }
                                else {
                                    NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                                    completion(.failure(.unauthorized))
                                }
                            }
                        } else {
                            NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                            completion(.failure(.unauthorized))
                        }
                        return
                    }
                    guard http.statusCode < 400, let data = data, !data.isEmpty else {
                        completion(.failure(.noData)); return
                    }
                    self.log("RESP status=\(http.statusCode) contentType=\(contentType) bytes=\(data.count)")
                    completion(.success(data))
                }
            }.resume()
        }

        makeRequest(retried: false)
    }

    func postForm<T: Decodable>(
        path: String,
        form: [String: String],
        completion: @escaping (Result<ApiResponse<T>, NetworkError>) -> Void
    ) {
        guard let url = URL(string: Configuration.tsimsV2BaseURL + path) else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.allHTTPHeaderFields = formHeaders
        request.setValue(Configuration.tsimsV2BaseURL + "/", forHTTPHeaderField: "Referer")

        let body = form.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        log("POST \(path) headers=\(formHeaders.keys.sorted()) cookies=[\(cookieSummary(for: url))]")
        func makeRequest(retried: Bool) {
            session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(.requestFailed(error))); return }
                    guard let http = response as? HTTPURLResponse else { completion(.failure(.noData)); return }
                    let contentType = (http.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
                    if http.statusCode == 302 || http.statusCode == 401 || contentType.contains("text/html") {
                        self.log("RESP unauthorized status=\(http.statusCode) contentType=\(contentType)")
                        if !retried {
                            AuthServiceV2.shared.refreshSessionIfNeeded { ok in
                                if ok { makeRequest(retried: true) }
                                else {
                                    NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                                    completion(.failure(.unauthorized))
                                }
                            }
                        } else {
                            NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                            completion(.failure(.unauthorized))
                        }
                        return
                    }
                    guard http.statusCode < 400 else {
                        self.log("RESP serverError status=\(http.statusCode)")
                        completion(.failure(.serverError(http.statusCode)))
                        return
                    }
                    guard let data = data, !data.isEmpty else {
                        self.log("RESP noData")
                        completion(.failure(.noData))
                        return
                    }
                    do {
                        let decoded = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
                        self
                            .log(
                                "RESP ok decoded type=\(T.self) isSuccess=\(decoded.isSuccess) msg=\(decoded.message ?? "")"
                            )
                        completion(.success(decoded))
                    } catch {
                        let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<bin>"
                        self.log("RESP decodeError=\(error.localizedDescription) bodyPreview=\(preview)")
                        completion(.failure(.decodingError(error)))
                    }
                }
            }.resume()
        }
        makeRequest(retried: false)
    }

    func getJSON<T: Decodable>(
        path: String,
        query: [String: String]? = nil,
        completion: @escaping (Result<ApiResponse<T>, NetworkError>) -> Void
    ) {
        var urlString = Configuration.tsimsV2BaseURL + path
        if let query = query, !query.isEmpty {
            let qs = query.map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encoded)"
            }.joined(separator: "&")
            urlString += (urlString.contains("?") ? "&" : "?") + qs
        }
        guard let url = URL(string: urlString) else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Configuration.tsimsV2BaseURL + "/", forHTTPHeaderField: "Referer")
        request.setValue(Configuration.tsimsV2BaseURL, forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Safari",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7", forHTTPHeaderField: "Accept-Language")

        log("GET \(path) cookies=[\(cookieSummary(for: url))]")
        func makeRequest(retried: Bool) {
            session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(.requestFailed(error))); return }
                    guard let http = response as? HTTPURLResponse else { completion(.failure(.noData)); return }
                    let contentType = (http.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
                    if http.statusCode == 302 || http.statusCode == 401 || contentType.contains("text/html") {
                        self.log("RESP unauthorized status=\(http.statusCode) contentType=\(contentType)")
                        if !retried {
                            AuthServiceV2.shared.refreshSessionIfNeeded { ok in
                                if ok { makeRequest(retried: true) }
                                else {
                                    NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                                    completion(.failure(.unauthorized))
                                }
                            }
                        } else {
                            NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                            completion(.failure(.unauthorized))
                        }
                        return
                    }
                    guard http.statusCode < 400 else {
                        self.log("RESP serverError status=\(http.statusCode)")
                        completion(.failure(.serverError(http.statusCode)))
                        return
                    }
                    guard let data = data, !data.isEmpty else {
                        self.log("RESP noData")
                        completion(.failure(.noData))
                        return
                    }
                    do {
                        let decoded = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
                        self
                            .log(
                                "RESP ok decoded type=\(T.self) isSuccess=\(decoded.isSuccess) msg=\(decoded.message ?? "")"
                            )
                        completion(.success(decoded))
                    } catch {
                        let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<bin>"
                        self.log("RESP decodeError=\(error.localizedDescription) bodyPreview=\(preview)")
                        completion(.failure(.decodingError(error)))
                    }
                }
            }.resume()
        }
        makeRequest(retried: false)
    }

    /// GET a server-rendered HTML page (e.g. `/Stu/Cas/GroupDetail/{id}`).
    /// Unlike `getJSON`, `text/html` is the expected content-type here; we detect expired
    /// sessions by looking at the *final* URL after redirects — if URLSession landed us on
    /// `/Home/Login`, the session needs refreshing and we retry once.
    func getHTMLRaw(
        path: String,
        completion: @escaping (Result<String, NetworkError>) -> Void
    ) {
        guard let url = URL(string: Configuration.tsimsV2BaseURL + path) else {
            completion(.failure(.invalidURL))
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue(Configuration.tsimsV2BaseURL + "/", forHTTPHeaderField: "Referer")
        request.setValue(Configuration.tsimsV2BaseURL, forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Safari",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7", forHTTPHeaderField: "Accept-Language")

        log("GET (html) \(path) cookies=[\(cookieSummary(for: url))]")
        func makeRequest(retried: Bool) {
            session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error { completion(.failure(.requestFailed(error))); return }
                    guard let http = response as? HTTPURLResponse else { completion(.failure(.noData)); return }
                    let finalPath = (http.url?.path ?? "").lowercased()
                    let landedOnLogin = finalPath.contains("/home/login") || finalPath.hasSuffix("/home/index")
                    if http.statusCode == 302 || http.statusCode == 401 || landedOnLogin {
                        self.log("RESP unauthorized status=\(http.statusCode) finalPath=\(finalPath)")
                        if !retried {
                            AuthServiceV2.shared.refreshSessionIfNeeded { ok in
                                if ok { makeRequest(retried: true) }
                                else {
                                    NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                                    completion(.failure(.unauthorized))
                                }
                            }
                        } else {
                            NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                            completion(.failure(.unauthorized))
                        }
                        return
                    }
                    guard http.statusCode < 400 else {
                        self.log("RESP serverError status=\(http.statusCode)")
                        completion(.failure(.serverError(http.statusCode)))
                        return
                    }
                    guard let data = data, !data.isEmpty else {
                        completion(.failure(.noData))
                        return
                    }
                    guard let html = String(data: data, encoding: .utf8) else {
                        completion(.failure(.noData))
                        return
                    }
                    self.log("RESP ok html bytes=\(data.count)")
                    completion(.success(html))
                }
            }.resume()
        }
        makeRequest(retried: false)
    }

    // MARK: - Internal

    private func handleResponse<T: Decodable>(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (Result<ApiResponse<T>, NetworkError>) -> Void
    ) {
        DispatchQueue.main.async {
            if let error = error {
                completion(.failure(.requestFailed(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.noData))
                return
            }
            // Some endpoints redirect to login when unauthorized; also detect HTML content-type
            let contentType = (http.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
            if http.statusCode == 302 || http.statusCode == 401 || contentType.contains("text/html") {
                self.log("RESP unauthorized status=\(http.statusCode) contentType=\(contentType)")
                NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
                completion(.failure(.unauthorized))
                return
            }
            guard http.statusCode < 400 else {
                self.log("RESP serverError status=\(http.statusCode)")
                completion(.failure(.serverError(http.statusCode)))
                return
            }
            guard let data = data, !data.isEmpty else {
                self.log("RESP noData")
                completion(.failure(.noData))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
                self.log("RESP ok decoded type=\(T.self) isSuccess=\(decoded.isSuccess) msg=\(decoded.message ?? "")")
                completion(.success(decoded))
            } catch {
                let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<bin>"
                self.log("RESP decodeError=\(error.localizedDescription) bodyPreview=\(preview)")
                completion(.failure(.decodingError(error)))
            }
        }
    }

    // MARK: - Async variants (non-breaking additions)

    @available(iOS 15.0, macOS 12.0, *)
    func postFormAsync<T: Decodable>(path: String, form: [String: String]) async throws -> ApiResponse<T> {
        guard let url = URL(string: Configuration.tsimsV2BaseURL + path) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.allHTTPHeaderFields = formHeaders
        request.setValue(Configuration.tsimsV2BaseURL + "/", forHTTPHeaderField: "Referer")
        let body = form.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
        log("POST (async) \(path) headers=\(formHeaders.keys.sorted()) cookies=[\(cookieSummary(for: url))]")

        do {
            let (data, response) = try await session.data(for: request)
            return try handleResponseAsync(data: data, response: response)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    func getJSONAsync<T: Decodable>(path: String, query: [String: String]? = nil) async throws -> ApiResponse<T> {
        var urlString = Configuration.tsimsV2BaseURL + path
        if let query = query, !query.isEmpty {
            let qs = query.map { key, value in
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(encoded)"
            }.joined(separator: "&")
            urlString += (urlString.contains("?") ? "&" : "?") + qs
        }
        guard let url = URL(string: urlString) else { throw NetworkError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = true
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Configuration.tsimsV2BaseURL + "/", forHTTPHeaderField: "Referer")
        request.setValue(Configuration.tsimsV2BaseURL, forHTTPHeaderField: "Origin")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile Safari",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("zh-CN,zh;q=0.9,en;q=0.8,ja;q=0.7", forHTTPHeaderField: "Accept-Language")

        log("GET (async) \(path) cookies=[\(cookieSummary(for: url))]")
        do {
            let (data, response) = try await session.data(for: request)
            return try handleResponseAsync(data: data, response: response)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(error)
        }
    }

    @available(iOS 15.0, macOS 12.0, *)
    private func handleResponseAsync<T: Decodable>(data: Data, response: URLResponse) throws -> ApiResponse<T> {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.noData }
        let contentType = (http.allHeaderFields["Content-Type"] as? String)?.lowercased() ?? ""
        if http.statusCode == 302 || http.statusCode == 401 || contentType.contains("text/html") {
            self.log("RESP unauthorized status=\(http.statusCode) contentType=\(contentType)")
            NotificationCenter.default.post(name: .tsimsV2Unauthorized, object: nil)
            throw NetworkError.unauthorized
        }
        guard http.statusCode < 400 else {
            self.log("RESP serverError status=\(http.statusCode)")
            throw NetworkError.serverError(http.statusCode)
        }
        do {
            let decoded = try JSONDecoder().decode(ApiResponse<T>.self, from: data)
            self.log("RESP ok decoded type=\(T.self) isSuccess=\(decoded.isSuccess) msg=\(decoded.message ?? "")")
            return decoded
        } catch {
            let preview = String(data: data, encoding: .utf8)?.prefix(200) ?? "<bin>"
            self.log("RESP decodeError=\(error.localizedDescription) bodyPreview=\(preview)")
            throw NetworkError.decodingError(error)
        }
    }
}
