import Foundation
@testable import cc_hdrm

/// Shared mock for HistoricalDataService used across test suites.
final class MockHistoricalDataService: HistoricalDataServiceProtocol, @unchecked Sendable {
    var persistPollCallCount = 0
    var lastPersistedResponse: UsageResponse?
    var lastPersistedTier: String?
    var shouldThrow = false
    var mockLastPoll: UsagePoll?
    var mockResetEvents: [ResetEvent] = []
    var recentPollsToReturn: [UsagePoll] = []
    var rolledUpDataToReturn: [UsageRollup] = []
    var shouldThrowOnGetRecentPolls = false
    var shouldThrowOnGetRolledUpData = false
    var shouldThrowOnEnsureRollupsUpToDate = false
    var getRecentPollsCallCount = 0
    var getRolledUpDataCallCount = 0
    var ensureRollupsUpToDateCallCount = 0
    var getResetEventsCallCount = 0
    var lastQueriedTimeRange: TimeRange?

    func persistPoll(_ response: UsageResponse) async throws {
        try await persistPoll(response, tier: nil)
    }

    func persistPoll(_ response: UsageResponse, tier: String?) async throws {
        persistPollCallCount += 1
        lastPersistedResponse = response
        lastPersistedTier = tier
        if shouldThrow {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 1))
        }
    }

    func getRecentPolls(hours: Int) async throws -> [UsagePoll] {
        getRecentPollsCallCount += 1
        if shouldThrowOnGetRecentPolls {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 2))
        }
        return recentPollsToReturn
    }

    func getLastPoll() async throws -> UsagePoll? {
        return mockLastPoll
    }

    func getResetEvents(fromTimestamp: Int64?, toTimestamp: Int64?) async throws -> [ResetEvent] {
        getResetEventsCallCount += 1
        return mockResetEvents.filter { event in
            if let from = fromTimestamp, event.timestamp < from { return false }
            if let to = toTimestamp, event.timestamp > to { return false }
            return true
        }
    }

    func getResetEvents(range: TimeRange) async throws -> [ResetEvent] {
        getResetEventsCallCount += 1
        lastQueriedTimeRange = range
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let fromTimestamp: Int64?

        switch range {
        case .day:
            fromTimestamp = nowMs - (24 * 60 * 60 * 1000)
        case .week:
            fromTimestamp = nowMs - (7 * 24 * 60 * 60 * 1000)
        case .month:
            fromTimestamp = nowMs - (30 * 24 * 60 * 60 * 1000)
        case .all:
            fromTimestamp = nil
        }

        return mockResetEvents.filter { event in
            guard let from = fromTimestamp else { return true }
            return event.timestamp >= from && event.timestamp <= nowMs
        }
    }

    func getDatabaseSize() async throws -> Int64 {
        return 0
    }

    func ensureRollupsUpToDate() async throws {
        ensureRollupsUpToDateCallCount += 1
        if shouldThrowOnEnsureRollupsUpToDate {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 3))
        }
    }

    func getRolledUpData(range: TimeRange) async throws -> [UsageRollup] {
        getRolledUpDataCallCount += 1
        lastQueriedTimeRange = range
        if shouldThrowOnGetRolledUpData {
            throw AppError.databaseQueryFailed(underlying: NSError(domain: "test", code: 4))
        }
        return rolledUpDataToReturn
    }

    func pruneOldData(retentionDays: Int) async throws {
        // No-op for mock
    }
}
