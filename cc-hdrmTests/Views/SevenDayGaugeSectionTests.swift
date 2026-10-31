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

    @Test("combinedAccessibilityLabel never mentions 5-hour quotas, even with credit limits")
    @MainActor
    func accessibilityLabelHasNoQuotas() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateCreditLimits(RateLimitTier.pro.creditLimits)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 70.0, resetsAt: Date().addingTimeInterval(86400))
        )
        let section = SevenDayGaugeSection(appState: appState)
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 30 percent"))
        #expect(!section.combinedAccessibilityLabel.contains("quotas"))
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

    @Test("combinedAccessibilityLabel without weekly data → \"7-day headroom: unavailable\"")
    @MainActor
    func unavailableAccessibilityLabel() {
        #expect(SevenDayGaugeSection(appState: AppState()).combinedAccessibilityLabel == "7-day headroom: unavailable")
    }
}

@Suite("SevenDayGaugeSection Pace Line")
@MainActor
struct SevenDayGaugeSectionPaceTests {

    private func section(utilization: Double, resetsIn: TimeInterval?) -> SevenDayGaugeSection {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: utilization, resetsAt: resetsIn.map { Date().addingTimeInterval($0) })
        )
        return SevenDayGaugeSection(appState: appState)
    }

    @Test("ahead of pace → \"Ahead of pace — runs out ~<day time>\" and VoiceOver reads it")
    func aheadOfPaceLine() throws {
        let section = section(utilization: 60, resetsIn: 4 * 86400)
        let pace = try #require(section.appState.weeklyPace)
        #expect(section.paceLineText?.hasPrefix("Ahead of pace \u{2014} runs out ~") == true)
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 40 percent, \(pace.accessibilityText), resets in "))
        #expect(section.combinedAccessibilityLabel.contains("ahead of pace, runs out around "))
        _ = section.body
    }

    @Test("behind pace at half-week → \"On pace\" and VoiceOver reads it")
    func onPaceLine() {
        let section = section(utilization: 40, resetsIn: 3.5 * 86400)
        #expect(section.paceLineText == "On pace")
        #expect(section.combinedAccessibilityLabel.hasPrefix("7-day headroom: 60 percent, on pace, resets in "))
    }

    @Test("well behind pace → \"On pace\"")
    func behindPaceLine() {
        #expect(section(utilization: 20, resetsIn: 2 * 86400).paceLineText == "On pace")
    }

    @Test("missing resets_at → no pace line")
    func missingResetsAtHasNoPaceLine() {
        let section = section(utilization: 60, resetsIn: nil)
        #expect(section.paceLineText == nil)
        #expect(section.combinedAccessibilityLabel == "7-day headroom: 40 percent")
    }

    @Test("exhausted → no pace line")
    func exhaustedHasNoPaceLine() {
        #expect(section(utilization: 100, resetsIn: 86400).paceLineText == nil)
    }
}
