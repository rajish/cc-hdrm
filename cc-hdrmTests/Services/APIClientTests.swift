import Foundation
import Testing
@testable import cc_hdrm

@Suite("APIClient Tests")
struct APIClientTests {

    // MARK: - Helpers

    private static func makeSuccessResponse(json: String = """
        {
            "five_hour": { "utilization": 18.0, "resets_at": "2026-01-31T01:59:59.782798+00:00" },
            "seven_day": { "utilization": 6.0, "resets_at": "2026-02-06T08:59:59.782818+00:00" }
        }
        """) -> (Data, URLResponse) {
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    private static func makeErrorResponse(statusCode: Int, body: String = "error") -> (Data, URLResponse) {
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    // MARK: - Success

    @Test("successful 200 response returns parsed UsageResponse")
    func successfulFetch() async throws {
        let client = APIClient(dataLoader: { _ in Self.makeSuccessResponse() })

        let response = try await client.fetchUsage(token: "test-token")

        #expect(response.fiveHour?.utilization == 18.0)
        #expect(response.sevenDay?.utilization == 6.0)
    }

    // MARK: - Error Responses

    @Test("401 response throws AppError.apiError with statusCode 401")
    func unauthorized401() async {
        let client = APIClient(dataLoader: { _ in Self.makeErrorResponse(statusCode: 401, body: "Unauthorized") })

        await #expect(throws: AppError.self) {
            try await client.fetchUsage(token: "bad-token")
        }

        do {
            _ = try await client.fetchUsage(token: "bad-token")
        } catch let error as AppError {
            #expect(error == AppError.apiError(statusCode: 401, body: "Unauthorized"))
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    @Test("500 response throws AppError.apiError with statusCode 500")
    func serverError500() async {
        let client = APIClient(dataLoader: { _ in Self.makeErrorResponse(statusCode: 500, body: "Internal Server Error") })

        do {
            _ = try await client.fetchUsage(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            #expect(error == AppError.apiError(statusCode: 500, body: "Internal Server Error"))
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    @Test("network timeout throws AppError.networkUnreachable")
    func networkTimeout() async {
        let client = APIClient(dataLoader: { _ in throw URLError(.timedOut) })

        do {
            _ = try await client.fetchUsage(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            #expect(error == AppError.networkUnreachable)
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    @Test("malformed JSON response throws AppError.parseError")
    func malformedJsonResponse() async {
        let data = "not json".data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = APIClient(dataLoader: { _ in (data, response) })

        do {
            _ = try await client.fetchUsage(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            if case .parseError = error {
                // expected
            } else {
                Issue.record("Expected .parseError but got \(error)")
            }
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    // MARK: - Request Validation

    /// Sendable wrapper for capturing URLRequest in concurrent contexts.
    private final class RequestCapture: @unchecked Sendable {
        var request: URLRequest?
    }

    @Test("request includes correct headers")
    func correctHeaders() async throws {
        let capture = RequestCapture()
        let client = APIClient(dataLoader: { request in
            capture.request = request
            return Self.makeSuccessResponse()
        })

        _ = try await client.fetchUsage(token: "my-token")

        #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
        #expect(capture.request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(capture.request?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("cc-hdrm/") == true)
    }

    @Test("request URL is exactly https://api.anthropic.com/api/oauth/usage")
    func correctURL() async throws {
        let capture = RequestCapture()
        let client = APIClient(dataLoader: { request in
            capture.request = request
            return Self.makeSuccessResponse()
        })

        _ = try await client.fetchUsage(token: "test-token")

        #expect(capture.request?.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    }

    @Test("request timeout is 10 seconds")
    func requestTimeout() async throws {
        let capture = RequestCapture()
        let client = APIClient(dataLoader: { request in
            capture.request = request
            return Self.makeSuccessResponse()
        })

        _ = try await client.fetchUsage(token: "test-token")

        #expect(capture.request?.timeoutInterval == 10)
    }

    @Test("network connection lost throws AppError.networkUnreachable")
    func networkConnectionLost() async {
        let client = APIClient(dataLoader: { _ in throw URLError(.networkConnectionLost) })

        do {
            _ = try await client.fetchUsage(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            #expect(error == AppError.networkUnreachable)
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    @Test("not connected to internet throws AppError.networkUnreachable")
    func notConnectedToInternet() async {
        let client = APIClient(dataLoader: { _ in throw URLError(.notConnectedToInternet) })

        do {
            _ = try await client.fetchUsage(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            #expect(error == AppError.networkUnreachable)
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }
}

// MARK: - fetchProfile Tests

@Suite("APIClient fetchProfile Tests")
struct APIClientFetchProfileTests {

    // MARK: - Helpers

    private static func makeProfileSuccessResponse(json: String = """
        {
            "organization": {
                "organization_type": "claude_pro",
                "rate_limit_tier": "default_claude_pro"
            }
        }
        """) -> (Data, URLResponse) {
        let data = json.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/profile")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    private static func makeProfileErrorResponse(statusCode: Int, body: String = "error") -> (Data, URLResponse) {
        let data = body.data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/profile")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    /// Sendable wrapper for capturing URLRequest in concurrent contexts.
    private final class RequestCapture: @unchecked Sendable {
        var request: URLRequest?
    }

    // MARK: - Success

    @Test("successful 200 response returns parsed ProfileResponse")
    func successfulProfileFetch() async throws {
        let client = APIClient(dataLoader: { _ in Self.makeProfileSuccessResponse() })

        let response = try await client.fetchProfile(token: "test-token")

        #expect(response.organization?.rateLimitTier == "default_claude_pro")
        #expect(response.organization?.organizationType == "claude_pro")
    }

    // MARK: - Error Responses

    @Test("non-200 status throws AppError.apiError")
    func profileNon200ThrowsApiError() async {
        let client = APIClient(dataLoader: { _ in Self.makeProfileErrorResponse(statusCode: 403, body: "Forbidden") })

        do {
            _ = try await client.fetchProfile(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            #expect(error == AppError.apiError(statusCode: 403, body: "Forbidden"))
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    @Test("malformed JSON throws AppError.parseError")
    func profileMalformedJsonThrowsParseError() async {
        let data = "not json".data(using: .utf8)!
        let response = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/api/oauth/profile")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let client = APIClient(dataLoader: { _ in (data, response) })

        do {
            _ = try await client.fetchProfile(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            if case .parseError = error {
                // expected
            } else {
                Issue.record("Expected .parseError but got \(error)")
            }
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    @Test("network error throws AppError.networkUnreachable")
    func profileNetworkErrorThrowsNetworkUnreachable() async {
        let client = APIClient(dataLoader: { _ in throw URLError(.timedOut) })

        do {
            _ = try await client.fetchProfile(token: "test-token")
            Issue.record("Expected error")
        } catch let error as AppError {
            #expect(error == AppError.networkUnreachable)
        } catch {
            Issue.record("Expected AppError but got \(error)")
        }
    }

    // MARK: - Request Validation

    @Test("fetchProfile request URL is https://api.anthropic.com/api/oauth/profile")
    func profileCorrectURL() async throws {
        let capture = RequestCapture()
        let client = APIClient(dataLoader: { request in
            capture.request = request
            return Self.makeProfileSuccessResponse()
        })

        _ = try await client.fetchProfile(token: "test-token")

        #expect(capture.request?.url?.absoluteString == "https://api.anthropic.com/api/oauth/profile")
    }

    @Test("fetchProfile request includes correct headers")
    func profileCorrectHeaders() async throws {
        let capture = RequestCapture()
        let client = APIClient(dataLoader: { request in
            capture.request = request
            return Self.makeProfileSuccessResponse()
        })

        _ = try await client.fetchProfile(token: "my-token")

        #expect(capture.request?.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
        #expect(capture.request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(capture.request?.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("cc-hdrm/") == true)
    }
}
