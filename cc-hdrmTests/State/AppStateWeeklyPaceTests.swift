import Foundation
import Observation
import os
import Testing
@testable import cc_hdrm

@Suite("AppState Weekly Pace Menu Bar")
@MainActor
struct AppStateWeeklyPaceTests {

    private let arrow = "\u{2197}"
    private let day: TimeInterval = 86400

    private func weekly(_ utilization: Double, resetsIn: TimeInterval?) -> WindowState {
        WindowState(utilization: utilization, resetsAt: resetsIn.map { Date().addingTimeInterval($0) })
    }

    private func connectedState(utilization: Double, resetsIn: TimeInterval?) -> AppState {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: weekly(utilization, resetsIn: resetsIn))
        return appState
    }

    // MARK: - No 5-hour number

    @Test("ahead of pace with run-out before reset → \"40% ↗\"")
    func aheadShowsArrow() {
        let appState = connectedState(utilization: 60, resetsIn: 4 * day)
        #expect(appState.weeklyPace?.runOut != nil)
        #expect(appState.menuBarText == "40% \(arrow)")
    }

    @Test("ahead of pace in the critical band → \"3% ↗\"")
    func aheadInCriticalBandShowsArrow() {
        let appState = connectedState(utilization: 97, resetsIn: 4 * day)
        #expect(appState.sevenDay?.headroomState == .critical)
        #expect(appState.weeklyPace?.runOut != nil)
        #expect(appState.menuBarText == "3% \(arrow)")
    }

    @Test("exactly even pace: 50% with 3.5 days left → no arrow")
    func evenPaceHasNoArrow() {
        let appState = connectedState(utilization: 50, resetsIn: 3.5 * day)
        #expect(appState.weeklyPace?.runOut == nil)
        #expect(appState.weeklyPace?.paceLineText == "On pace")
        #expect(appState.menuBarText == "50%")
    }

    @Test("a 1% step that crosses even pace → arrow, because run-out really moved before the reset")
    func stepAcrossEvenPaceShowsArrow() {
        let appState = connectedState(utilization: 50, resetsIn: 3.5 * day)
        appState.updateWindows(fiveHour: nil, sevenDay: weekly(51, resetsIn: 3.5 * day))
        #expect(appState.weeklyPace?.runOut != nil)
        #expect(appState.menuBarText == "49% \(arrow)")
    }

    @Test("reset already passed before the next poll → no pace, no arrow")
    func resetPassedHasNoPace() {
        let appState = connectedState(utilization: 80, resetsIn: -60)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "20%")
    }

    @Test("under-spending → no arrow")
    func behindHasNoArrow() {
        let appState = connectedState(utilization: 20, resetsIn: 2 * day)
        #expect(appState.weeklyPace?.runOut == nil)
        #expect(appState.menuBarText == "80%")
    }

    @Test("a single 1% step reading rising, while under an even pace → no arrow")
    func onePercentStepHasNoArrow() {
        let appState = connectedState(utilization: 40, resetsIn: 3.5 * day)
        appState.updateSlopes(fiveHour: .flat, sevenDay: .flat)
        #expect(appState.menuBarText == "60%")

        appState.updateWindows(fiveHour: nil, sevenDay: weekly(41, resetsIn: 3.5 * day))
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        #expect(appState.displayedSlope == .rising)
        #expect(appState.menuBarText == "59%")
    }

    @Test("steep slope cannot draw the arrow either")
    func steepSlopeHasNoArrow() {
        let appState = connectedState(utilization: 20, resetsIn: 2 * day)
        appState.updateSlopes(fiveHour: .flat, sevenDay: .steep)
        #expect(appState.menuBarText == "80%")
    }

    @Test("first 4 hours of the week → pace exists but no run-out, so no arrow")
    func firstHoursHaveNoArrow() throws {
        let appState = connectedState(utilization: 10, resetsIn: 7 * day - 2 * 3600)
        let pace = try #require(appState.weeklyPace)
        #expect(pace.paceDelta > 0)
        #expect(pace.runOut == nil)
        #expect(appState.menuBarText == "90%")
    }

    @Test("missing resets_at → no pace, no arrow")
    func missingResetsAtHasNoArrow() {
        let appState = connectedState(utilization: 60, resetsIn: nil)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "40%")
    }

    @Test("exhausted → countdown, no pace, no arrow")
    func exhaustedHasNoArrow() {
        let appState = connectedState(utilization: 100, resetsIn: 2 * day)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText.hasPrefix("\u{21BB}"))
        #expect(!appState.menuBarText.contains(arrow))
    }

    @Test("exhausted with no reset time → \"0%\", no pace, no arrow")
    func exhaustedNoResetHasNoArrow() {
        let appState = connectedState(utilization: 100, resetsIn: nil)
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "0%")
    }

    @Test("not connected, old weekly data → em dash, no pace",
          arguments: [ConnectionStatus.disconnected, .tokenExpired, .noCredentials])
    func notConnectedHasNoPace(status: ConnectionStatus) {
        let appState = connectedState(utilization: 60, resetsIn: 4 * day)
        appState.updateConnectionStatus(status)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "\u{2014}")
    }

    @Test("both windows nil → no pace")
    func noWindowsHaveNoPace() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: nil, sevenDay: nil)
        #expect(appState.weeklyPace == nil)
    }

    // MARK: - With a 5-hour number

    @Test("promoted weekly on an account with a number → slope arrow, no pace")
    func promotedWeeklyKeepsSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 20, resetsAt: nil), sevenDay: weekly(85, resetsIn: 4 * day))
        appState.updateSlopes(fiveHour: .flat, sevenDay: .rising)

        #expect(appState.displayedWindow == .sevenDay)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "15% \(SlopeLevel.rising.arrow)")
    }

    @Test("promoted weekly, flat slope, numbers that would be ahead of pace → no arrow")
    func promotedWeeklyIgnoresPace() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 20, resetsAt: nil), sevenDay: weekly(85, resetsIn: 4 * day))

        #expect(appState.displayedWindow == .sevenDay)
        #expect(appState.menuBarText == "15%")
    }

    @Test("5-hour displayed → 5-hour slope drives the arrow, weekly pace plays no part")
    func fiveHourDisplayedKeepsSlope() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 20, resetsAt: nil), sevenDay: weekly(60, resetsIn: 4 * day))
        #expect(appState.displayedWindow == .fiveHour)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "80%")

        appState.updateSlopes(fiveHour: .steep, sevenDay: .flat)
        #expect(appState.menuBarText == "80% \(SlopeLevel.steep.arrow)")
    }

    // MARK: - Clock

    private func tickFiresChange(_ appState: AppState) -> Bool {
        let fired = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = appState.menuBarText
        } onChange: {
            fired.withLock { $0 = true }
        }
        appState.tickCountdown()
        return fired.withLock { $0 }
    }

    @Test("no 5-hour number → the minute tick redraws the menu bar, so the arrow can clear between polls")
    func tickRedrawsWithoutFiveHourNumber() {
        #expect(tickFiresChange(connectedState(utilization: 60, resetsIn: 4 * day)))
    }

    @Test("with a 5-hour number → the minute tick redraws nothing, as before")
    func tickIgnoredWithFiveHourNumber() {
        let appState = AppState()
        appState.updateConnectionStatus(.connected)
        appState.updateWindows(fiveHour: WindowState(utilization: 20, resetsAt: nil), sevenDay: weekly(60, resetsIn: 4 * day))
        #expect(!tickFiresChange(appState))
    }

    // MARK: - State change

    @Test("number → none → number: arrow source follows the data with no restart")
    func flipFollowsTheData() {
        let appState = AppState()
        let fiveHour = WindowState(utilization: 20, resetsAt: nil)
        let ahead = weekly(60, resetsIn: 4 * day)
        appState.updateConnectionStatus(.connected)
        appState.updateSlopes(fiveHour: .rising, sevenDay: .flat)

        appState.updateWindows(fiveHour: fiveHour, sevenDay: ahead)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "80% \(SlopeLevel.rising.arrow)")

        appState.updateWindows(fiveHour: nil, sevenDay: weekly(20, resetsIn: 2 * day))
        #expect(appState.weeklyPace != nil)
        #expect(appState.menuBarText == "80%")

        appState.updateWindows(fiveHour: nil, sevenDay: ahead)
        #expect(appState.menuBarText == "40% \(arrow)")

        appState.updateWindows(fiveHour: fiveHour, sevenDay: ahead)
        #expect(appState.weeklyPace == nil)
        #expect(appState.menuBarText == "80% \(SlopeLevel.rising.arrow)")
    }
}
