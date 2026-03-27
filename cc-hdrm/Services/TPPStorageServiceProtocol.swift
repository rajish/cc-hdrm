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

    /// Stores a passive measurement result in the database.
    /// Uses the same INSERT logic as `storeBenchmarkResult` but with separate logging.
    /// - Parameter measurement: The measurement to persist
    func storePassiveResult(_ measurement: TPPMeasurement) async throws

    /// Retrieves TPP measurements within a time range with optional filters.
    /// - Parameters:
    ///   - from: Start of time range (Unix milliseconds, inclusive)
    ///   - to: End of time range (Unix milliseconds, inclusive)
    ///   - source: Optional source filter ("passive", "benchmark"). Nil returns all.
    ///   - model: Optional model filter. Nil returns all models.
    ///   - confidence: Optional confidence filter. Nil returns all confidence levels.
    /// - Returns: Measurements sorted by timestamp ascending
    func getMeasurements(from: Int64, to: Int64, source: MeasurementSource?, model: String?, confidence: MeasurementConfidence?) async throws -> [TPPMeasurement]

    /// Returns average TPP values for a time range with optional filters.
    /// - Parameters:
    ///   - from: Start of time range (Unix milliseconds, inclusive)
    ///   - to: End of time range (Unix milliseconds, inclusive)
    ///   - model: Optional model filter. Nil averages across all models.
    ///   - source: Optional source filter. Nil averages across all sources.
    /// - Returns: Tuple of average TPP values (nil if no data)
    func getAverageTPP(from: Int64, to: Int64, model: String?, source: MeasurementSource?) async throws -> (fiveHour: Double?, sevenDay: Double?)

    /// Deletes all backfill records (passive-backfill and rollup-backfill sources).
    /// Used by the force re-run backfill feature.
    func deleteBackfillRecords() async throws
}
