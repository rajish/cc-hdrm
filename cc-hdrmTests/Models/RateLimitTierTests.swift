import Testing
@testable import cc_hdrm

@Suite("RateLimitTier Tests")
struct RateLimitTierTests {

    // MARK: - Credit Limit Values (AC-1)

    @Test("Pro tier has fiveHourCredits == 550,000 and sevenDayCredits == 5,000,000")
    func proCreditLimits() {
        #expect(RateLimitTier.pro.fiveHourCredits == 550_000)
        #expect(RateLimitTier.pro.sevenDayCredits == 5_000_000)
    }

    @Test("Max 5x tier has fiveHourCredits == 3,300,000 and sevenDayCredits == 41,666,700")
    func max5xCreditLimits() {
        #expect(RateLimitTier.max5x.fiveHourCredits == 3_300_000)
        #expect(RateLimitTier.max5x.sevenDayCredits == 41_666_700)
    }

    @Test("Max 20x tier has fiveHourCredits == 11,000,000 and sevenDayCredits == 83,333,300")
    func max20xCreditLimits() {
        #expect(RateLimitTier.max20x.fiveHourCredits == 11_000_000)
        #expect(RateLimitTier.max20x.sevenDayCredits == 83_333_300)
    }

    // MARK: - Raw Value Mapping (AC-1)

    @Test("Raw value 'default_claude_pro' maps to .pro")
    func proRawValue() {
        #expect(RateLimitTier(rawValue: "default_claude_pro") == .pro)
    }

    @Test("Raw value 'default_claude_max_5x' maps to .max5x")
    func max5xRawValue() {
        #expect(RateLimitTier(rawValue: "default_claude_max_5x") == .max5x)
    }

    @Test("Raw value 'default_claude_max_20x' maps to .max20x")
    func max20xRawValue() {
        #expect(RateLimitTier(rawValue: "default_claude_max_20x") == .max20x)
    }

    @Test("Unknown raw value returns nil")
    func unknownRawValue() {
        #expect(RateLimitTier(rawValue: "unknown_tier") == nil)
    }

    // MARK: - resolve() (AC-1)

    @Test("resolve() with known tier string returns matching CreditLimits")
    func resolveKnownTier() {
        let limits = RateLimitTier.resolve(tierString: "default_claude_max_5x", preferencesManager: nil)
        #expect(limits != nil)
        #expect(limits?.fiveHourCredits == 3_300_000)
        #expect(limits?.sevenDayCredits == 41_666_700)
    }

    @Test("resolve() with unknown tier + custom limits in preferences returns custom CreditLimits")
    func resolveUnknownTierWithCustomLimits() {
        let mockPrefs = MockPreferencesManager()
        mockPrefs.customFiveHourCredits = 1_000_000
        mockPrefs.customSevenDayCredits = 10_000_000

        let limits = RateLimitTier.resolve(tierString: "some_future_tier", preferencesManager: mockPrefs)
        #expect(limits != nil)
        #expect(limits?.fiveHourCredits == 1_000_000)
        #expect(limits?.sevenDayCredits == 10_000_000)
    }

    @Test("resolve() with unknown tier + no custom limits returns nil")
    func resolveUnknownTierNoCustom() {
        let mockPrefs = MockPreferencesManager()
        let limits = RateLimitTier.resolve(tierString: "some_future_tier", preferencesManager: mockPrefs)
        #expect(limits == nil)
    }

    @Test("resolve() with nil tierString + no custom limits returns nil")
    func resolveNilTierString() {
        let mockPrefs = MockPreferencesManager()
        let limits = RateLimitTier.resolve(tierString: nil, preferencesManager: mockPrefs)
        #expect(limits == nil)
    }

    @Test("resolve() with nil tierString + custom limits returns custom CreditLimits")
    func resolveNilTierStringWithCustomLimits() {
        let mockPrefs = MockPreferencesManager()
        mockPrefs.customFiveHourCredits = 800_000
        mockPrefs.customSevenDayCredits = 8_000_000
        let limits = RateLimitTier.resolve(tierString: nil, preferencesManager: mockPrefs)
        #expect(limits != nil)
        #expect(limits?.fiveHourCredits == 800_000)
        #expect(limits?.sevenDayCredits == 8_000_000)
    }

    // MARK: - CreditLimits normalizationFactor

    @Test("CreditLimits.normalizationFactor is approximately correct for each tier")
    func normalizationFactors() {
        let proFactor = RateLimitTier.pro.creditLimits.normalizationFactor
        #expect(abs(proFactor - 9.09) < 0.01)

        let max5xFactor = RateLimitTier.max5x.creditLimits.normalizationFactor
        #expect(abs(max5xFactor - 12.63) < 0.01)

        let max20xFactor = RateLimitTier.max20x.creditLimits.normalizationFactor
        #expect(abs(max20xFactor - 7.58) < 0.01)
    }

    // MARK: - RateLimitTier.creditLimits

    @Test("RateLimitTier.creditLimits returns CreditLimits with matching values for each tier")
    func creditLimitsProperty() {
        for tier in RateLimitTier.allCases {
            let limits = tier.creditLimits
            #expect(limits.fiveHourCredits == tier.fiveHourCredits)
            #expect(limits.sevenDayCredits == tier.sevenDayCredits)
        }
    }

    // MARK: - Defensive Guards (Code Review Fixes)

    @Test("CreditLimits.normalizationFactor returns 0 when fiveHourCredits is 0 (defensive guard)")
    func normalizationFactorZeroGuard() {
        let limits = CreditLimits(fiveHourCredits: 0, sevenDayCredits: 1_000_000)
        #expect(limits.normalizationFactor == 0, "Should return 0, not infinity")
    }

    @Test("CreditLimits.normalizationFactor returns 0 when both credits are 0")
    func normalizationFactorBothZero() {
        let limits = CreditLimits(fiveHourCredits: 0, sevenDayCredits: 0)
        #expect(limits.normalizationFactor == 0)
    }
}
