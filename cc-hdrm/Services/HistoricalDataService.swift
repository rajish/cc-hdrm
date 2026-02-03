import Foundation
import os
import SQLite3

/// Service responsible for persisting and retrieving historical poll data.
/// Implements graceful degradation: if database is unavailable, operations are skipped silently.
final class HistoricalDataService: HistoricalDataServiceProtocol, @unchecked Sendable {
    private let databaseManager: any DatabaseManagerProtocol

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "historical"
    )

    /// Creates a HistoricalDataService with the specified database manager.
    /// - Parameter databaseManager: The database manager for persistence operations
    init(databaseManager: any DatabaseManagerProtocol) {
        self.databaseManager = databaseManager
    }

    // MARK: - HistoricalDataServiceProtocol

    func persistPoll(_ response: UsageResponse) async throws {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - skipping poll persistence")
            return
        }

        let connection = try databaseManager.getConnection()

        // Generate current timestamp in Unix milliseconds
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // Extract and convert values from response
        let fiveHourUtil = response.fiveHour?.utilization
        let fiveHourResetsAt = response.fiveHour?.resetsAt
            .flatMap { Date.fromISO8601($0) }
            .map { Int64($0.timeIntervalSince1970 * 1000) }

        let sevenDayUtil = response.sevenDay?.utilization
        let sevenDayResetsAt = response.sevenDay?.resetsAt
            .flatMap { Date.fromISO8601($0) }
            .map { Int64($0.timeIntervalSince1970 * 1000) }

        // Prepare INSERT statement
        let sql = """
            INSERT INTO usage_polls (
                timestamp,
                five_hour_util,
                five_hour_resets_at,
                seven_day_util,
                seven_day_resets_at
            ) VALUES (?, ?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to prepare INSERT statement: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        // Bind values
        sqlite3_bind_int64(statement, 1, timestamp)

        if let util = fiveHourUtil {
            sqlite3_bind_double(statement, 2, util)
        } else {
            sqlite3_bind_null(statement, 2)
        }

        if let resetsAt = fiveHourResetsAt {
            sqlite3_bind_int64(statement, 3, resetsAt)
        } else {
            sqlite3_bind_null(statement, 3)
        }

        if let util = sevenDayUtil {
            sqlite3_bind_double(statement, 4, util)
        } else {
            sqlite3_bind_null(statement, 4)
        }

        if let resetsAt = sevenDayResetsAt {
            sqlite3_bind_int64(statement, 5, resetsAt)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        // Execute
        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to execute INSERT: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }

        Self.logger.debug("Poll persisted: timestamp=\(timestamp), 5h=\(fiveHourUtil ?? -1, privacy: .public)%, 7d=\(sevenDayUtil ?? -1, privacy: .public)%")
    }

    func getRecentPolls(hours: Int) async throws -> [UsagePoll] {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - returning empty poll list")
            return []
        }

        let connection = try databaseManager.getConnection()

        // Calculate cutoff timestamp
        let cutoffMs = Int64((Date().timeIntervalSince1970 - Double(hours * 3600)) * 1000)

        let sql = """
            SELECT id, timestamp, five_hour_util, five_hour_resets_at, seven_day_util, seven_day_resets_at
            FROM usage_polls
            WHERE timestamp >= ?
            ORDER BY timestamp ASC
            """

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to prepare SELECT statement: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        var polls: [UsagePoll] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let timestamp = sqlite3_column_int64(statement, 1)

            let fiveHourUtil: Double? = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 2)
            let fiveHourResetsAt: Int64? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 3)
            let sevenDayUtil: Double? = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 4)
            let sevenDayResetsAt: Int64? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, 5)

            polls.append(UsagePoll(
                id: id,
                timestamp: timestamp,
                fiveHourUtil: fiveHourUtil,
                fiveHourResetsAt: fiveHourResetsAt,
                sevenDayUtil: sevenDayUtil,
                sevenDayResetsAt: sevenDayResetsAt
            ))
        }

        Self.logger.debug("Retrieved \(polls.count, privacy: .public) polls from last \(hours, privacy: .public) hours")
        return polls
    }

    func getDatabaseSize() async throws -> Int64 {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - returning 0 for size")
            return 0
        }

        let path = databaseManager.getDatabasePath()
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            let size = attributes[FileAttributeKey.size] as? Int64 ?? 0
            Self.logger.debug("Database size: \(size, privacy: .public) bytes")
            return size
        } catch {
            Self.logger.error("Failed to get database size: \(error.localizedDescription, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: error)
        }
    }
}
