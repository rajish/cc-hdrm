import SwiftUI
import Testing
@testable import cc_hdrm

@Suite("FiveHourGaugeSection Tests")
struct FiveHourGaugeSectionTests {

    @Test("Section renders with valid fiveHour data without crash")
    @MainActor
    func validFiveHourData() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let section = FiveHourGaugeSection(appState: appState)
        _ = section.body
    }

    @Test("Section renders with nil fiveHour data (disconnected) without crash")
    @MainActor
    func nilFiveHourData() {
        let appState = AppState()
        let section = FiveHourGaugeSection(appState: appState)
        _ = section.body
        #expect(appState.fiveHour == nil)
    }

    // MARK: - Story 4.6 — onTap + Accessibility Hint Tests

    @Test("Section renders with onTap callback without crash")
    @MainActor
    func rendersWithOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let section = FiveHourGaugeSection(appState: appState, onTap: {})
        _ = section.body
    }

    @Test("Section renders without onTap callback without crash")
    @MainActor
    func rendersWithoutOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let section = FiveHourGaugeSection(appState: appState, onTap: nil)
        _ = section.body
    }

    @Test("Section renders via NSHostingController with onTap without crash")
    @MainActor
    func rendersViaHostingWithOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let section = FiveHourGaugeSection(appState: appState, onTap: {})
        let hosting = NSHostingController(rootView: section)
        _ = hosting.view
    }

    @Test("Section renders via NSHostingController without onTap without crash")
    @MainActor
    func rendersViaHostingWithoutOnTap() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        let section = FiveHourGaugeSection(appState: appState, onTap: nil)
        let hosting = NSHostingController(rootView: section)
        _ = hosting.view
    }
}
