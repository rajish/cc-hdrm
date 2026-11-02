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
    /// - Returns: The average of 5-hour rows and the average of weekly rows (nil if no data). Bases are never combined.
    func getAverageTPP(from: Int64, to: Int64, model: String?, source: MeasurementSource?) async throws -> (fiveHour: Double?, sevenDay: Double?)

    /// Deletes the 5-hour backfill records a force re-run is about to rebuild, so rows it cannot rebuild survive.
    /// Weekly rows are never deleted: a rebuild starts unanchored and cannot recreate its first step.
    /// - Parameters:
    ///   - passiveFrom: Deletes passive-backfill rows at or after this time. Nil deletes none.
    ///   - rollupFrom: Deletes rollup-backfill rows at or after this time. Nil deletes none.
    func deleteBackfillRecords(passiveFrom: Int64?, rollupFrom: Int64?) async throws
}
