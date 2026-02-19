import Foundation
import Testing
@testable import cc_hdrm

@Suite("OAuthCallbackServer Tests")
struct OAuthCallbackServerTests {

    // MARK: - HTTP Request Parsing

    @Test("parseHTTPRequest extracts code and state from valid GET callback")
    func parseValidRequest() {
        let request = "GET /callback?code=auth_code_123&state=random_state HTTP/1.1\r\nHost: localhost:19876\r\n\r\n"
        let params = OAuthCallbackServer.parseHTTPRequest(request)

        #expect(params != nil)
        #expect(params?["code"] == "auth_code_123")
        #expect(params?["state"] == "random_state")
    }

    @Test("parseHTTPRequest returns nil for non-GET request")
    func parsePostRequest() {
        let request = "POST /callback?code=abc&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let params = OAuthCallbackServer.parseHTTPRequest(request)

        #expect(params == nil)
    }

    @Test("parseHTTPRequest returns nil for wrong path")
    func parseWrongPath() {
        let request = "GET /other?code=abc&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let params = OAuthCallbackServer.parseHTTPRequest(request)

        #expect(params == nil)
    }

    @Test("parseHTTPRequest returns nil for empty request")
    func parseEmptyRequest() {
        let params = OAuthCallbackServer.parseHTTPRequest("")
        #expect(params == nil)
    }

    @Test("parseHTTPRequest handles callback with no query params")
    func parseNoQueryParams() {
        let request = "GET /callback HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let params = OAuthCallbackServer.parseHTTPRequest(request)

        #expect(params != nil)
        #expect(params?["code"] == nil)
        #expect(params?["state"] == nil)
    }

    @Test("parseHTTPRequest handles URL-encoded values")
    func parseEncodedValues() {
        let request = "GET /callback?code=abc%20def&state=xyz%3D123 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let params = OAuthCallbackServer.parseHTTPRequest(request)

        #expect(params?["code"] == "abc def")
        #expect(params?["state"] == "xyz=123")
    }

    @Test("parseHTTPRequest handles extra query parameters gracefully")
    func parseExtraParams() {
        let request = "GET /callback?code=abc&state=xyz&extra=ignored HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let params = OAuthCallbackServer.parseHTTPRequest(request)

        #expect(params?["code"] == "abc")
        #expect(params?["state"] == "xyz")
        #expect(params?["extra"] == "ignored")
    }

    // MARK: - New AppError Cases

    @Test("oauthAuthorizationFailed equality with same message")
    func oauthAuthorizationFailedEquality() {
        let a = AppError.oauthAuthorizationFailed("test")
        let b = AppError.oauthAuthorizationFailed("test")
        #expect(a == b)
    }

    @Test("oauthAuthorizationFailed inequality with different message")
    func oauthAuthorizationFailedInequality() {
        let a = AppError.oauthAuthorizationFailed("one")
        let b = AppError.oauthAuthorizationFailed("two")
        #expect(a != b)
    }

    @Test("oauthCallbackTimeout equality")
    func oauthCallbackTimeoutEquality() {
        #expect(AppError.oauthCallbackTimeout == AppError.oauthCallbackTimeout)
    }

    @Test("oauthTokenExchangeFailed equality")
    func oauthTokenExchangeFailedEquality() {
        let a = AppError.oauthTokenExchangeFailed(underlying: URLError(.badURL))
        let b = AppError.oauthTokenExchangeFailed(underlying: URLError(.timedOut))
        #expect(a == b)
    }
}
