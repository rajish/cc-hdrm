import Foundation
import Testing
import SQLite3
@testable import cc_hdrm

@Suite("HistoricalDataService Tests")
struct HistoricalDataServiceTests {

    /// Creates an isolated DatabaseManager with a unique temporary database path.
    /// Returns the manager and path for cleanup.
    private func makeManager() -> (DatabaseManager, URL) {
        let tempDir = FileManager.default.temporaryDirectory
        let testPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db")
        let manager = DatabaseManager(databasePath: testPath)
        return (manager, testPath)
    }

    /// Closes connection and removes the test database file.
    private func cleanup(manager: DatabaseManager, path: URL) {
        manager.closeConnection()
        try? FileManager.default.removeItem(at: path)
        let parentDir = path.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: parentDir)
    }

    // MARK: - persistPoll Tests (AC #1)

    @Test("persistPoll inserts correct data with all fields")
    func persistPollInsertsCorrectData() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 45.5, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 23.1, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        try await service.persistPoll(response)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 1)
        #expect(polls[0].fiveHourUtil == 45.5)
        #expect(polls[0].sevenDayUtil == 23.1)
        #expect(polls[0].fiveHourResetsAt != nil)
        #expect(polls[0].sevenDayResetsAt != nil)
    }

    @Test("persistPoll handles nil values correctly")
    func persistPollHandlesNilValues() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Response with only 5-hour data
        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 50.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        try await service.persistPoll(response)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 1)
        #expect(polls[0].fiveHourUtil == 50.0)
        #expect(polls[0].sevenDayUtil == nil)
        #expect(polls[0].sevenDayResetsAt == nil)
    }

    @Test("persistPoll handles nil utilization in window")
    func persistPollHandlesNilUtilization() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Response with window but nil utilization
        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: nil, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 30.0, resetsAt: nil),
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        try await service.persistPoll(response)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 1)
        #expect(polls[0].fiveHourUtil == nil)
        #expect(polls[0].fiveHourResetsAt != nil)
        #expect(polls[0].sevenDayUtil == 30.0)
        #expect(polls[0].sevenDayResetsAt == nil)
    }

    @Test("persistPoll generates correct timestamp")
    func persistPollGeneratesCorrectTimestamp() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let beforeMs = Int64(Date().timeIntervalSince1970 * 1000)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 10.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        try await service.persistPoll(response)

        let afterMs = Int64(Date().timeIntervalSince1970 * 1000)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 1)
        #expect(polls[0].timestamp >= beforeMs)
        #expect(polls[0].timestamp <= afterMs)
    }

    // MARK: - getRecentPolls Tests (AC #3)

    @Test("getRecentPolls returns correct time range")
    func getRecentPollsReturnsCorrectTimeRange() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert polls at different times using raw SQL for precise control
        // Use offsets slightly less than the hour boundaries to ensure they fall within the query range
        let connection = try dbManager.getConnection()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let thirtyMinsAgo = now - (30 * 60 * 1000)
        let ninetyMinsAgo = now - (90 * 60 * 1000)
        let threeHoursAgo = now - (3 * 60 * 60 * 1000)

        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(threeHoursAgo), 10.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(ninetyMinsAgo), 20.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(thirtyMinsAgo), 30.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(now), 40.0)", nil, nil, &errorMessage)

        // Query for last 2 hours - should return 3 polls (90mins, 30mins, now)
        let polls = try await service.getRecentPolls(hours: 2)
        #expect(polls.count == 3)

        // Query for last 1 hour - should return 2 polls (30mins, now)
        let recentPolls = try await service.getRecentPolls(hours: 1)
        #expect(recentPolls.count == 2)
    }

    @Test("getRecentPolls returns polls ordered by timestamp ascending")
    func getRecentPollsOrderedByTimestamp() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert polls in random order
        let connection = try dbManager.getConnection()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let t1 = now - 30000
        let t2 = now - 20000
        let t3 = now - 10000

        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(t2), 20.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(t1), 10.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(t3), 30.0)", nil, nil, &errorMessage)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 3)
        #expect(polls[0].timestamp < polls[1].timestamp)
        #expect(polls[1].timestamp < polls[2].timestamp)
    }

    // MARK: - Graceful Degradation Tests (AC #2)

    @Test("persistPoll silently skips when database unavailable")
    func persistPollSkipsWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 50.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        // Should not throw - silently skips
        try await service.persistPoll(response)
    }

    @Test("getRecentPolls returns empty array when database unavailable")
    func getRecentPollsReturnsEmptyWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.isEmpty)
    }

    @Test("getDatabaseSize returns 0 when database unavailable")
    func getDatabaseSizeReturnsZeroWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let size = try await service.getDatabaseSize()
        #expect(size == 0)
    }

    // MARK: - Duplicate Prevention Tests (AC #3)

    @Test("Rapid calls create separate rows")
    func rapidCallsCreateSeparateRows() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 50.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        // Call persistPoll multiple times rapidly
        try await service.persistPoll(response)
        try await service.persistPoll(response)
        try await service.persistPoll(response)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 3)

        // Each should have a unique ID
        let ids = Set(polls.map { $0.id })
        #expect(ids.count == 3)
    }

    // MARK: - getDatabaseSize Tests

    @Test("getDatabaseSize returns non-zero for database with data")
    func getDatabaseSizeReturnsNonZero() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert some data
        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 50.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response)

        let size = try await service.getDatabaseSize()
        #expect(size > 0)
    }

    // MARK: - Protocol Conformance

    @Test("HistoricalDataService conforms to HistoricalDataServiceProtocol")
    func conformsToProtocol() throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        let service = HistoricalDataService(databaseManager: dbManager)
        let _: any HistoricalDataServiceProtocol = service
    }
}

// MARK: - Mock DatabaseManager for Graceful Degradation Tests

final class MockDatabaseManager: DatabaseManagerProtocol, @unchecked Sendable {
    var shouldBeAvailable: Bool = false

    var isAvailable: Bool {
        return shouldBeAvailable
    }

    func getConnection() throws -> OpaquePointer {
        throw AppError.databaseOpenFailed(path: "mock")
    }

    func ensureSchema() throws {
        // No-op for mock
    }

    func runMigrations() throws {
        // No-op for mock
    }

    func getDatabasePath() -> URL {
        return URL(fileURLWithPath: "/mock/path.db")
    }

    func getSchemaVersion() throws -> Int {
        return 0
    }

    func closeConnection() {
        // No-op for mock
    }
}
