import Foundation
import Testing
@testable import cc_hdrm

@Suite("HeadroomBreakdown Tests")
struct HeadroomBreakdownTests {

    @Test("HeadroomBreakdown stores all values correctly")
    func storesAllValues() {
        let breakdown = HeadroomBreakdown(
            usedPercent: 70.0,
            unusedPercent: 30.0,
            usedCredits: 3_500_000,
            unusedCredits: 1_500_000
        )

        #expect(breakdown.usedPercent == 70.0)
        #expect(breakdown.unusedPercent == 30.0)
        #expect(breakdown.usedCredits == 3_500_000)
        #expect(breakdown.unusedCredits == 1_500_000)
    }

    @Test("HeadroomBreakdown equality works correctly")
    func equalityWorks() {
        let b1 = HeadroomBreakdown(usedPercent: 70.0, unusedPercent: 30.0, usedCredits: 3_500_000, unusedCredits: 1_500_000)
        let b2 = HeadroomBreakdown(usedPercent: 70.0, unusedPercent: 30.0, usedCredits: 3_500_000, unusedCredits: 1_500_000)
        let b3 = HeadroomBreakdown(usedPercent: 50.0, unusedPercent: 50.0, usedCredits: 2_500_000, unusedCredits: 2_500_000)

        #expect(b1 == b2)
        #expect(b1 != b3)
    }

    @Test("PeriodSummary stores all values correctly")
    func periodSummaryStoresValues() {
        let summary = PeriodSummary(
            usedCredits: 1_000_000,
            constrainedCredits: 200_000,
            unusedCredits: 300_000,
            resetCount: 5,
            avgPeakUtilization: 65.0,
            usedPercent: 66.67,
            constrainedPercent: 13.33,
            unusedPercent: 20.0
        )

        #expect(summary.usedCredits == 1_000_000)
        #expect(summary.constrainedCredits == 200_000)
        #expect(summary.unusedCredits == 300_000)
        #expect(summary.resetCount == 5)
        #expect(summary.avgPeakUtilization == 65.0)
        #expect(summary.usedPercent == 66.67)
        #expect(summary.constrainedPercent == 13.33)
        #expect(summary.unusedPercent == 20.0)
    }

    @Test("PeriodSummary equality works correctly")
    func periodSummaryEquality() {
        let s1 = PeriodSummary(
            usedCredits: 1000, constrainedCredits: 200, unusedCredits: 300,
            resetCount: 3, avgPeakUtilization: 50.0,
            usedPercent: 66.67, constrainedPercent: 13.33, unusedPercent: 20.0
        )

        let s2 = PeriodSummary(
            usedCredits: 1000, constrainedCredits: 200, unusedCredits: 300,
            resetCount: 3, avgPeakUtilization: 50.0,
            usedPercent: 66.67, constrainedPercent: 13.33, unusedPercent: 20.0
        )

        #expect(s1 == s2)
    }

}
