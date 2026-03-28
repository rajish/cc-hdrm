import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Test Mocks

@MainActor
private final class MockBenchmarkPollingEngine: PollingEngineProtocol {
    var startCallCount = 0
    var stopCallCount = 0
    var restartPollingCallCount = 0
    var performForcedPollCallCount = 0

    func start() async { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func restartPolling() { restartPollingCallCount += 1 }
    func performForcedPoll() async { performForcedPollCallCount += 1 }
}

private final class MockTPPStorageService: TPPStorageServiceProtocol, @unchecked Sendable {
    var storedMeasurements: [TPPMeasurement] = []
    var latestBenchmarkResult: TPPMeasurement?
    var lastTimestamp: Int64?

    func storeBenchmarkResult(_ measurement: TPPMeasurement) async throws {
        storedMeasurements.append(measurement)
    }

    func latestBenchmark(model: String, variant: String?) async throws -> TPPMeasurement? {
        return latestBenchmarkResult
    }

    func lastBenchmarkTimestamp() async throws -> Int64? {
        return lastTimestamp
    }

    func storePassiveResult(_ measurement: TPPMeasurement) async throws {
        storedMeasurements.append(measurement)
    }

    func getMeasurements(from: Int64, to: Int64, source: MeasurementSource?, model: String?, confidence: MeasurementConfidence?) async throws -> [TPPMeasurement] {
        return []
    }

    func getAverageTPP(from: Int64, to: Int64, model: String?, source: MeasurementSource?) async throws -> (fiveHour: Double?, sevenDay: Double?) {
        return (nil, nil)
    }

    func deleteBackfillRecords() async throws {
        storedMeasurements.removeAll { $0.source == .passiveBackfill || $0.source == .rollupBackfill }
    }
}

private final class MockBenchmarkKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    var credentials = KeychainCredentials(
        accessToken: "test-token",
        refreshToken: nil,
        expiresAt: nil,
        subscriptionType: "pro",
        rateLimitTier: "tier_1",
        scopes: ["user:inference"]
    )

    func readCredentials() async throws -> KeychainCredentials {
        return credentials
    }

    func writeCredentials(_ credentials: KeychainCredentials) async throws { }
}

@Suite("BenchmarkService Tests")
@MainActor
struct BenchmarkServiceTests {

    @Test("validatePreconditions returns tokenExpired when not authenticated")
    func validateTokenExpired() async {
        let appState = AppState()
        appState.updateOAuthState(.unauthenticated)
        appState.updateConnectionStatus(.noCredentials)

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { _ in throw AppError.networkUnreachable }
        )

        let result = await service.validatePreconditions()
        #expect(result == .tokenExpired)
    }

    @Test("validatePreconditions returns utilizationTooHigh when above 90 percent")
    func validateUtilizationTooHigh() async {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 95.0, resetsAt: nil),
            sevenDay: nil
        )

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { _ in throw AppError.networkUnreachable }
        )

        let result = await service.validatePreconditions()
        #expect(result == .utilizationTooHigh)
    }

    @Test("validatePreconditions returns ready when conditions are met")
    func validateReady() async {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: nil
        )

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { _ in throw AppError.networkUnreachable }
        )

        let result = await service.validatePreconditions()
        #expect(result == .ready)
    }

    @Test("runBenchmark sends API request and forces poll")
    func runBenchmarkSendsRequest() async throws {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 10.0, resetsAt: nil)
        )

        let pollingEngine = MockBenchmarkPollingEngine()
        let tppStorage = MockTPPStorageService()

        // Mock API response
        let responseJSON = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "test output"}],
            "model": "claude-sonnet-4-6",
            "usage": {
                "input_tokens": 15,
                "output_tokens": 500,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 0
            }
        }
        """
        let responseData = responseJSON.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        // After forced poll, simulate utilization increasing
        var pollCount = 0
        let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { _ in
            return (responseData, httpResponse)
        }

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: pollingEngine,
            tppStorageService: tppStorage,
            historicalDataService: MockHistoricalDataService(),
            dataLoader: dataLoader
        )

        // Simulate utilization change during forced poll
        // The polling engine mock doesn't change appState, so delta will be 0
        // and the result will be inconclusive (that is the expected behavior with mocks)
        var progressUpdates: [BenchmarkProgress] = []
        let results = try await service.runBenchmark(
            models: ["claude-sonnet-4-6"],
            variants: [.outputHeavy],
            onProgress: { progress in
                progressUpdates.append(progress)
            }
        )

        // Verify forced poll was called (at least once per retry)
        #expect(pollingEngine.performForcedPollCallCount >= 1)

        // Verify we got results
        #expect(results.count == 1)

        // With no actual utilization change in mock, result should be inconclusive
        #expect(results[0].inconclusive == true)
        #expect(results[0].model == "claude-sonnet-4-6")
        #expect(results[0].variant == .outputHeavy)

        // Verify progress was reported
        #expect(progressUpdates.contains(.completed))
    }

    @Test("cancel stops the benchmark")
    func cancelStopsBenchmark() async throws {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: nil
        )

        let responseJSON = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "test"}],
            "model": "claude-sonnet-4-6",
            "usage": {"input_tokens": 10, "output_tokens": 100}
        }
        """
        let responseData = responseJSON.data(using: .utf8)!
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { _ in (responseData, httpResponse) }
        )

        // Cancel immediately
        service.cancel()

        let results = try await service.runBenchmark(
            models: ["claude-sonnet-4-6", "claude-opus-4-6"],
            variants: [.outputHeavy],
            onProgress: { _ in }
        )

        // Should have been cancelled before completing all models
        #expect(results.isEmpty || results.count < 2)
    }

    @Test("MessagesAPIResponse decodes correctly")
    func messagesAPIResponseDecoding() throws {
        let json = """
        {
            "usage": {
                "input_tokens": 15,
                "output_tokens": 532,
                "cache_creation_input_tokens": 10,
                "cache_read_input_tokens": 5
            }
        }
        """

        let response = try JSONDecoder().decode(MessagesAPIResponse.self, from: json.data(using: .utf8)!)
        #expect(response.usage.inputTokens == 15)
        #expect(response.usage.outputTokens == 532)
        #expect(response.usage.cacheCreationInputTokens == 10)
        #expect(response.usage.cacheReadInputTokens == 5)
    }

    @Test("MessagesAPIResponse decodes with nil cache tokens")
    func messagesAPIResponseNilCacheTokens() throws {
        let json = """
        {
            "usage": {
                "input_tokens": 15,
                "output_tokens": 532
            }
        }
        """

        let response = try JSONDecoder().decode(MessagesAPIResponse.self, from: json.data(using: .utf8)!)
        #expect(response.usage.inputTokens == 15)
        #expect(response.usage.outputTokens == 532)
        #expect(response.usage.cacheCreationInputTokens == nil)
        #expect(response.usage.cacheReadInputTokens == nil)
    }
}
