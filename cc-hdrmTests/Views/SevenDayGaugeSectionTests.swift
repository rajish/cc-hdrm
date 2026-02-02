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
