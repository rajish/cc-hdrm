import Foundation
@testable import cc_hdrm

extension ResetEvent {
    /// Pro tier 5h credit limit used to derive stored credits for legacy fixtures.
    static let fixtureFiveHourCredits: Double = 550_000

    /// Legacy 5h reset event whose stored credits follow its peak on the Pro 5h limit:
    /// used = peak% × 550,000, unused = the rest, constrained = 0 unless set.
    static func legacyFixture(
        id: Int64,
        timestamp: Int64,
        fiveHourPeak: Double,
        sevenDayUtil: Double?,
        tier: String? = "default_claude_pro",
        constrainedCredits: Double = 0
    ) -> ResetEvent {
        let used = fiveHourPeak / 100.0 * fixtureFiveHourCredits
        return ResetEvent(
            id: id,
            timestamp: timestamp,
            fiveHourPeak: fiveHourPeak,
            sevenDayUtil: sevenDayUtil,
            tier: tier,
            usedCredits: used,
            constrainedCredits: constrainedCredits,
            unusedCredits: fixtureFiveHourCredits - used - constrainedCredits
        )
    }
}
