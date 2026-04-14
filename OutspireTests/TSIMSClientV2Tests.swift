@testable import Outspire
import XCTest

private class TSIMSMockURLProtocol: URLProtocol {
    static var responseData: Data?
    static var statusCode: Int = 200
    static var responseHeaders: [String: String]? = ["Content-Type": "application/json"]
    static var error: Error?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        if let error = TSIMSMockURLProtocol.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: TSIMSMockURLProtocol.statusCode,
            httpVersion: nil,
            headerFields: TSIMSMockURLProtocol.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = TSIMSMockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class TSIMSClientV2Tests: XCTestCase {
    struct TestData: Codable, Equatable { let value: String; enum CodingKeys: String, CodingKey { case value = "Foo" } }

    @MainActor
    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TSIMSMockURLProtocol.self]
        let session = URLSession(configuration: config)
        #if DEBUG
            TSIMSClientV2.shared.setSession(session)
        #endif
    }

    @MainActor
    func test_getJSONAsync_success() async throws {
        guard #available(iOS 15.0, *) else { return }
        let payload = ["ResultType": 0, "Message": "ok", "Data": ["Foo": "bar"]] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        TSIMSMockURLProtocol.responseData = data
        TSIMSMockURLProtocol.statusCode = 200
        TSIMSMockURLProtocol.responseHeaders = ["Content-Type": "application/json"]
        TSIMSMockURLProtocol.error = nil

        let resp: ApiResponse<TestData> = try await TSIMSClientV2.shared.getJSONAsync(path: "/test")
        XCTAssertTrue(resp.isSuccess)
        XCTAssertEqual(resp.data?.value, "bar")
    }

    @MainActor
    func test_getJSONAsync_unauthorized_status() async {
        guard #available(iOS 15.0, *) else { return }
        TSIMSMockURLProtocol.responseData = Data("Unauthorized".utf8)
        TSIMSMockURLProtocol.statusCode = 401
        TSIMSMockURLProtocol.responseHeaders = ["Content-Type": "text/plain"]
        TSIMSMockURLProtocol.error = nil

        do {
            let _: ApiResponse<TestData> = try await TSIMSClientV2.shared.getJSONAsync(path: "/test")
            XCTFail("Expected NetworkError.unauthorized")
        } catch {
            guard case NetworkError.unauthorized = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    @MainActor
    func test_getJSONAsync_unauthorized_html() async {
        guard #available(iOS 15.0, *) else { return }
        // 200 OK but HTML content should be treated as unauthorized according to client logic
        TSIMSMockURLProtocol.responseData = Data("<html>login</html>".utf8)
        TSIMSMockURLProtocol.statusCode = 200
        TSIMSMockURLProtocol.responseHeaders = ["Content-Type": "text/html; charset=utf-8"]
        TSIMSMockURLProtocol.error = nil

        do {
            let _: ApiResponse<TestData> = try await TSIMSClientV2.shared.getJSONAsync(path: "/test")
            XCTFail("Expected NetworkError.unauthorized due to HTML content-type")
        } catch {
            guard case NetworkError.unauthorized = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
