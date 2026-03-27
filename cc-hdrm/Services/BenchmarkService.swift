import Foundation
import os

/// Messages API response structure for benchmark requests.
struct MessagesAPIResponse: Decodable, Sendable {
    let usage: MessagesAPIUsage

    struct MessagesAPIUsage: Decodable, Sendable {
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationInputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}

/// Orchestrates benchmark measurement sequences: sends controlled test requests to the
/// Messages API, forces usage polls, and computes TPP from observed utilization deltas.
@MainActor
final class BenchmarkService: BenchmarkServiceProtocol {
    private let appState: AppState
    private let keychainService: any KeychainServiceProtocol
    private let pollingEngine: any PollingEngineProtocol
    private let tppStorageService: any TPPStorageServiceProtocol
    private let historicalDataService: any HistoricalDataServiceProtocol
    private let dataLoader: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private var cancelled = false

    /// Maximum number of adaptive retries when utilization delta is 0.
    private let maxRetries = 3

    private static let messagesEndpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "benchmark"
    )

    /// User-Agent header for benchmark requests.
    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return "cc-hdrm/\(version)"
    }()

    /// ~3K tokens of generic English text for the input-heavy variant.
    static let inputHeavyText: String = """
    The history of computing is a fascinating journey through human ingenuity and technological \
    evolution. From the earliest mechanical calculators designed by Blaise Pascal and Gottfried \
    Wilhelm Leibniz in the 17th century, to Charles Babbage's ambitious Analytical Engine in the \
    19th century, the dream of automated computation has driven countless innovations. Ada Lovelace, \
    working alongside Babbage, is often credited as the first computer programmer for her notes on \
    the Analytical Engine, which included what many consider to be the first algorithm intended for \
    machine processing. The 20th century brought the most dramatic advances, beginning with Alan \
    Turing's theoretical foundations of computation and the development of the Turing machine concept, \
    which remains fundamental to computer science today. During World War II, the need for rapid \
    code-breaking and ballistic calculations spurred the development of electronic computers like \
    Colossus and ENIAC. The post-war era saw the transition from vacuum tubes to transistors, a \
    breakthrough that dramatically reduced the size and cost of computing while improving reliability. \
    The invention of the integrated circuit by Jack Kilby and Robert Noyce in the late 1950s set the \
    stage for Moore's Law and the exponential growth in computing power that continues to shape our \
    world. The personal computer revolution of the 1970s and 1980s, led by pioneers like Steve Jobs, \
    Steve Wozniak, and Bill Gates, democratized access to computing power. The Altair 8800, Apple II, \
    and IBM PC brought computers into homes and small businesses, fundamentally changing how people \
    work, communicate, and create. The development of graphical user interfaces, pioneered at Xerox \
    PARC and popularized by Apple's Macintosh and later Microsoft Windows, made computers accessible \
    to non-technical users. The Internet, evolving from ARPANET's humble beginnings in the late 1960s, \
    became the most transformative technology of the late 20th century. Tim Berners-Lee's invention of \
    the World Wide Web in 1989 created a new medium for information sharing, commerce, and social \
    interaction. The subsequent dot-com boom and bust, the rise of search engines like Google, and the \
    emergence of social media platforms like Facebook and Twitter reshaped society in profound ways. \
    Mobile computing, catalyzed by Apple's iPhone in 2007, shifted the computing paradigm yet again, \
    putting powerful computers in billions of pockets worldwide. The app economy that followed created \
    entirely new industries and business models. Cloud computing, pioneered by Amazon Web Services, \
    enabled startups to build global-scale services without massive upfront infrastructure investments. \
    Today, artificial intelligence and machine learning represent the latest frontier, with large \
    language models, computer vision, and autonomous systems pushing the boundaries of what machines \
    can achieve. Quantum computing promises to solve problems currently intractable for classical \
    computers, potentially revolutionizing fields from cryptography to drug discovery. The ongoing \
    convergence of computing with biotechnology, materials science, and energy systems suggests that \
    the most transformative impacts of computing may still lie ahead. As we look to the future, the \
    ethical implications of these technologies demand careful consideration, from privacy and security \
    concerns to the societal impacts of automation and artificial intelligence on employment and human \
    agency. The principles of responsible innovation, transparent governance, and inclusive design will \
    be essential as humanity navigates its relationship with increasingly powerful computing systems. \
    Edge computing brings processing closer to data sources, reducing latency for real-time applications. \
    Neuromorphic chips inspired by the human brain offer new paradigms for efficient AI processing. \
    The intersection of 5G networks and IoT devices creates a fabric of connected intelligence that \
    spans cities, industries, and ecosystems. Blockchain technology promises decentralized trust and \
    new models for digital ownership and governance. These threads weave together into a tapestry of \
    technological transformation that continues to accelerate, challenge, and inspire.
    """

    init(
        appState: AppState,
        keychainService: any KeychainServiceProtocol,
        pollingEngine: any PollingEngineProtocol,
        tppStorageService: any TPPStorageServiceProtocol,
        historicalDataService: any HistoricalDataServiceProtocol,
        dataLoader: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) {
        self.appState = appState
        self.keychainService = keychainService
        self.pollingEngine = pollingEngine
        self.tppStorageService = tppStorageService
        self.historicalDataService = historicalDataService
        self.dataLoader = dataLoader
    }

    /// Production convenience initializer using URLSession.shared.
    convenience init(
        appState: AppState,
        keychainService: any KeychainServiceProtocol,
        pollingEngine: any PollingEngineProtocol,
        tppStorageService: any TPPStorageServiceProtocol,
        historicalDataService: any HistoricalDataServiceProtocol
    ) {
        self.init(
            appState: appState,
            keychainService: keychainService,
            pollingEngine: pollingEngine,
            tppStorageService: tppStorageService,
            historicalDataService: historicalDataService,
            dataLoader: { request in
                try await URLSession.shared.data(for: request)
            }
        )
    }

    func validatePreconditions() async -> BenchmarkValidation {
        // Check OAuth state: must be authenticated and actively connected
        guard appState.oauthState == .authenticated,
              appState.connectionStatus == .connected else {
            return .tokenExpired
        }

        // Check 5h utilization <= 90%
        if let fiveHour = appState.fiveHour, fiveHour.utilization > 90.0 {
            return .utilizationTooHigh
        }

        // Check utilization stability: last 3 polls should have the same integer value
        do {
            let recentPolls = try await historicalDataService.getRecentPolls(hours: 1)
            let lastThree = recentPolls.suffix(3)
            if lastThree.count >= 3 {
                let values = lastThree.compactMap { $0.fiveHourUtil }.map { Int($0) }
                if values.count >= 3 {
                    let allSame = values.allSatisfy { $0 == values.first }
                    if !allSame {
                        return .recentActivity
                    }
                }
            }
        } catch {
            Self.logger.warning("Failed to check utilization stability: \(error.localizedDescription)")
        }

        return .ready
    }

    func runBenchmark(
        models: [String],
        variants: [BenchmarkVariant],
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> [BenchmarkVariantResult] {
        cancelled = false
        var results: [BenchmarkVariantResult] = []

        let token: String
        do {
            let credentials = try await keychainService.readCredentials()
            token = credentials.accessToken
        } catch {
            onProgress(.failed("Unable to read credentials"))
            throw error
        }

        for model in models {
            guard !cancelled else {
                onProgress(.cancelled)
                break
            }

            for variant in variants {
                guard !cancelled else {
                    onProgress(.cancelled)
                    break
                }

                let result = await runVariant(
                    model: model,
                    variant: variant,
                    token: token,
                    onProgress: onProgress
                )
                results.append(result)

                // Store successful measurements
                if let measurement = result.measurement {
                    do {
                        try await tppStorageService.storeBenchmarkResult(measurement)
                    } catch {
                        Self.logger.error("Failed to store benchmark result: \(error.localizedDescription)")
                    }
                }
            }
        }

        onProgress(.completed)
        return results
    }

    func cancel() {
        cancelled = true
    }

    // MARK: - Private

    /// Runs a single benchmark variant with adaptive retry.
    private func runVariant(
        model: String,
        variant: BenchmarkVariant,
        token: String,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async -> BenchmarkVariantResult {
        var retryCount = 0
        var wordCount = 500

        while retryCount <= maxRetries {
            guard !cancelled else {
                return BenchmarkVariantResult(model: model, variant: variant, measurement: nil, inconclusive: false, retryCount: retryCount)
            }

            // Record "before" utilization
            let fiveHourBefore = appState.fiveHour?.utilization ?? 0
            let sevenDayBefore = appState.sevenDay?.utilization

            // Send API request
            onProgress(.sendingRequest(model: model, variant: variant.displayName))

            let apiResponse: MessagesAPIResponse
            do {
                apiResponse = try await sendBenchmarkRequest(
                    model: model,
                    variant: variant,
                    token: token,
                    wordCount: wordCount
                )
            } catch {
                Self.logger.error("Benchmark API request failed: \(error.localizedDescription)")
                return BenchmarkVariantResult(model: model, variant: variant, measurement: nil, inconclusive: true, retryCount: retryCount)
            }

            // Log rate limit headers at debug level
            Self.logger.debug("Benchmark response usage: input=\(apiResponse.usage.inputTokens) output=\(apiResponse.usage.outputTokens)")

            // Force a poll to get updated utilization
            onProgress(.polling(model: model))
            await pollingEngine.performForcedPoll()

            // Record "after" utilization
            let fiveHourAfter = appState.fiveHour?.utilization ?? 0
            let sevenDayAfter = appState.sevenDay?.utilization

            let fiveHourDelta = fiveHourAfter - fiveHourBefore

            if fiveHourDelta <= 0 && retryCount < maxRetries {
                // Delta is 0 — below detection threshold. Double the word count and retry.
                retryCount += 1
                wordCount *= 2
                Self.logger.info("Benchmark delta is 0 for \(model, privacy: .public)/\(variant.rawValue, privacy: .public) — retrying with wordCount=\(wordCount)")
                continue
            }

            // Compute result
            onProgress(.computingResult(model: model, variant: variant.displayName))

            if fiveHourDelta <= 0 {
                // Still inconclusive after all retries
                return BenchmarkVariantResult(model: model, variant: variant, measurement: nil, inconclusive: true, retryCount: retryCount)
            }

            let measurement = TPPMeasurement.fromBenchmark(
                model: model,
                variant: variant,
                fiveHourBefore: fiveHourBefore,
                fiveHourAfter: fiveHourAfter,
                sevenDayBefore: sevenDayBefore,
                sevenDayAfter: sevenDayAfter,
                inputTokens: apiResponse.usage.inputTokens,
                outputTokens: apiResponse.usage.outputTokens,
                cacheCreateTokens: apiResponse.usage.cacheCreationInputTokens ?? 0,
                cacheReadTokens: apiResponse.usage.cacheReadInputTokens ?? 0
            )

            return BenchmarkVariantResult(model: model, variant: variant, measurement: measurement, inconclusive: false, retryCount: retryCount)
        }

        return BenchmarkVariantResult(model: model, variant: variant, measurement: nil, inconclusive: true, retryCount: retryCount)
    }

    /// Sends a Messages API request for the specified variant.
    private func sendBenchmarkRequest(
        model: String,
        variant: BenchmarkVariant,
        token: String,
        wordCount: Int
    ) async throws -> MessagesAPIResponse {
        let (content, maxTokens) = buildRequestParams(variant: variant, wordCount: wordCount)

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "user", "content": content]
            ]
        ]

        var request = URLRequest(url: Self.messagesEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await dataLoader(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.networkUnreachable
        }

        // Log rate limit headers at debug level
        if let requestsLimit = httpResponse.value(forHTTPHeaderField: "anthropic-ratelimit-requests-limit") {
            Self.logger.debug("Rate limit headers: requests-limit=\(requestsLimit, privacy: .public)")
        }
        if let tokensLimit = httpResponse.value(forHTTPHeaderField: "anthropic-ratelimit-tokens-limit") {
            Self.logger.debug("Rate limit headers: tokens-limit=\(tokensLimit, privacy: .public)")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            throw AppError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(MessagesAPIResponse.self, from: data)
    }

    /// Builds the prompt content and max_tokens for each variant.
    private func buildRequestParams(variant: BenchmarkVariant, wordCount: Int) -> (content: String, maxTokens: Int) {
        switch variant {
        case .outputHeavy:
            return (
                "Write exactly \(wordCount) words of varied placeholder text. No meta-commentary.",
                2048
            )
        case .inputHeavy:
            return (
                Self.inputHeavyText + "\n\nSummarize the above text in one sentence.",
                100
            )
        case .cacheHeavy:
            return (
                "Write exactly \(wordCount) words of varied placeholder text. No meta-commentary.",
                2048
            )
        }
    }
}
