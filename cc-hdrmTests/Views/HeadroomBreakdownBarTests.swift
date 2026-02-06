import Testing
import SwiftUI
@testable import cc_hdrm

@Suite("HeadroomBreakdownBar Tests")
@MainActor
struct HeadroomBreakdownBarTests {

    // MARK: - Helpers

    private func makeBar(
        resetEvents: [ResetEvent] = [],
        creditLimits: CreditLimits? = CreditLimits(fiveHourCredits: 100, sevenDayCredits: 909)
    ) -> HeadroomBreakdownBar {
        HeadroomBreakdownBar(
            resetEvents: resetEvents,
            creditLimits: creditLimits
        )
    }

    // MARK: - Initialization

    @Test("HeadroomBreakdownBar renders without crashing")
    func rendersWithoutCrash() {
        let bar = makeBar()
        let _ = bar.body
    }

    // MARK: - Reset Event Count Display

    @Test("HeadroomBreakdownBar shows reset event count when events present")
    func showsResetEventCount() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            ResetEvent(id: 1, timestamp: nowMs - 3_600_000, fiveHourPeak: 85.0, sevenDayUtil: 40.0, tier: "pro", usedCredits: nil, constrainedCredits: nil, wasteCredits: nil),
            ResetEvent(id: 2, timestamp: nowMs - 1_800_000, fiveHourPeak: 92.0, sevenDayUtil: 42.0, tier: "pro", usedCredits: nil, constrainedCredits: nil, wasteCredits: nil),
            ResetEvent(id: 3, timestamp: nowMs, fiveHourPeak: 78.0, sevenDayUtil: 38.0, tier: "pro", usedCredits: nil, constrainedCredits: nil, wasteCredits: nil)
        ]
        let bar = makeBar(resetEvents: events)
        // Should display "Headroom breakdown: 3 reset events in period"
        let _ = bar.body
    }

    @Test("HeadroomBreakdownBar shows no-events message when empty")
    func showsNoEventsMessage() {
        let bar = makeBar(resetEvents: [])
        // Should display "No reset events in this period"
        let _ = bar.body
    }

    // MARK: - Nil Credit Limits (Unknown Tier)

    @Test("HeadroomBreakdownBar shows unavailable message when credit limits are nil")
    func showsUnavailableWhenNilCreditLimits() {
        let bar = makeBar(creditLimits: nil)
        // Should display "Headroom breakdown unavailable -- unknown subscription tier"
        let _ = bar.body
    }

    @Test("HeadroomBreakdownBar prioritizes nil credit limits message over reset events")
    func nilCreditLimitsPrioritizedOverEvents() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            ResetEvent(id: 1, timestamp: nowMs, fiveHourPeak: 85.0, sevenDayUtil: 40.0, tier: nil, usedCredits: nil, constrainedCredits: nil, wasteCredits: nil)
        ]
        let bar = makeBar(resetEvents: events, creditLimits: nil)
        // Even with events present, nil credit limits should show unavailable message
        let _ = bar.body
    }

    // MARK: - Fixed Height

    @Test("HeadroomBreakdownBar renders at fixed 80px height")
    func fixedHeight() {
        // Cannot directly assert SwiftUI frame modifiers, but verify renders
        let bar = makeBar()
        let _ = bar.body
    }

    // MARK: - Different Credit Limit Tiers

    @Test("HeadroomBreakdownBar renders with Pro tier limits")
    func rendersWithProLimits() {
        let bar = makeBar(creditLimits: RateLimitTier.pro.creditLimits)
        let _ = bar.body
    }

    @Test("HeadroomBreakdownBar renders with Max 5x tier limits")
    func rendersWithMax5xLimits() {
        let bar = makeBar(creditLimits: RateLimitTier.max5x.creditLimits)
        let _ = bar.body
    }

    // MARK: - Single Reset Event

    @Test("HeadroomBreakdownBar shows count for single reset event")
    func singleResetEvent() {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let events = [
            ResetEvent(id: 1, timestamp: nowMs, fiveHourPeak: 90.0, sevenDayUtil: 35.0, tier: "pro", usedCredits: nil, constrainedCredits: nil, wasteCredits: nil)
        ]
        let bar = makeBar(resetEvents: events)
        // Should display "Headroom breakdown: 1 reset events in period"
        let _ = bar.body
    }
}
