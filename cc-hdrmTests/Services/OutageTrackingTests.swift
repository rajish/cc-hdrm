import Foundation
import Testing
import SQLite3
@testable import cc_hdrm

// MARK: - DatabaseManager: api_outages Table Tests

@Suite("DatabaseManager api_outages Tests")
struct DatabaseManagerOutageTests {

    private func makeManager() -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: testPath)
        return (manager, testPath)
    }

    private func cleanup(manager: DatabaseManager, path: URL) {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
    }

    @Test("Fresh install creates api_outages table")
    func freshInstallCreatesApiOutagesTable() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        #expect(manager.tableExists("api_outages"))
        #expect(manager.indexExists("idx_api_outages_started_at"))
    }

    @Test("Fresh install sets schema version to 6")
    func freshInstallSetsVersion6() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        #expect(try manager.getSchemaVersion() == 6)
    }

    @Test("Migration v5->v6 creates api_outages table and index")
    func migrationV5ToV6CreatesApiOutages() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")

        // Create a v5 database manually
        let manager1 = DatabaseManager(databasePath: testPath)
        let connection = try manager1.getConnection()

        // Create all v5 tables
        sqlite3_exec(connection, """
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
                extra_usage_utilization REAL,
                extra_usage_delta REAL
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
                waste_credits REAL,
                extra_usage_used_credits REAL,
                extra_usage_utilization REAL,
                extra_usage_delta REAL
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
        sqlite3_exec(connection, "PRAGMA user_version = 5", nil, nil, nil)

        // Insert data to verify existing tables aren't dropped
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (999, 0.99)", nil, nil, nil)

        // Verify api_outages does NOT exist yet
        #expect(!manager1.tableExists("api_outages"))

        manager1.closeConnection()

        // New manager triggers migration
        let manager2 = DatabaseManager(databasePath: testPath)
        defer { cleanup(manager: manager2, path: testPath) }
        try manager2.ensureSchema()

        // Verify api_outages table and index created
        #expect(manager2.tableExists("api_outages"))
        #expect(manager2.indexExists("idx_api_outages_started_at"))

        // Verify existing data preserved
        let connection2 = try manager2.getConnection()
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(connection2, "SELECT five_hour_util FROM usage_polls WHERE timestamp = 999", -1, &stmt, nil)
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_double(stmt, 0) == 0.99)
        sqlite3_finalize(stmt)

        // Verify version bumped to 6
        #expect(try manager2.getSchemaVersion() == 6)
    }

    @Test("api_outages table has correct columns")
    func apiOutagesTableHasCorrectColumns() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()

        let connection = try manager.getConnection()
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "PRAGMA table_info(api_outages)", -1, &statement, nil)

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1) {
                columns.append(String(cString: namePtr))
            }
        }
        sqlite3_finalize(statement)

        #expect(columns.contains("id"))
        #expect(columns.contains("started_at"))
        #expect(columns.contains("ended_at"))
        #expect(columns.contains("failure_reason"))
    }

    @Test("Can insert and select from api_outages table")
    func apiOutagesInsertSelect() throws {
        let (manager, path) = makeManager()
        defer { cleanup(manager: manager, path: path) }

        try manager.ensureSchema()
        let connection = try manager.getConnection()

        var errorMessage: UnsafeMutablePointer<CChar>?
        let insertSQL = "INSERT INTO api_outages (started_at, failure_reason) VALUES (1704067200000, 'networkUnreachable')"
        let insertResult = sqlite3_exec(connection, insertSQL, nil, nil, &errorMessage)
        #expect(insertResult == SQLITE_OK)

        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT started_at, ended_at, failure_reason FROM api_outages", -1, &statement, nil)
        #expect(sqlite3_step(statement) == SQLITE_ROW)

        let startedAt = sqlite3_column_int64(statement, 0)
        let endedAtType = sqlite3_column_type(statement, 1)
        let reason = String(cString: sqlite3_column_text(statement, 2))
        sqlite3_finalize(statement)

        #expect(startedAt == 1704067200000)
        #expect(endedAtType == SQLITE_NULL)
        #expect(reason == "networkUnreachable")
    }
}

// MARK: - HistoricalDataService: Outage Tracking Tests

@Suite("HistoricalDataService Outage Tracking Tests")
struct HistoricalDataServiceOutageTests {

    private func makeService() -> (HistoricalDataService, DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: testPath)
        manager.initialize()
        let service = HistoricalDataService(databaseManager: manager)
        return (service, manager, testPath)
    }

    private func cleanup(manager: DatabaseManager, path: URL) {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
    }

    private func getOutageCount(connection: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        defer {
            if let stmt = stmt { sqlite3_finalize(stmt) }
        }
        sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM api_outages", -1, &stmt, nil)
        sqlite3_step(stmt)
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func getOpenOutageCount(connection: OpaquePointer) -> Int {
        var stmt: OpaquePointer?
        defer {
            if let stmt = stmt { sqlite3_finalize(stmt) }
        }
        sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM api_outages WHERE ended_at IS NULL", -1, &stmt, nil)
        sqlite3_step(stmt)
        return Int(sqlite3_column_int(stmt, 0))
    }

    // Test 8.4: Single failure does NOT create outage record
    @Test("Single failure does not create outage record")
    func singleFailureNoOutage() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")

        let connection = try manager.getConnection()
        #expect(getOutageCount(connection: connection) == 0)
    }

    // Test 8.5: 2 consecutive failures creates outage record
    @Test("Two consecutive failures creates outage record with correct failure_reason")
    func twoFailuresCreatesOutage() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")

        let connection = try manager.getConnection()
        #expect(getOutageCount(connection: connection) == 1)

        // Check the record
        var stmt: OpaquePointer?
        defer {
            if let stmt = stmt { sqlite3_finalize(stmt) }
        }
        sqlite3_prepare_v2(connection, "SELECT failure_reason, ended_at FROM api_outages", -1, &stmt, nil)
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let reason = String(cString: sqlite3_column_text(stmt, 0))
        let endedAtType = sqlite3_column_type(stmt, 1)
        #expect(reason == "networkUnreachable")
        #expect(endedAtType == SQLITE_NULL) // ongoing
    }

    // Test 8.6: Success after outage closes the record
    @Test("Success after outage closes the record with ended_at")
    func successAfterOutageClosesRecord() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // Start outage
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")

        // Recover
        await service.evaluateOutageState(apiReachable: true, failureReason: nil)

        let connection = try manager.getConnection()
        #expect(getOutageCount(connection: connection) == 1)
        #expect(getOpenOutageCount(connection: connection) == 0) // all closed

        var stmt: OpaquePointer?
        defer {
            if let stmt = stmt { sqlite3_finalize(stmt) }
        }
        sqlite3_prepare_v2(connection, "SELECT ended_at FROM api_outages", -1, &stmt, nil)
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_type(stmt, 0) != SQLITE_NULL) // ended_at is set
    }

    // Test 8.7: Multiple failures after outage detection don't create duplicate records
    @Test("Multiple failures after outage detection don't create duplicate records")
    func multipleFailuresNoDuplicates() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")

        let connection = try manager.getConnection()
        #expect(getOutageCount(connection: connection) == 1) // Still just one record
    }

    // Test 8.8: Success when no outage active is a no-op
    @Test("Success when no outage active is a no-op")
    func successWhenNoOutageIsNoop() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        await service.evaluateOutageState(apiReachable: true, failureReason: nil)

        let connection = try manager.getConnection()
        #expect(getOutageCount(connection: connection) == 0)
    }

    // Test 8.9: getOutagePeriods returns correct results for time ranges
    @Test("getOutagePeriods returns correct results for time ranges")
    func getOutagePeriodsTimeRange() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // Insert outage records directly
        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (1000, 2000, 'networkUnreachable')", nil, nil, nil)
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (5000, 6000, 'httpError:503')", nil, nil, nil)
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (9000, 10000, 'parseError')", nil, nil, nil)

        // Query range that includes only the middle outage
        let from = Date(timeIntervalSince1970: 4.0) // 4000 ms
        let to = Date(timeIntervalSince1970: 7.0) // 7000 ms
        let results = try await service.getOutagePeriods(from: from, to: to)

        #expect(results.count == 1)
        #expect(results[0].failureReason == "httpError:503")
    }

    // Test 8.10: getOutagePeriods returns outages overlapping range boundaries
    @Test("getOutagePeriods returns outages overlapping range boundaries")
    func getOutagePeriodsOverlapping() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        let connection = try manager.getConnection()
        // Outage spans 1000-5000 — overlaps with range starting at 3000
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (1000, 5000, 'networkUnreachable')", nil, nil, nil)
        // Ongoing outage starting at 8000 — overlaps with any range that extends past 8000
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (8000, 'httpError:502')", nil, nil, nil)

        let from = Date(timeIntervalSince1970: 3.0) // 3000 ms
        let to = Date(timeIntervalSince1970: 10.0) // 10000 ms
        let results = try await service.getOutagePeriods(from: from, to: to)

        #expect(results.count == 2)
        #expect(results[0].startedAt == 1000) // Overlapping outage included
        #expect(results[1].startedAt == 8000) // Ongoing outage included
        #expect(results[1].isOngoing == true)
    }

    // Test 8.11: loadOutageState sets outageActive from open DB record
    @Test("loadOutageState sets outageActive from open DB record")
    func loadOutageStateFromOpenRecord() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // Insert an open outage record
        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (1000, 'networkUnreachable')", nil, nil, nil)

        // Load outage state
        try await service.loadOutageState()

        // Verify: success should close the open outage (proving outageActive was set)
        await service.evaluateOutageState(apiReachable: true, failureReason: nil)

        #expect(getOpenOutageCount(connection: connection) == 0) // Closed by recovery
    }

    // Test 8.12: Relaunch scenario: open outage + success closes it (AC 3)
    @Test("Relaunch: open outage + success closes it (AC 3)")
    func relaunchOpenOutagePlusSuccessClosesIt() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // Simulate previous session: outage was ongoing when app quit
        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (1000, 'networkUnreachable')", nil, nil, nil)

        // Simulate relaunch: load state, then first poll succeeds
        try await service.loadOutageState()
        await service.evaluateOutageState(apiReachable: true, failureReason: nil)

        // Outage should be closed
        #expect(getOutageCount(connection: connection) == 1)
        #expect(getOpenOutageCount(connection: connection) == 0)

        // Verify ended_at is set
        var stmt: OpaquePointer?
        defer {
            if let stmt = stmt { sqlite3_finalize(stmt) }
        }
        sqlite3_prepare_v2(connection, "SELECT ended_at FROM api_outages", -1, &stmt, nil)
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        #expect(sqlite3_column_type(stmt, 0) != SQLITE_NULL)
    }

    // Test 8.13: Relaunch scenario: open outage + failure keeps it open (AC 4)
    @Test("Relaunch: open outage + failure keeps it open (AC 4)")
    func relaunchOpenOutagePlusFailureKeepsItOpen() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // Simulate previous session: outage was ongoing when app quit
        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (1000, 'networkUnreachable')", nil, nil, nil)

        // Simulate relaunch: load state, then first poll also fails
        try await service.loadOutageState()
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")

        // Outage should remain open, no duplicate record
        #expect(getOutageCount(connection: connection) == 1)
        #expect(getOpenOutageCount(connection: connection) == 1)
    }

    // Test 8.14: Graceful degradation: database unavailable skips all operations
    @Test("Graceful degradation: database unavailable skips all operations")
    func gracefulDegradationDatabaseUnavailable() async throws {
        let invalidPath = URL(fileURLWithPath: "/invalid_root_directory/test.db")
        let manager = DatabaseManager(databasePath: invalidPath)
        // Don't call initialize — isAvailable remains false
        let service = HistoricalDataService(databaseManager: manager)

        // These should all silently no-op without crashing
        await service.evaluateOutageState(apiReachable: false, failureReason: "test")
        await service.evaluateOutageState(apiReachable: false, failureReason: "test")
        await service.evaluateOutageState(apiReachable: true, failureReason: nil)

        let results = try await service.getOutagePeriods(from: nil, to: nil)
        #expect(results.isEmpty)
    }

    // Test: getOutagePeriods with nil bounds returns all records
    @Test("getOutagePeriods with nil bounds returns all records")
    func getOutagePeriodsNilBounds() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (1000, 2000, 'a')", nil, nil, nil)
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (3000, 4000, 'b')", nil, nil, nil)
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (5000, 'c')", nil, nil, nil)

        let results = try await service.getOutagePeriods(from: nil, to: nil)
        #expect(results.count == 3)
        #expect(results[0].startedAt == 1000)
        #expect(results[1].startedAt == 3000)
        #expect(results[2].startedAt == 5000)
    }

    // Test: closeOpenOutages closes all open records
    @Test("closeOpenOutages closes all open records")
    func closeOpenOutagesClosesAll() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (1000, 'a')", nil, nil, nil)
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, failure_reason) VALUES (2000, 'b')", nil, nil, nil)

        #expect(getOpenOutageCount(connection: connection) == 2)

        try await service.closeOpenOutages(endedAt: Date())

        #expect(getOpenOutageCount(connection: connection) == 0)
    }

    // Test: loadOutageState with no open outages leaves state inactive
    @Test("loadOutageState with no open outages does not activate outage state")
    func loadOutageStateNoOpenOutages() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // Insert only CLOSED outage records (ended_at is set)
        let connection = try manager.getConnection()
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (1000, 2000, 'networkUnreachable')", nil, nil, nil)
        sqlite3_exec(connection, "INSERT INTO api_outages (started_at, ended_at, failure_reason) VALUES (3000, 4000, 'httpError:503')", nil, nil, nil)

        // Load outage state — should NOT activate outage
        try await service.loadOutageState()

        // Verify: a single failure should NOT create an outage record
        // (if loadOutageState had incorrectly set outageActive=true, this failure
        // would increment count to 3 and skip insertion since outageActive is already true;
        // but if outageActive=false, a single failure just increments count to 1 with no insert)
        await service.evaluateOutageState(apiReachable: false, failureReason: "test")
        #expect(getOutageCount(connection: connection) == 2) // Still just the 2 closed records

        // A second failure should now create a NEW outage (proving outageActive was false)
        await service.evaluateOutageState(apiReachable: false, failureReason: "test")
        #expect(getOutageCount(connection: connection) == 3) // New open outage created
    }

    // Test: Multiple outage cycles (outage->recovery->outage) create separate records
    @Test("Multiple outage cycles create separate records")
    func multipleOutageCycles() async throws {
        let (service, manager, path) = makeService()
        defer { cleanup(manager: manager, path: path) }

        // First outage
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        await service.evaluateOutageState(apiReachable: false, failureReason: "networkUnreachable")
        // Recovery
        await service.evaluateOutageState(apiReachable: true, failureReason: nil)
        // Second outage
        await service.evaluateOutageState(apiReachable: false, failureReason: "httpError:503")
        await service.evaluateOutageState(apiReachable: false, failureReason: "httpError:503")

        let connection = try manager.getConnection()
        #expect(getOutageCount(connection: connection) == 2)
        #expect(getOpenOutageCount(connection: connection) == 1) // Second outage still open
    }
}
