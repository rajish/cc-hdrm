import Foundation
import Testing
@testable import cc_hdrm

@Suite("TokenRefreshService Tests")
struct TokenRefreshServiceTests {

    // MARK: - Successful Refresh

    @Test("successful refresh returns updated credentials")
    func successfulRefresh() async throws {
        let responseJSON = """
        {
            "access_token": "new-access-token",
            "refresh_token": "new-refresh-token",
            "expires_in": 3600,
            "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = TokenRefreshService(dataLoader: { _ in
            (responseJSON, mockResponse)
        })

        let creds = try await service.refreshToken(using: "old-refresh-token")

        #expect(creds.accessToken == "new-access-token")
        #expect(creds.refreshToken == "new-refresh-token")
        #expect(creds.expiresAt != nil)
        // expiresAt should be roughly now + 3600s in milliseconds
        if let expiresAt = creds.expiresAt {
            let expectedMs = (Date().timeIntervalSince1970 + 3600) * 1000
            #expect(abs(expiresAt - expectedMs) < 5000) // within 5 seconds tolerance
        }
    }

    @Test("successful refresh without new refresh token keeps old one")
    func successfulRefreshKeepsOldRefreshToken() async throws {
        let responseJSON = """
        {
            "access_token": "new-access-token",
            "expires_in": 3600,
            "token_type": "Bearer"
        }
        """.data(using: .utf8)!

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = TokenRefreshService(dataLoader: { _ in
            (responseJSON, mockResponse)
        })

        let creds = try await service.refreshToken(using: "original-refresh-token")

        #expect(creds.refreshToken == "original-refresh-token")
    }

    // MARK: - Network Failure

    @Test("network failure throws tokenRefreshFailed")
    func networkFailure() async {
        let service = TokenRefreshService(dataLoader: { _ in
            throw URLError(.notConnectedToInternet)
        })

        await #expect(throws: AppError.self) {
            _ = try await service.refreshToken(using: "token")
        }
    }

    // MARK: - Invalid Response

    @Test("non-200 status throws tokenRefreshFailed")
    func non200Status() async {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = TokenRefreshService(dataLoader: { _ in
            ("{}".data(using: .utf8)!, mockResponse)
        })

        await #expect(throws: AppError.self) {
            _ = try await service.refreshToken(using: "token")
        }
    }

    @Test("invalid response body throws tokenRefreshFailed")
    func invalidResponseBody() async {
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = TokenRefreshService(dataLoader: { _ in
            ("not json".data(using: .utf8)!, mockResponse)
        })

        await #expect(throws: AppError.self) {
            _ = try await service.refreshToken(using: "token")
        }
    }

    @Test("response missing access_token throws tokenRefreshFailed")
    func missingAccessToken() async {
        let responseJSON = """
        { "refresh_token": "new-token", "expires_in": 3600 }
        """.data(using: .utf8)!

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = TokenRefreshService(dataLoader: { _ in
            (responseJSON, mockResponse)
        })

        await #expect(throws: AppError.self) {
            _ = try await service.refreshToken(using: "token")
        }
    }

    @Test("successful refresh without expires_in returns nil expiresAt")
    func missingExpiresIn() async throws {
        let responseJSON = """
        { "access_token": "new-token", "token_type": "Bearer" }
        """.data(using: .utf8)!

        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://platform.claude.com/v1/oauth/token")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = TokenRefreshService(dataLoader: { _ in
            (responseJSON, mockResponse)
        })

        let creds = try await service.refreshToken(using: "old-refresh")

        #expect(creds.accessToken == "new-token")
        #expect(creds.expiresAt == nil)
        #expect(creds.refreshToken == "old-refresh")
    }
}
