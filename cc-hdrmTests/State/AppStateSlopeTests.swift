import Foundation
import Testing
@testable import cc_hdrm

@Suite("AppState Menu Bar Slope Display")
struct AppStateSlopeTests {

    // MARK: - Task 4.2: menuBarText includes arrow when fiveHourSlope is .rising

    @Test("menuBarText includes rising arrow when slope is rising")
    @MainActor
    func menuBarTextIncludesRisingArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 22.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)

        #expect(appState.menuBarText == "78% \u{2197}")  // arrow-upper-right
    }

    // MARK: - Task 4.3: menuBarText includes arrow when fiveHourSlope is .steep

    @Test("menuBarText includes steep arrow when slope is steep")
    @MainActor
    func menuBarTextIncludesSteepArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 35.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)

        #expect(appState.menuBarText == "65% \u{2B06}")  // arrow-up
    }

    // MARK: - Task 4.4: menuBarText excludes arrow when fiveHourSlope is .flat

    @Test("menuBarText excludes arrow when slope is flat")
    @MainActor
    func menuBarTextExcludesArrowWhenFlat() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)

        #expect(appState.menuBarText == "83%")  // No arrow
    }

    // MARK: - Task 4.5: menuBarText excludes arrow when exhausted (countdown mode)

    @Test("menuBarText excludes arrow when exhausted")
    @MainActor
    func menuBarTextExcludesArrowWhenExhausted() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        let resetsAt = Date().addingTimeInterval(720)  // 12 minutes
        appState.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: resetsAt),
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)

        #expect(appState.menuBarText.hasPrefix("\u{21BB}"))  // Countdown, no slope
        #expect(!appState.menuBarText.contains("\u{2B06}"))  // No steep arrow
    }

    // MARK: - Task 4.6: menuBarText excludes arrow when disconnected

    @Test("menuBarText excludes arrow when disconnected")
    @MainActor
    func menuBarTextExcludesArrowWhenDisconnected() {
        let appState = AppState()
        appState.updateConnectionStatus(.disconnected)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .steep)

        #expect(appState.menuBarText == "\u{2014}")  // em dash only
        #expect(!appState.menuBarText.contains("\u{2B06}"))  // No arrow
    }

    // MARK: - Task 4.7: displayedSlope returns sevenDaySlope when 7d is promoted

    @Test("displayedSlope returns sevenDaySlope when 7d is promoted")
    @MainActor
    func displayedSlopeReturnsSevenDaySlopeWhenPromoted() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 88.0, resetsAt: Date().addingTimeInterval(86400))  // 12% headroom, warning
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)

        // 7d is promoted (lower headroom AND in warning state)
        #expect(appState.displayedWindow == .sevenDay)
        #expect(appState.displayedSlope == .rising)
    }

    // MARK: - Task 4.8: menuBarText uses sevenDaySlope arrow when 7d is promoted

    @Test("menuBarText uses sevenDaySlope arrow when 7d is promoted")
    @MainActor
    func menuBarTextUsesSevenDaySlopeArrowWhenPromoted() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 88.0, resetsAt: Date().addingTimeInterval(86400))  // 12% headroom, warning
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)

        // 7d is promoted (lower headroom AND in warning state)
        #expect(appState.displayedWindow == .sevenDay)
        #expect(appState.menuBarText == "12% \u{2197}")  // Uses 7d slope arrow
    }

    // MARK: - Task 4.9: menuBarText shows no arrow when slope has not been set (default .flat)

    @Test("menuBarText shows no arrow when slope not set (default .flat)")
    @MainActor
    func menuBarTextDefaultSlopeNoArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 17.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: nil
        )
        // NOTE: updateSlopes() not called - slope remains default .flat

        #expect(appState.fiveHourSlope == .flat)  // Verify default
        #expect(appState.menuBarText == "83%")    // No arrow
    }

    // MARK: - Task 4.10: 7d exhausted does NOT promote (exhausted ≠ warning/critical per displayedWindow logic)

    @Test("7d exhausted does not promote - stays on 5h with no slope arrow")
    @MainActor
    func sevenDayExhaustedDoesNotPromote() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        let resetsAt7d = Date().addingTimeInterval(2 * 3600 + 13 * 60)  // 2h 13m
        appState.updateWindows(
            fiveHour: WindowState(utilization: 20.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 100.0, resetsAt: resetsAt7d)  // 0% headroom, exhausted
        )
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)

        // 7d exhausted is NOT promoted (displayedWindow requires warning/critical, not exhausted)
        // So 5h is displayed with 80% headroom and no slope arrow (fiveHourSlope is .flat)
        #expect(appState.displayedWindow == .fiveHour)
        #expect(appState.menuBarText == "80%")  // 5h headroom, no arrow (flat)
    }

    // MARK: - Additional edge case tests

    @Test("displayedSlope returns fiveHourSlope when 5h is displayed")
    @MainActor
    func displayedSlopeReturnsFiveHourSlopeWhenDisplayed() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 30.0, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: WindowState(utilization: 50.0, resetsAt: Date().addingTimeInterval(86400))  // 50% headroom, normal
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)

        // 5h displayed (7d is normal, not warning/critical)
        #expect(appState.displayedWindow == .fiveHour)
        #expect(appState.displayedSlope == .steep)
        #expect(appState.menuBarText == "70% \u{2B06}")
    }

    @Test("tokenExpired maps to disconnected - no slope arrow")
    @MainActor
    func tokenExpiredNoSlopeArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.tokenExpired)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .steep)

        #expect(appState.menuBarText == "\u{2014}")  // em dash only
    }

    @Test("noCredentials maps to disconnected - no slope arrow")
    @MainActor
    func noCredentialsNoSlopeArrow() {
        let appState = AppState()
        appState.updateConnectionStatus(.noCredentials)
        appState.updateSlopes(fiveHour: .steep, sevenDay: .steep)

        #expect(appState.menuBarText == "\u{2014}")  // em dash only
    }

    @Test("exhausted with no resetsAt shows percentage without slope arrow")
    @MainActor
    func exhaustedNoResetsAtShowsPercentage() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(
            fiveHour: WindowState(utilization: 100.0, resetsAt: nil),  // No resetsAt
            sevenDay: nil
        )
        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)

        // Without resetsAt, exhausted shows 0% not countdown
        // Per current implementation, this goes through percentage path
        // But since headroomState is .exhausted without resetsAt, it falls to percentage
        #expect(appState.menuBarText == "0%")  // No countdown, no arrow (exhausted state)
        // Explicitly verify no arrow present even though slope IS actionable (.steep)
        #expect(!appState.menuBarText.contains("\u{2B06}"), "Exhausted state should never show steep arrow")
        #expect(!appState.menuBarText.contains("\u{2197}"), "Exhausted state should never show rising arrow")
        #expect(!appState.menuBarText.contains("\u{2192}"), "Exhausted state should never show flat arrow")
    }
}
