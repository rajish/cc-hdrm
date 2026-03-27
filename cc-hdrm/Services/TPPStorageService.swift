import Foundation
import os
import SQLite3

/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string data.
private let SQLITE_TRANSIENT_TPP = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Persists and retrieves TPP measurement results using the SQLite database.
/// Follows the same graceful degradation pattern as HistoricalDataService.
final class TPPStorageService: TPPStorageServiceProtocol, @unchecked Sendable {
    private let databaseManager: any DatabaseManagerProtocol

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "tpp-storage"
    )

    init(databaseManager: any DatabaseManagerProtocol) {
        self.databaseManager = databaseManager
    }

    func storeBenchmarkResult(_ measurement: TPPMeasurement) async throws {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - skipping TPP measurement persistence")
            return
        }

        let connection = try databaseManager.getConnection()

        let sql = """
            INSERT INTO tpp_measurements (
                timestamp, window_start, model, variant, source,
                five_hour_before, five_hour_after, five_hour_delta,
                seven_day_before, seven_day_after, seven_day_delta,
                input_tokens, output_tokens, cache_create_tokens, cache_read_tokens,
                total_raw_tokens, tpp_five_hour, tpp_seven_day, confidence, message_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        defer {
            if let statement { sqlite3_finalize(statement) }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to prepare INSERT: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, measurement.timestamp)
        bindOptionalInt64(statement, 2, measurement.windowStart)
        bindText(statement, 3, measurement.model)
        bindOptionalText(statement, 4, measurement.variant)
        bindText(statement, 5, measurement.source.rawValue)
        bindOptionalDouble(statement, 6, measurement.fiveHourBefore)
        bindOptionalDouble(statement, 7, measurement.fiveHourAfter)
        bindOptionalDouble(statement, 8, measurement.fiveHourDelta)
        bindOptionalDouble(statement, 9, measurement.sevenDayBefore)
        bindOptionalDouble(statement, 10, measurement.sevenDayAfter)
        bindOptionalDouble(statement, 11, measurement.sevenDayDelta)
        sqlite3_bind_int(statement, 12, Int32(measurement.inputTokens))
        sqlite3_bind_int(statement, 13, Int32(measurement.outputTokens))
        sqlite3_bind_int(statement, 14, Int32(measurement.cacheCreateTokens))
        sqlite3_bind_int(statement, 15, Int32(measurement.cacheReadTokens))
        sqlite3_bind_int(statement, 16, Int32(measurement.totalRawTokens))
        bindOptionalDouble(statement, 17, measurement.tppFiveHour)
        bindOptionalDouble(statement, 18, measurement.tppSevenDay)
        bindText(statement, 19, measurement.confidence.rawValue)
        sqlite3_bind_int(statement, 20, Int32(measurement.messageCount))

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to INSERT measurement: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }

        Self.logger.info("Stored TPP measurement: model=\(measurement.model, privacy: .public) source=\(measurement.source.rawValue, privacy: .public)")
    }

    func latestBenchmark(model: String, variant: String?) async throws -> TPPMeasurement? {
        guard databaseManager.isAvailable else { return nil }

        let connection = try databaseManager.getConnection()

        let sql: String
        if variant != nil {
            sql = """
                SELECT * FROM tpp_measurements
                WHERE model = ? AND variant = ? AND source = 'benchmark'
                ORDER BY timestamp DESC LIMIT 1
                """
        } else {
            sql = """
                SELECT * FROM tpp_measurements
                WHERE model = ? AND source = 'benchmark'
                ORDER BY timestamp DESC LIMIT 1
                """
        }

        var statement: OpaquePointer?
        defer {
            if let statement { sqlite3_finalize(statement) }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        bindText(statement, 1, model)
        if let variant {
            bindText(statement, 2, variant)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        return readMeasurement(from: statement!)
    }

    func lastBenchmarkTimestamp() async throws -> Int64? {
        guard databaseManager.isAvailable else { return nil }

        let connection = try databaseManager.getConnection()

        let sql = "SELECT MAX(timestamp) FROM tpp_measurements WHERE source = 'benchmark'"

        var statement: OpaquePointer?
        defer {
            if let statement { sqlite3_finalize(statement) }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }

        return sqlite3_column_int64(statement, 0)
    }

    // MARK: - Private Helpers

    private func readMeasurement(from statement: OpaquePointer) -> TPPMeasurement {
        let confidenceStr = String(cString: sqlite3_column_text(statement, 19))
        let sourceStr = String(cString: sqlite3_column_text(statement, 5))

        return TPPMeasurement(
            id: sqlite3_column_int64(statement, 0),
            timestamp: sqlite3_column_int64(statement, 1),
            windowStart: sqlite3_column_type(statement, 2) != SQLITE_NULL ? sqlite3_column_int64(statement, 2) : nil,
            model: String(cString: sqlite3_column_text(statement, 3)),
            variant: sqlite3_column_type(statement, 4) != SQLITE_NULL ? String(cString: sqlite3_column_text(statement, 4)) : nil,
            source: MeasurementSource(rawValue: sourceStr) ?? .benchmark,
            fiveHourBefore: sqlite3_column_type(statement, 6) != SQLITE_NULL ? sqlite3_column_double(statement, 6) : nil,
            fiveHourAfter: sqlite3_column_type(statement, 7) != SQLITE_NULL ? sqlite3_column_double(statement, 7) : nil,
            fiveHourDelta: sqlite3_column_type(statement, 8) != SQLITE_NULL ? sqlite3_column_double(statement, 8) : nil,
            sevenDayBefore: sqlite3_column_type(statement, 9) != SQLITE_NULL ? sqlite3_column_double(statement, 9) : nil,
            sevenDayAfter: sqlite3_column_type(statement, 10) != SQLITE_NULL ? sqlite3_column_double(statement, 10) : nil,
            sevenDayDelta: sqlite3_column_type(statement, 11) != SQLITE_NULL ? sqlite3_column_double(statement, 11) : nil,
            inputTokens: Int(sqlite3_column_int(statement, 12)),
            outputTokens: Int(sqlite3_column_int(statement, 13)),
            cacheCreateTokens: Int(sqlite3_column_int(statement, 14)),
            cacheReadTokens: Int(sqlite3_column_int(statement, 15)),
            totalRawTokens: Int(sqlite3_column_int(statement, 16)),
            tppFiveHour: sqlite3_column_type(statement, 17) != SQLITE_NULL ? sqlite3_column_double(statement, 17) : nil,
            tppSevenDay: sqlite3_column_type(statement, 18) != SQLITE_NULL ? sqlite3_column_double(statement, 18) : nil,
            confidence: MeasurementConfidence(rawValue: confidenceStr) ?? .high,
            messageCount: Int(sqlite3_column_int(statement, 20))
        )
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        value.withCString { cString in
            sqlite3_bind_text(statement, index, cString, -1, SQLITE_TRANSIENT_TPP)
        }
    }

    private func bindOptionalText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            bindText(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalDouble(_ statement: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalInt64(_ statement: OpaquePointer?, _ index: Int32, _ value: Int64?) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }
}
