import UserNotifications
import XCTest

@testable import Outspire

class NotificationManagerTests: XCTestCase {
    var notificationManager: NotificationManager!

    override func setUp() {
        super.setUp()
        notificationManager = NotificationManager.shared
    }

    override func tearDown() {
        super.tearDown()
    }

    @MainActor
    func testCentralizedNotificationManagement() {
        // Test the centralized notification management methods
        let expectation = XCTestExpectation(
            description: "Centralized management should work correctly")

        // Test settings change
        notificationManager.handleNotificationSettingsChange()

        // Test app became active
        notificationManager.handleAppBecameActive()

        // If we get here without crashing, the methods work
        expectation.fulfill()

        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Additional Unit Tests (SecureStore)

private class MockURLProtocol: URLProtocol {
    static var responseData: Data?
    static var statusCode: Int = 200
    static var responseHeaders: [String: String]? = ["Content-Type": "application/json"]
    static var error: Error?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let url = request.url ?? URL(string: "https://example.com")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: MockURLProtocol.statusCode,
            httpVersion: nil,
            headerFields: MockURLProtocol.responseHeaders
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let data = MockURLProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct TestDecodable: Codable, Equatable { let message: String }

extension NotificationManagerTests {
    func testSecureStore_set_get_remove() {
        let key = "test.keychain.key"
        let value = "secret-value"

        SecureStore.set(value, for: key)
        let fetched = SecureStore.get(key)
        XCTAssertEqual(fetched, value)

        SecureStore.remove(key)
        let removed = SecureStore.get(key)
        XCTAssertNil(removed)
    }
}
