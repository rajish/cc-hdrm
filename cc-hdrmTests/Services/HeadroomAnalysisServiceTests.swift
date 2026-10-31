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

    private static let preCutoverMs: Int64 = 1706976000000
    private static let postCutoverMs: Int64 = ResetEvent.fiveHourLimitRetiredAtMs + 7 * 86_400_000

    /// Legacy 5h event with stored credits (Pro: 72% peak, 85% 7d → used 396k, unused 154k).
    private func makeLegacyEvent(
        id: Int64 = 1,
        timestamp: Int64 = HeadroomAnalysisServiceTests.preCutoverMs,
        fiveHourPeak: Double? = 72.0,
        sevenDayUtil: Double? = 85.0,
        tier: String? = "default_claude_pro",
        usedCredits: Double? = 396_000,
        constrainedCredits: Double? = 0,
        unusedCredits: Double? = 154_000
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

    /// Post-cutover weekly cycle event (no 5h peak, no stored credits needed).
    private func makeWeeklyEvent(
        id: Int64 = 100,
        timestamp: Int64 = HeadroomAnalysisServiceTests.postCutoverMs,
        sevenDayUtil: Double = 70.0,
        tier: String? = "default_claude_pro"
    ) -> ResetEvent {
        ResetEvent(
            id: id,
            timestamp: timestamp,
            fiveHourPeak: nil,
            sevenDayUtil: sevenDayUtil,
            tier: tier,
            usedCredits: nil,
            constrainedCredits: nil,
            unusedCredits: nil
        )
    }

    // MARK: - analyzeResetEvent (weekly two-band)

    @Test("analyzeResetEvent: 70% weekly peak on Pro — used 70% (3.5M), unused 30% (1.5M)")
    func analyzeWeeklySeventyPercent() {
        let breakdown = service.analyzeResetEvent(sevenDayPeak: 70.0, creditLimits: proLimits)

        #expect(isClose(breakdown.usedPercent, 70.0))
        #expect(isClose(breakdown.unusedPercent, 30.0))
        #expect(isClose(breakdown.usedCredits, 3_500_000))
        #expect(isClose(breakdown.unusedCredits, 1_500_000))
    }

    @Test("analyzeResetEvent: percentages always sum to 100%")
    func percentagesSumTo100() {
        for peak in [0.0, 33.33, 70.0, 99.9, 100.0] {
            let breakdown = service.analyzeResetEvent(sevenDayPeak: peak, creditLimits: proLimits)
            let sum = breakdown.usedPercent + breakdown.unusedPercent
            #expect(isClose(sum, 100.0), "Percentages should sum to 100%, got \(sum) for peak=\(peak)")
            #expect(isClose(breakdown.usedCredits + breakdown.unusedCredits, 5_000_000))
        }
    }

    @Test("analyzeResetEvent: 0% peak — all unused")
    func analyzeWithZeroPeak() {
        let breakdown = service.analyzeResetEvent(sevenDayPeak: 0.0, creditLimits: proLimits)

        #expect(isClose(breakdown.usedPercent, 0.0))
        #expect(isClose(breakdown.usedCredits, 0.0))
        #expect(isClose(breakdown.unusedPercent, 100.0))
        #expect(isClose(breakdown.unusedCredits, 5_000_000))
    }

    @Test("analyzeResetEvent: peak over 100% clamps to used 100 / unused 0")
    func analyzeClampsOverHundred() {
        let breakdown = service.analyzeResetEvent(sevenDayPeak: 104.0, creditLimits: proLimits)

        #expect(isClose(breakdown.usedPercent, 100.0))
        #expect(isClose(breakdown.unusedPercent, 0.0))
        #expect(isClose(breakdown.usedCredits, 5_000_000))
        #expect(isClose(breakdown.unusedCredits, 0.0))
    }

    @Test("analyzeResetEvent: negative peak clamps to 0")
    func analyzeClampsNegative() {
        let breakdown = service.analyzeResetEvent(sevenDayPeak: -3.0, creditLimits: proLimits)

        #expect(isClose(breakdown.usedPercent, 0.0))
        #expect(isClose(breakdown.unusedPercent, 100.0))
    }

    // MARK: - aggregateBreakdown: weekly cycles

    @Test("aggregateBreakdown: weekly cycle with 70% peak reports 70% used / 30% unused")
    func aggregateWeeklyCycle() {
        let summary = service.aggregateBreakdown(events: [makeWeeklyEvent(sevenDayUtil: 70.0)])

        #expect(summary.resetCount == 1)
        #expect(isClose(summary.usedCredits, 3_500_000))
        #expect(isClose(summary.unusedCredits, 1_500_000))
        #expect(summary.constrainedCredits == 0)
        #expect(isClose(summary.usedPercent, 70.0))
        #expect(isClose(summary.unusedPercent, 30.0))
        #expect(summary.constrainedPercent == 0)
        #expect(isClose(summary.avgPeakUtilization, 70.0))
    }

    @Test("aggregateBreakdown: weekly cycle over 100% clamps to 100 used / 0 unused")
    func aggregateWeeklyOverHundred() {
        let summary = service.aggregateBreakdown(events: [makeWeeklyEvent(sevenDayUtil: 104.0)])

        #expect(isClose(summary.usedPercent, 100.0))
        #expect(isClose(summary.unusedPercent, 0.0))
        #expect(isClose(summary.usedCredits, 5_000_000))
        #expect(isClose(summary.avgPeakUtilization, 100.0))
    }

    @Test("aggregateBreakdown: weekly cycle ignores stored credits and recomputes from 7d peak")
    func aggregateWeeklyRecomputes() {
        let event = ResetEvent(
            id: 1, timestamp: Self.postCutoverMs, fiveHourPeak: nil, sevenDayUtil: 40.0,
            tier: "default_claude_pro", usedCredits: 1, constrainedCredits: 1, unusedCredits: 1
        )
        let summary = service.aggregateBreakdown(events: [event])

        #expect(isClose(summary.usedCredits, 2_000_000))
        #expect(isClose(summary.unusedCredits, 3_000_000))
        #expect(summary.constrainedCredits == 0)
    }

    @Test("aggregateBreakdown: weekly cycle with unresolvable tier is skipped")
    func aggregateWeeklyUnknownTier() {
        let summary = service.aggregateBreakdown(events: [
            makeWeeklyEvent(id: 1, tier: "unknown_tier_xyz"),
            makeWeeklyEvent(id: 2, tier: nil),
        ])

        #expect(summary.resetCount == 0)
        #expect(summary.usedCredits == 0)
    }

    @Test("aggregateBreakdown: weekly cycles resolve per-event tier")
    func aggregateWeeklyMixedTier() {
        let summary = service.aggregateBreakdown(events: [
            makeWeeklyEvent(id: 1, sevenDayUtil: 50.0, tier: "default_claude_pro"),
            makeWeeklyEvent(id: 2, timestamp: Self.postCutoverMs + 7 * 86_400_000, sevenDayUtil: 50.0, tier: "default_claude_max_5x"),
        ])

        let max5x = Double(RateLimitTier.max5x.creditLimits.sevenDayCredits)
        #expect(summary.resetCount == 2)
        #expect(isClose(summary.usedCredits, 2_500_000 + max5x / 2))
        #expect(isClose(summary.usedPercent, 50.0))
    }

    // MARK: - aggregateBreakdown: legacy 5h events

    @Test("aggregateBreakdown: legacy events use stored credits unchanged")
    func aggregateLegacyStoredCredits() {
        let events = [
            makeLegacyEvent(id: 1, fiveHourPeak: 72.0, usedCredits: 396_000, constrainedCredits: 0, unusedCredits: 154_000),
            makeLegacyEvent(id: 2, fiveHourPeak: 50.0, sevenDayUtil: 98.0, usedCredits: 275_000, constrainedCredits: 175_000, unusedCredits: 100_000),
        ]

        let summary = service.aggregateBreakdown(events: events)

        #expect(isClose(summary.usedCredits, 396_000 + 275_000))
        #expect(isClose(summary.constrainedCredits, 0 + 175_000))
        #expect(isClose(summary.unusedCredits, 154_000 + 100_000))
        #expect(summary.resetCount == 2)
        #expect(isClose(summary.avgPeakUtilization, (72.0 + 50.0) / 2.0))

        let sum = summary.usedPercent + summary.constrainedPercent + summary.unusedPercent
        #expect(isClose(sum, 100.0))
    }

    @Test("aggregateBreakdown: legacy event stored credits are not recomputed from peak or tier")
    func aggregateLegacyNotRecomputed() {
        // Stored values deliberately inconsistent with peak × 5h credits, and tier unresolvable
        let event = makeLegacyEvent(tier: "unknown_tier_xyz", usedCredits: 123, constrainedCredits: 45, unusedCredits: 678)
        let summary = service.aggregateBreakdown(events: [event])

        #expect(summary.resetCount == 1)
        #expect(summary.usedCredits == 123)
        #expect(summary.constrainedCredits == 45)
        #expect(summary.unusedCredits == 678)
    }

    @Test("aggregateBreakdown: legacy event with nil stored constrained counts as 0 constrained")
    func aggregateLegacyNilConstrained() {
        let summary = service.aggregateBreakdown(events: [makeLegacyEvent(constrainedCredits: nil)])

        #expect(summary.resetCount == 1)
        #expect(summary.constrainedCredits == 0)
        #expect(isClose(summary.usedCredits, 396_000))
    }

    @Test("aggregateBreakdown: legacy event without stored credits is rebuilt from the historical 5h limit")
    func aggregateLegacyNoStoredCreditsRebuilt() {
        // Pro 5h limit 550,000: 72% peak -> used 396,000; 7d remaining 750,000 > 5h remaining -> unused 154,000
        let events = [
            makeLegacyEvent(id: 1, usedCredits: nil, constrainedCredits: nil, unusedCredits: nil),
            makeLegacyEvent(id: 2, usedCredits: 100, constrainedCredits: nil, unusedCredits: nil),
        ]

        let summary = service.aggregateBreakdown(events: events)

        #expect(summary.resetCount == 2)
        #expect(isClose(summary.usedCredits, 2 * 396_000))
        #expect(isClose(summary.constrainedCredits, 0))
        #expect(isClose(summary.unusedCredits, 2 * 154_000))
        #expect(isClose(summary.avgPeakUtilization, 72.0))
    }

    @Test("aggregateBreakdown: rebuilt legacy event reports the 7d-constrained band")
    func aggregateLegacyNoStoredCreditsConstrained() {
        // Pro: 10% peak -> used 55,000, 5h remaining 495,000; 7d at 99.5% -> remaining 25,000
        let event = makeLegacyEvent(fiveHourPeak: 10.0, sevenDayUtil: 99.5, usedCredits: nil, constrainedCredits: nil, unusedCredits: nil)

        let summary = service.aggregateBreakdown(events: [event])

        #expect(isClose(summary.usedCredits, 55_000))
        #expect(isClose(summary.constrainedCredits, 470_000))
        #expect(isClose(summary.unusedCredits, 25_000))
    }

    @Test("aggregateBreakdown: legacy event without stored credits and unknown tier is skipped")
    func aggregateLegacyNoStoredCreditsUnknownTier() {
        let events = [
            makeLegacyEvent(id: 1),
            makeLegacyEvent(id: 2, tier: nil, usedCredits: nil, constrainedCredits: nil, unusedCredits: nil),
            makeLegacyEvent(id: 3, sevenDayUtil: nil, usedCredits: nil, constrainedCredits: nil, unusedCredits: nil),
        ]

        let summary = service.aggregateBreakdown(events: events)

        #expect(summary.resetCount == 1)
        #expect(isClose(summary.usedCredits, 396_000))
    }

    @Test("aggregateBreakdown: legacy events inside the first weekly cycle are not counted twice")
    func aggregateExcludesWeeklyOverlap() {
        let weekly = makeWeeklyEvent(id: 3, timestamp: ResetEvent.fiveHourLimitRetiredAtMs + 2 * 86_400_000, sevenDayUtil: 70.0)
        let overlapping = makeLegacyEvent(id: 2, timestamp: weekly.timestamp - 6 * 86_400_000)
        let older = makeLegacyEvent(id: 1, timestamp: weekly.timestamp - 8 * 86_400_000)

        let summary = service.aggregateBreakdown(events: [older, overlapping, weekly])

        #expect(summary.resetCount == 2)
        #expect(isClose(summary.usedCredits, 396_000 + 3_500_000))
    }

    @Test("analyzeResetEvent: non-finite peak is treated as 0")
    func analyzeNonFinitePeak() {
        let breakdown = service.analyzeResetEvent(sevenDayPeak: .nan, creditLimits: proLimits)
        #expect(breakdown.usedPercent == 0)
        #expect(breakdown.unusedCredits == 5_000_000)
    }

    @Test("aggregateBreakdown: pre-cutover peak-nil event is not a weekly cycle and is skipped")
    func aggregatePreCutoverPeakNilSkipped() {
        let events = [
            makeLegacyEvent(id: 1, fiveHourPeak: nil, sevenDayUtil: 70.0, usedCredits: nil, constrainedCredits: nil, unusedCredits: nil),
            // Even with stored credits, a peak-nil pre-cutover event is not counted
            makeLegacyEvent(id: 2, fiveHourPeak: nil, sevenDayUtil: 70.0, usedCredits: 1_000, constrainedCredits: 0, unusedCredits: 1_000),
        ]

        let summary = service.aggregateBreakdown(events: events)

        #expect(summary.resetCount == 0)
        #expect(summary.usedCredits == 0)
    }

    @Test("aggregateBreakdown: post-cutover event without peak or 7d util is skipped")
    func aggregatePostCutoverNoDataSkipped() {
        let event = makeLegacyEvent(timestamp: Self.postCutoverMs, fiveHourPeak: nil, sevenDayUtil: nil, usedCredits: nil, constrainedCredits: nil, unusedCredits: nil)
        let summary = service.aggregateBreakdown(events: [event])

        #expect(summary.resetCount == 0)
    }

    // MARK: - aggregateBreakdown: mixed and empty

    @Test("aggregateBreakdown: mixed legacy and weekly events sum both")
    func aggregateMixed() {
        let events = [
            makeLegacyEvent(id: 1),
            makeWeeklyEvent(id: 2, sevenDayUtil: 70.0),
        ]

        let summary = service.aggregateBreakdown(events: events)

        #expect(summary.resetCount == 2)
        #expect(isClose(summary.usedCredits, 396_000 + 3_500_000))
        #expect(isClose(summary.unusedCredits, 154_000 + 1_500_000))
        #expect(isClose(summary.avgPeakUtilization, (72.0 + 70.0) / 2.0))
    }

    @Test("aggregateBreakdown: zero events returns zeroed PeriodSummary")
    func aggregateWithZeroEvents() {
        let summary = service.aggregateBreakdown(events: [])

        #expect(summary.usedCredits == 0)
        #expect(summary.constrainedCredits == 0)
        #expect(summary.unusedCredits == 0)
        #expect(summary.resetCount == 0)
        #expect(summary.avgPeakUtilization == 0)
        #expect(summary.usedPercent == 0)
        #expect(summary.constrainedPercent == 0)
        #expect(summary.unusedPercent == 0)
    }

    // MARK: - Floating Point Helper

    private func isClose(_ a: Double, _ b: Double, tolerance: Double = 0.01) -> Bool {
        abs(a - b) < tolerance
    }
}
