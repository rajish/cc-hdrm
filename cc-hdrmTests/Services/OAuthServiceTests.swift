import CryptoKit
import Foundation
import Testing
@testable import cc_hdrm

@Suite("OAuthService Tests")
struct OAuthServiceTests {

    // MARK: - PKCE Generation

    @Test("code verifier is 43 characters (32 bytes base64url)")
    func codeVerifierLength() {
        let verifier = OAuthService.generateCodeVerifier()
        #expect(verifier.count == 43)
    }

    @Test("code verifier contains only base64url characters")
    func codeVerifierCharacters() {
        let verifier = OAuthService.generateCodeVerifier()
        let base64urlPattern = /^[A-Za-z0-9\-_]+$/
        #expect(verifier.contains(base64urlPattern))
    }

    @Test("code challenge is SHA256 of verifier, base64url-encoded")
    func codeChallengeIsSHA256() {
        let verifier = OAuthService.generateCodeVerifier()
        let challenge = OAuthService.generateCodeChallenge(from: verifier)

        // Manually compute expected challenge
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let expected = Data(hash).base64URLEncodedString()

        #expect(challenge == expected)
    }

    @Test("code challenge is different from verifier")
    func challengeDiffersFromVerifier() {
        let verifier = OAuthService.generateCodeVerifier()
        let challenge = OAuthService.generateCodeChallenge(from: verifier)
        #expect(verifier != challenge)
    }

    // MARK: - State Generation

    @Test("state is 64 hex characters (32 bytes)")
    func stateLength() {
        let state = OAuthService.generateState()
        #expect(state.count == 64)
    }

    @Test("state contains only hex characters")
    func stateHexCharacters() {
        let state = OAuthService.generateState()
        let hexPattern = /^[0-9a-f]+$/
        #expect(state.contains(hexPattern))
    }

    @Test("state is different on each call")
    func stateIsRandom() {
        let state1 = OAuthService.generateState()
        let state2 = OAuthService.generateState()
        #expect(state1 != state2)
    }

    // MARK: - Authorization URL

    @Test("authorization URL contains all required parameters")
    func authURLContainsAllParams() {
        let url = OAuthService.buildAuthorizationURL(
            codeChallenge: "test_challenge",
            state: "test_state",
            redirectUri: "http://localhost:19876/callback"
        )

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let params = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        #expect(params["client_id"] == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
        #expect(params["response_type"] == "code")
        #expect(params["redirect_uri"] == "http://localhost:19876/callback")
        #expect(params["scope"] == "org:create_api_key user:profile user:inference")
        #expect(params["code_challenge"] == "test_challenge")
        #expect(params["code_challenge_method"] == "S256")
        #expect(params["state"] == "test_state")
    }

    @Test("authorization URL uses correct base endpoint")
    func authURLBaseEndpoint() {
        let url = OAuthService.buildAuthorizationURL(
            codeChallenge: "c",
            state: "s",
            redirectUri: "http://localhost:1234/callback"
        )

        #expect(url.host == "claude.ai")
        #expect(url.path == "/oauth/authorize")
    }

    @Test("authorization URL redirect_uri uses the actual port")
    func authURLUsesActualPort() {
        let url = OAuthService.buildAuthorizationURL(
            codeChallenge: "c",
            state: "s",
            redirectUri: "http://localhost:54321/callback"
        )

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let redirectUri = components.queryItems!.first(where: { $0.name == "redirect_uri" })!.value!
        #expect(redirectUri == "http://localhost:54321/callback")
    }

    @Test("scope includes org:create_api_key")
    func scopeIncludesCreateApiKey() {
        let url = OAuthService.buildAuthorizationURL(
            codeChallenge: "c",
            state: "s",
            redirectUri: "http://localhost:1234/callback"
        )

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let scope = components.queryItems!.first(where: { $0.name == "scope" })!.value!
        #expect(scope.contains("org:create_api_key"))
    }

    // MARK: - Token Exchange

    @Test("successful token exchange returns credentials with all fields")
    func tokenExchangeSuccess() async throws {
        let responseJSON = """
        {
            "access_token": "test_access_token",
            "refresh_token": "test_refresh_token",
            "expires_in": 3600
        }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (responseJSON, mockResponse) },
            urlOpener: { _ in true }
        )

        let creds = try await service.exchangeCode(
            code: "auth_code_123",
            state: "test_state",
            codeVerifier: "test_verifier",
            redirectUri: "http://localhost:19876/callback"
        )

        #expect(creds.accessToken == "test_access_token")
        #expect(creds.refreshToken == "test_refresh_token")
        #expect(creds.expiresAt != nil)
        if let expiresAt = creds.expiresAt {
            let expectedMs = (Date().timeIntervalSince1970 + 3600) * 1000
            #expect(abs(expiresAt - expectedMs) < 5000)
        }
    }

    @Test("token exchange sends correct JSON body")
    func tokenExchangeRequestBody() async throws {
        let responseJSON = """
        { "access_token": "tok", "expires_in": 3600 }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        actor RequestCapture {
            var request: URLRequest?
            func capture(_ req: URLRequest) { request = req }
        }
        let capture = RequestCapture()

        let service = OAuthService(
            dataLoader: { req in
                await capture.capture(req)
                return (responseJSON, mockResponse)
            },
            urlOpener: { _ in true }
        )

        _ = try await service.exchangeCode(
            code: "my_code",
            state: "my_state",
            codeVerifier: "my_verifier",
            redirectUri: "http://localhost:9999/callback"
        )

        let capturedRequest = await capture.request
        #expect(capturedRequest?.url?.absoluteString == "https://console.anthropic.com/v1/oauth/token")
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json")

        if let data = capturedRequest?.httpBody,
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            #expect(json["code"] == "my_code")
            #expect(json["state"] == "my_state")
            #expect(json["grant_type"] == "authorization_code")
            #expect(json["client_id"] == "9d1c250a-e61b-44d9-88ed-5944d1962f5e")
            #expect(json["redirect_uri"] == "http://localhost:9999/callback")
            #expect(json["code_verifier"] == "my_verifier")
        } else {
            Issue.record("Request body should be valid JSON with expected fields")
        }
    }

    @Test("token exchange with 400 response throws oauthTokenExchangeFailed")
    func tokenExchangeError400() async {
        let errorResponse = """
        {"error": "invalid_grant"}
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (errorResponse, mockResponse) },
            urlOpener: { _ in true }
        )

        await #expect(throws: AppError.self) {
            _ = try await service.exchangeCode(
                code: "bad_code",
                state: "s",
                codeVerifier: "v",
                redirectUri: "http://localhost:1234/callback"
            )
        }
    }

    @Test("token exchange with 401 response throws oauthTokenExchangeFailed")
    func tokenExchangeError401() async {
        let errorResponse = "Unauthorized".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (errorResponse, mockResponse) },
            urlOpener: { _ in true }
        )

        await #expect(throws: AppError.self) {
            _ = try await service.exchangeCode(
                code: "c",
                state: "s",
                codeVerifier: "v",
                redirectUri: "http://localhost:1234/callback"
            )
        }
    }

    @Test("token exchange with malformed JSON throws oauthTokenExchangeFailed")
    func tokenExchangeMalformedResponse() async {
        let malformed = "not json".data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (malformed, mockResponse) },
            urlOpener: { _ in true }
        )

        await #expect(throws: AppError.self) {
            _ = try await service.exchangeCode(
                code: "c",
                state: "s",
                codeVerifier: "v",
                redirectUri: "http://localhost:1234/callback"
            )
        }
    }

    @Test("token exchange with missing access_token throws oauthTokenExchangeFailed")
    func tokenExchangeMissingAccessToken() async {
        let noToken = """
        { "refresh_token": "rt", "expires_in": 3600 }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (noToken, mockResponse) },
            urlOpener: { _ in true }
        )

        await #expect(throws: AppError.self) {
            _ = try await service.exchangeCode(
                code: "c",
                state: "s",
                codeVerifier: "v",
                redirectUri: "http://localhost:1234/callback"
            )
        }
    }

    @Test("token exchange with network error throws oauthTokenExchangeFailed")
    func tokenExchangeNetworkError() async {
        let service = OAuthService(
            dataLoader: { _ in throw URLError(.notConnectedToInternet) },
            urlOpener: { _ in true }
        )

        await #expect(throws: AppError.self) {
            _ = try await service.exchangeCode(
                code: "c",
                state: "s",
                codeVerifier: "v",
                redirectUri: "http://localhost:1234/callback"
            )
        }
    }

    @Test("token exchange without refresh_token returns nil refreshToken")
    func tokenExchangeNoRefreshToken() async throws {
        let responseJSON = """
        { "access_token": "at", "expires_in": 3600 }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (responseJSON, mockResponse) },
            urlOpener: { _ in true }
        )

        let creds = try await service.exchangeCode(
            code: "c",
            state: "s",
            codeVerifier: "v",
            redirectUri: "http://localhost:1234/callback"
        )

        #expect(creds.accessToken == "at")
        #expect(creds.refreshToken == nil)
    }

    @Test("token exchange without expires_in returns nil expiresAt")
    func tokenExchangeNoExpiresIn() async throws {
        let responseJSON = """
        { "access_token": "at" }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (responseJSON, mockResponse) },
            urlOpener: { _ in true }
        )

        let creds = try await service.exchangeCode(
            code: "c",
            state: "s",
            codeVerifier: "v",
            redirectUri: "http://localhost:1234/callback"
        )

        #expect(creds.accessToken == "at")
        #expect(creds.expiresAt == nil)
    }

    @Test("token exchange parses scope as space-separated string")
    func tokenExchangeScopeAsString() async throws {
        let responseJSON = """
        { "access_token": "at", "scope": "org:create_api_key user:profile" }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (responseJSON, mockResponse) },
            urlOpener: { _ in true }
        )

        let creds = try await service.exchangeCode(
            code: "c",
            state: "s",
            codeVerifier: "v",
            redirectUri: "http://localhost:1234/callback"
        )

        #expect(creds.scopes == ["org:create_api_key", "user:profile"])
    }

    @Test("token exchange parses scope as array")
    func tokenExchangeScopeAsArray() async throws {
        let responseJSON = """
        { "access_token": "at", "scope": ["org:create_api_key", "user:profile"] }
        """.data(using: .utf8)!
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://console.anthropic.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = OAuthService(
            dataLoader: { _ in (responseJSON, mockResponse) },
            urlOpener: { _ in true }
        )

        let creds = try await service.exchangeCode(
            code: "c",
            state: "s",
            codeVerifier: "v",
            redirectUri: "http://localhost:1234/callback"
        )

        #expect(creds.scopes == ["org:create_api_key", "user:profile"])
    }

    // MARK: - Browser Open Failure

    @Test("authorize throws when browser fails to open")
    func authorizeThrowsOnBrowserFailure() async {
        let service = OAuthService(
            dataLoader: { _ in throw URLError(.badURL) },
            urlOpener: { _ in false }  // Browser open fails
        )

        await #expect(throws: AppError.self) {
            _ = try await service.authorize()
        }
    }
}
