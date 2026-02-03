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

    /// Threshold for fallback reset detection: 50% absolute drop
    private let utilizationDropThreshold: Double = 50.0

    /// Creates a HistoricalDataService with the specified database manager.
    /// - Parameter databaseManager: The database manager for persistence operations
    init(databaseManager: any DatabaseManagerProtocol) {
        self.databaseManager = databaseManager
    }

    // MARK: - HistoricalDataServiceProtocol

    func persistPoll(_ response: UsageResponse) async throws {
        // Delegate to the new overload with nil tier for backward compatibility
        try await persistPoll(response, tier: nil)
    }

    func persistPoll(_ response: UsageResponse, tier: String?) async throws {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - skipping poll persistence")
            return
        }

        let connection = try databaseManager.getConnection()

        // Get previous poll BEFORE inserting new one (for reset detection)
        let previousPoll = try await getLastPoll()

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

        // Check for reset event after persisting poll
        if let previousPoll = previousPoll {
            let currentPoll = UsagePoll(
                id: 0,
                timestamp: timestamp,
                fiveHourUtil: fiveHourUtil,
                fiveHourResetsAt: fiveHourResetsAt,
                sevenDayUtil: sevenDayUtil,
                sevenDayResetsAt: sevenDayResetsAt
            )
            try await detectAndRecordResetIfNeeded(
                currentPoll: currentPoll,
                previousPoll: previousPoll,
                tier: tier,
                connection: connection
            )
        }
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

    func getLastPoll() async throws -> UsagePoll? {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - returning nil for last poll")
            return nil
        }

        let connection = try databaseManager.getConnection()

        let sql = """
            SELECT id, timestamp, five_hour_util, five_hour_resets_at, seven_day_util, seven_day_resets_at
            FROM usage_polls
            ORDER BY timestamp DESC
            LIMIT 1
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
            Self.logger.error("Failed to prepare getLastPoll statement: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            Self.logger.debug("No previous polls found")
            return nil
        }

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

        return UsagePoll(
            id: id,
            timestamp: timestamp,
            fiveHourUtil: fiveHourUtil,
            fiveHourResetsAt: fiveHourResetsAt,
            sevenDayUtil: sevenDayUtil,
            sevenDayResetsAt: sevenDayResetsAt
        )
    }

    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent] {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - returning empty reset events list")
            return []
        }

        let connection = try databaseManager.getConnection()

        let sql = """
            SELECT id, timestamp, five_hour_peak, seven_day_util, tier, used_credits, constrained_credits, waste_credits
            FROM reset_events
            WHERE timestamp >= COALESCE(?, 0)
              AND timestamp <= COALESCE(?, 9223372036854775807)
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
            Self.logger.error("Failed to prepare getResetEvents statement: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        // Bind optional parameters
        if let from = fromTimestamp {
            sqlite3_bind_int64(statement, 1, from)
        } else {
            sqlite3_bind_null(statement, 1)
        }

        if let to = toTimestamp {
            sqlite3_bind_int64(statement, 2, to)
        } else {
            sqlite3_bind_null(statement, 2)
        }

        var events: [ResetEvent] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let timestamp = sqlite3_column_int64(statement, 1)
            let fiveHourPeak: Double? = sqlite3_column_type(statement, 2) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 2)
            let sevenDayUtil: Double? = sqlite3_column_type(statement, 3) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 3)
            let tier: String? = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : String(cString: sqlite3_column_text(statement, 4))
            let usedCredits: Double? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 5)
            let constrainedCredits: Double? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 6)
            let wasteCredits: Double? = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 7)

            events.append(ResetEvent(
                id: id,
                timestamp: timestamp,
                fiveHourPeak: fiveHourPeak,
                sevenDayUtil: sevenDayUtil,
                tier: tier,
                usedCredits: usedCredits,
                constrainedCredits: constrainedCredits,
                wasteCredits: wasteCredits
            ))
        }

        Self.logger.debug("Retrieved \(events.count, privacy: .public) reset events")
        return events
    }

    // MARK: - Private Reset Detection

    /// Detects if a reset occurred and records it if so.
    private func detectAndRecordResetIfNeeded(
        currentPoll: UsagePoll,
        previousPoll: UsagePoll,
        tier: String?,
        connection: OpaquePointer
    ) async throws {
        let resetDetected: Bool
        let detectionMethod: String

        // Primary detection: resets_at timestamp shift
        if let currentResetsAt = currentPoll.fiveHourResetsAt,
           let previousResetsAt = previousPoll.fiveHourResetsAt,
           currentResetsAt != previousResetsAt {
            resetDetected = true
            detectionMethod = "resets_at shifted from \(previousResetsAt) to \(currentResetsAt)"
        }
        // Fallback detection: large utilization drop
        else if let currentUtil = currentPoll.fiveHourUtil,
                let previousUtil = previousPoll.fiveHourUtil,
                currentPoll.fiveHourResetsAt == nil || previousPoll.fiveHourResetsAt == nil {
            let drop = previousUtil - currentUtil
            if drop >= utilizationDropThreshold {
                resetDetected = true
                detectionMethod = "utilization dropped from \(previousUtil)% to \(currentUtil)%"
            } else {
                resetDetected = false
                detectionMethod = ""
            }
        } else {
            resetDetected = false
            detectionMethod = ""
        }

        guard resetDetected else { return }

        // Calculate peak utilization from recent polls (last 5 hours)
        let peakUtil = try await getRecentPeakUtilization(beforeTimestamp: currentPoll.timestamp, connection: connection)

        // Record the reset event
        // Use previousPoll's 7d util - represents the constraint at window end (pre-reset)
        try recordResetEvent(
            timestamp: currentPoll.timestamp,
            fiveHourPeak: peakUtil,
            sevenDayUtil: previousPoll.sevenDayUtil,
            tier: tier,
            connection: connection
        )

        Self.logger.info("Reset detected: \(detectionMethod, privacy: .public)")
        Self.logger.info("Reset event recorded: peak=\(peakUtil ?? -1, privacy: .public)%, 7d=\(currentPoll.sevenDayUtil ?? -1, privacy: .public)%, tier=\(tier ?? "unknown", privacy: .public)")
    }

    /// Queries the maximum 5-hour utilization from polls within the last 5 hours.
    /// - Parameters:
    ///   - beforeTimestamp: Upper bound timestamp (Unix ms), exclusive
    ///   - connection: Active SQLite connection
    /// - Returns: Peak utilization percentage (0-100), or nil if no polls in range
    private func getRecentPeakUtilization(beforeTimestamp: Int64, connection: OpaquePointer) async throws -> Double? {
        let fiveHoursMs: Int64 = 5 * 60 * 60 * 1000
        let cutoff = beforeTimestamp - fiveHoursMs

        let sql = "SELECT MAX(five_hour_util) FROM usage_polls WHERE timestamp >= ? AND timestamp < ?"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to prepare peak utilization query: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, cutoff)
        sqlite3_bind_int64(statement, 2, beforeTimestamp)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return nil
        }

        return sqlite3_column_double(statement, 0)
    }

    /// Records a reset event in the database.
    private func recordResetEvent(
        timestamp: Int64,
        fiveHourPeak: Double?,
        sevenDayUtil: Double?,
        tier: String?,
        connection: OpaquePointer
    ) throws {
        let sql = """
            INSERT INTO reset_events (
                timestamp,
                five_hour_peak,
                seven_day_util,
                tier,
                used_credits,
                constrained_credits,
                waste_credits
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
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
            Self.logger.error("Failed to prepare reset event INSERT: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        // Bind values
        sqlite3_bind_int64(statement, 1, timestamp)

        if let peak = fiveHourPeak {
            sqlite3_bind_double(statement, 2, peak)
        } else {
            sqlite3_bind_null(statement, 2)
        }

        if let util = sevenDayUtil {
            sqlite3_bind_double(statement, 3, util)
        } else {
            sqlite3_bind_null(statement, 3)
        }

        if let tierStr = tier {
            // Use SQLITE_TRANSIENT for temporary Swift strings
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 4, tierStr, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }

        // Credit fields are NULL until Epic 14
        sqlite3_bind_null(statement, 5)  // used_credits
        sqlite3_bind_null(statement, 6)  // constrained_credits
        sqlite3_bind_null(statement, 7)  // waste_credits

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            Self.logger.error("Failed to execute reset event INSERT: \(errorMessage, privacy: .public)")
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }
    }
}
