import XCTest
@testable import AgentMeter

final class ErrorRedactionTests: XCTestCase {
    func testRedactsBase64Token() {
        let token = "ya29.a0AfB_byC1+2/3xYzAbCdEfGhIjKlMnOpQ=="
        XCTAssertFalse(ErrorRedaction.redact("rejected \(token) today").contains(token))
    }

    func testRedactsBearerTokenWithBase64Characters() {
        XCTAssertEqual(ErrorRedaction.redact("Bearer ab+c/d=="), "Bearer …")
    }

    func testRedactsShortKeyAssignments() {
        let redacted = ErrorRedaction.redact("bad request: api_key=abc123 token: xyz")
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("xyz"))
        XCTAssertTrue(redacted.contains("api_key=…"))
    }

    func testKeepsPlainMessagesReadable() {
        let message = "Run Claude Code to renew its credentials, then refresh Allowance Bar (HTTP 401)"
        XCTAssertEqual(ErrorRedaction.redact(message), message)
        XCTAssertEqual(
            ErrorRedaction.redact("Internationalization-configuration-unavailable"),
            "Internationalization-configuration-unavailable"
        )
    }
}
