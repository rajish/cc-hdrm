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

    // MARK: - Story 4.6 — onTap + Accessibility Hint Tests

    @Test("Section renders with onTap callback without crash")
    @MainActor
    func rendersWithOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let section = SevenDayGaugeSection(appState: appState, onTap: {})
        _ = section.body
    }

    @Test("Section renders without onTap callback without crash")
    @MainActor
    func rendersWithoutOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let section = SevenDayGaugeSection(appState: appState, onTap: nil)
        _ = section.body
    }

    @Test("Section renders via NSHostingController with onTap without crash")
    @MainActor
    func rendersViaHostingWithOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let section = SevenDayGaugeSection(appState: appState, onTap: {})
        let hosting = NSHostingController(rootView: section)
        _ = hosting.view
    }

    @Test("Section renders via NSHostingController without onTap without crash")
    @MainActor
    func rendersViaHostingWithoutOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        let section = SevenDayGaugeSection(appState: appState, onTap: nil)
        let hosting = NSHostingController(rootView: section)
        _ = hosting.view
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

    // MARK: - No 5-Hour Number

    @Test("no 5-hour number → quotas line and its VoiceOver text are gone, section is shorter apart from the larger ring")
    @MainActor
    func noFiveHourHidesQuotas() {
        let sevenDay = WindowState(utilization: 70.0, resetsAt: nil)
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateCreditLimits(RateLimitTier.pro.creditLimits)

        appState.updateWindows(fiveHour: WindowState(utilization: 20.0, resetsAt: nil), sevenDay: sevenDay)
        let heightWithQuotas = NSHostingController(rootView: SevenDayGaugeSection(appState: appState)).view.fittingSize.height
        #expect(SevenDayGaugeSection(appState: appState).combinedAccessibilityLabel.contains("quotas"))

        appState.updateWindows(fiveHour: nil, sevenDay: sevenDay)
        let heightWithoutQuotas = NSHostingController(rootView: SevenDayGaugeSection(appState: appState)).view.fittingSize.height
        #expect(!SevenDayGaugeSection(appState: appState).combinedAccessibilityLabel.contains("quotas"))
        let ringGrowth: CGFloat = 40
        #expect(heightWithoutQuotas - ringGrowth < heightWithQuotas)
    }
}

@Suite("SevenDayGaugeSection Pace Line")
@MainActor
struct SevenDayGaugeSectionPaceTests {

    private let day: TimeInterval = 86400

    private func section(utilization: Double, resetsIn: TimeInterval?, slope: SlopeLevel = .rising) -> SevenDayGaugeSection {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateSlopes(fiveHour: .flat, sevenDay: slope)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: utilization, resetsAt: resetsIn.map { Date().addingTimeInterval($0) })
        )
        return SevenDayGaugeSection(appState: appState)
    }

    private func height(_ section: SevenDayGaugeSection) -> CGFloat {
        NSHostingController(rootView: section).view.fittingSize.height
    }

    @Test("ahead of pace → line with run-out, VoiceOver reads it, slope gone")
    func aheadOfPaceLine() throws {
        let section = section(utilization: 60, resetsIn: 4 * day)
        let pace = try #require(section.appState.weeklyPace)
        #expect(section.paceLineText?.hasPrefix("Ahead of pace \u{2014} runs out ~") == true)
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 40 percent, \(pace.accessibilityText), resets in "))
        #expect(section.combinedAccessibilityLabel.contains("ahead of pace, runs out around "))
        #expect(!section.combinedAccessibilityLabel.contains(SlopeLevel.rising.accessibilityLabel))
        #expect(section.ringSlopeLevel == nil)
    }

    @Test("under an even pace → \"On pace\", VoiceOver reads it")
    func onPaceLine() {
        let section = section(utilization: 40, resetsIn: 3.5 * day)
        #expect(section.paceLineText == "On pace")
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 60 percent, on pace, resets in "))
        #expect(section.ringSlopeLevel == nil)
    }

    @Test("missing resets_at → no line, no pace or slope in VoiceOver")
    func missingResetsAtHasNoPaceLine() {
        let section = section(utilization: 60, resetsIn: nil)
        #expect(section.paceLineText == nil)
        #expect(section.combinedAccessibilityLabel == "7-day headroom: 40 percent")
        #expect(section.ringSlopeLevel == nil)
    }

    @Test("exhausted → no line")
    func exhaustedHasNoPaceLine() {
        let section = section(utilization: 100, resetsIn: day)
        #expect(section.paceLineText == nil)
        #expect(!section.combinedAccessibilityLabel.contains("pace"))
    }

    @Test("outage with old weekly data → no line and no slope, section gets shorter")
    func outageHasNoPaceOrSlope() {
        let section = section(utilization: 40, resetsIn: 3.5 * day)
        let heightWithLine = height(section)

        section.appState.updateConnectionStatus(.disconnected)
        #expect(section.paceLineText == nil)
        #expect(section.ringSlopeLevel == nil)
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 60 percent, resets in "))
        #expect(height(section) < heightWithLine)
    }

    @Test("with a 5-hour number, including promoted weekly → slope stays, no line")
    func fiveHourNumberKeepsSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20, resetsAt: nil),
            sevenDay: WindowState(utilization: 85, resetsAt: Date().addingTimeInterval(4 * day))
        )
        let section = SevenDayGaugeSection(appState: appState)

        #expect(appState.displayedWindow == .sevenDay)
        #expect(section.paceLineText == nil)
        #expect(section.ringSlopeLevel == .rising)
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 15 percent, \(SlopeLevel.rising.accessibilityLabel), resets in "))
    }

    @Test("number → none → number at the next update: line and slope swap each time")
    func flipSwapsLineAndSlope() {
        let section = section(utilization: 60, resetsIn: 4 * day)
        let appState = section.appState
        let weekly = appState.sevenDay
        let fiveHour = WindowState(utilization: 20, resetsAt: nil)
        #expect(section.paceLineText != nil)

        appState.updateWindows(fiveHour: fiveHour, sevenDay: weekly)
        #expect(section.paceLineText == nil)
        #expect(section.ringSlopeLevel == .rising)

        appState.updateWindows(fiveHour: nil, sevenDay: weekly)
        #expect(section.paceLineText != nil)
        #expect(section.ringSlopeLevel == nil)
    }

    // MARK: - Ring Size

    @Test("no 5-hour number → the weekly ring takes the primary size")
    @MainActor
    func noFiveHourLargeRing() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: WindowState(utilization: 35, resetsAt: Date().addingTimeInterval(86400)))
        let section = SevenDayGaugeSection(appState: appState)
        #expect(section.ringSize == 96)
        #expect(section.ringStrokeWidth == 7)
    }

    @Test("5-hour number present → the weekly ring stays at 56, including when weekly is promoted")
    @MainActor
    func fiveHourKeepsSmallRing() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 10, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 97, resetsAt: Date().addingTimeInterval(86400))
        )
        #expect(appState.displayedWindow == .sevenDay)
        let section = SevenDayGaugeSection(appState: appState)
        #expect(section.ringSize == 56)
        #expect(section.ringStrokeWidth == 4)
    }

    @Test("the ring follows a state change at the next update, and the drawn section grows by the ring")
    @MainActor
    func ringFollowsFlip() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        let weekly = WindowState(utilization: 35, resetsAt: Date().addingTimeInterval(86400))
        let fiveHour = WindowState(utilization: 10, resetsAt: Date().addingTimeInterval(3600))
        let section = SevenDayGaugeSection(appState: appState)

        appState.updateWindows(fiveHour: fiveHour, sevenDay: weekly)
        let small = NSHostingController(rootView: section).view.fittingSize.height
        #expect(section.ringSize == 56)

        appState.updateWindows(fiveHour: nil, sevenDay: weekly)
        let large = NSHostingController(rootView: section).view.fittingSize.height
        #expect(section.ringSize == 96)
        // The on-pace line accounts for whatever exceeds the 40-point ring growth
        #expect(large - small >= 40)

        appState.updateWindows(fiveHour: fiveHour, sevenDay: weekly)
        #expect(section.ringSize == 56)
    }
}
