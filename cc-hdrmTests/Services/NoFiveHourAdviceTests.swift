import Foundation
import Testing
@testable import cc_hdrm

private let dayMs: Int64 = 24 * 60 * 60 * 1000
private let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

private func cycle(daysAgo: Int64, peak: Double, tier: RateLimitTier = .max20x) -> ResetEvent {
    ResetEvent(
        id: daysAgo,
        timestamp: nowMs - daysAgo * dayMs,
        fiveHourPeak: nil,
        sevenDayUtil: peak,
        tier: tier.rawValue,
        usedCredits: nil,
        constrainedCredits: nil,
        unusedCredits: nil,
        isWeeklyCycle: true
    )
}

private func fiveHourEvent(daysAgo: Int64, peak: Double?, sevenDay: Double, tier: RateLimitTier = .max20x) -> ResetEvent {
    ResetEvent(
        id: daysAgo,
        timestamp: nowMs - daysAgo * dayMs,
        fiveHourPeak: peak,
        sevenDayUtil: sevenDay,
        tier: tier.rawValue,
        usedCredits: nil,
        constrainedCredits: nil,
        unusedCredits: nil
    )
}

private func poll(daysAgo: Int64, fiveHour: Double?, sevenDay: Double?) -> UsagePoll {
    UsagePoll(
        id: daysAgo,
        timestamp: nowMs - daysAgo * dayMs,
        fiveHourUtil: fiveHour,
        fiveHourResetsAt: nil,
        sevenDayUtil: sevenDay,
        sevenDayResetsAt: nil
    )
}

/// Mid-month timestamp `monthsAgo` calendar months back, so each value lands in its own month.
private func midMonthMs(monthsAgo: Int) -> Int64 {
    let calendar = Calendar.current
    let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
    let month = calendar.date(byAdding: .month, value: -monthsAgo, to: startOfMonth)!
    return Int64(month.timeIntervalSince1970 * 1000) + 14 * dayMs
}

private func monthlyCycle(monthsAgo: Int, peak: Double, tier: RateLimitTier = .max20x) -> ResetEvent {
    ResetEvent(
        id: Int64(monthsAgo),
        timestamp: midMonthMs(monthsAgo: monthsAgo),
        fiveHourPeak: nil,
        sevenDayUtil: peak,
        tier: tier.rawValue,
        usedCredits: nil,
        constrainedCredits: nil,
        unusedCredits: nil,
        isWeeklyCycle: true
    )
}

private func monthlyRollup(monthsAgo: Int, fiveHourAvg: Double) -> UsageRollup {
    let start = midMonthMs(monthsAgo: monthsAgo)
    return UsageRollup(
        id: Int64(monthsAgo),
        periodStart: start,
        periodEnd: start + dayMs,
        resolution: .daily,
        fiveHourAvg: fiveHourAvg,
        fiveHourPeak: fiveHourAvg,
        fiveHourMin: fiveHourAvg,
        sevenDayAvg: 30,
        sevenDayPeak: 30,
        sevenDayMin: 30,
        resetCount: 0,
        unusedCredits: nil
    )
}

@Suite("Tier advice with no 5-hour number")
struct NoFiveHourTierAdviceTests {
    private func advice(_ events: [ResetEvent]) async throws -> TierRecommendation? {
        let historical = MockHistoricalDataService()
        historical.mockResetEvents = events
        return try await TierRecommendationService(
            historicalDataService: historical,
            preferencesManager: MockPreferencesManager()
        ).recommendTier(for: .all)
    }

    private func threeCycles(peak: Double, tier: RateLimitTier = .max20x) -> [ResetEvent] {
        [21, 14, 7].map { cycle(daysAgo: $0, peak: peak, tier: tier) }
    }

    @Test("Heavy weekly use on Ultra is a good fit with its real headroom")
    func heavyWeeklyOnly() async throws {
        let result = try await advice(threeCycles(peak: 70))
        #expect(result == .goodFit(tier: .max20x, headroomPercent: 30))

        // Past the 20% margin no plan fits, and Ultra is the highest plan.
        #expect(try await advice(threeCycles(peak: 90)) == .goodFit(tier: .max20x, headroomPercent: 10))
    }

    @Test("A reading over 100% is limited to 100 before it is averaged")
    func headroomClamped() async throws {
        let events = [cycle(daysAgo: 14, peak: 120), cycle(daysAgo: 7, peak: 50)]
        #expect(try await advice(events) == .goodFit(tier: .max20x, headroomPercent: 25))
    }

    @Test("The 20% margin applies to the whole-week check")
    func wholeWeekMargin() async throws {
        // 3.5% of 83,333,300 = 2.92M, under Max's 3.3M only until the margin makes it 3.5M.
        #expect(try await advice(threeCycles(peak: 3.5)) == .goodFit(tier: .max20x, headroomPercent: 96.5))
    }

    @Test("The current plan comes from the latest row, even one left out of the peaks")
    func currentPlanFromLatestRow() async throws {
        let events = [cycle(daysAgo: 21, peak: 40, tier: .pro), cycle(daysAgo: 14, peak: 40, tier: .pro)]
            + [fiveHourEvent(daysAgo: 7, peak: nil, sevenDay: 40, tier: .max5x)]
        guard case .goodFit(.max5x, _) = try await advice(events) ?? .goodFit(tier: .pro, headroomPercent: 0) else {
            Issue.record("Expected advice for Max, the plan on the latest row")
            return
        }
    }

    @Test("Only exhausted cycles count as rate limits once the account reports no number")
    func rateLimitCountUsesCurrentLimit() async throws {
        let events = [
            fiveHourEvent(daysAgo: 40, peak: 100, sevenDay: 10, tier: .pro),
            cycle(daysAgo: 21, peak: 100, tier: .pro),
            fiveHourEvent(daysAgo: 16, peak: 100, sevenDay: 50, tier: .pro),
            cycle(daysAgo: 14, peak: 100, tier: .pro),
            cycle(daysAgo: 7, peak: 94, tier: .pro),
        ]
        // The old 5-hour hit and the event inside a cycle's week do not count, nor does a cycle under 95%.
        guard case .upgrade(_, _, .max5x, _, 2, _) = try await advice(events) ?? .goodFit(tier: .pro, headroomPercent: 0) else {
            Issue.record("Expected an upgrade to Max with 2 rate limits")
            return
        }
    }

    @Test("Current plan names reach the card text")
    @MainActor
    func planNamesInCardText() async throws {
        #expect(TierRecommendationCard.buildTitle(for: .goodFit(tier: .max20x, headroomPercent: 50)) == "Ultra is a good fit")

        let historical = MockHistoricalDataService()
        historical.mockResetEvents = threeCycles(peak: 100, tier: .max5x)
        historical.recentPollsToReturn = [UsagePoll(
            id: 1,
            timestamp: nowMs - dayMs,
            fiveHourUtil: nil,
            fiveHourResetsAt: nil,
            sevenDayUtil: 100,
            sevenDayResetsAt: nil,
            extraUsageEnabled: true,
            extraUsageUsedCredits: 15_000
        )]
        let result = try await TierRecommendationService(
            historicalDataService: historical,
            preferencesManager: MockPreferencesManager()
        ).recommendTier(for: .all)
        guard case let .upgrade(_, _, .max20x, _, _, comparison) = result ?? .goodFit(tier: .pro, headroomPercent: 0) else {
            Issue.record("Expected an upgrade to Ultra")
            return
        }
        #expect(comparison == "On Max ($100/mo) you paid ~$150 in extra usage ($250 total) — Ultra ($200/mo) would have covered you and saved $50")
    }

    @Test("Moderate weekly use is not told to downgrade to a plan whose 5-hour limit it cannot check")
    func moderateWeeklyOnly() async throws {
        // 30% of 83.3M = 25M, which fits Max's weekly allowance but not its 3.3M 5-hour limit.
        let result = try await advice(threeCycles(peak: 30))
        #expect(result == .goodFit(tier: .max20x, headroomPercent: 70))
    }

    @Test("Tiny weekly use downgrades, because the whole week fits one 5-hour window")
    func tinyWeeklyOnly() async throws {
        // 3% of 83,333,300 = 2.5M; with the 20% margin 3.0M, under Max's 3.3M and over Pro's 550K.
        let result = try await advice(threeCycles(peak: 3))
        #expect(result == .downgrade(
            currentTier: .max20x,
            currentMonthlyCost: 200,
            recommendedTier: .max5x,
            recommendedMonthlyCost: 100,
            monthlySavings: 100,
            weeksOfData: 3
        ))
    }

    @Test("Weekly exhaustion on Pro recommends Max and counts the exhausted cycles")
    func weeklyExhausted() async throws {
        let result = try await advice(threeCycles(peak: 100, tier: .pro))
        #expect(result == .upgrade(
            currentTier: .pro,
            currentMonthlyCost: 20,
            recommendedTier: .max5x,
            recommendedMonthlyPrice: 100,
            rateLimitsAvoided: 3,
            costComparison: nil
        ))
    }

    @Test("Two weekly cycles cover 14 days; one does not")
    func minimumData() async throws {
        #expect(try await advice([cycle(daysAgo: 14, peak: 70), cycle(daysAgo: 7, peak: 70)]) != nil)
        #expect(try await advice([cycle(daysAgo: 7, peak: 70)]) == nil)
    }

    @Test("A high old 5-hour peak does not call for Ultra once the account reports no number")
    func mixedOldPeakDoesNotUpgrade() async throws {
        let old = [40, 35, 30].map { fiveHourEvent(daysAgo: $0, peak: 100, sevenDay: 20, tier: .max5x) }
        let withCycles = old + threeCycles(peak: 20, tier: .max5x)
        #expect(try await advice(withCycles) == .goodFit(tier: .max5x, headroomPercent: 80))

        // The same old events alone still follow the 1.6.0 rule.
        guard case .upgrade(_, _, .max20x, _, 4, _) = try await advice(old + [fiveHourEvent(daysAgo: 21, peak: 100, sevenDay: 20, tier: .max5x)]) ?? .goodFit(tier: .pro, headroomPercent: 0) else {
            Issue.record("Expected the 1.6.0 upgrade to Ultra")
            return
        }
    }

    @Test("An Ultra account that lost its number gets headroom from cycles, not its old 5-hour peaks")
    func mixedUltraHeadroomFromCycles() async throws {
        let old = [40, 35].map { fiveHourEvent(daysAgo: $0, peak: 95, sevenDay: 30) }
        #expect(try await advice(old + threeCycles(peak: 40)) == .goodFit(tier: .max20x, headroomPercent: 60))
    }

    @Test("Old 5-hour peaks still count against a cheaper plan, which keeps its limit")
    func mixedOldPeakBlocksDowngrade() async throws {
        let high = [40, 35].map { fiveHourEvent(daysAgo: $0, peak: 50, sevenDay: 1) }
        #expect(try await advice(high + threeCycles(peak: 1)) == .goodFit(tier: .max20x, headroomPercent: 99))

        let low = [40, 35].map { fiveHourEvent(daysAgo: $0, peak: 10, sevenDay: 1) }
        guard case .downgrade(_, _, .max5x, _, _, _) = try await advice(low + threeCycles(peak: 3)) ?? .goodFit(tier: .pro, headroomPercent: 0) else {
            Issue.record("Expected a downgrade to Max")
            return
        }
    }

    @Test("Events inside a cycle's 7 days are left out, so the week is not counted twice")
    func mixedOverlapLeftOut() async throws {
        let events = [
            fiveHourEvent(daysAgo: 40, peak: 20, sevenDay: 10, tier: .max5x),
            fiveHourEvent(daysAgo: 30, peak: 20, sevenDay: 10, tier: .max5x),
            cycle(daysAgo: 14, peak: 30, tier: .max5x),
            fiveHourEvent(daysAgo: 9, peak: 30, sevenDay: 95, tier: .max5x),
            cycle(daysAgo: 7, peak: 30, tier: .max5x),
        ]
        // Counted, the 95% snapshot would push this account to Ultra.
        #expect(try await advice(events) == .goodFit(tier: .max5x, headroomPercent: 70))
    }

    @Test("An account back on a number uses its 5-hour peaks, and old cycles still block a downgrade")
    func backOnANumber() async throws {
        let events = [cycle(daysAgo: 30, peak: 1, tier: .pro), cycle(daysAgo: 23, peak: 1, tier: .pro)]
            + [fiveHourEvent(daysAgo: 10, peak: 40, sevenDay: 20, tier: .pro)]
        #expect(try await advice(events) == .goodFit(tier: .pro, headroomPercent: 60))

        // One low 5-hour event says nothing about the weeks at 30% that had no 5-hour number.
        let ultra = [21, 14].map { cycle(daysAgo: $0, peak: 30) }
            + [fiveHourEvent(daysAgo: 5, peak: 5, sevenDay: 10)]
        #expect(try await advice(ultra) == .goodFit(tier: .max20x, headroomPercent: 95))
    }

    @Test("A number with a sleep gap matches 1.6.0: hand-worked average of the real peaks")
    func numberWithSleepGap() async throws {
        let events = [
            fiveHourEvent(daysAgo: 30, peak: 50, sevenDay: 30, tier: .pro),
            fiveHourEvent(daysAgo: 25, peak: nil, sevenDay: 30, tier: .pro),
            fiveHourEvent(daysAgo: 20, peak: 40, sevenDay: 30, tier: .pro),
            fiveHourEvent(daysAgo: 15, peak: 60, sevenDay: 30, tier: .pro),
        ]
        #expect(try await advice(events) == .goodFit(tier: .pro, headroomPercent: 50))
    }

    @Test("A number with low use still gets the 1.6.0 downgrade the weekly rule would refuse")
    func numberKeepsDowngrade() async throws {
        let events = [21, 14, 7, 1].map { fiveHourEvent(daysAgo: $0, peak: 10, sevenDay: 30) }
        guard case .downgrade(_, _, .max5x, _, 100, _) = try await advice(events) ?? .goodFit(tier: .pro, headroomPercent: 0) else {
            Issue.record("Expected the 1.6.0 downgrade to Max")
            return
        }
    }

    @Test("An unknown tier gets no advice and no invented credits")
    func unknownTier() async throws {
        let events = [21, 14, 7].map { daysAgo in
            ResetEvent(
                id: Int64(daysAgo),
                timestamp: nowMs - Int64(daysAgo) * dayMs,
                fiveHourPeak: nil,
                sevenDayUtil: 40,
                tier: "some_future_tier",
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil,
                isWeeklyCycle: true
            )
        }
        #expect(try await advice(events) == nil)
    }
}

@Suite("Subscription patterns with no 5-hour number")
struct NoFiveHourPatternTests {
    private let historical = MockHistoricalDataService()

    private func findings() async throws -> [PatternFinding] {
        try await SubscriptionPatternDetector(
            historicalDataService: historical,
            preferencesManager: MockPreferencesManager()
        ).analyzePatterns()
    }

    private func forgotten(_ findings: [PatternFinding]) -> PatternFinding? {
        findings.first { if case .forgottenSubscription = $0 { return true } else { return false } }
    }

    private func overpaying(_ findings: [PatternFinding]) -> PatternFinding? {
        findings.first { if case .chronicOverpaying = $0 { return true } else { return false } }
    }

    private func decay(_ findings: [PatternFinding]) -> PatternFinding? {
        findings.first { if case .usageDecay = $0 { return true } else { return false } }
    }

    @Test("Forgotten subscription fires from the weekly peak")
    func forgottenFromWeeklyPeak() async throws {
        historical.recentPollsToReturn = (0..<21).reversed().map { poll(daysAgo: Int64($0), fiveHour: nil, sevenDay: 3) }
        historical.mockResetEvents = [cycle(daysAgo: 1, peak: 3)]

        guard case let .forgottenSubscription(weeks, avgUtil, cost) = forgotten(try await findings()) else {
            Issue.record("Expected a forgotten subscription")
            return
        }
        #expect(weeks >= 2)
        #expect(avgUtil == 3)
        #expect(cost == 200)
    }

    @Test("A weekly value that climbs past 5% is not forgotten, even when its average is under 5%")
    func climbingWeeklyNotForgotten() async throws {
        historical.recentPollsToReturn = (0..<21).reversed().map {
            poll(daysAgo: Int64($0), fiveHour: nil, sevenDay: Double($0 % 7) * 1.5)
        }
        historical.mockResetEvents = [cycle(daysAgo: 1, peak: 9)]

        #expect(forgotten(try await findings()) == nil)
    }

    @Test("With a number, a stray poll with no 5-hour value does not change forgotten: 1.6.0")
    func strayPollKeepsFiveHourBase() async throws {
        let numbered = (0..<21).map { poll(daysAgo: Int64($0), fiveHour: 2, sevenDay: 60) }
        let stray = stride(from: 0, to: 21, by: 3).map { poll(daysAgo: Int64($0), fiveHour: nil, sevenDay: 60) }
        historical.recentPollsToReturn = (numbered + stray).sorted { $0.timestamp < $1.timestamp }
        historical.mockResetEvents = [fiveHourEvent(daysAgo: 1, peak: 2, sevenDay: 60)]

        guard case let .forgottenSubscription(_, avgUtil, _) = forgotten(try await findings()) else {
            Issue.record("Expected a forgotten subscription")
            return
        }
        #expect(avgUtil == 2)
    }

    @Test("Usage decay fires from monthly cycle peaks with no rollups needed")
    func decayFromCyclePeaks() async throws {
        historical.mockResetEvents = [
            monthlyCycle(monthsAgo: 4, peak: 80),
            monthlyCycle(monthsAgo: 3, peak: 60),
            monthlyCycle(monthsAgo: 2, peak: 40),
            monthlyCycle(monthsAgo: 1, peak: 20),
        ]
        #expect(decay(try await findings()) == .usageDecay(currentUtil: 20, threeMonthAgoUtil: 80))
    }

    @Test("Usage decay is not measured across 5-hour and weekly bases")
    func decayNotAcrossBases() async throws {
        let rollups = [80.0, 70, 60, 50].enumerated().map { index, avg in
            monthlyRollup(monthsAgo: 5 - index, fiveHourAvg: avg)
        }
        historical.rolledUpDataToReturn = rollups

        // With a number the rollups decide, as in 1.6.0.
        historical.mockResetEvents = [fiveHourEvent(daysAgo: 1, peak: 50, sevenDay: 30)]
        #expect(decay(try await findings()) == .usageDecay(currentUtil: 50, threeMonthAgoUtil: 80))

        // Once the account ends in a weekly cycle, the same rollups no longer count.
        historical.mockResetEvents = [monthlyCycle(monthsAgo: 1, peak: 10)]
        #expect(decay(try await findings()) == nil)
    }

    @Test("Usage decay ignores 5-hour events and averages the cycles in a month")
    func decayFromCyclesOnly() async throws {
        let old = [8, 7, 6].map { monthsAgo in
            ResetEvent(
                id: Int64(100 + monthsAgo),
                timestamp: midMonthMs(monthsAgo: monthsAgo),
                fiveHourPeak: 50,
                sevenDayUtil: 90,
                tier: RateLimitTier.max20x.rawValue,
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil
            )
        }
        historical.mockResetEvents = old + [3, 2, 1].map { monthlyCycle(monthsAgo: $0, peak: Double($0) * 20) }
        #expect(decay(try await findings()) == nil)

        let early = monthlyCycle(monthsAgo: 4, peak: 70)
        let late = ResetEvent(
            id: 40,
            timestamp: early.timestamp + 7 * dayMs,
            fiveHourPeak: nil,
            sevenDayUtil: 90,
            tier: early.tier,
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil,
            isWeeklyCycle: true
        )
        historical.mockResetEvents = [early, late] + [3, 2, 1].map { monthlyCycle(monthsAgo: $0, peak: Double($0) * 20) }
        #expect(decay(try await findings()) == .usageDecay(currentUtil: 20, threeMonthAgoUtil: 80))
    }

    @Test("An account back on a number measures decay from rollups again")
    func decayBackOnANumber() async throws {
        historical.rolledUpDataToReturn = [80.0, 70, 60, 50].enumerated().map { index, avg in
            monthlyRollup(monthsAgo: 5 - index, fiveHourAvg: avg)
        }
        historical.mockResetEvents = [monthlyCycle(monthsAgo: 2, peak: 10), fiveHourEvent(daysAgo: 1, peak: 50, sevenDay: 30)]
        #expect(decay(try await findings()) == .usageDecay(currentUtil: 50, threeMonthAgoUtil: 80))
    }

    @Test("Chronic overpaying needs the whole week, with margin, to fit the cheaper plan's 5-hour limit")
    func overpayingFromCycles() async throws {
        historical.mockResetEvents = [3, 2, 1].map { monthlyCycle(monthsAgo: $0, peak: 2) }
        #expect(overpaying(try await findings()) == .chronicOverpaying(currentTier: "Ultra", recommendedTier: "Max", monthlySavings: 100))

        historical.mockResetEvents = [3, 2, 1].map { monthlyCycle(monthsAgo: $0, peak: 30) }
        #expect(overpaying(try await findings()) == nil)

        // Agrees with the tier card, which also refuses this at the same margin.
        historical.mockResetEvents = [3, 2, 1].map { monthlyCycle(monthsAgo: $0, peak: 3.5) }
        #expect(overpaying(try await findings()) == nil)
    }

    @Test("Chronic overpaying leaves out overlapping events and empty-peak rows")
    func overpayingOverlap() async throws {
        let cycles = [3, 2, 1].map { monthlyCycle(monthsAgo: $0, peak: 2) }
        let insideLastCycle = ResetEvent(
            id: 50,
            timestamp: midMonthMs(monthsAgo: 1) - 3 * dayMs,
            fiveHourPeak: 90,
            sevenDayUtil: 90,
            tier: RateLimitTier.max20x.rawValue,
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )
        historical.mockResetEvents = (cycles + [insideLastCycle]).sorted { $0.timestamp < $1.timestamp }
        #expect(overpaying(try await findings()) == .chronicOverpaying(currentTier: "Ultra", recommendedTier: "Max", monthlySavings: 100))

        // Empty-peak rows do not make up the 3 months that the finding needs.
        let emptyPeak = [3, 2].map { monthsAgo in
            ResetEvent(
                id: Int64(60 + monthsAgo),
                timestamp: midMonthMs(monthsAgo: monthsAgo),
                fiveHourPeak: nil,
                sevenDayUtil: 2,
                tier: RateLimitTier.max20x.rawValue,
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil
            )
        }
        historical.mockResetEvents = emptyPeak + [monthlyCycle(monthsAgo: 1, peak: 2)]
        #expect(overpaying(try await findings()) == nil)
    }

    @Test("With a number, chronic overpaying matches 1.6.0 at the weekly use the cycle rule refuses")
    func overpayingWithNumber() async throws {
        historical.mockResetEvents = [3, 2, 1].map { monthsAgo in
            ResetEvent(
                id: Int64(monthsAgo),
                timestamp: midMonthMs(monthsAgo: monthsAgo),
                fiveHourPeak: 5,
                sevenDayUtil: 30,
                tier: RateLimitTier.max20x.rawValue,
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil
            )
        }
        #expect(overpaying(try await findings()) == .chronicOverpaying(currentTier: "Ultra", recommendedTier: "Max", monthlySavings: 100))
    }

    @Test("Weekly exhaustion on polls with no 5-hour number drives chronic underpowering")
    func underpoweringFromWeekly() async throws {
        historical.mockResetEvents = [monthlyCycle(monthsAgo: 1, peak: 100, tier: .pro)]
        historical.recentPollsToReturn = [2, 1].flatMap { monthsAgo in
            (0..<3).map { offset in
                UsagePoll(
                    id: Int64(monthsAgo * 10 + offset),
                    timestamp: midMonthMs(monthsAgo: monthsAgo) + Int64(offset) * dayMs,
                    fiveHourUtil: nil,
                    fiveHourResetsAt: nil,
                    sevenDayUtil: 100,
                    sevenDayResetsAt: nil
                )
            }
        }

        let finding = try await findings().first { if case .chronicUnderpowering = $0 { return true } else { return false } }
        #expect(finding == .chronicUnderpowering(rateLimitCount: 6, currentTier: "Pro", suggestedTier: "Max"))
    }

    @Test("An unknown tier is safe: no tier finding and no invented price")
    func unknownTier() async throws {
        historical.recentPollsToReturn = (0..<21).reversed().map { poll(daysAgo: Int64($0), fiveHour: nil, sevenDay: 3) }
        historical.mockResetEvents = [3, 2, 1].map { monthsAgo in
            ResetEvent(
                id: Int64(monthsAgo),
                timestamp: midMonthMs(monthsAgo: monthsAgo),
                fiveHourPeak: nil,
                sevenDayUtil: 3,
                tier: "some_future_tier",
                usedCredits: nil,
                constrainedCredits: nil,
                unusedCredits: nil,
                isWeeklyCycle: true
            )
        }

        let results = try await findings()
        #expect(overpaying(results) == nil)
        guard case let .forgottenSubscription(_, _, cost) = forgotten(results) else {
            Issue.record("Expected a forgotten subscription")
            return
        }
        #expect(cost == 0)
    }
}
