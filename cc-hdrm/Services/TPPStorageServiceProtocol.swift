import Foundation

/// Protocol for persisting and retrieving TPP measurement results.
protocol TPPStorageServiceProtocol: Sendable {
    /// Stores a benchmark measurement result in the database.
    /// - Parameter measurement: The measurement to persist
    func storeBenchmarkResult(_ measurement: TPPMeasurement) async throws

    /// Retrieves the most recent benchmark for a given model and variant.
    /// - Parameters:
    ///   - model: The model identifier
    ///   - variant: The benchmark variant (optional, nil matches any variant)
    /// - Returns: The latest measurement, or nil if none exists
    func latestBenchmark(model: String, variant: String?) async throws -> TPPMeasurement?

    /// Returns the timestamp of the most recent benchmark measurement.
    /// - Returns: Unix milliseconds of the last benchmark, or nil if none exists
    func lastBenchmarkTimestamp() async throws -> Int64?
}
