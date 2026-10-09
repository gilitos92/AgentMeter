import XCTest
@testable import AgentMeter

private final class RotatingMockOAuthServer {
    private let lock = NSLock()
    private var currentRefreshToken = "R0"
    private var currentAccessToken = "A0"
    private var refreshCount = 0
    private var requests: [String] = []

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentRefreshToken = "R0"
        currentAccessToken = "A0"
        refreshCount = 0
        requests = []
    }

    func requestLog() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func successfulRefreshCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return refreshCount
    }

    func respond(to request: URLRequest) -> (Int, Data) {
        lock.lock()
        defer { lock.unlock() }

        let path = request.url?.path ?? ""
        requests.append("\(request.httpMethod ?? "GET") \(path)")
        if path == "/v1/oauth/token" {
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let refreshToken = URLComponents(string: "?\(body)")?.queryItems?
                .first(where: { $0.name == "refresh_token" })?.value
            guard refreshToken == currentRefreshToken else {
                return (400, Data(#"{"error":"invalid_grant"}"#.utf8))
            }
            refreshCount += 1
            currentRefreshToken = "R\(refreshCount)"
            currentAccessToken = "A\(refreshCount)"
            return (200, Data(#"{"access_token":"A1","refresh_token":"R1","expires_in":86400}"#.utf8))
        }

        if path == "/api/oauth/usage" {
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(currentAccessToken)" else {
                return (401, Data(#"{"error":"unauthorized"}"#.utf8))
            }
            return (200, Data(#"{"five_hour":{"utilization":12.5}}"#.utf8))
        }

        return (404, Data(#"{"error":"not_found"}"#.utf8))
    }
}

private final class RotatingMockOAuthURLProtocol: URLProtocol {
    static let server = RotatingMockOAuthServer()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (statusCode, data) = Self.server.respond(to: request)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class ClaudeProviderTests: XCTestCase {
    private func makeCredentialsFile(expiresAt: Double) throws -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(".credentials.json")
        let json = """
        {"claudeAiOauth":{"accessToken":"A0","refreshToken":"R0","expiresAt":\(expiresAt),"subscriptionType":"max"}}
        """
        try Data(json.utf8).write(to: file)
        return (directory, file)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RotatingMockOAuthURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    func testExpiredCredentialsAreLeftForClaudeCodeToRenew() async throws {
        let credentials = try makeCredentialsFile(expiresAt: 1)
        defer { try? FileManager.default.removeItem(at: credentials.directory) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        RotatingMockOAuthURLProtocol.server.reset()
        let provider = ClaudeProvider(credentialsPath: credentials.file.path, session: session)

        for _ in 0..<2 {
            do {
                _ = try await provider.fetch()
                XCTFail("Expired shared credentials should request renewal")
            } catch let error as ClaudeError {
                guard case .refreshRequired = error else {
                    return XCTFail("Unexpected Claude error: \(error)")
                }
            }
        }

        XCTAssertEqual(RotatingMockOAuthURLProtocol.server.successfulRefreshCount(), 0)
        XCTAssertEqual(RotatingMockOAuthURLProtocol.server.requestLog(), [])
        let stored = try XCTUnwrap(ClaudeProvider.decodeCredentials(Data(contentsOf: credentials.file)))
        XCTAssertEqual(stored.refreshToken, "R0")
    }

    func testUnexpiredCredentialsFetchUsageWithoutRefreshing() async throws {
        let expiresAt = Date().addingTimeInterval(3_600).timeIntervalSince1970 * 1_000
        let credentials = try makeCredentialsFile(expiresAt: expiresAt)
        defer { try? FileManager.default.removeItem(at: credentials.directory) }
        let session = makeSession()
        defer { session.invalidateAndCancel() }
        RotatingMockOAuthURLProtocol.server.reset()
        let provider = ClaudeProvider(credentialsPath: credentials.file.path, session: session)

        let usage = try await provider.fetch()

        XCTAssertEqual(usage.windows.map(\.usedPercent), [12.5])
        XCTAssertEqual(RotatingMockOAuthURLProtocol.server.successfulRefreshCount(), 0)
        XCTAssertEqual(RotatingMockOAuthURLProtocol.server.requestLog(), ["GET /api/oauth/usage"])
    }

    func testDecodeCredentialsMillisecondExpiry() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"at","refreshToken":"rt","expiresAt":1770073758676,"subscriptionType":"max"}}
        """
        let creds = try XCTUnwrap(ClaudeProvider.decodeCredentials(Data(json.utf8)))
        XCTAssertEqual(creds.accessToken, "at")
        XCTAssertEqual(creds.refreshToken, "rt")
        XCTAssertEqual(creds.subscriptionType, "max")
        // 1770073758676 ms == 2026-02-02, well in the past -> expired.
        XCTAssertTrue(creds.isExpired)
    }

    func testUsageMappingFromResponse() throws {
        let json = """
        {
          "five_hour": {"utilization": 12.5, "resets_at": "2026-07-01T20:24:41Z"},
          "seven_day": {"utilization": 5.0, "resets_at": "2026-07-08T00:00:00Z"},
          "seven_day_opus": {"utilization": 40.0, "resets_at": "2026-07-08T00:00:00Z"}
        }
        """
        let response = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: Data(json.utf8))
        let usage = ClaudeProvider.usage(from: response, plan: "max", now: Date())
        XCTAssertEqual(usage.planName, "Max")
        XCTAssertEqual(usage.windows.map(\.label), ["5h limit", "Weekly limit", "Weekly (Opus)"])
        XCTAssertEqual(usage.worstWindow?.label, "Weekly (Opus)")
        XCTAssertEqual(usage.worstWindow?.usedPercent, 40.0)
        XCTAssertNotNil(usage.windows[0].resetsAt)
    }

    func testUsageMappingSkipsMissingWindows() throws {
        let json = #"{"five_hour": {"utilization": 3.0, "resets_at": "2026-07-01T20:24:41Z"}}"#
        let response = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: Data(json.utf8))
        let usage = ClaudeProvider.usage(from: response, plan: nil, now: Date())
        XCTAssertEqual(usage.windows.count, 1)
    }
}
