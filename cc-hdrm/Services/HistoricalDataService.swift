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
        Self.logger.info("Reset event recorded: peak=\(peakUtil ?? -1, privacy: .public)%, 7d=\(previousPoll.sevenDayUtil ?? -1, privacy: .public)%, tier=\(tier ?? "unknown", privacy: .public)")
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

    // MARK: - Story 10.4: Tiered Rollup Engine

    /// Time constants in milliseconds
    private static let fiveMinutesMs: Int64 = 5 * 60 * 1000
    private static let oneHourMs: Int64 = 60 * 60 * 1000
    private static let oneDayMs: Int64 = 24 * 60 * 60 * 1000
    private static let sevenDaysMs: Int64 = 7 * oneDayMs
    private static let thirtyDaysMs: Int64 = 30 * oneDayMs

    /// Default data retention period in days (used when pruning old data)
    private static let defaultRetentionDays: Int = 90

    /// SQLITE_TRANSIENT tells SQLite to make its own copy of the string data.
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    // MARK: - Rollup Metadata Helpers

    /// Gets the last rollup timestamp from metadata.
    /// - Parameter connection: Active SQLite connection
    /// - Returns: Unix milliseconds of last rollup, or nil if never run
    private func getLastRollupTimestamp(connection: OpaquePointer) throws -> Int64? {
        let sql = "SELECT value FROM rollup_metadata WHERE key = 'last_rollup_timestamp'"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else {
            return nil
        }

        let valueString = String(cString: sqlite3_column_text(statement, 0))
        return Int64(valueString)
    }

    /// Sets the last rollup timestamp in metadata.
    /// - Parameters:
    ///   - timestamp: Unix milliseconds of last rollup
    ///   - connection: Active SQLite connection
    private func setLastRollupTimestamp(_ timestamp: Int64, connection: OpaquePointer) throws {
        let sql = "INSERT OR REPLACE INTO rollup_metadata (key, value) VALUES ('last_rollup_timestamp', ?)"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        let timestampString = String(timestamp)
        timestampString.withCString { cString in
            sqlite3_bind_text(statement, 1, cString, -1, Self.SQLITE_TRANSIENT)
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }
    }

    func ensureRollupsUpToDate() async throws {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - skipping rollup")
            return
        }

        let startTime = CFAbsoluteTimeGetCurrent()
        let connection = try databaseManager.getConnection()

        // Check last rollup timestamp (Task 7.1)
        let lastRollup = try getLastRollupTimestamp(connection: connection)
        if let lastRollup = lastRollup {
            Self.logger.debug("Last rollup timestamp: \(lastRollup, privacy: .public)")
        }

        // Begin transaction for atomicity
        guard sqlite3_exec(connection, "BEGIN TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: "Failed to begin transaction"))
        }

        do {
            // Execute rollups in order: raw->5min, 5min->hourly, hourly->daily (Task 7.2)
            try await performRawTo5MinRollup(connection: connection)
            try await perform5MinToHourlyRollup(connection: connection)
            try await performHourlyToDailyRollup(connection: connection)

            // Prune old data as final step (Task 9.4)
            try await performPruneOldData(retentionDays: Self.defaultRetentionDays, connection: connection)

            // Update last rollup timestamp after successful completion (Task 7.4)
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            try setLastRollupTimestamp(nowMs, connection: connection)

            // Commit transaction (Task 7.3 - atomicity)
            guard sqlite3_exec(connection, "COMMIT", nil, nil, nil) == SQLITE_OK else {
                throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: "Failed to commit transaction"))
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            Self.logger.debug("Rollup completed in \(elapsed, privacy: .public)ms")
        } catch {
            // Rollback on any error
            sqlite3_exec(connection, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }

    func getRolledUpData(range: TimeRange) async throws -> [UsageRollup] {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - returning empty rollup list")
            return []
        }
        // Implementation in Task 8
        let connection = try databaseManager.getConnection()
        return try await queryRolledUpData(range: range, connection: connection)
    }

    func pruneOldData(retentionDays: Int) async throws {
        guard databaseManager.isAvailable else {
            Self.logger.debug("Database unavailable - skipping prune")
            return
        }
        let connection = try databaseManager.getConnection()
        try await performPruneOldData(retentionDays: retentionDays, connection: connection)
    }

    // MARK: - Time Bucket Calculations

    /// Returns the start of the 5-minute bucket containing the timestamp.
    private func fiveMinuteBucketStart(for timestamp: Int64) -> Int64 {
        return (timestamp / Self.fiveMinutesMs) * Self.fiveMinutesMs
    }

    /// Returns the start of the hourly bucket containing the timestamp.
    private func hourlyBucketStart(for timestamp: Int64) -> Int64 {
        return (timestamp / Self.oneHourMs) * Self.oneHourMs
    }

    /// Returns the start of the daily bucket (UTC midnight) containing the timestamp.
    private func dailyBucketStart(for timestamp: Int64) -> Int64 {
        return (timestamp / Self.oneDayMs) * Self.oneDayMs
    }

    // MARK: - Task 4: Raw to 5-Minute Rollup

    /// Rolls up raw polls from 24h-7d ago into 5-minute aggregates.
    private func performRawTo5MinRollup(connection: OpaquePointer) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let twentyFourHoursAgo = nowMs - Self.oneDayMs
        let sevenDaysAgo = nowMs - Self.sevenDaysMs

        // Query raw polls in the rollup window (24h-7d ago)
        let polls = try queryRawPollsForRollup(
            from: sevenDaysAgo,
            to: twentyFourHoursAgo,
            connection: connection
        )

        guard !polls.isEmpty else {
            Self.logger.debug("No raw polls to roll up (24h-7d window)")
            return
        }

        // Group polls by 5-minute bucket
        var buckets: [Int64: [UsagePoll]] = [:]
        for poll in polls {
            let bucketStart = fiveMinuteBucketStart(for: poll.timestamp)
            buckets[bucketStart, default: []].append(poll)
        }

        // Create rollup for each bucket
        for (bucketStart, bucketPolls) in buckets {
            let bucketEnd = bucketStart + Self.fiveMinutesMs

            // Calculate aggregates
            let fiveHourValues = bucketPolls.compactMap { $0.fiveHourUtil }
            let sevenDayValues = bucketPolls.compactMap { $0.sevenDayUtil }

            let fiveHourAvg = fiveHourValues.isEmpty ? nil : fiveHourValues.reduce(0, +) / Double(fiveHourValues.count)
            let fiveHourPeak = fiveHourValues.max()
            let fiveHourMin = fiveHourValues.min()

            let sevenDayAvg = sevenDayValues.isEmpty ? nil : sevenDayValues.reduce(0, +) / Double(sevenDayValues.count)
            let sevenDayPeak = sevenDayValues.max()
            let sevenDayMin = sevenDayValues.min()

            // Count reset events in this bucket
            let resetCount = try countResetEvents(from: bucketStart, to: bucketEnd, connection: connection)

            // Insert rollup row
            try insertRollup(
                periodStart: bucketStart,
                periodEnd: bucketEnd,
                resolution: .fiveMin,
                fiveHourAvg: fiveHourAvg,
                fiveHourPeak: fiveHourPeak,
                fiveHourMin: fiveHourMin,
                sevenDayAvg: sevenDayAvg,
                sevenDayPeak: sevenDayPeak,
                sevenDayMin: sevenDayMin,
                resetCount: resetCount,
                wasteCredits: nil,
                connection: connection
            )
        }

        // Delete original raw polls after successful rollup
        try deleteRawPolls(from: sevenDaysAgo, to: twentyFourHoursAgo, connection: connection)

        Self.logger.info("Rolled up \(polls.count, privacy: .public) raw polls into \(buckets.count, privacy: .public) 5-minute rollups")
    }

    /// Queries raw polls in a time range for rollup processing.
    private func queryRawPollsForRollup(from: Int64, to: Int64, connection: OpaquePointer) throws -> [UsagePoll] {
        let sql = """
            SELECT id, timestamp, five_hour_util, five_hour_resets_at, seven_day_util, seven_day_resets_at
            FROM usage_polls
            WHERE timestamp >= ? AND timestamp < ?
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
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, from)
        sqlite3_bind_int64(statement, 2, to)

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

        return polls
    }

    /// Counts reset events in a time range.
    private func countResetEvents(from: Int64, to: Int64, connection: OpaquePointer) throws -> Int {
        let sql = "SELECT COUNT(*) FROM reset_events WHERE timestamp >= ? AND timestamp < ?"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, from)
        sqlite3_bind_int64(statement, 2, to)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// Inserts a rollup row into usage_rollups table.
    private func insertRollup(
        periodStart: Int64,
        periodEnd: Int64,
        resolution: UsageRollup.Resolution,
        fiveHourAvg: Double?,
        fiveHourPeak: Double?,
        fiveHourMin: Double?,
        sevenDayAvg: Double?,
        sevenDayPeak: Double?,
        sevenDayMin: Double?,
        resetCount: Int,
        wasteCredits: Double?,
        connection: OpaquePointer
    ) throws {
        let sql = """
            INSERT INTO usage_rollups (
                period_start, period_end, resolution,
                five_hour_avg, five_hour_peak, five_hour_min,
                seven_day_avg, seven_day_peak, seven_day_min,
                reset_count, waste_credits
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, periodStart)
        sqlite3_bind_int64(statement, 2, periodEnd)

        resolution.rawValue.withCString { cString in
            sqlite3_bind_text(statement, 3, cString, -1, Self.SQLITE_TRANSIENT)
        }

        if let avg = fiveHourAvg { sqlite3_bind_double(statement, 4, avg) }
        else { sqlite3_bind_null(statement, 4) }

        if let peak = fiveHourPeak { sqlite3_bind_double(statement, 5, peak) }
        else { sqlite3_bind_null(statement, 5) }

        if let min = fiveHourMin { sqlite3_bind_double(statement, 6, min) }
        else { sqlite3_bind_null(statement, 6) }

        if let avg = sevenDayAvg { sqlite3_bind_double(statement, 7, avg) }
        else { sqlite3_bind_null(statement, 7) }

        if let peak = sevenDayPeak { sqlite3_bind_double(statement, 8, peak) }
        else { sqlite3_bind_null(statement, 8) }

        if let min = sevenDayMin { sqlite3_bind_double(statement, 9, min) }
        else { sqlite3_bind_null(statement, 9) }

        sqlite3_bind_int(statement, 10, Int32(resetCount))

        if let waste = wasteCredits { sqlite3_bind_double(statement, 11, waste) }
        else { sqlite3_bind_null(statement, 11) }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }
    }

    /// Deletes raw polls in a time range after successful rollup.
    private func deleteRawPolls(from: Int64, to: Int64, connection: OpaquePointer) throws {
        let sql = "DELETE FROM usage_polls WHERE timestamp >= ? AND timestamp < ?"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, from)
        sqlite3_bind_int64(statement, 2, to)

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }
    }

    // MARK: - Task 5: 5-Minute to Hourly Rollup

    /// Rolls up 5-minute rollups from 7d-30d ago into hourly aggregates.
    private func perform5MinToHourlyRollup(connection: OpaquePointer) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sevenDaysAgo = nowMs - Self.sevenDaysMs
        let thirtyDaysAgo = nowMs - Self.thirtyDaysMs

        // Query 5-minute rollups in the rollup window (7d-30d ago)
        let rollups = try queryRollupsForRollup(
            resolution: .fiveMin,
            from: thirtyDaysAgo,
            to: sevenDaysAgo,
            connection: connection
        )

        guard !rollups.isEmpty else {
            Self.logger.debug("No 5-minute rollups to aggregate (7d-30d window)")
            return
        }

        // Group by hourly bucket
        var buckets: [Int64: [UsageRollup]] = [:]
        for rollup in rollups {
            let bucketStart = hourlyBucketStart(for: rollup.periodStart)
            buckets[bucketStart, default: []].append(rollup)
        }

        // Create rollup for each bucket
        for (bucketStart, bucketRollups) in buckets {
            let bucketEnd = bucketStart + Self.oneHourMs

            // Aggregate: avg of avgs, max of peaks, min of mins
            let fiveHourAvgs = bucketRollups.compactMap { $0.fiveHourAvg }
            let fiveHourPeaks = bucketRollups.compactMap { $0.fiveHourPeak }
            let fiveHourMins = bucketRollups.compactMap { $0.fiveHourMin }
            let sevenDayAvgs = bucketRollups.compactMap { $0.sevenDayAvg }
            let sevenDayPeaks = bucketRollups.compactMap { $0.sevenDayPeak }
            let sevenDayMins = bucketRollups.compactMap { $0.sevenDayMin }

            let fiveHourAvg = fiveHourAvgs.isEmpty ? nil : fiveHourAvgs.reduce(0, +) / Double(fiveHourAvgs.count)
            let fiveHourPeak = fiveHourPeaks.max()
            let fiveHourMin = fiveHourMins.min()

            let sevenDayAvg = sevenDayAvgs.isEmpty ? nil : sevenDayAvgs.reduce(0, +) / Double(sevenDayAvgs.count)
            let sevenDayPeak = sevenDayPeaks.max()
            let sevenDayMin = sevenDayMins.min()

            // Sum reset counts
            let resetCount = bucketRollups.reduce(0) { $0 + $1.resetCount }

            try insertRollup(
                periodStart: bucketStart,
                periodEnd: bucketEnd,
                resolution: .hourly,
                fiveHourAvg: fiveHourAvg,
                fiveHourPeak: fiveHourPeak,
                fiveHourMin: fiveHourMin,
                sevenDayAvg: sevenDayAvg,
                sevenDayPeak: sevenDayPeak,
                sevenDayMin: sevenDayMin,
                resetCount: resetCount,
                wasteCredits: nil,
                connection: connection
            )
        }

        // Delete original 5-minute rollups
        try deleteRollups(resolution: .fiveMin, from: thirtyDaysAgo, to: sevenDaysAgo, connection: connection)

        Self.logger.info("Rolled up \(rollups.count, privacy: .public) 5-minute rollups into \(buckets.count, privacy: .public) hourly rollups")
    }

    // MARK: - Task 6: Hourly to Daily Rollup

    /// Rolls up hourly rollups from 30d+ ago into daily aggregates.
    private func performHourlyToDailyRollup(connection: OpaquePointer) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let thirtyDaysAgo = nowMs - Self.thirtyDaysMs

        // Query hourly rollups older than 30 days
        let rollups = try queryRollupsForRollup(
            resolution: .hourly,
            from: 0,
            to: thirtyDaysAgo,
            connection: connection
        )

        guard !rollups.isEmpty else {
            Self.logger.debug("No hourly rollups to aggregate (30d+ window)")
            return
        }

        // Group by daily bucket (UTC midnight)
        var buckets: [Int64: [UsageRollup]] = [:]
        for rollup in rollups {
            let bucketStart = dailyBucketStart(for: rollup.periodStart)
            buckets[bucketStart, default: []].append(rollup)
        }

        // Create rollup for each bucket
        for (bucketStart, bucketRollups) in buckets {
            let bucketEnd = bucketStart + Self.oneDayMs

            // Aggregate: avg of avgs, max of peaks, min of mins
            let fiveHourAvgs = bucketRollups.compactMap { $0.fiveHourAvg }
            let fiveHourPeaks = bucketRollups.compactMap { $0.fiveHourPeak }
            let fiveHourMins = bucketRollups.compactMap { $0.fiveHourMin }
            let sevenDayAvgs = bucketRollups.compactMap { $0.sevenDayAvg }
            let sevenDayPeaks = bucketRollups.compactMap { $0.sevenDayPeak }
            let sevenDayMins = bucketRollups.compactMap { $0.sevenDayMin }

            let fiveHourAvg = fiveHourAvgs.isEmpty ? nil : fiveHourAvgs.reduce(0, +) / Double(fiveHourAvgs.count)
            let fiveHourPeak = fiveHourPeaks.max()
            let fiveHourMin = fiveHourMins.min()

            let sevenDayAvg = sevenDayAvgs.isEmpty ? nil : sevenDayAvgs.reduce(0, +) / Double(sevenDayAvgs.count)
            let sevenDayPeak = sevenDayPeaks.max()
            let sevenDayMin = sevenDayMins.min()

            // Sum reset counts and waste credits
            let resetCount = bucketRollups.reduce(0) { $0 + $1.resetCount }
            let wasteCreditsValues = bucketRollups.compactMap { $0.wasteCredits }
            let wasteCredits = wasteCreditsValues.isEmpty ? nil : wasteCreditsValues.reduce(0, +)

            // Also sum waste_credits from reset_events in this day
            let dailyWasteCredits = try sumWasteCredits(from: bucketStart, to: bucketEnd, connection: connection)
            let totalWasteCredits: Double?
            if wasteCredits != nil || dailyWasteCredits != nil {
                totalWasteCredits = (wasteCredits ?? 0) + (dailyWasteCredits ?? 0)
            } else {
                totalWasteCredits = nil
            }

            try insertRollup(
                periodStart: bucketStart,
                periodEnd: bucketEnd,
                resolution: .daily,
                fiveHourAvg: fiveHourAvg,
                fiveHourPeak: fiveHourPeak,
                fiveHourMin: fiveHourMin,
                sevenDayAvg: sevenDayAvg,
                sevenDayPeak: sevenDayPeak,
                sevenDayMin: sevenDayMin,
                resetCount: resetCount,
                wasteCredits: totalWasteCredits,
                connection: connection
            )
        }

        // Delete original hourly rollups
        try deleteRollups(resolution: .hourly, from: 0, to: thirtyDaysAgo, connection: connection)

        Self.logger.info("Rolled up \(rollups.count, privacy: .public) hourly rollups into \(buckets.count, privacy: .public) daily rollups")
    }

    /// Queries rollups of a specific resolution in a time range.
    private func queryRollupsForRollup(
        resolution: UsageRollup.Resolution,
        from: Int64,
        to: Int64,
        connection: OpaquePointer
    ) throws -> [UsageRollup] {
        let sql = """
            SELECT id, period_start, period_end, resolution,
                   five_hour_avg, five_hour_peak, five_hour_min,
                   seven_day_avg, seven_day_peak, seven_day_min,
                   reset_count, waste_credits
            FROM usage_rollups
            WHERE resolution = ? AND period_start >= ? AND period_start < ?
            ORDER BY period_start ASC
            """

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        resolution.rawValue.withCString { cString in
            sqlite3_bind_text(statement, 1, cString, -1, Self.SQLITE_TRANSIENT)
        }
        sqlite3_bind_int64(statement, 2, from)
        sqlite3_bind_int64(statement, 3, to)

        var rollups: [UsageRollup] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let periodStart = sqlite3_column_int64(statement, 1)
            let periodEnd = sqlite3_column_int64(statement, 2)
            let resolutionStr = String(cString: sqlite3_column_text(statement, 3))
            let resolutionValue = UsageRollup.Resolution(rawValue: resolutionStr) ?? resolution

            let fiveHourAvg: Double? = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 4)
            let fiveHourPeak: Double? = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 5)
            let fiveHourMin: Double? = sqlite3_column_type(statement, 6) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 6)
            let sevenDayAvg: Double? = sqlite3_column_type(statement, 7) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 7)
            let sevenDayPeak: Double? = sqlite3_column_type(statement, 8) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 8)
            let sevenDayMin: Double? = sqlite3_column_type(statement, 9) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 9)
            let resetCount = Int(sqlite3_column_int(statement, 10))
            let wasteCredits: Double? = sqlite3_column_type(statement, 11) == SQLITE_NULL
                ? nil : sqlite3_column_double(statement, 11)

            rollups.append(UsageRollup(
                id: id,
                periodStart: periodStart,
                periodEnd: periodEnd,
                resolution: resolutionValue,
                fiveHourAvg: fiveHourAvg,
                fiveHourPeak: fiveHourPeak,
                fiveHourMin: fiveHourMin,
                sevenDayAvg: sevenDayAvg,
                sevenDayPeak: sevenDayPeak,
                sevenDayMin: sevenDayMin,
                resetCount: resetCount,
                wasteCredits: wasteCredits
            ))
        }

        return rollups
    }

    /// Deletes rollups of a specific resolution in a time range.
    private func deleteRollups(
        resolution: UsageRollup.Resolution,
        from: Int64,
        to: Int64,
        connection: OpaquePointer
    ) throws {
        let sql = "DELETE FROM usage_rollups WHERE resolution = ? AND period_start >= ? AND period_start < ?"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        resolution.rawValue.withCString { cString in
            sqlite3_bind_text(statement, 1, cString, -1, Self.SQLITE_TRANSIENT)
        }
        sqlite3_bind_int64(statement, 2, from)
        sqlite3_bind_int64(statement, 3, to)

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }
    }

    /// Sums waste_credits from reset_events in a time range.
    private func sumWasteCredits(from: Int64, to: Int64, connection: OpaquePointer) throws -> Double? {
        let sql = "SELECT SUM(waste_credits) FROM reset_events WHERE timestamp >= ? AND timestamp < ?"

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let prepareResult = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, from)
        sqlite3_bind_int64(statement, 2, to)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return nil
        }

        return sqlite3_column_double(statement, 0)
    }

    // MARK: - Task 8: Query Rolled Up Data

    /// Estimated poll interval in milliseconds (used for pseudo-rollup period calculation)
    private static let estimatedPollIntervalMs: Int64 = 30_000

    /// Converts a raw poll to a pseudo-rollup for consistent query results.
    /// - Parameter poll: The raw usage poll
    /// - Returns: UsageRollup representing the single poll
    private func pollToRollup(_ poll: UsagePoll) -> UsageRollup {
        UsageRollup(
            id: poll.id,
            periodStart: poll.timestamp,
            periodEnd: poll.timestamp + Self.estimatedPollIntervalMs,
            resolution: .fiveMin, // Use fiveMin as placeholder for raw
            fiveHourAvg: poll.fiveHourUtil,
            fiveHourPeak: poll.fiveHourUtil,
            fiveHourMin: poll.fiveHourUtil,
            sevenDayAvg: poll.sevenDayUtil,
            sevenDayPeak: poll.sevenDayUtil,
            sevenDayMin: poll.sevenDayUtil,
            resetCount: 0,
            wasteCredits: nil
        )
    }

    /// Queries historical data at appropriate resolution for the time range.
    private func queryRolledUpData(range: TimeRange, connection: OpaquePointer) async throws -> [UsageRollup] {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let twentyFourHoursAgo = nowMs - Self.oneDayMs
        let sevenDaysAgo = nowMs - Self.sevenDaysMs
        let thirtyDaysAgo = nowMs - Self.thirtyDaysMs

        var allRollups: [UsageRollup] = []

        switch range {
        case .day:
            // Raw polls only from last 24h - convert to rollup format for consistency
            let polls = try queryRawPollsForRollup(from: twentyFourHoursAgo, to: nowMs, connection: connection)
            allRollups.append(contentsOf: polls.map { pollToRollup($0) })

        case .week:
            // Raw <24h + 5min rollups 1-7d
            let recentPolls = try queryRawPollsForRollup(from: twentyFourHoursAgo, to: nowMs, connection: connection)
            allRollups.append(contentsOf: recentPolls.map { pollToRollup($0) })
            let fiveMinRollups = try queryRollupsForRollup(
                resolution: .fiveMin,
                from: sevenDaysAgo,
                to: twentyFourHoursAgo,
                connection: connection
            )
            allRollups.append(contentsOf: fiveMinRollups)

        case .month:
            // Raw + 5min + hourly
            let recentPolls = try queryRawPollsForRollup(from: twentyFourHoursAgo, to: nowMs, connection: connection)
            allRollups.append(contentsOf: recentPolls.map { pollToRollup($0) })
            let fiveMinRollups = try queryRollupsForRollup(
                resolution: .fiveMin,
                from: sevenDaysAgo,
                to: twentyFourHoursAgo,
                connection: connection
            )
            allRollups.append(contentsOf: fiveMinRollups)
            let hourlyRollups = try queryRollupsForRollup(
                resolution: .hourly,
                from: thirtyDaysAgo,
                to: sevenDaysAgo,
                connection: connection
            )
            allRollups.append(contentsOf: hourlyRollups)

        case .all:
            // Raw + 5min + hourly + daily
            let recentPolls = try queryRawPollsForRollup(from: twentyFourHoursAgo, to: nowMs, connection: connection)
            allRollups.append(contentsOf: recentPolls.map { pollToRollup($0) })
            let fiveMinRollups = try queryRollupsForRollup(
                resolution: .fiveMin,
                from: sevenDaysAgo,
                to: twentyFourHoursAgo,
                connection: connection
            )
            allRollups.append(contentsOf: fiveMinRollups)
            let hourlyRollups = try queryRollupsForRollup(
                resolution: .hourly,
                from: thirtyDaysAgo,
                to: sevenDaysAgo,
                connection: connection
            )
            allRollups.append(contentsOf: hourlyRollups)
            let dailyRollups = try queryRollupsForRollup(
                resolution: .daily,
                from: 0,
                to: thirtyDaysAgo,
                connection: connection
            )
            allRollups.append(contentsOf: dailyRollups)
        }

        // Sort by period_start ascending
        return allRollups.sorted { $0.periodStart < $1.periodStart }
    }

    // MARK: - Task 9: Prune Old Data

    /// Prunes data older than the retention period.
    private func performPruneOldData(retentionDays: Int, connection: OpaquePointer) async throws {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let retentionMs = Int64(retentionDays) * Self.oneDayMs
        let cutoffMs = nowMs - retentionMs

        // Delete old rollups
        let deleteSql = "DELETE FROM usage_rollups WHERE period_end < ?"
        var statement: OpaquePointer?

        let prepareResult = sqlite3_prepare_v2(connection, deleteSql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResult))
        }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        var stepResult = sqlite3_step(statement)
        // Capture error message BEFORE finalize (finalize can clear error state)
        var errorMessage: String?
        if stepResult != SQLITE_DONE {
            errorMessage = String(cString: sqlite3_errmsg(connection))
        }
        sqlite3_finalize(statement)
        statement = nil

        guard stepResult == SQLITE_DONE else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage ?? "Unknown error"))
        }

        // Delete old reset events
        let deleteResetSql = "DELETE FROM reset_events WHERE timestamp < ?"

        let prepareResetResult = sqlite3_prepare_v2(connection, deleteResetSql, -1, &statement, nil)
        guard prepareResetResult == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: prepareResetResult))
        }

        sqlite3_bind_int64(statement, 1, cutoffMs)

        stepResult = sqlite3_step(statement)
        // Capture error message BEFORE finalize (finalize can clear error state)
        if stepResult != SQLITE_DONE {
            errorMessage = String(cString: sqlite3_errmsg(connection))
        }
        sqlite3_finalize(statement)

        guard stepResult == SQLITE_DONE else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage ?? "Unknown error"))
        }

        Self.logger.info("Pruned data older than \(retentionDays, privacy: .public) days")
    }
}
