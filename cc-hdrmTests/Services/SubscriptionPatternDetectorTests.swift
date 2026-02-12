import Foundation
import Testing
@testable import cc_hdrm

@Suite("SubscriptionPatternDetector Tests")
struct SubscriptionPatternDetectorTests {

    // MARK: - Test Helpers

    private let mockHistorical = MockHistoricalDataService()
    private let mockPreferences = MockPreferencesManager()

    private var detector: SubscriptionPatternDetector {
        SubscriptionPatternDetector(
            historicalDataService: mockHistorical,
            preferencesManager: mockPreferences
        )
    }

    /// Creates a poll at the given timestamp with specified utilization values.
    private func makePoll(
        daysAgo: Int,
        fiveHourUtil: Double? = 50.0,
        sevenDayUtil: Double? = 30.0,
        extraUsageEnabled: Bool? = nil,
        extraUsageUsedCredits: Double? = nil,
        extraUsageMonthlyLimit: Double? = nil
    ) -> UsagePoll {
        let timestamp = Int64((Date().timeIntervalSince1970 - Double(daysAgo) * 86400) * 1000)
        return UsagePoll(
            id: Int64(daysAgo),
            timestamp: timestamp,
            fiveHourUtil: fiveHourUtil,
            fiveHourResetsAt: nil,
            sevenDayUtil: sevenDayUtil,
            sevenDayResetsAt: nil,
            extraUsageEnabled: extraUsageEnabled,
            extraUsageMonthlyLimit: extraUsageMonthlyLimit,
            extraUsageUsedCredits: extraUsageUsedCredits,
            extraUsageUtilization: nil
        )
    }

    /// Creates a reset event at the given days ago.
    private func makeResetEvent(
        daysAgo: Int,
        fiveHourPeak: Double? = 72.0,
        sevenDayUtil: Double? = 50.0,
        tier: String? = "default_claude_pro"
    ) -> ResetEvent {
        let timestamp = Int64((Date().timeIntervalSince1970 - Double(daysAgo) * 86400) * 1000)
        return ResetEvent(
            id: Int64(daysAgo),
            timestamp: timestamp,
            fiveHourPeak: fiveHourPeak,
            sevenDayUtil: sevenDayUtil,
            tier: tier,
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )
    }

    /// Creates a usage rollup at the given days ago.
    private func makeRollup(
        daysAgo: Int,
        fiveHourAvg: Double? = 50.0,
        sevenDayAvg: Double? = 30.0,
        resetCount: Int = 0
    ) -> UsageRollup {
        let start = Int64((Date().timeIntervalSince1970 - Double(daysAgo) * 86400) * 1000)
        let end = start + 86400 * 1000
        return UsageRollup(
            id: Int64(daysAgo),
            periodStart: start,
            periodEnd: end,
            resolution: .daily,
            fiveHourAvg: fiveHourAvg,
            fiveHourPeak: fiveHourAvg,
            fiveHourMin: fiveHourAvg,
            sevenDayAvg: sevenDayAvg,
            sevenDayPeak: sevenDayAvg,
            sevenDayMin: sevenDayAvg,
            resetCount: resetCount,
            unusedCredits: nil
        )
    }

    // MARK: - AC 8: Empty results when no patterns

    @Test("analyzePatterns returns empty array when no patterns detected")
    func emptyWhenNoPatterns() async throws {
        // No data at all
        mockHistorical.recentPollsToReturn = []
        mockHistorical.mockResetEvents = []
        mockHistorical.rolledUpDataToReturn = []

        let findings = try await detector.analyzePatterns()
        #expect(findings.isEmpty)
    }

    // MARK: - AC 2: Forgotten Subscription

    @Test("forgottenSubscription detected when avg utilization < 5% for 14+ days")
    func forgottenSubscriptionDetected() async throws {
        // Create 3 weeks of very low usage
        var polls: [UsagePoll] = []
        for day in 0..<21 {
            polls.append(makePoll(daysAgo: day, fiveHourUtil: 2.0))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1, tier: "default_claude_pro")]

        let findings = try await detector.analyzePatterns()

        let forgotten = findings.first {
            if case .forgottenSubscription = $0 { return true }
            return false
        }
        #expect(forgotten != nil)

        if case .forgottenSubscription(let weeks, let avgUtil, let cost) = forgotten {
            #expect(weeks >= 2)
            #expect(avgUtil < 5.0)
            #expect(cost == 20.0) // Pro tier
        }
    }

    @Test("forgottenSubscription NOT detected when utilization above 5%")
    func forgottenSubscriptionNotDetectedHighUsage() async throws {
        var polls: [UsagePoll] = []
        for day in 0..<21 {
            polls.append(makePoll(daysAgo: day, fiveHourUtil: 50.0))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1)]

        let findings = try await detector.analyzePatterns()
        let forgotten = findings.first {
            if case .forgottenSubscription = $0 { return true }
            return false
        }
        #expect(forgotten == nil)
    }

    @Test("forgottenSubscription skipped with insufficient data (< 14 days)")
    func forgottenSubscriptionInsufficientData() async throws {
        var polls: [UsagePoll] = []
        for day in 0..<10 {
            polls.append(makePoll(daysAgo: day, fiveHourUtil: 1.0))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = []

        let findings = try await detector.analyzePatterns()
        let forgotten = findings.first {
            if case .forgottenSubscription = $0 { return true }
            return false
        }
        #expect(forgotten == nil)
    }

    // MARK: - AC 3: Chronic Overpaying

    @Test("chronicOverpaying detected when total cost fits cheaper tier for 3+ months")
    func chronicOverpayingDetected() async throws {
        // User on Max 5x ($100/mo) but only using Pro-level capacity
        var resetEvents: [ResetEvent] = []
        for month in 0..<4 {
            for week in 0..<4 {
                let daysAgo = month * 30 + week * 7
                resetEvents.append(makeResetEvent(
                    daysAgo: daysAgo,
                    fiveHourPeak: 10.0,  // 10% of Max 5x capacity, well within Pro limits
                    sevenDayUtil: 5.0,
                    tier: "default_claude_max_5x"
                ))
            }
        }
        mockHistorical.mockResetEvents = resetEvents.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.recentPollsToReturn = [] // No extra usage

        let findings = try await detector.analyzePatterns()
        let overpaying = findings.first {
            if case .chronicOverpaying = $0 { return true }
            return false
        }
        #expect(overpaying != nil)

        if case .chronicOverpaying(let current, let recommended, let savings) = overpaying {
            #expect(current == "Max 5x")
            #expect(recommended == "Pro")
            #expect(savings > 0)
        }
    }

    @Test("chronicOverpaying NOT detected when on cheapest tier")
    func chronicOverpayingNotOnCheapest() async throws {
        var resetEvents: [ResetEvent] = []
        for month in 0..<4 {
            resetEvents.append(makeResetEvent(
                daysAgo: month * 30,
                fiveHourPeak: 10.0,
                tier: "default_claude_pro"
            ))
        }
        mockHistorical.mockResetEvents = resetEvents.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.recentPollsToReturn = []

        let findings = try await detector.analyzePatterns()
        let overpaying = findings.first {
            if case .chronicOverpaying = $0 { return true }
            return false
        }
        #expect(overpaying == nil)
    }

    @Test("chronicOverpaying skipped with insufficient data")
    func chronicOverpayingInsufficientData() async throws {
        // Only 2 months of data, need 3
        var resetEvents: [ResetEvent] = []
        for month in 0..<2 {
            resetEvents.append(makeResetEvent(
                daysAgo: month * 30,
                fiveHourPeak: 10.0,
                tier: "default_claude_max_5x"
            ))
        }
        mockHistorical.mockResetEvents = resetEvents.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.recentPollsToReturn = []

        let findings = try await detector.analyzePatterns()
        let overpaying = findings.first {
            if case .chronicOverpaying = $0 { return true }
            return false
        }
        #expect(overpaying == nil)
    }

    // MARK: - AC 4: Chronic Underpowering

    @Test("chronicUnderpowering detected when rate-limited N+ times for 2+ cycles")
    func chronicUnderpoweringDetected() async throws {
        // Create polls showing frequent rate-limiting over 2 months
        var polls: [UsagePoll] = []
        for day in 0..<60 {
            if day % 5 == 0 {
                // Rate-limited poll every 5 days
                polls.append(makePoll(daysAgo: day, fiveHourUtil: 100.0))
            } else {
                polls.append(makePoll(daysAgo: day, fiveHourUtil: 70.0))
            }
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1, tier: "default_claude_pro")]

        let findings = try await detector.analyzePatterns()
        let underpowering = findings.first {
            if case .chronicUnderpowering = $0 { return true }
            return false
        }
        #expect(underpowering != nil)

        if case .chronicUnderpowering(let count, let current, let suggested) = underpowering {
            #expect(count >= 3)
            #expect(current == "Pro")
            #expect(suggested == "Max 5x")
        }
    }

    @Test("chronicUnderpowering cost-based trigger when extra usage enabled")
    func chronicUnderpoweringCostBased() async throws {
        // Pro user ($20/mo) with extra usage costing $90/mo = $110 total > Max 5x $100/mo
        var polls: [UsagePoll] = []
        for day in 0..<60 {
            polls.append(makePoll(
                daysAgo: day,
                fiveHourUtil: 70.0,
                extraUsageEnabled: true,
                extraUsageUsedCredits: 90.0
            ))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1, tier: "default_claude_pro")]

        let findings = try await detector.analyzePatterns()
        let underpowering = findings.first {
            if case .chronicUnderpowering = $0 { return true }
            return false
        }
        #expect(underpowering != nil)

        if case .chronicUnderpowering(_, let current, let suggested) = underpowering {
            #expect(current == "Pro")
            #expect(suggested == "Max 5x")
        }
    }

    // MARK: - AC 5: Usage Decay

    @Test("usageDecay detected when utilization declines 3+ consecutive months")
    func usageDecayDetected() async throws {
        // Create rollups showing declining utilization over 4 months
        var rollups: [UsageRollup] = []
        let utilValues: [Double] = [80.0, 65.0, 45.0, 30.0] // declining
        for (index, util) in utilValues.enumerated() {
            let daysAgo = (utilValues.count - index) * 30
            rollups.append(makeRollup(daysAgo: daysAgo, fiveHourAvg: util))
        }
        mockHistorical.rolledUpDataToReturn = rollups.sorted { $0.periodStart < $1.periodStart }
        mockHistorical.recentPollsToReturn = []
        mockHistorical.mockResetEvents = []

        let findings = try await detector.analyzePatterns()
        let decay = findings.first {
            if case .usageDecay = $0 { return true }
            return false
        }
        #expect(decay != nil)

        if case .usageDecay(let current, let threeMonthAgo) = decay {
            #expect(current < threeMonthAgo)
        }
    }

    @Test("usageDecay NOT detected when utilization increases")
    func usageDecayNotDetectedIncreasing() async throws {
        var rollups: [UsageRollup] = []
        let utilValues: [Double] = [30.0, 45.0, 65.0, 80.0] // increasing
        for (index, util) in utilValues.enumerated() {
            let daysAgo = (utilValues.count - index) * 30
            rollups.append(makeRollup(daysAgo: daysAgo, fiveHourAvg: util))
        }
        mockHistorical.rolledUpDataToReturn = rollups.sorted { $0.periodStart < $1.periodStart }
        mockHistorical.recentPollsToReturn = []
        mockHistorical.mockResetEvents = []

        let findings = try await detector.analyzePatterns()
        let decay = findings.first {
            if case .usageDecay = $0 { return true }
            return false
        }
        #expect(decay == nil)
    }

    // MARK: - AC 6: Extra Usage Overflow

    @Test("extraUsageOverflow detected with 2+ consecutive periods of overflow")
    func extraUsageOverflowDetected() async throws {
        // Create polls with extra usage over 2+ months
        // Extra usage of $100/mo on Pro ($20) = $120 total > Max 5x ($100), so savings = $20
        var polls: [UsagePoll] = []
        for day in 0..<60 {
            polls.append(makePoll(
                daysAgo: day,
                fiveHourUtil: 80.0,
                extraUsageEnabled: true,
                extraUsageUsedCredits: 100.0
            ))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1, tier: "default_claude_pro")]

        let findings = try await detector.analyzePatterns()
        let overflow = findings.first {
            if case .extraUsageOverflow = $0 { return true }
            return false
        }
        #expect(overflow != nil)

        if case .extraUsageOverflow(let avgExtra, let recommended, let savings) = overflow {
            #expect(avgExtra > 0)
            #expect(!recommended.isEmpty)
            #expect(savings > 0)
        }
    }

    @Test("extraUsageOverflow skipped when extra_usage disabled")
    func extraUsageOverflowSkippedDisabled() async throws {
        var polls: [UsagePoll] = []
        for day in 0..<60 {
            polls.append(makePoll(daysAgo: day, fiveHourUtil: 80.0, extraUsageEnabled: false))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1)]

        let findings = try await detector.analyzePatterns()
        let overflow = findings.first {
            if case .extraUsageOverflow = $0 { return true }
            return false
        }
        #expect(overflow == nil)
    }

    // MARK: - AC 7: Persistent Extra Usage

    @Test("persistentExtraUsage detected when extra > 50% of base for 2+ months")
    func persistentExtraUsageDetected() async throws {
        // Pro at $20/mo with $15/mo extra usage (75% of base, > 50% threshold)
        var polls: [UsagePoll] = []
        for day in 0..<60 {
            polls.append(makePoll(
                daysAgo: day,
                fiveHourUtil: 70.0,
                extraUsageEnabled: true,
                extraUsageUsedCredits: 15.0
            ))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1, tier: "default_claude_pro")]

        let findings = try await detector.analyzePatterns()
        let persistent = findings.first {
            if case .persistentExtraUsage = $0 { return true }
            return false
        }
        #expect(persistent != nil)

        if case .persistentExtraUsage(let avgExtra, let base, let recommended) = persistent {
            #expect(avgExtra > 0)
            #expect(base == 20.0)
            #expect(!recommended.isEmpty)
        }
    }

    @Test("persistentExtraUsage skipped when extra usage data nil")
    func persistentExtraUsageSkippedNilData() async throws {
        var polls: [UsagePoll] = []
        for day in 0..<60 {
            polls.append(makePoll(daysAgo: day, fiveHourUtil: 70.0))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1)]

        let findings = try await detector.analyzePatterns()
        let persistent = findings.first {
            if case .persistentExtraUsage = $0 { return true }
            return false
        }
        #expect(persistent == nil)
    }

    // MARK: - Multiple findings

    @Test("analyzePatterns returns multiple findings when multiple patterns match")
    func multipleFindings() async throws {
        // Set up data that triggers both forgotten subscription AND extra usage
        var polls: [UsagePoll] = []
        for day in 0..<21 {
            polls.append(makePoll(
                daysAgo: day,
                fiveHourUtil: 2.0,
                extraUsageEnabled: true,
                extraUsageUsedCredits: 15.0
            ))
        }
        mockHistorical.recentPollsToReturn = polls.sorted { $0.timestamp < $1.timestamp }
        mockHistorical.mockResetEvents = [makeResetEvent(daysAgo: 1, tier: "default_claude_pro")]

        let findings = try await detector.analyzePatterns()
        // Should detect at least forgotten subscription (low utilization for 3 weeks)
        let hasForgotten = findings.contains {
            if case .forgottenSubscription = $0 { return true }
            return false
        }
        #expect(hasForgotten)
        // May also detect persistent extra usage since $15 > 50% of $20
    }
}
