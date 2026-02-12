import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("TierRecommendationCard Tests")
@MainActor
struct TierRecommendationCardTests {

    // MARK: - Helpers

    private func makeDowngrade(
        savings: Double = 80,
        weeksOfData: Int = 4
    ) -> TierRecommendation {
        .downgrade(
            currentTier: .max5x,
            currentMonthlyCost: 100,
            recommendedTier: .pro,
            recommendedMonthlyCost: 20,
            monthlySavings: savings,
            weeksOfData: weeksOfData
        )
    }

    private func makeUpgrade(
        rateLimitsAvoided: Int = 5,
        costComparison: String? = nil
    ) -> TierRecommendation {
        .upgrade(
            currentTier: .pro,
            currentMonthlyCost: 45,
            recommendedTier: .max5x,
            recommendedMonthlyPrice: 100,
            rateLimitsAvoided: rateLimitsAvoided,
            costComparison: costComparison
        )
    }

    private func makeGoodFit() -> TierRecommendation {
        .goodFit(tier: .pro, headroomPercent: 45.0)
    }

    // MARK: - Rendering

    @Test("Card renders without crash for downgrade recommendation")
    func rendersDowngrade() {
        let card = TierRecommendationCard(recommendation: makeDowngrade(), onDismiss: {})
        _ = card.body
    }

    @Test("Card renders without crash for upgrade recommendation")
    func rendersUpgrade() {
        let card = TierRecommendationCard(recommendation: makeUpgrade(), onDismiss: {})
        _ = card.body
    }

    @Test("Card renders without crash for goodFit recommendation")
    func rendersGoodFit() {
        let card = TierRecommendationCard(recommendation: makeGoodFit(), onDismiss: {})
        _ = card.body
    }

    // MARK: - Dismiss Callback

    @Test("onDismiss callback is invoked when dismiss is triggered")
    func onDismissCallbackInvoked() {
        var dismissed = false
        let card = TierRecommendationCard(recommendation: makeDowngrade(), onDismiss: { dismissed = true })
        card.onDismiss()
        #expect(dismissed == true)
    }

    // MARK: - Title Text

    @Test("buildTitle returns 'Consider Pro' for downgrade to Pro")
    func titleDowngrade() {
        let title = TierRecommendationCard.buildTitle(for: makeDowngrade())
        #expect(title == "Consider Pro")
    }

    @Test("buildTitle returns 'Consider Max 5x' for upgrade to Max 5x")
    func titleUpgrade() {
        let title = TierRecommendationCard.buildTitle(for: makeUpgrade())
        #expect(title == "Consider Max 5x")
    }

    @Test("buildTitle returns 'Pro is a good fit' for goodFit on Pro")
    func titleGoodFit() {
        let title = TierRecommendationCard.buildTitle(for: makeGoodFit())
        #expect(title == "Pro is a good fit")
    }

    // MARK: - Summary Text

    @Test("buildSummary for downgrade includes savings amount")
    func summaryDowngrade() {
        let summary = TierRecommendationCard.buildSummary(for: makeDowngrade(savings: 80))
        #expect(summary.contains("$80"))
        #expect(summary.contains("Pro"))
    }

    @Test("buildSummary for upgrade with cost comparison returns the comparison text")
    func summaryUpgradeWithCostComparison() {
        let comparison = "Pro ($20/mo) + $25 extra usage ($45 total) vs Max 5x ($100/mo)"
        let recommendation = makeUpgrade(costComparison: comparison)
        let summary = TierRecommendationCard.buildSummary(for: recommendation)
        #expect(summary == comparison)
    }

    @Test("buildSummary for upgrade without cost comparison mentions rate limits when count > 0")
    func summaryUpgradeWithRateLimits() {
        let summary = TierRecommendationCard.buildSummary(for: makeUpgrade(rateLimitsAvoided: 5))
        #expect(summary.contains("5 rate limits"))
    }

    @Test("buildSummary for upgrade with 1 rate limit uses singular form")
    func summaryUpgradeSingularRateLimit() {
        let summary = TierRecommendationCard.buildSummary(for: makeUpgrade(rateLimitsAvoided: 1))
        #expect(summary.contains("1 rate limit"))
        #expect(!summary.contains("rate limits"))
    }

    @Test("buildSummary for upgrade with 0 rate limits and no cost comparison uses generic message")
    func summaryUpgradeGeneric() {
        let summary = TierRecommendationCard.buildSummary(for: makeUpgrade(rateLimitsAvoided: 0, costComparison: nil))
        #expect(summary.contains("higher tier"))
    }

    @Test("buildSummary for goodFit includes headroom percentage")
    func summaryGoodFit() {
        let summary = TierRecommendationCard.buildSummary(for: makeGoodFit())
        #expect(summary.contains("45%"))
    }

    // MARK: - Context Text

    @Test("buildContext for downgrade returns weeks of data message")
    func contextDowngrade() {
        let context = TierRecommendationCard.buildContext(for: makeDowngrade(weeksOfData: 4))
        #expect(context != nil)
        #expect(context!.contains("4 weeks"))
    }

    @Test("buildContext for downgrade with 1 week uses singular form")
    func contextDowngradeSingular() {
        let context = TierRecommendationCard.buildContext(for: makeDowngrade(weeksOfData: 1))
        #expect(context != nil)
        #expect(context!.contains("1 week"))
        #expect(!context!.contains("weeks"))
    }

    @Test("buildContext for upgrade with rate limits returns rate limit count")
    func contextUpgradeWithRateLimits() {
        let context = TierRecommendationCard.buildContext(for: makeUpgrade(rateLimitsAvoided: 3))
        #expect(context != nil)
        #expect(context!.contains("3 rate limits"))
    }

    @Test("buildContext for upgrade with 0 rate limits returns nil")
    func contextUpgradeNoRateLimits() {
        let context = TierRecommendationCard.buildContext(for: makeUpgrade(rateLimitsAvoided: 0))
        #expect(context == nil)
    }

    @Test("buildContext for goodFit returns nil")
    func contextGoodFit() {
        let context = TierRecommendationCard.buildContext(for: makeGoodFit())
        #expect(context == nil)
    }

    // MARK: - Accessibility Label

    @Test("buildAccessibilityLabel combines title, summary, and context")
    func accessibilityLabel() {
        let label = TierRecommendationCard.buildAccessibilityLabel(for: makeDowngrade(weeksOfData: 4))
        #expect(label.contains("Consider Pro"))
        #expect(label.contains("$80"))
        #expect(label.contains("4 weeks"))
    }

    @Test("buildAccessibilityLabel omits context when nil")
    func accessibilityLabelNoContext() {
        let label = TierRecommendationCard.buildAccessibilityLabel(for: makeGoodFit())
        #expect(label.contains("Pro is a good fit"))
        #expect(label.contains("45%"))
        // No "Based on" context for goodFit
        #expect(!label.contains("Based on"))
    }
}

// MARK: - TierRecommendation Fingerprint & Actionable Tests

@Suite("TierRecommendation Fingerprint Tests")
struct TierRecommendationFingerprintTests {

    @Test("downgrade fingerprint includes both tier raw values")
    func downgradeFingerprintFormat() {
        let rec = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 100,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 80, weeksOfData: 4
        )
        #expect(rec.recommendationFingerprint == "downgrade-default_claude_max_5x-default_claude_pro")
    }

    @Test("upgrade fingerprint includes both tier raw values")
    func upgradeFingerprintFormat() {
        let rec = TierRecommendation.upgrade(
            currentTier: .pro, currentMonthlyCost: 45,
            recommendedTier: .max5x, recommendedMonthlyPrice: 100,
            rateLimitsAvoided: 5, costComparison: nil
        )
        #expect(rec.recommendationFingerprint == "upgrade-default_claude_pro-default_claude_max_5x")
    }

    @Test("goodFit fingerprint includes tier raw value")
    func goodFitFingerprintFormat() {
        let rec = TierRecommendation.goodFit(tier: .pro, headroomPercent: 45.0)
        #expect(rec.recommendationFingerprint == "goodFit-default_claude_pro")
    }

    @Test("same recommendation type and tiers produce same fingerprint")
    func sameFingerprintForSameTypeAndTiers() {
        let a = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 100,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 80, weeksOfData: 4
        )
        let b = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 120,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 100, weeksOfData: 8
        )
        #expect(a.recommendationFingerprint == b.recommendationFingerprint)
    }

    @Test("different tier combinations produce different fingerprints")
    func differentFingerprintsForDifferentTiers() {
        let a = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 100,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 80, weeksOfData: 4
        )
        let b = TierRecommendation.downgrade(
            currentTier: .max20x, currentMonthlyCost: 200,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 180, weeksOfData: 4
        )
        #expect(a.recommendationFingerprint != b.recommendationFingerprint)
    }

    @Test("downgrade and upgrade are actionable")
    func actionableForDowngradeAndUpgrade() {
        let downgrade = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 100,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 80, weeksOfData: 4
        )
        let upgrade = TierRecommendation.upgrade(
            currentTier: .pro, currentMonthlyCost: 45,
            recommendedTier: .max5x, recommendedMonthlyPrice: 100,
            rateLimitsAvoided: 5, costComparison: nil
        )
        #expect(downgrade.isActionable == true)
        #expect(upgrade.isActionable == true)
    }

    @Test("goodFit is not actionable")
    func goodFitNotActionable() {
        let rec = TierRecommendation.goodFit(tier: .pro, headroomPercent: 45.0)
        #expect(rec.isActionable == false)
    }
}

// MARK: - AnalyticsView Tier Recommendation Integration Tests

@Suite("AnalyticsView Tier Recommendation Integration Tests")
@MainActor
struct AnalyticsViewTierRecommendationTests {

    @Test("AnalyticsView accepts optional tierRecommendationService")
    func acceptsTierRecommendationService() {
        let mock = MockTierRecommendationService()
        let view = AnalyticsView(
            onClose: {},
            historicalDataService: MockHistoricalDataService(),
            appState: AppState(),
            headroomAnalysisService: MockHeadroomAnalysisService(),
            tierRecommendationService: mock
        )
        _ = view.body
    }

    @Test("AnalyticsView accepts optional preferencesManager")
    func acceptsPreferencesManager() {
        let mock = MockPreferencesManager()
        let view = AnalyticsView(
            onClose: {},
            historicalDataService: MockHistoricalDataService(),
            appState: AppState(),
            headroomAnalysisService: MockHeadroomAnalysisService(),
            preferencesManager: mock
        )
        _ = view.body
    }

    @Test("AnalyticsView renders without crash when both optional services are nil")
    func rendersWithNilOptionalServices() {
        let view = AnalyticsView(
            onClose: {},
            historicalDataService: MockHistoricalDataService(),
            appState: AppState(),
            headroomAnalysisService: MockHeadroomAnalysisService()
        )
        _ = view.body
    }

    @Test("AnalyticsView renders without crash when both optional services are provided")
    func rendersWithBothOptionalServices() {
        let view = AnalyticsView(
            onClose: {},
            historicalDataService: MockHistoricalDataService(),
            appState: AppState(),
            headroomAnalysisService: MockHeadroomAnalysisService(),
            tierRecommendationService: MockTierRecommendationService(),
            preferencesManager: MockPreferencesManager()
        )
        _ = view.body
    }
}

// MARK: - AnalyticsWindow Tier Recommendation Wiring Tests

@Suite("AnalyticsWindow Tier Recommendation Wiring Tests")
@MainActor
struct AnalyticsWindowTierRecommendationTests {

    init() {
        AnalyticsWindow.shared.reset()
    }

    @Test("AnalyticsWindow.configure accepts tierRecommendationService and preferencesManager")
    func configureAcceptsNewParams() {
        let window = AnalyticsWindow.shared
        let appState = AppState()
        let mockHistorical = MockHistoricalDataService()
        let mockHeadroom = MockHeadroomAnalysisService()
        let mockTierRec = MockTierRecommendationService()
        let mockPrefs = MockPreferencesManager()

        window.configure(
            appState: appState,
            historicalDataService: mockHistorical,
            headroomAnalysisService: mockHeadroom,
            tierRecommendationService: mockTierRec,
            preferencesManager: mockPrefs
        )

        // Verify window can open without crash
        window.toggle()
        #expect(appState.isAnalyticsWindowOpen == true)
        window.close()
    }

    @Test("AnalyticsWindow.configure still works without optional params (backward compatible)")
    func configureBackwardCompatible() {
        let window = AnalyticsWindow.shared
        let appState = AppState()

        window.configure(
            appState: appState,
            historicalDataService: MockHistoricalDataService(),
            headroomAnalysisService: MockHeadroomAnalysisService()
        )

        window.toggle()
        #expect(appState.isAnalyticsWindowOpen == true)
        window.close()
    }
}

// MARK: - Dismissal Persistence Tests

@Suite("Tier Recommendation Dismissal Tests")
@MainActor
struct TierRecommendationDismissalTests {

    @Test("MockPreferencesManager stores and retrieves dismissedTierRecommendation")
    func mockStoreDismissedFingerprint() {
        let prefs = MockPreferencesManager()
        #expect(prefs.dismissedTierRecommendation == nil)

        prefs.dismissedTierRecommendation = "downgrade-default_claude_max_5x-default_claude_pro"
        #expect(prefs.dismissedTierRecommendation == "downgrade-default_claude_max_5x-default_claude_pro")
    }

    @Test("resetToDefaults clears dismissedTierRecommendation")
    func resetClearsDismissed() {
        let prefs = MockPreferencesManager()
        prefs.dismissedTierRecommendation = "some-fingerprint"
        prefs.resetToDefaults()
        #expect(prefs.dismissedTierRecommendation == nil)
    }

    @Test("Dismissed fingerprint matching suppresses card display (logic verification)")
    func dismissedFingerprintSuppressesCard() {
        let rec = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 100,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 80, weeksOfData: 4
        )
        let prefs = MockPreferencesManager()
        prefs.dismissedTierRecommendation = rec.recommendationFingerprint

        // Replicate the AnalyticsView tierRecommendationCard guard logic:
        // if recommendation.isActionable && prefs.dismissedTierRecommendation != recommendation.fingerprint
        let shouldShow = rec.isActionable && prefs.dismissedTierRecommendation != rec.recommendationFingerprint
        #expect(shouldShow == false, "Card should be suppressed when fingerprint matches")
    }

    @Test("Different fingerprint does not suppress card")
    func differentFingerprintDoesNotSuppress() {
        let rec = TierRecommendation.downgrade(
            currentTier: .max5x, currentMonthlyCost: 100,
            recommendedTier: .pro, recommendedMonthlyCost: 20,
            monthlySavings: 80, weeksOfData: 4
        )
        let prefs = MockPreferencesManager()
        prefs.dismissedTierRecommendation = "upgrade-different-tiers"

        let shouldShow = rec.isActionable && prefs.dismissedTierRecommendation != rec.recommendationFingerprint
        #expect(shouldShow == true, "Card should show when fingerprint differs")
    }
}

// MARK: - Billing Cycle Day Settings Tests

@Suite("SettingsView Billing Cycle Day Tests")
@MainActor
struct SettingsViewBillingCycleDayTests {

    @Test("SettingsView renders with billing cycle day not set")
    func rendersWithBillingCycleDayNotSet() {
        let mock = MockPreferencesManager()
        let mockLaunch = MockLaunchAtLoginService()
        // billingCycleDay defaults to nil in MockPreferencesManager
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("SettingsView renders with billing cycle day set")
    func rendersWithBillingCycleDaySet() {
        let mock = MockPreferencesManager()
        mock.billingCycleDay = 15
        let mockLaunch = MockLaunchAtLoginService()
        let view = SettingsView(preferencesManager: mock, launchAtLoginService: mockLaunch)
        _ = view.body
    }

    @Test("Reset to Defaults clears billing cycle day")
    func resetClearsBillingCycleDay() {
        let mock = MockPreferencesManager()
        mock.billingCycleDay = 15
        mock.resetToDefaults()
        #expect(mock.billingCycleDay == nil)
    }

    @Test("Billing cycle day persists through MockPreferencesManager")
    func billingCycleDayPersists() {
        let mock = MockPreferencesManager()
        mock.billingCycleDay = 1
        #expect(mock.billingCycleDay == 1)

        mock.billingCycleDay = 28
        #expect(mock.billingCycleDay == 28)

        mock.billingCycleDay = nil
        #expect(mock.billingCycleDay == nil)
    }
}
