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

    // MARK: - Reset Detection Tests (Story 10.3)

    @Test("Reset detected when resets_at changes (AC #1)")
    func resetDetectedWhenResetsAtChanges() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // First poll with resets_at = T1
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 50.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: WindowUsage(utilization: 30.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: "test_tier")

        // Second poll with different resets_at = T2 (indicates reset occurred)
        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 10.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 30.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: "test_tier")

        // Verify reset event was recorded
        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].tier == "test_tier")
    }

    @Test("Fallback detection on large utilization drop (AC #2)")
    func fallbackDetectionOnLargeUtilizationDrop() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // First poll at 80% utilization (no resets_at)
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 80.0, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 40.0, resetsAt: nil),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        // Second poll at 5% utilization (large drop, no resets_at)
        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: nil),
            sevenDay: WindowUsage(utilization: 40.0, resetsAt: nil),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        // Verify reset event was inferred
        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
    }

    @Test("No false positive on small utilization change (AC #1)")
    func noFalsePositiveOnSmallUtilizationChange() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert polls with small changes (shouldn't trigger reset)
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 50.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        // Same resets_at, small utilization increase
        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 52.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 0)
    }

    @Test("No false positive on small utilization drop without resets_at")
    func noFalsePositiveOnSmallUtilizationDrop() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // First poll at 60%
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 60.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        // Small drop to 45% (only 15% drop, below 50% threshold)
        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 45.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 0)
    }

    @Test("getResetEvents returns correct data (AC #3)")
    func getResetEventsReturnsCorrectData() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Trigger a reset
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 80.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: WindowUsage(utilization: 45.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: "my_tier")

        // Small delay to ensure different timestamps (peak lookup uses timestamp < currentTimestamp)
        try await Task.sleep(for: .milliseconds(10))

        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 45.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: "my_tier")

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].tier == "my_tier")
        #expect(events[0].fiveHourPeak != nil)
        #expect(events[0].sevenDayUtil == 45.0)
    }

    @Test("Credit fields are NULL when tier unknown (AC #3)")
    func creditFieldsNullWhenTierUnknown() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Trigger reset with nil tier
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 75.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        // Small delay to ensure different timestamps (peak lookup uses timestamp < currentTimestamp)
        try await Task.sleep(for: .milliseconds(10))

        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 10.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].tier == nil)
        #expect(events[0].usedCredits == nil)
        #expect(events[0].constrainedCredits == nil)
        #expect(events[0].wasteCredits == nil)
    }

    @Test("getLastPoll returns most recent poll")
    func getLastPollReturnsMostRecent() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert multiple polls
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 10.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 20.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        let response3 = UsageResponse(
            fiveHour: WindowUsage(utilization: 30.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response3, tier: nil)

        let lastPoll = try await service.getLastPoll()
        #expect(lastPoll != nil)
        #expect(lastPoll?.fiveHourUtil == 30.0)
    }

    @Test("getLastPoll returns nil when no polls exist")
    func getLastPollReturnsNilWhenEmpty() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let lastPoll = try await service.getLastPoll()
        #expect(lastPoll == nil)
    }

    @Test("getLastPoll returns nil when database unavailable")
    func getLastPollReturnsNilWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let lastPoll = try await service.getLastPoll()
        #expect(lastPoll == nil)
    }

    @Test("getResetEvents returns empty when database unavailable")
    func getResetEventsReturnsEmptyWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.isEmpty)
    }

    @Test("getResetEvents filters by timestamp range")
    func getResetEventsFiltersByTimestampRange() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Trigger two resets at different times
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 80.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        // Get all events first
        let allEvents = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(allEvents.count == 1)

        // Now filter with a timestamp range that includes the event
        let eventTimestamp = allEvents[0].timestamp
        let filteredEvents = try await service.getResetEvents(
            fromTimestamp: eventTimestamp - 1000,
            toTimestamp: eventTimestamp + 1000
        )
        #expect(filteredEvents.count == 1)

        // Filter with a range that excludes the event
        let excludedEvents = try await service.getResetEvents(
            fromTimestamp: eventTimestamp + 10000,
            toTimestamp: eventTimestamp + 20000
        )
        #expect(excludedEvents.count == 0)
    }

    @Test("Reset event captures pre-reset 7d utilization (from previous poll)")
    func resetEventCapturesPreReset7dUtil() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // First poll: 7d util = 40% (this is the PRE-reset value we should capture)
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 80.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: WindowUsage(utilization: 40.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: nil)

        // Second poll: 7d util = 42% (POST-reset value, should NOT be captured)
        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 42.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: nil)

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        // Should capture pre-reset 7d util (40%), not post-reset (42%)
        #expect(events[0].sevenDayUtil == 40.0)
    }

    @Test("Peak utilization is recorded from recent polls")
    func peakUtilizationRecordedFromRecentPolls() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert polls with increasing utilization
        // Small delays ensure different timestamps (peak lookup uses timestamp < currentTimestamp)
        for util in [10.0, 30.0, 75.0, 50.0] {
            let response = UsageResponse(
                fiveHour: WindowUsage(utilization: util, resetsAt: "2026-02-03T10:00:00Z"),
                sevenDay: nil,
                sevenDaySonnet: nil,
                extraUsage: nil
            )
            try await service.persistPoll(response, tier: nil)
            try await Task.sleep(for: .milliseconds(10))
        }

        // Now trigger a reset - the peak should be 75.0
        let resetResponse = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(resetResponse, tier: nil)

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].fiveHourPeak == 75.0)
    }

    // MARK: - Story 14.2: Credit Field Population Tests

    @Test("Reset event populates credit fields when tier is known (AC 1)")
    func creditFieldsPopulatedWhenTierKnown() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let analysisService = HeadroomAnalysisService()
        let service = HistoricalDataService(
            databaseManager: dbManager,
            headroomAnalysisService: analysisService,
            preferencesManager: nil
        )

        // First poll: 72% peak, 85% 7d util (Pro tier example from story dev notes)
        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 72.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: WindowUsage(utilization: 85.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: "default_claude_pro")

        try await Task.sleep(for: .milliseconds(10))

        // Second poll: triggers reset (different resets_at)
        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 85.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: "default_claude_pro")

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].usedCredits != nil, "usedCredits should be populated for known tier")
        #expect(events[0].constrainedCredits != nil, "constrainedCredits should be populated for known tier")
        #expect(events[0].wasteCredits != nil, "wasteCredits should be populated for known tier")

        // Pro tier: 5h_limit = 550,000. Peak 72% -> used = 396,000
        if let used = events[0].usedCredits {
            #expect(abs(used - 396_000) < 1.0, "Expected usedCredits ~396,000, got \(used)")
        }
    }

    @Test("Reset event credit fields NULL when tier unknown and no analysis service (AC 2)")
    func creditFieldsNullWhenNoAnalysisService() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        // No headroomAnalysisService injected
        let service = HistoricalDataService(databaseManager: dbManager)

        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 72.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: WindowUsage(utilization: 85.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: "default_claude_pro")

        try await Task.sleep(for: .milliseconds(10))

        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 85.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: "default_claude_pro")

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].usedCredits == nil, "usedCredits should be NULL without analysis service")
        #expect(events[0].constrainedCredits == nil, "constrainedCredits should be NULL without analysis service")
        #expect(events[0].wasteCredits == nil, "wasteCredits should be NULL without analysis service")
    }

    @Test("Reset event credit fields NULL when tier is unrecognized (AC 2)")
    func creditFieldsNullWhenTierUnrecognized() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let analysisService = HeadroomAnalysisService()
        let service = HistoricalDataService(
            databaseManager: dbManager,
            headroomAnalysisService: analysisService,
            preferencesManager: nil
        )

        let response1 = UsageResponse(
            fiveHour: WindowUsage(utilization: 72.0, resetsAt: "2026-02-03T10:00:00Z"),
            sevenDay: WindowUsage(utilization: 85.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response1, tier: "unknown_tier_xyz")

        try await Task.sleep(for: .milliseconds(10))

        let response2 = UsageResponse(
            fiveHour: WindowUsage(utilization: 5.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: WindowUsage(utilization: 85.0, resetsAt: "2026-02-10T00:00:00Z"),
            sevenDaySonnet: nil,
            extraUsage: nil
        )
        try await service.persistPoll(response2, tier: "unknown_tier_xyz")

        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
        #expect(events[0].usedCredits == nil, "usedCredits should be NULL for unknown tier")
        #expect(events[0].constrainedCredits == nil, "constrainedCredits should be NULL for unknown tier")
        #expect(events[0].wasteCredits == nil, "wasteCredits should be NULL for unknown tier")
    }

    // MARK: - Story 10.4: Tiered Rollup Engine Tests

    @Test("ensureRollupsUpToDate skips when database unavailable")
    func ensureRollupsUpToDateSkipsWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        // Should not throw - silently skips
        try await service.ensureRollupsUpToDate()
    }

    @Test("ensureRollupsUpToDate completes without error on empty database")
    func ensureRollupsUpToDateCompletesOnEmptyDatabase() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Should complete without error even with no data
        try await service.ensureRollupsUpToDate()
    }

    @Test("getRolledUpData returns empty when database unavailable")
    func getRolledUpDataReturnsEmptyWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let rollups = try await service.getRolledUpData(range: .week)
        #expect(rollups.isEmpty)
    }

    @Test("pruneOldData skips when database unavailable")
    func pruneOldDataSkipsWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        // Should not throw - silently skips
        try await service.pruneOldData(retentionDays: 90)
    }

    @Test("getRolledUpData returns raw polls for day range (AC 4)")
    func getRolledUpDataReturnsRawPollsForDayRange() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        // Insert polls with distinct timestamps using direct SQL
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(now - 60000), 10.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(now - 30000), 20.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(now), 30.0)", nil, nil, &errorMessage)

        let rollups = try await service.getRolledUpData(range: .day)
        #expect(rollups.count == 3)
        // Data should be ordered by period_start
        #expect(rollups[0].periodStart <= rollups[1].periodStart)
        #expect(rollups[1].periodStart <= rollups[2].periodStart)
    }

    @Test("pruneOldData removes data older than retention period (AC 1)")
    func pruneOldDataRemovesOldData() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert a reset event that's very old (simulate 100 days ago)
        let connection = try dbManager.getConnection()
        let oldTimestamp = Int64(Date().timeIntervalSince1970 * 1000) - (100 * 24 * 60 * 60 * 1000)
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(
            connection,
            "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(oldTimestamp), 50.0)",
            nil, nil, &errorMessage
        )

        // Verify it exists
        var events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)

        // Prune with 30 day retention
        try await service.pruneOldData(retentionDays: 30)

        // Verify it's gone
        events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 0)
    }

    @Test("pruneOldData keeps recent data (AC 1)")
    func pruneOldDataKeepsRecentData() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Insert a recent reset event (simulate 5 days ago)
        let connection = try dbManager.getConnection()
        let recentTimestamp = Int64(Date().timeIntervalSince1970 * 1000) - (5 * 24 * 60 * 60 * 1000)
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(
            connection,
            "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(recentTimestamp), 50.0)",
            nil, nil, &errorMessage
        )

        // Prune with 30 day retention
        try await service.pruneOldData(retentionDays: 30)

        // Verify recent data is kept
        let events = try await service.getResetEvents(fromTimestamp: nil, toTimestamp: nil)
        #expect(events.count == 1)
    }

    @Test("raw to 5min rollup produces correct aggregates (AC 1)")
    func rawTo5MinRollupProducesCorrectAggregates() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        // Insert raw polls from exactly 25 hours ago (within 24h-7d window)
        // All in the same 5-minute bucket
        let baseTimestamp = Int64(Date().timeIntervalSince1970 * 1000) - (25 * 60 * 60 * 1000)
        // Align to 5-minute bucket
        let fiveMinutesMs: Int64 = 5 * 60 * 1000
        let bucketStart = (baseTimestamp / fiveMinutesMs) * fiveMinutesMs

        var errorMessage: UnsafeMutablePointer<CChar>?
        // Insert 3 polls in the same bucket with different utilization values
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, seven_day_util) VALUES (\(bucketStart), 50.0, 40.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, seven_day_util) VALUES (\(bucketStart + 30000), 60.0, 45.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util, seven_day_util) VALUES (\(bucketStart + 60000), 55.0, 42.0)", nil, nil, &errorMessage)

        // Trigger rollup
        try await service.ensureRollupsUpToDate()

        // Query rollups
        let rollups = try await service.getRolledUpData(range: .week)

        // Find the 5-minute rollup for our specific bucket
        let fiveMinRollups = rollups.filter { 
            $0.resolution == .fiveMin && $0.periodStart == bucketStart 
        }

        // Verify rollup was created with correct aggregates
        // Expected: avg=(50+60+55)/3=55, peak=60, min=50 for 5h window
        // Expected: avg=(40+45+42)/3=42.33, peak=45, min=40 for 7d window
        #expect(!fiveMinRollups.isEmpty, "Expected 5-minute rollup to be created for bucket \(bucketStart)")
        
        if let rollup = fiveMinRollups.first {
            // Verify 5-hour aggregates
            if let avg = rollup.fiveHourAvg {
                #expect(abs(avg - 55.0) < 0.01, "Expected fiveHourAvg ~55.0, got \(avg)")
            }
            #expect(rollup.fiveHourPeak == 60.0, "Expected fiveHourPeak 60.0, got \(String(describing: rollup.fiveHourPeak))")
            #expect(rollup.fiveHourMin == 50.0, "Expected fiveHourMin 50.0, got \(String(describing: rollup.fiveHourMin))")
            
            // Verify 7-day aggregates
            if let avg = rollup.sevenDayAvg {
                #expect(abs(avg - 42.33) < 0.34, "Expected sevenDayAvg ~42.33, got \(avg)")
            }
            #expect(rollup.sevenDayPeak == 45.0, "Expected sevenDayPeak 45.0, got \(String(describing: rollup.sevenDayPeak))")
            #expect(rollup.sevenDayMin == 40.0, "Expected sevenDayMin 40.0, got \(String(describing: rollup.sevenDayMin))")
        }
    }

    @Test("original data deleted after successful rollup (AC 1)")
    func originalDataDeletedAfterRollup() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        // Insert raw poll older than 24h (will be rolled up)
        let oldTimestamp = Int64(Date().timeIntervalSince1970 * 1000) - (25 * 60 * 60 * 1000)
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO usage_polls (timestamp, five_hour_util) VALUES (\(oldTimestamp), 50.0)", nil, nil, &errorMessage)

        // Verify poll exists via direct query
        var statement: OpaquePointer?
        sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM usage_polls WHERE timestamp = \(oldTimestamp)", -1, &statement, nil)
        sqlite3_step(statement)
        let countBefore = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        #expect(countBefore == 1)

        // Trigger rollup
        try await service.ensureRollupsUpToDate()

        // Verify original poll is deleted
        sqlite3_prepare_v2(connection, "SELECT COUNT(*) FROM usage_polls WHERE timestamp = \(oldTimestamp)", -1, &statement, nil)
        sqlite3_step(statement)
        let countAfter = sqlite3_column_int(statement, 0)
        sqlite3_finalize(statement)
        #expect(countAfter == 0)
    }

    @Test("rollup skips if already current")
    func rollupSkipsIfAlreadyCurrent() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        // Run rollup twice on empty database - should be very fast
        let startTime = CFAbsoluteTimeGetCurrent()
        try await service.ensureRollupsUpToDate()
        try await service.ensureRollupsUpToDate()
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete in under 1 second for empty database
        #expect(elapsed < 1.0)
    }

    @Test("graceful degradation when database unavailable during rollup")
    func gracefulDegradationDuringRollup() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        // All operations should complete without throwing
        try await service.ensureRollupsUpToDate()
        let rollups = try await service.getRolledUpData(range: .all)
        try await service.pruneOldData(retentionDays: 90)

        #expect(rollups.isEmpty)
    }

    // MARK: - Extra Usage Persistence Tests

    @Test("persistPoll stores extra usage data")
    func persistPollStoresExtraUsageData() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 45.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: ExtraUsage(isEnabled: true, monthlyLimit: 500.0, usedCredits: 123.45, utilization: 0.247)
        )

        try await service.persistPoll(response)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 1)
        #expect(polls[0].extraUsageEnabled == true)
        #expect(polls[0].extraUsageMonthlyLimit == 500.0)
        #expect(polls[0].extraUsageUsedCredits == 123.45)
        #expect(polls[0].extraUsageUtilization == 0.247)
    }

    @Test("persistPoll stores nil extra usage fields when not reported")
    func persistPollStoresNilExtraUsage() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 45.0, resetsAt: "2026-02-03T15:00:00Z"),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )

        try await service.persistPoll(response)

        let polls = try await service.getRecentPolls(hours: 1)
        #expect(polls.count == 1)
        #expect(polls[0].extraUsageEnabled == nil)
        #expect(polls[0].extraUsageMonthlyLimit == nil)
        #expect(polls[0].extraUsageUsedCredits == nil)
        #expect(polls[0].extraUsageUtilization == nil)
    }

    @Test("getLastPoll returns extra usage data")
    func getLastPollReturnsExtraUsageData() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)

        let response = UsageResponse(
            fiveHour: WindowUsage(utilization: 20.0, resetsAt: nil),
            sevenDay: nil,
            sevenDaySonnet: nil,
            extraUsage: ExtraUsage(isEnabled: false, monthlyLimit: 1000.0, usedCredits: 0.0, utilization: 0.0)
        )

        try await service.persistPoll(response)

        let lastPoll = try await service.getLastPoll()
        #expect(lastPoll != nil)
        #expect(lastPoll?.extraUsageEnabled == false)
        #expect(lastPoll?.extraUsageMonthlyLimit == 1000.0)
        #expect(lastPoll?.extraUsageUsedCredits == 0.0)
        #expect(lastPoll?.extraUsageUtilization == 0.0)
    }

    // MARK: - Story 10.5: Data Query APIs - getResetEvents(range:) Tests

    @Test("getResetEvents with day range returns events in last 24h (AC 4)")
    func getResetEventsWithDayRangeReturnsLast24h() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        // Insert reset events at various times
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let twelveHoursAgo = nowMs - (12 * 60 * 60 * 1000)
        let thirtySixHoursAgo = nowMs - (36 * 60 * 60 * 1000)

        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(twelveHoursAgo), 80.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(thirtySixHoursAgo), 70.0)", nil, nil, &errorMessage)

        let events = try await service.getResetEvents(range: .day)

        #expect(events.count == 1)
        #expect(events[0].timestamp == twelveHoursAgo)
    }

    @Test("getResetEvents with week range returns events in last 7 days (AC 4)")
    func getResetEventsWithWeekRangeReturnsLast7Days() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let threeDaysAgo = nowMs - (3 * 24 * 60 * 60 * 1000)
        let tenDaysAgo = nowMs - (10 * 24 * 60 * 60 * 1000)

        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(threeDaysAgo), 75.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(tenDaysAgo), 65.0)", nil, nil, &errorMessage)

        let events = try await service.getResetEvents(range: .week)

        #expect(events.count == 1)
        #expect(events[0].timestamp == threeDaysAgo)
    }

    @Test("getResetEvents with month range returns events in last 30 days (AC 4)")
    func getResetEventsWithMonthRangeReturnsLast30Days() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let fifteenDaysAgo = nowMs - (15 * 24 * 60 * 60 * 1000)
        let sixtyDaysAgo = nowMs - (60 * 24 * 60 * 60 * 1000)

        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(fifteenDaysAgo), 85.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(sixtyDaysAgo), 55.0)", nil, nil, &errorMessage)

        let events = try await service.getResetEvents(range: .month)

        #expect(events.count == 1)
        #expect(events[0].timestamp == fifteenDaysAgo)
    }

    @Test("getResetEvents with all range returns all events (AC 4)")
    func getResetEventsWithAllRangeReturnsAllEvents() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let oneDayAgo = nowMs - (1 * 24 * 60 * 60 * 1000)
        let fiftyDaysAgo = nowMs - (50 * 24 * 60 * 60 * 1000)
        let hundredDaysAgo = nowMs - (100 * 24 * 60 * 60 * 1000)

        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(oneDayAgo), 90.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(fiftyDaysAgo), 60.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(hundredDaysAgo), 40.0)", nil, nil, &errorMessage)

        let events = try await service.getResetEvents(range: .all)

        #expect(events.count == 3)
    }

    @Test("getResetEvents with range returns events ordered by timestamp ascending (AC 4)")
    func getResetEventsWithRangeOrderedByTimestamp() async throws {
        let (dbManager, path) = makeManager()
        defer { cleanup(manager: dbManager, path: path) }

        try dbManager.ensureSchema()

        let service = HistoricalDataService(databaseManager: dbManager)
        let connection = try dbManager.getConnection()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let t1 = nowMs - 30000
        let t2 = nowMs - 20000
        let t3 = nowMs - 10000

        // Insert in non-chronological order
        var errorMessage: UnsafeMutablePointer<CChar>?
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(t3), 30.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(t1), 10.0)", nil, nil, &errorMessage)
        sqlite3_exec(connection, "INSERT INTO reset_events (timestamp, five_hour_peak) VALUES (\(t2), 20.0)", nil, nil, &errorMessage)

        let events = try await service.getResetEvents(range: .day)

        #expect(events.count == 3)
        #expect(events[0].timestamp == t1)
        #expect(events[1].timestamp == t2)
        #expect(events[2].timestamp == t3)
    }

    @Test("getResetEvents(range:) returns empty when database unavailable")
    func getResetEventsWithRangeReturnsEmptyWhenDatabaseUnavailable() async throws {
        let mockManager = MockDatabaseManager()
        mockManager.shouldBeAvailable = false

        let service = HistoricalDataService(databaseManager: mockManager)

        let events = try await service.getResetEvents(range: .week)
        #expect(events.isEmpty)
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
