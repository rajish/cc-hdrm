import Foundation
import Testing
@testable import cc_hdrm

@Suite("AppState Menu Bar Slope Display")
struct AppStateSlopeTests {

    @Test("menuBarText appends ↗ when weekly slope is rising")
    @MainActor
    func menuBarTextIncludesArrowWhenRising() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 22.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)

        #expect(appState.menuBarText == "78% \u{2197}")
    }

    @Test("menuBarText appends ↗ (not ⬆) when weekly slope is steep")
    @MainActor
    func menuBarTextIncludesArrowWhenSteep() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 42.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        #expect(appState.menuBarText == "58% \u{2197}")
        #expect(!appState.menuBarText.contains("\u{2B06}"))
    }

    @Test("menuBarText excludes arrow when weekly slope is flat")
    @MainActor
    func menuBarTextExcludesArrowWhenFlat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)

        #expect(appState.menuBarText == "83%")
    }

    @Test("menuBarText ignores the 5h slope")
    @MainActor
    func menuBarTextIgnoresFiveHourSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)

        #expect(appState.menuBarText == "50%")
    }

    @Test("menuBarText excludes arrow when weekly exhausted (countdown mode)")
    @MainActor
    func menuBarTextExcludesArrowWhenExhausted() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: Date().addingTimeInterval(2 * 86400))
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        #expect(appState.menuBarText.hasPrefix("\u{21BB}"))
        #expect(!appState.menuBarText.contains("\u{2197}"))
    }

    @Test("menuBarText excludes arrow when disconnected")
    @MainActor
    func menuBarTextExcludesArrowWhenDisconnected() {
        let appState = AppState()
        appState.updateConnectionStatus(.disconnected)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .steep)

        #expect(appState.menuBarText == "\u{2014}")
    }

    @Test("menuBarText shows no arrow when slope not set (default .flat)")
    @MainActor
    func menuBarTextDefaultSlopeNoArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3 * 86400))
        )

        #expect(appState.sevenDaySlope == .flat)
        #expect(appState.menuBarText == "83%")
    }

    @Test("tokenExpired maps to disconnected - no slope arrow")
    @MainActor
    func tokenExpiredNoSlopeArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.tokenExpired)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .steep)

        #expect(appState.menuBarText == "\u{2014}")
    }

    @Test("noCredentials maps to disconnected - no slope arrow")
    @MainActor
    func noCredentialsNoSlopeArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.noCredentials)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .steep)

        #expect(appState.menuBarText == "\u{2014}")
    }

    @Test("weekly exhausted with no resetsAt shows 0% without arrow")
    @MainActor
    func exhaustedNoResetsAtShowsPercentage() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: nil,
            sevenDay: WindowState(utilization: 100.0, resetsAt: nil)
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        #expect(appState.menuBarText == "0%")
    }
}
