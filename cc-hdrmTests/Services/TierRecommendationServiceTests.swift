import Testing
import Foundation
@testable import cc_hdrm

// MARK: - Test Helpers

private func makeResetEvent(
    id: Int64 = 1,
    timestamp: Int64,
    fiveHourPeak: Double? = 50.0,
    sevenDayUtil: Double? = 30.0,
    tier: String? = RateLimitTier.pro.rawValue,
    usedCredits: Double? = nil,
    constrainedCredits: Double? = nil,
    unusedCredits: Double? = nil
) -> ResetEvent {
    ResetEvent(
        id: id,
        timestamp: timestamp,
        fiveHourPeak: fiveHourPeak,
        sevenDayUtil: sevenDayUtil,
        tier: tier,
        usedCredits: usedCredits,
        constrainedCredits: constrainedCredits,
        unusedCredits: unusedCredits
    )
}

private func makePoll(
    id: Int64 = 1,
    timestamp: Int64,
    extraUsageEnabled: Bool? = nil,
    extraUsageUsedCredits: Double? = nil
) -> UsagePoll {
    UsagePoll(
        id: id,
        timestamp: timestamp,
        fiveHourUtil: 50.0,
        fiveHourResetsAt: nil,
        sevenDayUtil: 30.0,
        sevenDayResetsAt: nil,
        extraUsageEnabled: extraUsageEnabled,
        extraUsageMonthlyLimit: nil,
        extraUsageUsedCredits: extraUsageUsedCredits,
        extraUsageUtilization: nil
    )
}

/// Returns a timestamp N days ago from now in Unix milliseconds.
private func daysAgo(_ days: Int) -> Int64 {
    let date = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    return Int64(date.timeIntervalSince1970 * 1000)
}

// MARK: - TierRecommendationService Tests

@Suite("TierRecommendationService")
struct TierRecommendationServiceTests {

    // MARK: - AC 5: Insufficient Data

    @Test("Returns nil when fewer than 14 days of data exist")
    func insufficientData() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Only 10 days of data
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(10), tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(5), tier: RateLimitTier.pro.rawValue),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        #expect(result == nil)
    }

    @Test("Returns nil when no reset events exist")
    func noResetEvents() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()
        mockHistorical.mockResetEvents = []

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        #expect(result == nil)
    }

    // MARK: - AC 4: Good Fit

    @Test("Returns goodFit when user is on optimal tier with headroom")
    func goodFit() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Pro user with moderate usage — 50% peak means Pro is fine
        // Pro 5h: 550,000 credits. 50% peak = 275,000 credits.
        // 275,000 * 1.2 (safety) = 330,000 < 550,000 (Pro) — fits Pro
        // Pro is the cheapest tier that fits — no cheaper option.
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 50.0, sevenDayUtil: 30.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(25), fiveHourPeak: 45.0, sevenDayUtil: 28.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 3, timestamp: daysAgo(20), fiveHourPeak: 48.0, sevenDayUtil: 29.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 4, timestamp: daysAgo(15), fiveHourPeak: 50.0, sevenDayUtil: 30.0, tier: RateLimitTier.pro.rawValue),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        guard case let .goodFit(tier, headroom) = result else {
            Issue.record("Expected goodFit, got \(String(describing: result))")
            return
        }
        #expect(tier == .pro)
        #expect(headroom > 0)
    }

    // MARK: - AC 2: Downgrade

    @Test("Returns downgrade when usage fits a cheaper tier with safety margin")
    func downgrade() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Max 5x user ($100/mo) with low usage that fits Pro ($20/mo)
        // Max 5x 5h: 3,300,000 credits. 10% peak = 330,000 credits.
        // 330,000 * 1.2 (safety) = 396,000 < 550,000 (Pro 5h) — fits Pro
        // Max 5x 7d: 41,666,700 credits. 5% peak = 2,083,335 credits.
        // 2,083,335 * 1.2 = 2,500,002 < 5,000,000 (Pro 7d) — fits Pro
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 10.0, sevenDayUtil: 5.0, tier: RateLimitTier.max5x.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(25), fiveHourPeak: 8.0, sevenDayUtil: 4.0, tier: RateLimitTier.max5x.rawValue),
            makeResetEvent(id: 3, timestamp: daysAgo(20), fiveHourPeak: 10.0, sevenDayUtil: 5.0, tier: RateLimitTier.max5x.rawValue),
            makeResetEvent(id: 4, timestamp: daysAgo(15), fiveHourPeak: 9.0, sevenDayUtil: 4.5, tier: RateLimitTier.max5x.rawValue),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        guard case let .downgrade(currentTier, currentCost, recommendedTier, recommendedCost, savings, weeks) = result else {
            Issue.record("Expected downgrade, got \(String(describing: result))")
            return
        }
        #expect(currentTier == .max5x)
        #expect(currentCost == 100.0) // base only, no extra usage
        #expect(recommendedTier == .pro)
        #expect(recommendedCost == 20.0)
        #expect(savings == 80.0)
        #expect(weeks >= 2)
    }

    // MARK: - AC 3: Upgrade

    @Test("Returns upgrade when higher tier is cheaper than current base plus extra usage")
    func upgradeWithExtraUsage() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Pro user ($20/mo) with high usage that exceeds Pro limits
        // Peak 95% of Pro 5h credits = 522,500 credits
        // 522,500 * 1.2 = 627,000 > 550,000 (Pro) — does NOT fit Pro
        // 627,000 < 3,300,000 (Max 5x) — fits Max 5x
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 95.0, sevenDayUtil: 80.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(25), fiveHourPeak: 98.0, sevenDayUtil: 85.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 3, timestamp: daysAgo(20), fiveHourPeak: 96.0, sevenDayUtil: 82.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 4, timestamp: daysAgo(15), fiveHourPeak: 97.0, sevenDayUtil: 83.0, tier: RateLimitTier.pro.rawValue),
        ]

        // Polls show $47/mo in extra usage
        let oneMonthAgo = daysAgo(30)
        mockHistorical.recentPollsToReturn = [
            makePoll(id: 1, timestamp: oneMonthAgo, extraUsageEnabled: true, extraUsageUsedCredits: 47.0),
            makePoll(id: 2, timestamp: daysAgo(15), extraUsageEnabled: true, extraUsageUsedCredits: 47.0),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        guard case let .upgrade(currentTier, currentCost, recommendedTier, recommendedPrice, rateLimits, _) = result else {
            Issue.record("Expected upgrade, got \(String(describing: result))")
            return
        }
        #expect(currentTier == .pro)
        #expect(currentCost > 20.0) // base + extra usage
        #expect(recommendedTier == .max5x)
        #expect(recommendedPrice == 100.0)
        #expect(rateLimits >= 2) // At least 2 events with peak >= 95%
    }

    // MARK: - Safety Margin

    @Test("Usage at 85% of tier limit is NOT a downgrade candidate due to safety margin")
    func safetyMarginPreventsFalseDowngrade() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Max 5x user with usage at 85% of Max 5x limits
        // 85% peak of 3,300,000 = 2,805,000 credits
        // 2,805,000 * 1.2 (safety) = 3,366,000 > 3,300,000 (Max 5x 5h) — does NOT fit Max 5x with safety
        // But also > 550,000 (Pro) — does NOT fit Pro
        // So the only tier that fits is Max 20x, but that's more expensive
        // Since usage doesn't even fit current tier with margin, this should be goodFit (staying put is reasonable)
        // Actually: let's test with lower usage that is right at the margin boundary
        // Pro 5h: 550,000. If user has peak at 85%: 85% * 550,000 = 467,500 credits
        // 467,500 * 1.2 = 561,000 > 550,000 (Pro) — doesn't fit Pro with safety
        // But it does fit Pro WITHOUT safety. It's still a goodFit (stay on Pro).
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 85.0, sevenDayUtil: 40.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(25), fiveHourPeak: 80.0, sevenDayUtil: 38.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 3, timestamp: daysAgo(20), fiveHourPeak: 85.0, sevenDayUtil: 40.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 4, timestamp: daysAgo(15), fiveHourPeak: 83.0, sevenDayUtil: 39.0, tier: RateLimitTier.pro.rawValue),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        // Pro is the cheapest tier. Usage at 85% with 20% safety doesn't fit Pro
        // but no cheaper option exists. This should NOT be a downgrade.
        // It could be an upgrade if there's extra usage, or goodFit if not.
        // With no extra usage, it's a goodFit (staying on Pro).
        switch result {
        case .goodFit, .upgrade:
            // Both are acceptable — user should NOT be downgraded
            break
        case .downgrade:
            Issue.record("Should NOT recommend downgrade when peak is 85% with 20% safety margin")
        case nil:
            Issue.record("Expected a recommendation, got nil")
        }
    }

    // MARK: - AC 7: Credit-Only Fallback

    @Test("Falls back to credit-only comparison when extra usage data is unavailable")
    func creditOnlyFallback() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Max 5x user with low usage — no extra usage data
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 10.0, sevenDayUtil: 5.0, tier: RateLimitTier.max5x.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(25), fiveHourPeak: 8.0, sevenDayUtil: 4.0, tier: RateLimitTier.max5x.rawValue),
            makeResetEvent(id: 3, timestamp: daysAgo(20), fiveHourPeak: 10.0, sevenDayUtil: 5.0, tier: RateLimitTier.max5x.rawValue),
            makeResetEvent(id: 4, timestamp: daysAgo(15), fiveHourPeak: 9.0, sevenDayUtil: 4.5, tier: RateLimitTier.max5x.rawValue),
        ]

        // No extra usage polls
        mockHistorical.recentPollsToReturn = []

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        guard case let .downgrade(_, currentCost, recommendedTier, _, savings, _) = result else {
            Issue.record("Expected downgrade, got \(String(describing: result))")
            return
        }
        // No extra usage means current cost = base price only
        #expect(currentCost == 100.0)
        #expect(recommendedTier == .pro)
        #expect(savings == 80.0) // $100 - $20
    }

    // MARK: - Rate-Limit Count

    @Test("Counts rate-limit events for upgrade recommendation")
    func rateLimitCount() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Pro user with 3 rate-limit events (peak >= 95%)
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 96.0, sevenDayUtil: 80.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(25), fiveHourPeak: 60.0, sevenDayUtil: 70.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 3, timestamp: daysAgo(20), fiveHourPeak: 98.0, sevenDayUtil: 85.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 4, timestamp: daysAgo(15), fiveHourPeak: 99.0, sevenDayUtil: 90.0, tier: RateLimitTier.pro.rawValue),
        ]

        // Extra usage to make upgrade recommendation
        mockHistorical.recentPollsToReturn = [
            makePoll(id: 1, timestamp: daysAgo(30), extraUsageEnabled: true, extraUsageUsedCredits: 150.0),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        guard case let .upgrade(_, _, _, _, rateLimits, _) = result else {
            Issue.record("Expected upgrade, got \(String(describing: result))")
            return
        }
        #expect(rateLimits == 3) // Events at 96%, 98%, 99% (not 60%)
    }

    // MARK: - Cost Comparison String

    @Test("Generates cost comparison string for upgrade with extra usage context")
    func costComparisonString() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        // Pro user with extra usage that makes Max 5x cheaper
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 98.0, sevenDayUtil: 85.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(15), fiveHourPeak: 96.0, sevenDayUtil: 80.0, tier: RateLimitTier.pro.rawValue),
        ]

        mockHistorical.recentPollsToReturn = [
            makePoll(id: 1, timestamp: daysAgo(30), extraUsageEnabled: true, extraUsageUsedCredits: 120.0),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        guard case let .upgrade(_, _, _, _, _, costComparison) = result else {
            Issue.record("Expected upgrade, got \(String(describing: result))")
            return
        }
        // Should have a cost comparison since there's extra usage
        #expect(costComparison != nil)
        if let comparison = costComparison {
            #expect(comparison.contains("Pro"))
            #expect(comparison.contains("extra usage"))
        }
    }

    // MARK: - AC 6: Billing Cycle Alignment

    @Test("Aligns to billing cycles when billingCycleDay is configured")
    func billingCycleAlignment() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()
        mockPrefs.billingCycleDay = 15

        // Enough data for recommendation
        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), fiveHourPeak: 40.0, sevenDayUtil: 20.0, tier: RateLimitTier.pro.rawValue),
            makeResetEvent(id: 2, timestamp: daysAgo(15), fiveHourPeak: 45.0, sevenDayUtil: 22.0, tier: RateLimitTier.pro.rawValue),
        ]

        // Extra usage polls to verify billing cycle grouping
        mockHistorical.recentPollsToReturn = [
            makePoll(id: 1, timestamp: daysAgo(30), extraUsageEnabled: true, extraUsageUsedCredits: 10.0),
            makePoll(id: 2, timestamp: daysAgo(15), extraUsageEnabled: true, extraUsageUsedCredits: 15.0),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        // Should produce a recommendation (exact type depends on cost calculations)
        #expect(result != nil)
    }

    // MARK: - Unknown Tier

    @Test("Returns nil when current tier is unresolvable")
    func unknownTier() async throws {
        let mockHistorical = MockHistoricalDataService()
        let mockPrefs = MockPreferencesManager()

        mockHistorical.mockResetEvents = [
            makeResetEvent(id: 1, timestamp: daysAgo(30), tier: "unknown_tier_xyz"),
            makeResetEvent(id: 2, timestamp: daysAgo(15), tier: "unknown_tier_xyz"),
        ]

        let service = TierRecommendationService(
            historicalDataService: mockHistorical,
            preferencesManager: mockPrefs
        )

        let result = try await service.recommendTier(for: .all)
        #expect(result == nil)
    }
}

// MARK: - Billing Cycle Day Preference Tests

@Suite("BillingCycleDayPreference")
struct BillingCycleDayPreferenceTests {

    @Test("billingCycleDay defaults to nil")
    func defaultsToNil() {
        let prefs = PreferencesManager(defaults: UserDefaults(suiteName: "BillingCycleDayTest-\(UUID())")!)
        #expect(prefs.billingCycleDay == nil)
    }

    @Test("Valid values 1-28 persist and read back correctly")
    func validValues() {
        let defaults = UserDefaults(suiteName: "BillingCycleDayTest-\(UUID())")!
        let prefs = PreferencesManager(defaults: defaults)

        prefs.billingCycleDay = 1
        #expect(prefs.billingCycleDay == 1)

        prefs.billingCycleDay = 15
        #expect(prefs.billingCycleDay == 15)

        prefs.billingCycleDay = 28
        #expect(prefs.billingCycleDay == 28)
    }

    @Test("Out-of-range values return nil")
    func outOfRangeValues() {
        let defaults = UserDefaults(suiteName: "BillingCycleDayTest-\(UUID())")!
        let prefs = PreferencesManager(defaults: defaults)

        // 0 should return nil (defaults.integer returns 0 for missing key)
        defaults.set(0, forKey: "com.cc-hdrm.billingCycleDay")
        #expect(prefs.billingCycleDay == nil)

        // Negative should return nil
        defaults.set(-1, forKey: "com.cc-hdrm.billingCycleDay")
        #expect(prefs.billingCycleDay == nil)

        // 29 should return nil
        defaults.set(29, forKey: "com.cc-hdrm.billingCycleDay")
        #expect(prefs.billingCycleDay == nil)
    }

    @Test("Setting nil removes the preference")
    func settingNilRemoves() {
        let defaults = UserDefaults(suiteName: "BillingCycleDayTest-\(UUID())")!
        let prefs = PreferencesManager(defaults: defaults)

        prefs.billingCycleDay = 15
        #expect(prefs.billingCycleDay == 15)

        prefs.billingCycleDay = nil
        #expect(prefs.billingCycleDay == nil)
    }

    @Test("resetToDefaults clears billingCycleDay")
    func resetClearsBillingCycleDay() {
        let defaults = UserDefaults(suiteName: "BillingCycleDayTest-\(UUID())")!
        let prefs = PreferencesManager(defaults: defaults)

        prefs.billingCycleDay = 20
        #expect(prefs.billingCycleDay == 20)

        prefs.resetToDefaults()
        #expect(prefs.billingCycleDay == nil)
    }
}

// MARK: - TierRecommendation Equatable Tests

@Suite("TierRecommendation")
struct TierRecommendationTests {

    @Test("Downgrade values are accessible")
    func downgradeValues() {
        let rec = TierRecommendation.downgrade(
            currentTier: .max5x,
            currentMonthlyCost: 100,
            recommendedTier: .pro,
            recommendedMonthlyCost: 20,
            monthlySavings: 80,
            weeksOfData: 4
        )
        if case let .downgrade(current, cost, recommended, recCost, savings, weeks) = rec {
            #expect(current == .max5x)
            #expect(cost == 100)
            #expect(recommended == .pro)
            #expect(recCost == 20)
            #expect(savings == 80)
            #expect(weeks == 4)
        } else {
            Issue.record("Expected downgrade")
        }
    }

    @Test("Upgrade values are accessible")
    func upgradeValues() {
        let rec = TierRecommendation.upgrade(
            currentTier: .pro,
            currentMonthlyCost: 67,
            recommendedTier: .max5x,
            recommendedMonthlyPrice: 100,
            rateLimitsAvoided: 5,
            costComparison: "Save $67"
        )
        if case let .upgrade(current, cost, recommended, price, limits, comparison) = rec {
            #expect(current == .pro)
            #expect(cost == 67)
            #expect(recommended == .max5x)
            #expect(price == 100)
            #expect(limits == 5)
            #expect(comparison == "Save $67")
        } else {
            Issue.record("Expected upgrade")
        }
    }

    @Test("GoodFit values are accessible")
    func goodFitValues() {
        let rec = TierRecommendation.goodFit(tier: .pro, headroomPercent: 45.0)
        if case let .goodFit(tier, headroom) = rec {
            #expect(tier == .pro)
            #expect(headroom == 45.0)
        } else {
            Issue.record("Expected goodFit")
        }
    }
}
