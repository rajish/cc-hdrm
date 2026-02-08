import Foundation
import Testing
@testable import cc_hdrm

@Suite("HeadroomAnalysisService Tests")
struct HeadroomAnalysisServiceTests {

    // MARK: - Test Helpers

    /// Pro tier limits: 5h=550,000, 7d=5,000,000
    private let proLimits = CreditLimits(fiveHourCredits: 550_000, sevenDayCredits: 5_000_000)

    /// Service instance (no preferencesManager — tests pass explicit creditLimits to analyzeResetEvent)
    private let service = HeadroomAnalysisService()

    private func makeEvent(
        id: Int64 = 1,
        timestamp: Int64 = 1706976000000,
        fiveHourPeak: Double? = 72.0,
        sevenDayUtil: Double? = 85.0,
        tier: String? = "default_claude_pro"
    ) -> ResetEvent {
        ResetEvent(
            id: id,
            timestamp: timestamp,
            fiveHourPeak: fiveHourPeak,
            sevenDayUtil: sevenDayUtil,
            tier: tier,
            usedCredits: nil,
            constrainedCredits: nil,
            wasteCredits: nil
        )
    }

    // MARK: - 8.2: 5h_remaining <= 7d_remaining (AC-1 case 1)

    @Test("analyzeResetEvent: 5h_remaining <= 7d_remaining — true_waste = 5h_remaining, constrained = 0")
    func analyzeWithFiveHourNotConstrained() {
        // 72% peak, 85% 7d util
        // 5h_remaining = (1-0.72) * 550,000 = 154,000
        // 7d_remaining = (1-0.85) * 5,000,000 = 750,000
        // 5h_remaining (154,000) <= 7d_remaining (750,000)
        let breakdown = service.analyzeResetEvent(
            fiveHourPeak: 72.0,
            sevenDayUtil: 85.0,
            creditLimits: proLimits
        )

        #expect(isClose(breakdown.usedPercent, 72.0))
        #expect(isClose(breakdown.wastePercent, 28.0))
        #expect(isClose(breakdown.constrainedPercent, 0.0))
        #expect(isClose(breakdown.usedCredits, 396_000))
        #expect(isClose(breakdown.wasteCredits, 154_000))
        #expect(isClose(breakdown.constrainedCredits, 0))
    }

    // MARK: - 8.3: 5h_remaining > 7d_remaining (AC-1 case 2)

    @Test("analyzeResetEvent: 5h_remaining > 7d_remaining — true_waste = 7d_remaining, constrained = difference")
    func analyzeWithSevenDayConstrained() {
        // 50% peak, 98% 7d util
        // 5h_remaining = (1-0.50) * 550,000 = 275,000
        // 7d_remaining = (1-0.98) * 5,000,000 = 100,000
        // 5h_remaining (275,000) > 7d_remaining (100,000)
        let breakdown = service.analyzeResetEvent(
            fiveHourPeak: 50.0,
            sevenDayUtil: 98.0,
            creditLimits: proLimits
        )

        #expect(isClose(breakdown.usedPercent, 50.0))
        #expect(isClose(breakdown.usedCredits, 275_000))

        // true_waste = 7d_remaining = 100,000
        #expect(isClose(breakdown.wasteCredits, 100_000))

        // constrained = 5h_remaining - 7d_remaining = 175,000
        #expect(isClose(breakdown.constrainedCredits, 175_000))

        // Percentages relative to 5h limit (550,000)
        let expectedWastePercent = (100_000.0 / 550_000.0) * 100.0
        let expectedConstrainedPercent = (175_000.0 / 550_000.0) * 100.0
        #expect(isClose(breakdown.wastePercent, expectedWastePercent))
        #expect(isClose(breakdown.constrainedPercent, expectedConstrainedPercent))
    }

    // MARK: - 8.4: Percentages sum to 100%

    @Test("analyzeResetEvent: percentages always sum to 100%")
    func percentagesSumTo100() {
        // Test several scenarios
        let scenarios: [(peak: Double, util7d: Double)] = [
            (72.0, 85.0),
            (50.0, 98.0),
            (0.0, 0.0),
            (100.0, 100.0),
            (33.33, 66.66),
            (99.9, 10.0),
            (10.0, 99.9),
        ]

        for scenario in scenarios {
            let breakdown = service.analyzeResetEvent(
                fiveHourPeak: scenario.peak,
                sevenDayUtil: scenario.util7d,
                creditLimits: proLimits
            )

            let sum = breakdown.usedPercent + breakdown.constrainedPercent + breakdown.wastePercent
            #expect(isClose(sum, 100.0), "Percentages should sum to 100%, got \(sum) for peak=\(scenario.peak), 7d=\(scenario.util7d)")
        }
    }

    // MARK: - 8.5: 0% peak (no usage = 100% waste)

    @Test("analyzeResetEvent: 0% peak — all waste, no usage, no constrained")
    func analyzeWithZeroPeak() {
        let breakdown = service.analyzeResetEvent(
            fiveHourPeak: 0.0,
            sevenDayUtil: 0.0,
            creditLimits: proLimits
        )

        #expect(isClose(breakdown.usedPercent, 0.0))
        #expect(isClose(breakdown.usedCredits, 0.0))
        #expect(isClose(breakdown.constrainedPercent, 0.0))
        #expect(isClose(breakdown.constrainedCredits, 0.0))

        // All 550,000 credits wasted
        #expect(isClose(breakdown.wastePercent, 100.0))
        #expect(isClose(breakdown.wasteCredits, 550_000))
    }

    // MARK: - 8.6: 100% peak (all used, 0 waste, 0 constrained)

    @Test("analyzeResetEvent: 100% peak — all used, no waste, no constrained")
    func analyzeWithFullPeak() {
        let breakdown = service.analyzeResetEvent(
            fiveHourPeak: 100.0,
            sevenDayUtil: 100.0,
            creditLimits: proLimits
        )

        #expect(isClose(breakdown.usedPercent, 100.0))
        #expect(isClose(breakdown.usedCredits, 550_000))
        #expect(isClose(breakdown.wastePercent, 0.0))
        #expect(isClose(breakdown.wasteCredits, 0.0))
        #expect(isClose(breakdown.constrainedPercent, 0.0))
        #expect(isClose(breakdown.constrainedCredits, 0.0))
    }

    // MARK: - 8.7: aggregateBreakdown sums credits across multiple events

    @Test("aggregateBreakdown: sums credits across multiple events correctly")
    func aggregateSumsCredits() {
        let events = [
            makeEvent(id: 1, fiveHourPeak: 72.0, sevenDayUtil: 85.0),
            makeEvent(id: 2, fiveHourPeak: 50.0, sevenDayUtil: 98.0),
        ]

        let summary = service.aggregateBreakdown(events: events)

        // Event 1: used=396,000 constrained=0 waste=154,000
        // Event 2: used=275,000 constrained=175,000 waste=100,000
        #expect(isClose(summary.usedCredits, 396_000 + 275_000))
        #expect(isClose(summary.constrainedCredits, 0 + 175_000))
        #expect(isClose(summary.wasteCredits, 154_000 + 100_000))
        #expect(summary.resetCount == 2)
        #expect(isClose(summary.avgPeakUtilization, (72.0 + 50.0) / 2.0))

        // Percentages should sum to 100%
        let sum = summary.usedPercent + summary.constrainedPercent + summary.wastePercent
        #expect(isClose(sum, 100.0))
    }

    // MARK: - 8.8: aggregateBreakdown with zero events

    @Test("aggregateBreakdown: zero events returns zeroed PeriodSummary")
    func aggregateWithZeroEvents() {
        let summary = service.aggregateBreakdown(events: [])

        #expect(summary.usedCredits == 0)
        #expect(summary.constrainedCredits == 0)
        #expect(summary.wasteCredits == 0)
        #expect(summary.resetCount == 0)
        #expect(summary.avgPeakUtilization == 0)
        #expect(summary.usedPercent == 0)
        #expect(summary.constrainedPercent == 0)
        #expect(summary.wastePercent == 0)
    }

    // MARK: - 8.9: aggregateBreakdown skips events with nil peak/util

    @Test("aggregateBreakdown: skips events with nil fiveHourPeak or sevenDayUtil")
    func aggregateSkipsNilEvents() {
        let events = [
            makeEvent(id: 1, fiveHourPeak: 72.0, sevenDayUtil: 85.0),
            makeEvent(id: 2, fiveHourPeak: nil, sevenDayUtil: 85.0),   // skipped
            makeEvent(id: 3, fiveHourPeak: 72.0, sevenDayUtil: nil),   // skipped
            makeEvent(id: 4, fiveHourPeak: nil, sevenDayUtil: nil),    // skipped
        ]

        let summary = service.aggregateBreakdown(events: events)

        // Only event 1 should be counted
        #expect(summary.resetCount == 1)
        #expect(isClose(summary.usedCredits, 396_000))
        #expect(isClose(summary.constrainedCredits, 0))
        #expect(isClose(summary.wasteCredits, 154_000))
        #expect(isClose(summary.avgPeakUtilization, 72.0))
    }

    // MARK: - 8.10 (review fix): aggregateBreakdown skips events with unknown tier

    @Test("aggregateBreakdown: skips events with unresolvable tier")
    func aggregateSkipsUnknownTierEvents() {
        let events = [
            makeEvent(id: 1, fiveHourPeak: 72.0, sevenDayUtil: 85.0, tier: "default_claude_pro"),
            makeEvent(id: 2, fiveHourPeak: 50.0, sevenDayUtil: 98.0, tier: "unknown_tier_xyz"),  // skipped
            makeEvent(id: 3, fiveHourPeak: 60.0, sevenDayUtil: 90.0, tier: nil),                  // skipped
        ]

        let summary = service.aggregateBreakdown(events: events)

        // Only event 1 should be counted (Pro tier resolves, others don't)
        #expect(summary.resetCount == 1)
        #expect(isClose(summary.usedCredits, 396_000))
        #expect(isClose(summary.avgPeakUtilization, 72.0))
    }

    // MARK: - Floating Point Helper

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.01) -> Bool {
        abs(a - b) < tolerance
    }
}
