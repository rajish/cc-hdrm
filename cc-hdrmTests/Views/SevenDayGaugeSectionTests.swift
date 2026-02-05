import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("SevenDayGaugeSection Tests")
struct SevenDayGaugeSectionTests {

    @Test("Section renders with valid sevenDay data without crash")
    @MainActor
    func validSevenDayData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
    }

    @Test("Section renders as empty when sevenDay is nil (AC #6)")
    @MainActor
    func nilSevenDayHidesSection() {
        let appState = AppState()
        // Default: no sevenDay data
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
        // No crash — EmptyView produced when sevenDay is nil
        #expect(appState.sevenDay == nil)
    }

    @Test("Section renders with exhausted (0% headroom) sevenDay data")
    @MainActor
    func exhaustedSevenDayData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
    }

    @Test("Section renders with normal headroom state")
    @MainActor
    func normalHeadroomState() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
        #expect(appState.sevenDay?.headroomState == .normal)
    }

    @Test("Section renders with caution headroom state")
    @MainActor
    func cautionHeadroomState() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 70.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
        #expect(appState.sevenDay?.headroomState == .caution)
    }

    @Test("Section renders with warning headroom state")
    @MainActor
    func warningHeadroomState() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 88.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
        #expect(appState.sevenDay?.headroomState == .warning)
    }

    @Test("Section renders with critical headroom state")
    @MainActor
    func criticalHeadroomState() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 97.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        _ = section.body
        #expect(appState.sevenDay?.headroomState == .critical)
    }

    // MARK: - Quotas Display Tests (Story 3.3, AC-7)

    @Test("combinedAccessibilityLabel includes quotas when quotasRemaining is non-nil")
    @MainActor
    func accessibilityLabelIncludesQuotas() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateCreditLimits(RateLimitTier.pro.creditLimits)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        #expect(section.combinedAccessibilityLabel.contains("full 5-hour quotas left"))
    }

    @Test("combinedAccessibilityLabel does NOT include quotas when quotasRemaining is nil")
    @MainActor
    func accessibilityLabelExcludesQuotasWhenNil() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        // No credit limits → quotasRemaining is nil
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 70.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        #expect(!section.combinedAccessibilityLabel.contains("quotas"))
    }

    @Test("quotasRemaining 2.7 → accessibility says '2 full 5-hour quotas left' (floored)")
    @MainActor
    func accessibilityLabelFlooredQuotas() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        // Pro tier: 7d util = 72.73% → remaining = 0.2727 * 5,000,000 = 1,363,636 → quotas = 1,363,636/550,000 = 2.48
        // Let's use custom limits to get exactly 2.7
        appState.updateCreditLimits(CreditLimits(fiveHourCredits: 100, sevenDayCredits: 1000))
        // 7d util = 73% → remaining = 0.27 * 1000 = 270 → quotas = 270/100 = 2.7
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 73.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        #expect(section.combinedAccessibilityLabel.contains("2 full 5-hour quotas left"))
    }

    @Test("quotasRemaining 0.3 → accessibility says '0 full 5-hour quotas left'")
    @MainActor
    func accessibilityLabelZeroQuotas() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateCreditLimits(CreditLimits(fiveHourCredits: 100, sevenDayCredits: 1000))
        // 7d util = 97% → remaining = 0.03 * 1000 = 30 → quotas = 30/100 = 0.3
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: nil),
            sevenDay: WindowState(utilization: 97.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        #expect(section.combinedAccessibilityLabel.contains("0 full 5-hour quotas left"))
    }

    @Test("HeadroomState derivation is correct for 7d window")
    @MainActor
    func headroomStateDerivation() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)

        // Normal: utilization 30% → headroom 70%
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 30.0, resetsAt: nil))
        #expect(appState.sevenDay?.headroomState == .normal)

        // Caution: utilization 70% → headroom 30%
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 70.0, resetsAt: nil))
        #expect(appState.sevenDay?.headroomState == .caution)

        // Warning: utilization 88% → headroom 12%
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 88.0, resetsAt: nil))
        #expect(appState.sevenDay?.headroomState == .warning)

        // Critical: utilization 97% → headroom 3%
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 97.0, resetsAt: nil))
        #expect(appState.sevenDay?.headroomState == .critical)

        // Exhausted: utilization 100% → headroom 0%
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 100.0, resetsAt: nil))
        #expect(appState.sevenDay?.headroomState == .exhausted)

        // Nil → disconnected
        appState.updateWindows(fiveHour: nil, sevenDay: nil)
        #expect(appState.sevenDay?.headroomState == nil)
    }
}
