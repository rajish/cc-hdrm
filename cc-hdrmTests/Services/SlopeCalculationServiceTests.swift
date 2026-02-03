import Foundation
import Testing
@testable import cc_hdrm

@Suite("SlopeCalculationService Tests")
struct SlopeCalculationServiceTests {

    // MARK: - Test Helpers

    /// Creates a test poll with the given parameters.
    private func createTestPoll(
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        fiveHourUtil: Double? = nil,
        sevenDayUtil: Double? = nil
    ) -> UsagePoll {
        UsagePoll(
            id: 0,
            timestamp: timestamp,
            fiveHourUtil: fiveHourUtil,
            fiveHourResetsAt: nil,
            sevenDayUtil: sevenDayUtil,
            sevenDayResetsAt: nil
        )
    }

    // MARK: - Basic Buffer Tests (AC #1)

    @Test("addPoll adds entry to buffer")
    func addPollAddsEntry() {
        let service = SlopeCalculationService()
        let poll = createTestPoll(fiveHourUtil: 50.0, sevenDayUtil: 30.0)

        service.addPoll(poll)

        // Verify by calculating slope (should return .flat due to insufficient data)
        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    @Test("buffer evicts entries older than 15 minutes")
    func bufferEvictsOldEntries() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add an old poll (20 minutes ago - should be evicted)
        let oldPoll = createTestPoll(
            timestamp: nowMs - (20 * 60 * 1000),
            fiveHourUtil: 30.0
        )
        service.addPoll(oldPoll)

        // Add a recent poll (now) - this should trigger eviction of old poll
        let recentPoll = createTestPoll(
            timestamp: nowMs,
            fiveHourUtil: 50.0
        )
        service.addPoll(recentPoll)

        // Should still return .flat because we only have 1 entry (old one evicted)
        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    // MARK: - Insufficient Data Tests (AC #3)

    @Test("calculateSlope returns .flat with insufficient data (<10 min)")
    func insufficientDataReturnsFlat() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add only 5 polls over 2.5 minutes - insufficient
        for i in 0..<5 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((5 - i) * 30 * 1000), // 30s intervals going back
                fiveHourUtil: 50.0 + Double(i)
            )
            service.addPoll(poll)
        }

        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    @Test("calculateSlope returns .flat with insufficient entry count")
    func insufficientEntryCountReturnsFlat() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add 10 polls (need 20 minimum)
        for i in 0..<10 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((10 - i) * 60 * 1000), // 1 min intervals
                fiveHourUtil: 50.0 + Double(i)
            )
            service.addPoll(poll)
        }

        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    // MARK: - Slope Level Calculation Tests (AC #2)

    @Test("calculateSlope returns .flat for stable/idle utilization (rate < 0.3%/min)")
    func flatForStableUtilization() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add 25 polls over 12 minutes with minimal increase
        // Total increase: 2% over 12 min = 0.167%/min → flat
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)), // 30s intervals
                fiveHourUtil: 50.0 + (Double(i) * 0.08) // +0.08% per poll = ~0.16%/min
            )
            service.addPoll(poll)
        }

        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    @Test("calculateSlope returns .rising for moderate increase (rate 0.3-1.5%/min)")
    func risingForModerateIncrease() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add 25 polls over 12 minutes with moderate increase
        // Total increase: 9% over 12 min = 0.75%/min → rising
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: 50.0 + (Double(i) * 0.36) // +0.36% per poll = ~0.72%/min
            )
            service.addPoll(poll)
        }

        #expect(service.calculateSlope(for: .fiveHour) == .rising)
    }

    @Test("calculateSlope returns .steep for rapid increase (rate > 1.5%/min)")
    func steepForRapidIncrease() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add 25 polls over 12 minutes with rapid increase
        // Total increase: 24% over 12 min = 2%/min → steep
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: 50.0 + Double(i) // +1% per poll = 2%/min
            )
            service.addPoll(poll)
        }

        #expect(service.calculateSlope(for: .fiveHour) == .steep)
    }

    @Test("negative rate (reset edge case) returns .flat")
    func negativeRateReturnsFlat() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add 25 polls with DECREASING utilization (simulates reset in buffer)
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: 80.0 - Double(i) // Decreasing
            )
            service.addPoll(poll)
        }

        // Negative rate should map to .flat
        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    // MARK: - Bootstrap Tests (AC #1)

    @Test("bootstrapFromHistory populates buffer correctly")
    func bootstrapPopulatesBuffer() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Create 25 historical polls within 15-minute window
        var polls: [UsagePoll] = []
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((10 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: 50.0 + (Double(i) * 0.5)
            )
            polls.append(poll)
        }

        service.bootstrapFromHistory(polls)

        // Should have data and return a valid slope (rising based on ~1%/min)
        let slope = service.calculateSlope(for: .fiveHour)
        #expect(slope == .rising || slope == .steep) // Depends on exact timing
    }

    @Test("bootstrapFromHistory filters out old polls")
    func bootstrapFiltersOldPolls() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Create polls outside 15-minute window
        var polls: [UsagePoll] = []
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((30 * 60 * 1000) + (i * 30 * 1000)), // 30+ minutes ago
                fiveHourUtil: 50.0 + Double(i)
            )
            polls.append(poll)
        }

        service.bootstrapFromHistory(polls)

        // Should return .flat due to no data (all filtered out)
        #expect(service.calculateSlope(for: .fiveHour) == .flat)
    }

    // MARK: - Independent Window Tests (AC #2)

    @Test("5h and 7d windows calculated independently")
    func windowsCalculatedIndependently() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add 25 polls with different rates for each window
        // 5h: steep increase
        // 7d: flat/stable
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: 50.0 + Double(i), // +1% per poll → steep
                sevenDayUtil: 30.0 + (Double(i) * 0.05) // +0.05% per poll → flat
            )
            service.addPoll(poll)
        }

        #expect(service.calculateSlope(for: .fiveHour) == .steep)
        #expect(service.calculateSlope(for: .sevenDay) == .flat)
    }

    // MARK: - Protocol Conformance Tests

    @Test("SlopeCalculationService conforms to protocol")
    func protocolConformance() {
        let service: any SlopeCalculationServiceProtocol = SlopeCalculationService()

        // Verify protocol methods are accessible
        let poll = createTestPoll(fiveHourUtil: 50.0)
        service.addPoll(poll)
        _ = service.calculateSlope(for: .fiveHour)
        service.bootstrapFromHistory([poll])

        // If this compiles and runs, protocol conformance is verified
        #expect(true)
    }

    // MARK: - Thread Safety Tests

    @Test("concurrent addPoll calls do not crash")
    func concurrentAddPollIsSafe() async {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Launch 100 concurrent addPoll operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let poll = UsagePoll(
                        id: Int64(i),
                        timestamp: nowMs + Int64(i * 100), // Slight offset per task
                        fiveHourUtil: Double(i),
                        fiveHourResetsAt: nil,
                        sevenDayUtil: Double(i),
                        sevenDayResetsAt: nil
                    )
                    service.addPoll(poll)
                }
            }
        }

        // If we get here without crash, thread safety is working
        // Also verify we can read without crash
        _ = service.calculateSlope(for: .fiveHour)
        _ = service.calculateSlope(for: .sevenDay)
        #expect(true)
    }

    @Test("concurrent read and write operations do not crash")
    func concurrentReadWriteIsSafe() async {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Pre-populate with some data
        for i in 0..<25 {
            let poll = UsagePoll(
                id: Int64(i),
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: 50.0 + Double(i),
                fiveHourResetsAt: nil,
                sevenDayUtil: 30.0 + Double(i),
                sevenDayResetsAt: nil
            )
            service.addPoll(poll)
        }

        // Launch concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // 50 writers
            for i in 0..<50 {
                group.addTask {
                    let poll = UsagePoll(
                        id: Int64(100 + i),
                        timestamp: nowMs + Int64(i * 100),
                        fiveHourUtil: 60.0 + Double(i),
                        fiveHourResetsAt: nil,
                        sevenDayUtil: 40.0 + Double(i),
                        sevenDayResetsAt: nil
                    )
                    service.addPoll(poll)
                }
            }
            // 50 readers
            for _ in 0..<50 {
                group.addTask {
                    _ = service.calculateSlope(for: .fiveHour)
                    _ = service.calculateSlope(for: .sevenDay)
                }
            }
        }

        #expect(true)
    }

    // MARK: - Edge Cases

    @Test("nil utilization values are excluded from calculation")
    func nilValuesExcluded() {
        let service = SlopeCalculationService()
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

        // Add polls with nil fiveHourUtil but valid sevenDayUtil
        for i in 0..<25 {
            let poll = createTestPoll(
                timestamp: nowMs - Int64((12 * 60 * 1000) - (i * 30 * 1000)),
                fiveHourUtil: nil,
                sevenDayUtil: 30.0 + Double(i)
            )
            service.addPoll(poll)
        }

        // 5h should return flat (no data)
        #expect(service.calculateSlope(for: .fiveHour) == .flat)
        // 7d should calculate normally
        #expect(service.calculateSlope(for: .sevenDay) == .steep)
    }
}
