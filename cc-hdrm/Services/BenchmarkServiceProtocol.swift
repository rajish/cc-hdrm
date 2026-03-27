import Foundation

/// Result of pre-measurement validation checks.
enum BenchmarkValidation: Sendable, Equatable {
    case ready
    case tokenExpired
    case utilizationTooHigh
    case recentActivity
}

/// Progress state during benchmark execution.
enum BenchmarkProgress: Sendable, Equatable {
    case idle
    case validating
    case sendingRequest(model: String, variant: String)
    case polling(model: String)
    case computingResult(model: String, variant: String)
    case completed
    case cancelled
    case failed(String)
}

/// Result of a single benchmark variant execution.
struct BenchmarkVariantResult: Sendable, Equatable {
    let model: String
    let variant: BenchmarkVariant
    let measurement: TPPMeasurement?
    let inconclusive: Bool
    let retryCount: Int
}

/// Protocol for the benchmark measurement service.
@MainActor
protocol BenchmarkServiceProtocol: Sendable {
    /// Validates whether conditions are suitable for benchmark execution.
    func validatePreconditions() async -> BenchmarkValidation

    /// Runs the full benchmark sequence for the specified models and variants.
    /// - Parameters:
    ///   - models: Model identifiers to benchmark
    ///   - variants: Benchmark variants to run per model
    ///   - onProgress: Called with progress updates
    /// - Returns: Array of results per model/variant combination
    func runBenchmark(
        models: [String],
        variants: [BenchmarkVariant],
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> [BenchmarkVariantResult]

    /// Cancels any in-progress benchmark.
    func cancel()
}
