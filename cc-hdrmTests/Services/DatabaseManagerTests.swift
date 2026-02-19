import Foundation
import Testing
import SQLite3
@testable import cc_hdrm

@Suite("DatabaseManager Tests")
struct DatabaseManagerTests {

    /// Creates an isolated DatabaseManager with a unique temporary database path.
    /// Returns the manager and path for cleanup.
    private func makeManager() -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: testPath)
        return (manager, testPath)
    }

    /// Closes connection and removes the test database file.
    /// Must close connection BEFORE deleting file to avoid SQLite warnings.
    private func cleanup(manager: DatabaseManager, path: URL) {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
        // Also try to remove the parent directory if empty
        let parentDir = path.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parentDir)
    }

    // MARK: - Schema Creation (AC #1, Task 7.2)

    @Test("Schema creation creates all three tables")
    func schemaCreatesAllTables() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        #expect(manager.tableExists("usage_polls"))
        #expect(manager.tableExists("usage_rollups"))
        #expect(manager.tableExists("reset_events"))
    }

    @Test("Schema creation creates all required indexes")
    func schemaCreatesAllIndexes() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        #expect(manager.indexExists("idx_usage_polls_timestamp"))
        #expect(manager.indexExists("idx_usage_rollups_resolution_period"))
        #expect(manager.indexExists("idx_reset_events_timestamp"))
    }

    @Test("Schema creation sets schema version to current (5)")
    func schemaCreationSetsVersion() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        let version = try manager.getSchemaVersion()
        #expect(version == 5)
    }

    @Test("Database path is correct")
    func databasePathIsCorrect() {
        let (manager, expectedPath) = makeManager()
        defer { cleanup(manager: manager, path: expectedPath) }

        let actualPath = manager.getDatabasePath()
        #expect(actualPath == expectedPath)
    }

    @Test("isAvailable is true after successful ensureSchema")
    func isAvailableTrueAfterSuccess() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        #expect(manager.isAvailable == false)
        try manager.ensureSchema()
        #expect(manager.isAvailable == true)
    }

    // MARK: - Idempotent Schema (AC #2, Task 7.3)

    @Test("Re-running ensureSchema does not recreate tables")
    func schemaIsIdempotent() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        // First run - creates tables
        try manager.ensureSchema()
        let versionAfterFirst = try manager.getSchemaVersion()

        // Insert a test row
        let connection = try manager.getConnection()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let insertSQL = "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (1234567890, 0.5)"
        sqlite3_exec(connection, insertSQL, nil, nil, &errorMessage)

        // Second run - should not recreate tables
        try manager.ensureSchema()
        let versionAfterSecond = try manager.getSchemaVersion()

        // Verify version unchanged
        #expect(versionAfterFirst == versionAfterSecond)

        // Verify data still exists
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM usage_polls", -1, &statement, nil)
        sqlite3_step(statement)
        let count = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)

        #expect(count == 1)
    }

    @Test("Existing database opens without recreating tables")
    func existingDatabaseOpensCorrectly() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        // First manager creates and populates database
        let manager1 = DatabaseManager(databasePath: testPath)
        try manager1.ensureSchema()

        let connection1 = try manager1.getConnection()
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection1, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (111, 0.25)", nil, nil, &errorMessage)
        
        // Close first manager before opening second
        manager1.closeConnection()

        // Second manager (simulates app restart) opens existing database
        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        try manager2.ensureSchema()

        // Verify data persists
        let connection2 = try manager2.getConnection()
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection2, "SELECT five_hour_util FROM usage_polls WHERE timestamp = 111", -1, &statement, nil)
        sqlite3_step(statement)
        let util = sqlite3_column_double(statement, 0)
        sqlite3_finalize(statement)

        #expect(util == 0.25)
    }

    // MARK: - Graceful Degradation (AC #3, Task 7.4)

    @Test("Initialize sets isAvailable to false when path is invalid")
    func gracefulDegradationOnInvalidPath() {
        // Use a path that cannot be created (e.g., root directory on macOS)
        let invalidPath = URL(fileURLWithPath: "/invalid_root_directory/test.db")
        let manager = DatabaseManager(databasePath: invalidPath)

        manager.initialize()

        #expect(manager.isAvailable == false)
    }

    @Test("tableExists returns false when database unavailable")
    func tableExistsReturnsFalseWhenUnavailable() {
        let invalidPath = URL(fileURLWithPath: "/invalid_root_directory/test.db")
        let manager = DatabaseManager(databasePath: invalidPath)

        #expect(manager.tableExists("usage_polls") == false)
    }

    // MARK: - Schema Version / Migration (Task 7.5)

    @Test("getSchemaVersion returns 0 for fresh database before ensureSchema")
    func schemaVersionZeroBeforeEnsure() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        // Open database but don't call ensureSchema
        _ = try manager.getConnection()
        let version = try manager.getSchemaVersion()

        #expect(version == 0)
    }

    @Test("Schema version is persisted across manager instances")
    func schemaVersionPersistsAcrossInstances() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        // First manager sets schema version
        let manager1 = DatabaseManager(databasePath: testPath)
        try manager1.ensureSchema()
        let version1 = try manager1.getSchemaVersion()
        
        // Close first manager before opening second
        manager1.closeConnection()

        // Second manager reads same version
        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        _ = try manager2.getConnection()
        let version2 = try manager2.getSchemaVersion()

        #expect(version1 == version2)
        #expect(version1 == 5)
    }

    @Test("Migration v1->v2 creates rollup_metadata table")
    func migrationV1ToV2CreatesRollupMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        // Create a v1 database manually (without rollup_metadata)
        let manager1 = DatabaseManager(databasePath: testPath)
        let connection = try manager1.getConnection()

        // Create only the v1 tables (no rollup_metadata)
        sqlite3_exec(connection, """
            CREATE TABLE IF NOT EXISTS usage_polls (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                five_hour_util REAL,
                five_hour_resets_at INTEGER,
                seven_day_util REAL,
                seven_day_resets_at INTEGER
            )
            """, nil, nil, nil)
        sqlite3_exec(connection, """
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
                waste_credits REAL
            )
            """, nil, nil, nil)
        sqlite3_exec(connection, """
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
            """, nil, nil, nil)
        sqlite3_exec(connection, "PRAGMA user_version = 1", nil, nil, nil)

        // Insert data to verify tables aren't dropped
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (999, 0.99)", nil, nil, nil)

        // Verify rollup_metadata does NOT exist yet
        var checkStmt: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT name FROM sqlite_master WHERE type='table' AND name='rollup_metadata'", -1, &checkStmt, nil)
        let beforeExists = sqlite3_step(checkStmt) == SQLITE_ROW
        sqlite3_finalize(checkStmt)
        #expect(!beforeExists, "rollup_metadata should NOT exist before migration")

        manager1.closeConnection()

        // New manager triggers migration
        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        try manager2.ensureSchema()

        // Verify migration ran: rollup_metadata exists
        let connection2 = try manager2.getConnection()
        var checkStmt2: OpaquePointer?
        sqlite3_prepare_v2(connection2, "SELECT name FROM sqlite_master WHERE type='table' AND name='rollup_metadata'", -1, &checkStmt2, nil)
        let afterExists = sqlite3_step(checkStmt2) == SQLITE_ROW
        sqlite3_finalize(checkStmt2)
        #expect(afterExists, "rollup_metadata should exist after migration")

        // Verify data persists (tables weren't dropped/recreated)
        var dataStmt: OpaquePointer?
        sqlite3_prepare_v2(connection2, "SELECT five_hour_util FROM usage_polls WHERE timestamp = 999", -1, &dataStmt, nil)
        #expect(sqlite3_step(dataStmt) == SQLITE_ROW)
        let util = sqlite3_column_double(dataStmt, 0)
        sqlite3_finalize(dataStmt)
        #expect(util == 0.99)

        // Verify version bumped to current (migration runs all the way through)
        #expect(try manager2.getSchemaVersion() == 5)
    }

    @Test("Migration v2->v3 adds extra_usage columns to usage_polls")
    func migrationV2ToV3AddsExtraUsageColumns() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        // Create a v2 database manually (with rollup_metadata but no extra_usage columns)
        let manager1 = DatabaseManager(databasePath: testPath)
        let connection = try manager1.getConnection()

        // Create v2 tables (no extra_usage columns on usage_polls)
        sqlite3_exec(connection, """
            CREATE TABLE IF NOT EXISTS usage_polls (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER NOT NULL,
                five_hour_util REAL,
                five_hour_resets_at INTEGER,
                seven_day_util REAL,
                seven_day_resets_at INTEGER
            )
            """, nil, nil, nil)
        sqlite3_exec(connection, """
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
                waste_credits REAL
            )
            """, nil, nil, nil)
        sqlite3_exec(connection, """
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
            """, nil, nil, nil)
        sqlite3_exec(connection, """
            CREATE TABLE IF NOT EXISTS rollup_metadata (
                key TEXT PRIMARY KEY,
                value TEXT
            )
            """, nil, nil, nil)
        sqlite3_exec(connection, "PRAGMA user_version = 2", nil, nil, nil)

        // Insert data to verify tables aren't dropped
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (888, 0.88)", nil, nil, nil)

        manager1.closeConnection()

        // New manager triggers migration
        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        try manager2.ensureSchema()

        // Verify extra_usage columns exist by inserting data that uses them
        let connection2 = try manager2.getConnection()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let insertResult = sqlite3_exec(
            connection2,
            "INSERT INTO usage_polls (timestamp, extra_usage_enabled, extra_usage_monthly_limit, extra_usage_used_credits, extra_usage_utilization) VALUES (999, 1, 500.0, 123.45, 0.247)",
            nil, nil, &errorMessage
        )
        #expect(insertResult == SQLITE_OK, "INSERT with extra_usage columns should succeed after migration")

        // Verify original data persists
        var dataStmt: OpaquePointer?
        sqlite3_prepare_v2(connection2, "SELECT five_hour_util FROM usage_polls WHERE timestamp = 888", -1, &dataStmt, nil)
        #expect(sqlite3_step(dataStmt) == SQLITE_ROW)
        let util = sqlite3_column_double(dataStmt, 0)
        sqlite3_finalize(dataStmt)
        #expect(util == 0.88)

        // Verify version bumped to 4
        #expect(try manager2.getSchemaVersion() == 5)
    }

    // MARK: - Table Schema Verification (AC #1)

    @Test("usage_polls table has correct columns")
    func usagePollsTableHasCorrectColumns() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        let connection = try manager.getConnection()
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "PRAGMA table_info(usage_polls)", -1, &statement, nil)

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: namePtr))
            }
        }
        sqlite3_finalize(statement)

        #expect(columns.contains("id"))
        #expect(columns.contains("timestamp"))
        #expect(columns.contains("five_hour_util"))
        #expect(columns.contains("five_hour_resets_at"))
        #expect(columns.contains("seven_day_util"))
        #expect(columns.contains("seven_day_resets_at"))
        #expect(columns.contains("extra_usage_enabled"))
        #expect(columns.contains("extra_usage_monthly_limit"))
        #expect(columns.contains("extra_usage_used_credits"))
        #expect(columns.contains("extra_usage_utilization"))
        #expect(columns.contains("extra_usage_delta"))
    }

    @Test("usage_rollups table has correct columns")
    func usageRollupsTableHasCorrectColumns() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        let connection = try manager.getConnection()
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "PRAGMA table_info(usage_rollups)", -1, &statement, nil)

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: namePtr))
            }
        }
        sqlite3_finalize(statement)

        #expect(columns.contains("id"))
        #expect(columns.contains("period_start"))
        #expect(columns.contains("period_end"))
        #expect(columns.contains("resolution"))
        #expect(columns.contains("five_hour_avg"))
        #expect(columns.contains("five_hour_peak"))
        #expect(columns.contains("five_hour_min"))
        #expect(columns.contains("seven_day_avg"))
        #expect(columns.contains("seven_day_peak"))
        #expect(columns.contains("seven_day_min"))
        #expect(columns.contains("reset_count"))
        #expect(columns.contains("waste_credits"))
        #expect(columns.contains("extra_usage_used_credits"))
        #expect(columns.contains("extra_usage_utilization"))
        #expect(columns.contains("extra_usage_delta"))
    }

    @Test("reset_events table has correct columns")
    func resetEventsTableHasCorrectColumns() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        let connection = try manager.getConnection()
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "PRAGMA table_info(reset_events)", -1, &statement, nil)

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: namePtr))
            }
        }
        sqlite3_finalize(statement)

        #expect(columns.contains("id"))
        #expect(columns.contains("timestamp"))
        #expect(columns.contains("five_hour_peak"))
        #expect(columns.contains("seven_day_util"))
        #expect(columns.contains("tier"))
        #expect(columns.contains("used_credits"))
        #expect(columns.contains("constrained_credits"))
        #expect(columns.contains("waste_credits"))
    }

    // MARK: - Insert/Select Verification (AC #1)

    @Test("Can insert and select from usage_polls table")
    func usagePollsInsertSelect() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()
        let connection = try manager.getConnection()

        // Insert
        var errorMessage: UnsafeMutablePointer<CChar>?
        let insertSQL = """
            INSERT INTO usage_polls (timestamp, five_hour_util, five_hour_resets_at, seven_day_util, seven_day_resets_at)
            VALUES (1704067200, 0.75, 1704070800, 0.45, 1704672000)
            """
        let insertResult = sqlite3_exec(connection, insertSQL, nil, nil, &errorMessage)
        #expect(insertResult == SQLITE_OK)

        // Select
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT * FROM usage_polls WHERE timestamp = 1704067200", -1, &statement, nil)
        #expect(sqlite3_step(statement) == SQLITE_ROW)

        let fiveHourUtil = sqlite3_column_double(statement, 2)
        let sevenDayUtil = sqlite3_column_double(statement, 4)
        sqlite3_finalize(statement)

        #expect(fiveHourUtil == 0.75)
        #expect(sevenDayUtil == 0.45)
    }

    @Test("Can insert and select from usage_rollups table")
    func usageRollupsInsertSelect() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()
        let connection = try manager.getConnection()

        // Insert
        var errorMessage: UnsafeMutablePointer<CChar>?
        let insertSQL = """
            INSERT INTO usage_rollups (period_start, period_end, resolution, five_hour_avg, five_hour_peak, reset_count)
            VALUES (1704067200, 1704153600, 'hourly', 0.65, 0.85, 3)
            """
        let insertResult = sqlite3_exec(connection, insertSQL, nil, nil, &errorMessage)
        #expect(insertResult == SQLITE_OK)

        // Select
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT resolution, five_hour_avg, reset_count FROM usage_rollups", -1, &statement, nil)
        #expect(sqlite3_step(statement) == SQLITE_ROW)

        let resolution = String(cString: sqlite3_column_text(statement, 0))
        let fiveHourAvg = sqlite3_column_double(statement, 1)
        let resetCount = sqlite3_column_int(statement, 2)
        sqlite3_finalize(statement)

        #expect(resolution == "hourly")
        #expect(fiveHourAvg == 0.65)
        #expect(resetCount == 3)
    }

    @Test("Can insert and select from reset_events table")
    func resetEventsInsertSelect() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()
        let connection = try manager.getConnection()

        // Insert
        var errorMessage: UnsafeMutablePointer<CChar>?
        let insertSQL = """
            INSERT INTO reset_events (timestamp, five_hour_peak, seven_day_util, tier, used_credits, constrained_credits, waste_credits)
            VALUES (1704067200, 0.95, 0.55, 'pro', 1000.0, 200.0, 50.0)
            """
        let insertResult = sqlite3_exec(connection, insertSQL, nil, nil, &errorMessage)
        #expect(insertResult == SQLITE_OK)

        // Select
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT tier, waste_credits FROM reset_events", -1, &statement, nil)
        #expect(sqlite3_step(statement) == SQLITE_ROW)

        let tier = String(cString: sqlite3_column_text(statement, 0))
        let unusedCredits = sqlite3_column_double(statement, 1)
        sqlite3_finalize(statement)

        #expect(tier == "pro")
        #expect(unusedCredits == 50.0)
    }

    // MARK: - Story 17.5: Migration v4->v5 (extra_usage_delta)

    @Test("Migration v4->v5 adds extra_usage_delta columns to both tables")
    func migrationV4ToV5AddsExtraUsageDeltaColumns() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        let manager1 = DatabaseManager(databasePath: testPath)
        let connection = try manager1.getConnection()

        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS usage_polls (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, five_hour_util REAL, five_hour_resets_at INTEGER, seven_day_util REAL, seven_day_resets_at INTEGER, extra_usage_enabled INTEGER, extra_usage_monthly_limit REAL, extra_usage_used_credits REAL, extra_usage_utilization REAL)", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS usage_rollups (id INTEGER PRIMARY KEY AUTOINCREMENT, period_start INTEGER NOT NULL, period_end INTEGER NOT NULL, resolution TEXT NOT NULL, five_hour_avg REAL, five_hour_peak REAL, five_hour_min REAL, seven_day_avg REAL, seven_day_peak REAL, seven_day_min REAL, reset_count INTEGER DEFAULT 0, waste_credits REAL, extra_usage_used_credits REAL, extra_usage_utilization REAL)", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS reset_events (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, five_hour_peak REAL, seven_day_util REAL, tier TEXT, used_credits REAL, constrained_credits REAL, waste_credits REAL)", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS rollup_metadata (key TEXT PRIMARY KEY, value TEXT)", nil, nil, nil)
        sqlite3_exec(connection, "PRAGMA user_version = 4", nil, nil, nil)

        manager1.closeConnection()

        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        try manager2.ensureSchema()

        let connection2 = try manager2.getConnection()
        var errorMessage: UnsafeMutablePointer<CChar>?
        let pollResult = sqlite3_exec(connection2, "INSERT INTO usage_polls (timestamp, extra_usage_delta) VALUES (999, 5.25)", nil, nil, &errorMessage)
        #expect(pollResult == SQLITE_OK, "INSERT with extra_usage_delta into usage_polls should succeed")

        let rollupResult = sqlite3_exec(connection2, "INSERT INTO usage_rollups (period_start, period_end, resolution, extra_usage_delta) VALUES (1000, 2000, '5min', 10.5)", nil, nil, &errorMessage)
        #expect(rollupResult == SQLITE_OK, "INSERT with extra_usage_delta into usage_rollups should succeed")

        #expect(try manager2.getSchemaVersion() == 5)
    }

    @Test("Migration v4->v5 backfills deltas from consecutive polls")
    func migrationV4ToV5BackfillsDeltas() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        let manager1 = DatabaseManager(databasePath: testPath)
        let connection = try manager1.getConnection()

        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS usage_polls (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, five_hour_util REAL, five_hour_resets_at INTEGER, seven_day_util REAL, seven_day_resets_at INTEGER, extra_usage_enabled INTEGER, extra_usage_monthly_limit REAL, extra_usage_used_credits REAL, extra_usage_utilization REAL)", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS usage_rollups (id INTEGER PRIMARY KEY AUTOINCREMENT, period_start INTEGER NOT NULL, period_end INTEGER NOT NULL, resolution TEXT NOT NULL, five_hour_avg REAL, five_hour_peak REAL, five_hour_min REAL, seven_day_avg REAL, seven_day_peak REAL, seven_day_min REAL, reset_count INTEGER DEFAULT 0, waste_credits REAL, extra_usage_used_credits REAL, extra_usage_utilization REAL)", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS reset_events (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp INTEGER NOT NULL, five_hour_peak REAL, seven_day_util REAL, tier TEXT, used_credits REAL, constrained_credits REAL, waste_credits REAL)", nil, nil, nil)
        sqlite3_exec(connection, "CREATE TABLE IF NOT EXISTS rollup_metadata (key TEXT PRIMARY KEY, value TEXT)", nil, nil, nil)
        sqlite3_exec(connection, "PRAGMA user_version = 4", nil, nil, nil)

        // Insert consecutive polls: 0, 10, 25, 20 (reset), NULL
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, extra_usage_used_credits) VALUES (1000, 50.0, 0.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, extra_usage_used_credits) VALUES (2000, 55.0, 10.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, extra_usage_used_credits) VALUES (3000, 60.0, 25.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, extra_usage_used_credits) VALUES (4000, 65.0, 20.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (5000, 70.0)", nil, nil, &errorMessage)

        manager1.closeConnection()

        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        try manager2.ensureSchema()

        let connection2 = try manager2.getConnection()
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(connection2, "SELECT timestamp, extra_usage_delta FROM usage_polls ORDER BY timestamp ASC", -1, &stmt, nil)

        var deltas: [(timestamp: Int64, delta: Double?)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = sqlite3_column_int64(stmt, 0)
            let delta: Double? = sqlite3_column_type(stmt, 1) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 1)
            deltas.append((timestamp: ts, delta: delta))
        }
        sqlite3_finalize(stmt)

        #expect(deltas.count == 5)
        #expect(deltas[0].delta == 0.0, "First poll delta should be 0")
        #expect(deltas[1].delta == 10.0, "Poll 2 delta should be 10.0")
        #expect(deltas[2].delta == 15.0, "Poll 3 delta should be 15.0")
        #expect(deltas[3].delta == 0.0, "Poll 4 (billing reset) delta should be 0")
        #expect(deltas[4].delta == 0.0, "Poll 5 (NULL credits) delta should be 0")
    }

    // MARK: - Protocol Conformance

    @Test("DatabaseManager conforms to DatabaseManagerProtocol")
    func conformsToProtocol() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }
        let _: any DatabaseManagerProtocol = manager
    }
}
