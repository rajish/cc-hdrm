import Foundation
import os
import SQLite3

/// Current database schema version. Increment when schema changes require migration.
private let currentSchemaVersion: Int = 4

/// SQLITE_TRANSIENT tells SQLite to make its own copy of the string data.
/// Required when binding strings from Swift's withCString which uses temporary buffers.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Manages SQLite database creation, schema, and migrations for historical usage data.
/// This is the ONLY component that manages the SQLite database.
///
/// ## Thread Safety
/// This class uses `@unchecked Sendable` with an internal `NSLock` to protect all mutable state.
/// All access to `db` and `_isAvailable` is synchronized through the lock.
/// The SQLite connection is opened with `SQLITE_OPEN_FULLMUTEX` for additional thread safety.
final class DatabaseManager: DatabaseManagerProtocol, @unchecked Sendable {
    /// Shared singleton instance for production use.
    static let shared = DatabaseManager()

    private static let logger = Logger(
        subsystem: "com.cc-hdrm.app",
        category: "database"
    )

    /// Lock protecting all mutable state (`db` and `_isAvailable`).
    private let lock = NSLock()
    
    // MARK: - Protected State (access only under lock)
    private var db: OpaquePointer?
    private var _isAvailable: Bool = false
    
    // MARK: - Immutable State
    private let databasePath: URL
    
    /// Indicates whether the database is available and operational.
    /// Thread-safe: reads are synchronized.
    var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAvailable
    }

    /// Creates a DatabaseManager with a custom database path (for testing).
    /// - Parameter databasePath: Custom path to the database file
    init(databasePath: URL) {
        self.databasePath = databasePath
    }

    /// Creates a DatabaseManager with the default production path.
    /// Database location: `~/Library/Application Support/cc-hdrm/usage.db`
    private convenience init() {
        let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let databaseURL = appSupportURL
            .appendingPathComponent("cc-hdrm", isDirectory: true)
            .appendingPathComponent("usage.db")
        self.init(databasePath: databaseURL)
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - DatabaseManagerProtocol

    func getDatabasePath() -> URL {
        return databasePath
    }

    func getConnection() throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }

        if let existingDb = db {
            return existingDb
        }

        try getOrCreateDatabaseDirectory()

        let path = databasePath.path
        var newDb: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(path, &newDb, flags, nil)

        guard result == SQLITE_OK, let openedDb = newDb else {
            let errorMessage = String(cString: sqlite3_errmsg(newDb))
            Self.logger.error("Failed to open database at \(path, privacy: .public): \(errorMessage, privacy: .public)")
            if let newDb = newDb {
                sqlite3_close(newDb)
            }
            throw AppError.databaseOpenFailed(path: path)
        }

        db = openedDb
        Self.logger.info("Database opened at \(path, privacy: .public)")
        return openedDb
    }

    func ensureSchema() throws {
        let connection = try getConnection()

        // Check current schema version
        let existingVersion = try getSchemaVersion()

        if existingVersion == 0 {
            // First launch - create all tables
            Self.logger.info("Creating database schema (version \(currentSchemaVersion))")
            try createUsagePollsTable(connection)
            try createUsageRollupsTable(connection)
            try createResetEventsTable(connection)
            try createRollupMetadataTable(connection)
            try setSchemaVersion(currentSchemaVersion)
            Self.logger.info("Database schema created successfully")
        } else if existingVersion < currentSchemaVersion {
            // Migration needed
            Self.logger.info("Schema migration needed: \(existingVersion) -> \(currentSchemaVersion)")
            try runMigrations()
        } else {
            Self.logger.info("Database schema is current (version \(existingVersion))")
        }

        setAvailable(true)
    }
    
    /// Thread-safe setter for isAvailable.
    private func setAvailable(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _isAvailable = value
    }

    func runMigrations() throws {
        let existingVersion = try getSchemaVersion()

        if existingVersion < 2 {
            let connection = try getConnection()
            try createRollupMetadataTable(connection)
            Self.logger.info("Migration v1->v2: created rollup_metadata table")
        }

        if existingVersion < 3 {
            let connection = try getConnection()
            try executeSQL("ALTER TABLE usage_polls ADD COLUMN extra_usage_enabled INTEGER", on: connection)
            try executeSQL("ALTER TABLE usage_polls ADD COLUMN extra_usage_monthly_limit REAL", on: connection)
            try executeSQL("ALTER TABLE usage_polls ADD COLUMN extra_usage_used_credits REAL", on: connection)
            try executeSQL("ALTER TABLE usage_polls ADD COLUMN extra_usage_utilization REAL", on: connection)
            Self.logger.info("Migration v2->v3: added extra_usage columns to usage_polls")
        }

        if existingVersion < 4 {
            let connection = try getConnection()
            try executeSQL("ALTER TABLE usage_rollups ADD COLUMN extra_usage_used_credits REAL", on: connection)
            try executeSQL("ALTER TABLE usage_rollups ADD COLUMN extra_usage_utilization REAL", on: connection)
            Self.logger.info("Migration v3->v4: added extra_usage columns to usage_rollups")
        }

        Self.logger.info("Migrations complete: \(existingVersion) -> \(currentSchemaVersion)")
        try setSchemaVersion(currentSchemaVersion)
    }

    func getSchemaVersion() throws -> Int {
        let connection = try getConnection()
        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let result = sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &statement, nil)
        guard result == SQLITE_OK else {
            throw AppError.databaseQueryFailed(underlying: SQLiteError.prepareFailed(code: result))
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return 0
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    // MARK: - Private Helpers

    private func getOrCreateDatabaseDirectory() throws {
        let directoryURL = databasePath.deletingLastPathComponent()
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                Self.logger.info("Created database directory at \(directoryURL.path, privacy: .public)")
            } catch {
                Self.logger.error("Failed to create database directory: \(error.localizedDescription, privacy: .public)")
                throw AppError.databaseOpenFailed(path: directoryURL.path)
            }
        }
    }

    private func setSchemaVersion(_ version: Int) throws {
        let connection = try getConnection()
        let sql = "PRAGMA user_version = \(version)"
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            Self.logger.error("Failed to set schema version: \(message, privacy: .public)")
            throw AppError.databaseSchemaFailed(underlying: SQLiteError.execFailed(message: message))
        }
    }

    private func executeSQL(_ sql: String, on connection: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(connection, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            Self.logger.error("SQL execution failed: \(message, privacy: .public)")
            throw AppError.databaseSchemaFailed(underlying: SQLiteError.execFailed(message: message))
        }
    }

    // MARK: - Table Creation (Tasks 3-5 will verify these)

    private func createUsagePollsTable(_ connection: OpaquePointer) throws {
        let createTable = """
            CREATE TABLE IF NOT EXISTS usage_polls (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                five_hour_util REAL,
                five_hour_resets_at INTEGER,
                seven_day_util REAL,
                seven_day_resets_at INTEGER,
                extra_usage_enabled INTEGER,
                extra_usage_monthly_limit REAL,
                extra_usage_used_credits REAL,
                extra_usage_utilization REAL
            )
            """
        try executeSQL(createTable, on: connection)

        let createIndex = "CREATE INDEX IF NOT EXISTS idx_usage_polls_timestamp ON usage_polls(timestamp)"
        try executeSQL(createIndex, on: connection)

        Self.logger.info("Created usage_polls table and index")
    }

    private func createUsageRollupsTable(_ connection: OpaquePointer) throws {
        let createTable = """
            CREATE TABLE IF NOT EXISTS usage_rollups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                period_start INTEGER NOT NULL,
                period_end INTEGER NOT NULL,
                resolution TEXT NOT NULL,
                five_hour_avg REAL,
                five_hour_peak REAL,
                five_hour_min REAL,
                seven_day_avg REAL,
                seven_day_peak REAL,
                seven_day_min REAL,
                reset_count INTEGER DEFAULT 0,
                waste_credits REAL,
                extra_usage_used_credits REAL,
                extra_usage_utilization REAL
            )
            """
        try executeSQL(createTable, on: connection)

        let createIndex = """
            CREATE INDEX IF NOT EXISTS idx_usage_rollups_resolution_period 
            ON usage_rollups(resolution, period_start)
            """
        try executeSQL(createIndex, on: connection)

        Self.logger.info("Created usage_rollups table and index")
    }

    private func createResetEventsTable(_ connection: OpaquePointer) throws {
        let createTable = """
            CREATE TABLE IF NOT EXISTS reset_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                five_hour_peak REAL,
                seven_day_util REAL,
                tier TEXT,
                used_credits REAL,
                constrained_credits REAL,
                waste_credits REAL
            )
            """
        try executeSQL(createTable, on: connection)

        let createIndex = "CREATE INDEX IF NOT EXISTS idx_reset_events_timestamp ON reset_events(timestamp)"
        try executeSQL(createIndex, on: connection)

        Self.logger.info("Created reset_events table and index")
    }

    private func createRollupMetadataTable(_ connection: OpaquePointer) throws {
        let createTable = """
            CREATE TABLE IF NOT EXISTS rollup_metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """
        try executeSQL(createTable, on: connection)

        Self.logger.info("Created rollup_metadata table")
    }

    // MARK: - Rollup Metadata Helpers

    /// Gets the last rollup timestamp from metadata.
    /// - Returns: Unix milliseconds of last rollup, or nil if never run
    func getLastRollupTimestamp() throws -> Int64? {
        let connection = try getConnection()

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
    /// - Parameter timestamp: Unix milliseconds of last rollup
    func setLastRollupTimestamp(_ timestamp: Int64) throws {
        let connection = try getConnection()

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
            sqlite3_bind_text(statement, 1, cString, -1, SQLITE_TRANSIENT)
        }

        let stepResult = sqlite3_step(statement)
        guard stepResult == SQLITE_DONE else {
            let errorMessage = String(cString: sqlite3_errmsg(connection))
            throw AppError.databaseQueryFailed(underlying: SQLiteError.execFailed(message: errorMessage))
        }
    }

    // MARK: - Schema Verification Helpers (for testing)

    /// Checks if a table exists in the database.
    /// - Parameter tableName: The name of the table to check
    /// - Returns: `true` if the table exists, `false` otherwise
    func tableExists(_ tableName: String) -> Bool {
        guard let connection = try? getConnection() else {
            return false
        }

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=?"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        return tableName.withCString { cString in
            sqlite3_bind_text(statement, 1, cString, -1, SQLITE_TRANSIENT)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    /// Checks if an index exists in the database.
    /// - Parameter indexName: The name of the index to check
    /// - Returns: `true` if the index exists, `false` otherwise
    func indexExists(_ indexName: String) -> Bool {
        guard let connection = try? getConnection() else {
            return false
        }

        var statement: OpaquePointer?
        defer {
            if let statement = statement {
                sqlite3_finalize(statement)
            }
        }

        let sql = "SELECT name FROM sqlite_master WHERE type='index' AND name=?"
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        return indexName.withCString { cString in
            sqlite3_bind_text(statement, 1, cString, -1, SQLITE_TRANSIENT)
            return sqlite3_step(statement) == SQLITE_ROW
        }
    }

    // MARK: - Connection Management

    /// Closes the database connection if open.
    /// Call this before deleting the database file (e.g., in tests) to avoid SQLite warnings.
    /// Thread-safe: synchronized with the internal lock.
    func closeConnection() {
        lock.lock()
        defer { lock.unlock() }
        if let existingDb = db {
            sqlite3_close(existingDb)
            db = nil
            Self.logger.info("Database connection closed")
        }
    }

    // MARK: - Initialization Helper

    /// Initializes the database with graceful degradation.
    /// Call this at app startup. If initialization fails, the app continues without historical features.
    func initialize() {
        do {
            try ensureSchema()
            Self.logger.info("Database initialized successfully")
        } catch {
            setAvailable(false)
            Self.logger.error("Database initialization failed: \(error.localizedDescription, privacy: .public) - historical features disabled")
        }
    }
}

// MARK: - SQLite Error Helper

/// Internal error type for SQLite operations.
enum SQLiteError: Error, Sendable {
    case prepareFailed(code: Int32)
    case execFailed(message: String)
}
