import Foundation
import Testing
@testable import cc_hdrm

// MARK: - Test Mocks

private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [BenchmarkProgress] = []

    func append(_ progress: BenchmarkProgress) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(progress)
    }

    var values: [BenchmarkProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
private final class MockBenchmarkPollingEngine: PollingEngineProtocol {
    var startCallCount = 0
    var stopCallCount = 0
    var restartPollingCallCount = 0
    var performForcedPollCallCount = 0
    var onForcedPoll: (@MainActor () -> Void)?

    func start() async { startCallCount += 1 }
    func stop() { stopCallCount += 1 }
    func restartPolling() { restartPollingCallCount += 1 }
    func performForcedPoll() async {
        performForcedPollCallCount += 1
        onForcedPoll?()
    }
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
        let progressUpdates = ProgressCollector()
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
        #expect(progressUpdates.values.contains(.completed))
    }

    @Test("runBenchmark forwards claude-fable-5 model ID unchanged in the request body")
    func runBenchmarkForwardsFableModel() async throws {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 10.0, resetsAt: nil)
        )

        let responseJSON = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "test output"}],
            "model": "claude-fable-5",
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

        final class RequestCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [URLRequest] = []
            func append(_ request: URLRequest) {
                lock.lock()
                defer { lock.unlock() }
                storage.append(request)
            }
            var requests: [URLRequest] {
                lock.lock()
                defer { lock.unlock() }
                return storage
            }
        }
        let capture = RequestCapture()

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { request in
                capture.append(request)
                return (responseData, httpResponse)
            }
        )

        let progressUpdates = ProgressCollector()
        let results = try await service.runBenchmark(
            models: ["claude-fable-5"],
            variants: [.outputHeavy],
            onProgress: { progress in
                progressUpdates.append(progress)
            }
        )

        let firstRequest = try #require(capture.requests.first)
        #expect(firstRequest.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(firstRequest.httpMethod == "POST")
        #expect(firstRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(firstRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(firstRequest.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)

        let bodyData = try #require(firstRequest.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        #expect(body["model"] as? String == "claude-fable-5")
        #expect(body["max_tokens"] as? Int == 2048)
        #expect((body["messages"] as? [[String: Any]])?.count == 1)

        for request in capture.requests {
            let data = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["model"] as? String == "claude-fable-5")
        }

        #expect(progressUpdates.values.contains(
            .sendingRequest(model: "claude-fable-5", variant: BenchmarkVariant.outputHeavy.displayName)
        ))
        #expect(results.count == 1)
        #expect(results[0].model == "claude-fable-5")
        #expect(results[0].variant == .outputHeavy)
        #expect(progressUpdates.values.contains(.completed))
    }

    @Test("runBenchmark marks rejected model inconclusive without affecting other models")
    func runBenchmarkRejectedModelIsolated() async throws {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 10.0, resetsAt: nil)
        )

        let okJSON = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "test output"}],
            "model": "claude-sonnet-4-6",
            "usage": {"input_tokens": 15, "output_tokens": 500}
        }
        """
        let okData = okJSON.data(using: .utf8)!
        let okResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        let rejectedData = #"{"type":"error","error":{"type":"not_found_error","message":"model not found"}}"#.data(using: .utf8)!
        let rejectedResponse = HTTPURLResponse(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { request in
                let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                if body?["model"] as? String == "claude-fable-5" {
                    return (rejectedData, rejectedResponse)
                }
                return (okData, okResponse)
            }
        )

        let results = try await service.runBenchmark(
            models: ["claude-sonnet-4-6", "claude-fable-5"],
            variants: [.outputHeavy],
            onProgress: { _ in }
        )

        #expect(results.count == 2)
        #expect(results[0].model == "claude-sonnet-4-6")
        #expect(results[0].retryCount >= 1)
        #expect(results[1].model == "claude-fable-5")
        #expect(results[1].inconclusive == true)
        #expect(results[1].measurement == nil)
        #expect(results[1].retryCount == 0)
    }

    @Test("runBenchmark produces a conclusive claude-fable-5 measurement end to end")
    func runBenchmarkProducesFableMeasurement() async throws {
        let appState = AppState()
        appState.updateOAuthState(.authenticated)
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 50.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 10.0, resetsAt: nil)
        )

        let responseJSON = """
        {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "content": [{"type": "text", "text": "test output"}],
            "model": "claude-fable-5",
            "usage": {
                "input_tokens": 20,
                "output_tokens": 600,
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

        let pollingEngine = MockBenchmarkPollingEngine()
        pollingEngine.onForcedPoll = {
            appState.updateWindows(
                fiveHour: WindowState(utilization: 52.0, resetsAt: nil),
                sevenDay: WindowState(utilization: 10.5, resetsAt: nil)
            )
        }
        let tppStorage = MockTPPStorageService()

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: pollingEngine,
            tppStorageService: tppStorage,
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { _ in (responseData, httpResponse) }
        )

        let results = try await service.runBenchmark(
            models: ["claude-fable-5"],
            variants: [.outputHeavy],
            onProgress: { _ in }
        )

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.model == "claude-fable-5")
        #expect(result.inconclusive == false)
        #expect(result.retryCount == 0)
        #expect(result.measurement != nil)
        #expect(result.measurement?.model == "claude-fable-5")
        #expect(result.measurement?.tppFiveHour != nil)
        #expect(pollingEngine.performForcedPollCallCount == 1)
        #expect(tppStorage.storedMeasurements.count == 1)
        #expect(tppStorage.storedMeasurements.first?.model == "claude-fable-5")
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

        // runBenchmark resets the cancel flag on entry, so cancel mid-run
        // via the data loader: the first API call cancels the service.
        final class ServiceBox: @unchecked Sendable {
            @MainActor var service: BenchmarkService?
        }
        let box = ServiceBox()

        let service = BenchmarkService(
            appState: appState,
            keychainService: MockBenchmarkKeychainService(),
            pollingEngine: MockBenchmarkPollingEngine(),
            tppStorageService: MockTPPStorageService(),
            historicalDataService: MockHistoricalDataService(),
            dataLoader: { _ in
                await MainActor.run { box.service?.cancel() }
                return (responseData, httpResponse)
            }
        )
        box.service = service

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
